#include "x11_compositor.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysymdef.h>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>

using namespace godot;

X11Compositor::X11Compositor() :
    display(nullptr),
    root_window(0),
    screen(0),
    display_number(0),
    xephyr_pid(0),
    composite_available(false),
    damage_available(false),
    next_window_id(1),
    initialized(false) {
}

X11Compositor::~X11Compositor() {
    cleanup();
}

void X11Compositor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize"), &X11Compositor::initialize);
    ClassDB::bind_method(D_METHOD("get_window_ids"), &X11Compositor::get_window_ids);
    ClassDB::bind_method(D_METHOD("get_window_buffer", "window_id"), &X11Compositor::get_window_buffer);
    ClassDB::bind_method(D_METHOD("get_window_size", "window_id"), &X11Compositor::get_window_size);
    ClassDB::bind_method(D_METHOD("get_display_name"), &X11Compositor::get_display_name);
    ClassDB::bind_method(D_METHOD("is_initialized"), &X11Compositor::is_initialized);

    // Window properties
    ClassDB::bind_method(D_METHOD("get_window_class", "window_id"), &X11Compositor::get_window_class);
    ClassDB::bind_method(D_METHOD("get_window_title", "window_id"), &X11Compositor::get_window_title);
    ClassDB::bind_method(D_METHOD("get_window_pid", "window_id"), &X11Compositor::get_window_pid);
    ClassDB::bind_method(D_METHOD("get_parent_window_id", "window_id"), &X11Compositor::get_parent_window_id);
    ClassDB::bind_method(D_METHOD("get_window_position", "window_id"), &X11Compositor::get_window_position);

    // Input handling
    ClassDB::bind_method(D_METHOD("send_mouse_button", "window_id", "button", "pressed", "x", "y"), &X11Compositor::send_mouse_button);
    ClassDB::bind_method(D_METHOD("send_mouse_motion", "window_id", "x", "y"), &X11Compositor::send_mouse_motion);
    ClassDB::bind_method(D_METHOD("send_key_event", "window_id", "keycode", "pressed"), &X11Compositor::send_key_event);
    ClassDB::bind_method(D_METHOD("set_window_focus", "window_id"), &X11Compositor::set_window_focus);
}

void X11Compositor::_ready() {
    UtilityFunctions::print("X11Compositor ready");

    // Auto-initialize the compositor
    if (!initialize()) {
        UtilityFunctions::printerr("Failed to auto-initialize X11Compositor");
    }
}

void X11Compositor::_process(double delta) {
    if (!initialized || !display) {
        return;
    }

    // Process X11 events (non-blocking)
    while (XPending(display) > 0) {
        XEvent event;
        XNextEvent(display, &event);

        switch (event.type) {
            case CreateNotify:
                handle_create_notify(&event.xcreatewindow);
                break;
            case DestroyNotify:
                handle_destroy_notify(&event.xdestroywindow);
                break;
            case MapNotify:
                handle_map_notify(&event.xmap);
                break;
            case UnmapNotify:
                handle_unmap_notify(&event.xunmap);
                break;
            case ConfigureNotify:
                handle_configure_notify(&event.xconfigure);
                break;
            default:
                // Check for Damage events
                if (damage_available && event.type == damage_event_base + XDamageNotify) {
                    handle_damage_notify((XDamageNotifyEvent*)&event);
                }
                break;
        }
    }

    // Periodically capture window contents for all mapped windows
    // (in a real implementation, we'd only do this on damage events)
    for (auto &pair : windows) {
        X11Window *window = pair.second;
        if (window->mapped) {
            capture_window_contents(window);
        }
    }
}

void X11Compositor::_exit_tree() {
    cleanup();
}

int X11Compositor::find_available_display() {
    // Try display numbers from 1 to 99
    for (int disp_num = 1; disp_num < 100; disp_num++) {
        char display_str[32];
        snprintf(display_str, sizeof(display_str), ":%d", disp_num);

        // Try to connect to see if it's already in use
        Display *test_display = XOpenDisplay(display_str);
        if (test_display) {
            // Display exists, try next one
            XCloseDisplay(test_display);
            continue;
        }

        // Check if socket file exists
        char socket_path[256];
        snprintf(socket_path, sizeof(socket_path), "/tmp/.X11-unix/X%d", disp_num);
        if (access(socket_path, F_OK) == 0) {
            // Socket exists, try next one
            continue;
        }

        // This display number is available
        return disp_num;
    }

    return -1;  // No available display found
}

bool X11Compositor::launch_xephyr(int disp_num) {
    UtilityFunctions::print("Launching Xvfb (headless X server) on display :", disp_num);

    pid_t pid = fork();

    if (pid < 0) {
        UtilityFunctions::printerr("Failed to fork for Xvfb");
        return false;
    }

    if (pid == 0) {
        // Child process - launch Xvfb (headless X server)
        char display_arg[32];
        char screen_arg[64];
        snprintf(display_arg, sizeof(display_arg), ":%d", disp_num);
        snprintf(screen_arg, sizeof(screen_arg), "1280x720x24");

        // Launch Xvfb with reasonable defaults
        // -ac = disable access control (allow all connections)
        // -screen 0 WxHxD = set screen 0 size and depth
        // +extension COMPOSITE = enable Composite extension explicitly
        execlp("Xvfb", "Xvfb",
               display_arg,
               "-ac",
               "-screen", "0", screen_arg,
               "+extension", "Composite",
               nullptr);

        // If execlp returns, it failed
        _exit(1);
    }

    // Parent process
    xephyr_pid = pid;

    // Wait a bit for Xvfb to start
    UtilityFunctions::print("Waiting for Xvfb to start...");

    // Try to connect for up to 5 seconds
    for (int attempts = 0; attempts < 50; attempts++) {
        usleep(100000);  // 100ms

        char display_str[32];
        snprintf(display_str, sizeof(display_str), ":%d", disp_num);
        Display *test_display = XOpenDisplay(display_str);

        if (test_display) {
            XCloseDisplay(test_display);
            UtilityFunctions::print("Xvfb started successfully");
            return true;
        }

        // Check if Xvfb process died
        int status;
        if (waitpid(pid, &status, WNOHANG) > 0) {
            UtilityFunctions::printerr("Xvfb process died");
            xephyr_pid = 0;
            return false;
        }
    }

    UtilityFunctions::printerr("Timeout waiting for Xvfb to start");

    // Kill the Xvfb process
    if (xephyr_pid > 0) {
        kill(xephyr_pid, SIGTERM);
        waitpid(xephyr_pid, nullptr, 0);
        xephyr_pid = 0;
    }

    return false;
}

bool X11Compositor::initialize() {
    if (initialized) {
        UtilityFunctions::print("X11Compositor already initialized");
        return true;
    }

    UtilityFunctions::print("Initializing X11Compositor...");

    // Find an available display number
    display_number = find_available_display();
    if (display_number < 0) {
        UtilityFunctions::printerr("No available X11 display numbers found");
        return false;
    }

    UtilityFunctions::print("Using display number: ", display_number);

    // Launch Xvfb on that display
    if (!launch_xephyr(display_number)) {
        UtilityFunctions::printerr("Failed to launch Xvfb");
        return false;
    }

    // Connect to our Xvfb display
    char display_str[32];
    snprintf(display_str, sizeof(display_str), ":%d", display_number);
    display = XOpenDisplay(display_str);
    if (!display) {
        UtilityFunctions::printerr("Failed to connect to Xvfb display");
        cleanup();
        return false;
    }

    screen = DefaultScreen(display);
    root_window = RootWindow(display, screen);

    UtilityFunctions::print("Connected to Xvfb display: ", DisplayString(display));

    // Check for Composite extension
    int composite_major, composite_minor;
    if (XCompositeQueryExtension(display, &composite_event_base, &composite_error_base)) {
        XCompositeQueryVersion(display, &composite_major, &composite_minor);
        UtilityFunctions::print("Composite extension available: ", composite_major, ".", composite_minor);
        composite_available = true;

        // Enable composite redirection for the root window
        // This causes all windows to be rendered off-screen
        XCompositeRedirectSubwindows(display, root_window, CompositeRedirectAutomatic);
    } else {
        UtilityFunctions::printerr("Composite extension not available!");
        UtilityFunctions::printerr("Window capture will not work without Composite extension");
        composite_available = false;
    }

    // Check for Damage extension
    int damage_major, damage_minor;
    if (XDamageQueryExtension(display, &damage_event_base, &damage_error_base)) {
        XDamageQueryVersion(display, &damage_major, &damage_minor);
        UtilityFunctions::print("Damage extension available: ", damage_major, ".", damage_minor);
        damage_available = true;
    } else {
        UtilityFunctions::print("Damage extension not available (will use polling instead)");
        damage_available = false;
    }

    // Select events on root window to track window creation/destruction
    // Note: We use SubstructureNotifyMask to get notifications about window changes
    // We do NOT use SubstructureRedirectMask because that would make us a window manager
    // and require us to handle MapRequest events
    XSelectInput(display, root_window, SubstructureNotifyMask);

    // Scan for existing windows
    scan_existing_windows();

    initialized = true;
    UtilityFunctions::print("X11Compositor initialized successfully");
    UtilityFunctions::print("Tracking ", (int)windows.size(), " windows");

    return true;
}

void X11Compositor::scan_existing_windows() {
    X11WindowHandle returned_root, returned_parent;
    X11WindowHandle *children;
    unsigned int num_children;

    if (XQueryTree(display, root_window, &returned_root, &returned_parent,
                   &children, &num_children)) {
        for (unsigned int i = 0; i < num_children; i++) {
            if (should_track_window(children[i])) {
                add_window(children[i]);
            }
        }
        XFree(children);
    }
}

bool X11Compositor::should_track_window(X11WindowHandle xwin) {
    // Get window attributes
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(display, xwin, &attrs)) {
        return false;
    }

    // Skip InputOnly windows (they have no visual content)
    if (attrs.c_class == InputOnly) {
        return false;
    }

    // Skip tiny windows (< 10x10) which are likely internal/invisible windows
    // But DO track popup menus which can be as small as 50x20
    if (attrs.width < 10 || attrs.height < 10) {
        return false;
    }

    // Check if window has WM_STATE property (indicates it's a managed window)
    Atom wm_state = XInternAtom(display, "WM_STATE", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *prop;

    if (XGetWindowProperty(display, xwin, wm_state, 0, 0, False, AnyPropertyType,
                          &actual_type, &actual_format, &nitems, &bytes_after, &prop) == Success) {
        if (prop) XFree(prop);
        if (actual_type != None) {
            return true;  // Window has WM_STATE, so it's managed
        }
    }

    // Also track mapped windows without WM_STATE (including popups)
    return attrs.map_state == IsViewable;
}

void X11Compositor::add_window(X11WindowHandle xwin) {
    // Check if already tracking
    if (xwindow_to_id.find(xwin) != xwindow_to_id.end()) {
        return;
    }

    XWindowAttributes attrs;
    if (!XGetWindowAttributes(display, xwin, &attrs)) {
        return;
    }

    // Create tracking structure
    X11Window *window = new X11Window();
    window->id = next_window_id++;
    window->xwindow = xwin;
    window->width = attrs.width;
    window->height = attrs.height;
    window->x = attrs.x;
    window->y = attrs.y;
    window->mapped = (attrs.map_state == IsViewable);
    window->has_image = false;
    window->pid = -1;
    window->parent_window_id = -1;  // Default: no parent

    // Get window title (WM_NAME)
    char *window_name = nullptr;
    XFetchName(display, xwin, &window_name);
    window->wm_name = window_name ? String(window_name) : String("");
    if (window_name) XFree(window_name);

    // Get window class (WM_CLASS)
    XClassHint class_hint;
    if (XGetClassHint(display, xwin, &class_hint)) {
        window->wm_class = class_hint.res_class ? String(class_hint.res_class) : String("");
        if (class_hint.res_name) XFree(class_hint.res_name);
        if (class_hint.res_class) XFree(class_hint.res_class);
    } else {
        window->wm_class = String("");
    }

    // Get PID (_NET_WM_PID property)
    Atom pid_atom = XInternAtom(display, "_NET_WM_PID", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *prop = nullptr;

    if (XGetWindowProperty(display, xwin, pid_atom, 0, 1, False, XA_CARDINAL,
                          &actual_type, &actual_format, &nitems, &bytes_after, &prop) == Success) {
        if (prop && nitems > 0) {
            window->pid = *((int*)prop);
        }
        if (prop) XFree(prop);
    }

    // Check for parent window (WM_TRANSIENT_FOR property)
    // This indicates this window is a popup/dialog for another window
    Atom transient_atom = XInternAtom(display, "WM_TRANSIENT_FOR", False);
    X11WindowHandle parent_xwin = None;

    prop = nullptr;
    if (XGetWindowProperty(display, xwin, transient_atom, 0, 1, False, XA_WINDOW,
                          &actual_type, &actual_format, &nitems, &bytes_after, &prop) == Success) {
        if (prop && nitems > 0) {
            parent_xwin = *((X11WindowHandle*)prop);

            // Look up our internal window ID for this parent
            auto parent_it = xwindow_to_id.find(parent_xwin);
            if (parent_it != xwindow_to_id.end()) {
                window->parent_window_id = parent_it->second;
                UtilityFunctions::print("  Window is transient for window ", window->parent_window_id);
            }
        }
        if (prop) XFree(prop);
    }

    // Set up damage tracking if available
    if (damage_available) {
        window->damage = XDamageCreate(display, xwin, XDamageReportNonEmpty);
    }

    // Select events for this window
    XSelectInput(display, xwin, StructureNotifyMask);

    // Store in our maps
    windows[window->id] = window;
    xwindow_to_id[xwin] = window->id;

    UtilityFunctions::print("Tracking window ", window->id, ": ",
                           window->wm_name, " [", window->wm_class, "] ",
                           " (", window->width, "x", window->height, ")");
}

void X11Compositor::remove_window(X11WindowHandle xwin) {
    auto it = xwindow_to_id.find(xwin);
    if (it == xwindow_to_id.end()) {
        return;
    }

    int window_id = it->second;
    X11Window *window = windows[window_id];

    UtilityFunctions::print("Removing window ", window_id);

    // Clean up damage tracking - set error handler to ignore BadDamage errors
    // (window might already be destroyed on X11 side)
    if (damage_available && window->damage) {
        // Ignore errors when destroying damage - window might be gone
        XSync(display, False);  // Flush pending requests first
        XDamageDestroy(display, window->damage);
        XSync(display, False);  // Ensure the destroy completes
    }

    // Remove from maps
    windows.erase(window_id);
    xwindow_to_id.erase(xwin);

    delete window;
}

void X11Compositor::handle_create_notify(XCreateWindowEvent *event) {
    if (should_track_window(event->window)) {
        add_window(event->window);
    }
}

void X11Compositor::handle_destroy_notify(XDestroyWindowEvent *event) {
    remove_window(event->window);
}

void X11Compositor::handle_map_notify(XMapEvent *event) {
    auto it = xwindow_to_id.find(event->window);
    if (it != xwindow_to_id.end()) {
        X11Window *window = windows[it->second];
        window->mapped = true;
        UtilityFunctions::print("Window ", window->id, " mapped");
    } else if (should_track_window(event->window)) {
        // New window that just became visible
        add_window(event->window);
    }
}

void X11Compositor::handle_unmap_notify(XUnmapEvent *event) {
    auto it = xwindow_to_id.find(event->window);
    if (it != xwindow_to_id.end()) {
        X11Window *window = windows[it->second];
        window->mapped = false;
        UtilityFunctions::print("Window ", window->id, " unmapped");
    }
}

void X11Compositor::handle_configure_notify(XConfigureEvent *event) {
    auto it = xwindow_to_id.find(event->window);
    if (it != xwindow_to_id.end()) {
        X11Window *window = windows[it->second];

        bool size_changed = (window->width != event->width || window->height != event->height);

        window->width = event->width;
        window->height = event->height;
        window->x = event->x;
        window->y = event->y;

        if (size_changed) {
            UtilityFunctions::print("Window ", window->id, " resized to ",
                                   window->width, "x", window->height);
            // Invalidate cached image on size change
            window->has_image = false;
        }
    }
}

void X11Compositor::handle_damage_notify(XDamageNotifyEvent *event) {
    // Find window by damage object
    for (auto &pair : windows) {
        X11Window *window = pair.second;
        if (window->damage == event->damage) {
            // Window has been damaged, needs re-capture
            // Subtract the damage
            XDamageSubtract(display, window->damage, None, None);

            // Mark for recapture
            window->has_image = false;
            break;
        }
    }
}

void X11Compositor::capture_window_contents(X11Window *window) {
    if (!composite_available || !window->mapped) {
        return;
    }

    // Skip if we already have a valid image and no damage
    if (window->has_image && damage_available) {
        return;
    }

    if (window->width <= 0 || window->height <= 0) {
        return;
    }

    // Get the window's composite pixmap (off-screen buffer)
    Pixmap pixmap = XCompositeNameWindowPixmap(display, window->xwindow);
    if (!pixmap) {
        return;
    }

    // Get an XImage from the pixmap
    XImage *image = XGetImage(display, pixmap, 0, 0, window->width, window->height,
                              AllPlanes, ZPixmap);

    if (!image) {
        XFreePixmap(display, pixmap);
        return;
    }

    // Convert XImage to RGBA format
    size_t size = window->width * window->height * 4;
    window->image_data.resize(size);

    // Convert based on image format
    // Most X11 servers use 32-bit BGRA or BGRX format
    if (image->bits_per_pixel == 32) {
        // Access the raw pixel data directly
        // For 32bpp with depth 24, format is typically BGRX (LSB first) or XBGR (MSB first)
        uint8_t *src = (uint8_t*)image->data;
        int bytes_per_pixel = image->bits_per_pixel / 8;

        // Debug: Sample a few pixels to see what we're getting
        static bool printed_samples = false;
        if (!printed_samples && window->width > 10 && window->height > 10) {
            // Sample pixel at (10, 10)
            int sample_idx = (10 * image->bytes_per_line) + (10 * bytes_per_pixel);
            UtilityFunctions::print("Sample pixel at (10,10): [0]=", (int)src[sample_idx+0],
                                   " [1]=", (int)src[sample_idx+1],
                                   " [2]=", (int)src[sample_idx+2],
                                   " [3]=", (int)src[sample_idx+3]);
            printed_samples = true;
        }

        for (int y = 0; y < window->height; y++) {
            for (int x = 0; x < window->width; x++) {
                // Calculate source offset in the XImage data
                int src_idx = (y * image->bytes_per_line) + (x * bytes_per_pixel);

                // Calculate destination offset in our RGBA buffer
                size_t dst_idx = (y * window->width + x) * 4;

                // Read pixel data - try different byte orders
                uint8_t byte0 = src[src_idx + 0];
                uint8_t byte1 = src[src_idx + 1];
                uint8_t byte2 = src[src_idx + 2];
                uint8_t byte3 = src[src_idx + 3];

                // Write to RGBA format for Godot
                // Let's try: byte0=B, byte1=G, byte2=R (standard BGRA)
                window->image_data[dst_idx + 0] = byte2;  // R
                window->image_data[dst_idx + 1] = byte1;  // G
                window->image_data[dst_idx + 2] = byte0;  // B
                window->image_data[dst_idx + 3] = 255;     // A
            }
        }
        window->has_image = true;
    } else {
        UtilityFunctions::printerr("Unsupported image format: ", image->bits_per_pixel, " bits per pixel");
    }

    XDestroyImage(image);
    XFreePixmap(display, pixmap);
}

TypedArray<int> X11Compositor::get_window_ids() {
    TypedArray<int> ids;
    for (const auto &pair : windows) {
        ids.push_back(pair.first);
    }
    return ids;
}

Ref<Image> X11Compositor::get_window_buffer(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return Ref<Image>();
    }

    X11Window *window = it->second;

    if (!window->has_image || window->image_data.empty()) {
        return Ref<Image>();
    }

    if (window->width <= 0 || window->height <= 0) {
        return Ref<Image>();
    }

    // Create PackedByteArray from cached image data
    PackedByteArray image_data;
    image_data.resize(window->image_data.size());
    memcpy(image_data.ptrw(), window->image_data.data(), window->image_data.size());

    // Create Godot Image
    Ref<Image> image = Image::create_from_data(window->width, window->height,
                                               false, Image::FORMAT_RGBA8, image_data);

    return image;
}

Vector2i X11Compositor::get_window_size(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return Vector2i(0, 0);
    }

    X11Window *window = it->second;
    return Vector2i(window->width, window->height);
}

String X11Compositor::get_display_name() {
    if (!initialized || display_number == 0) {
        return String();
    }
    char display_str[32];
    snprintf(display_str, sizeof(display_str), ":%d", display_number);
    return String(display_str);
}

bool X11Compositor::is_initialized() {
    return initialized;
}

// Window property getters
String X11Compositor::get_window_class(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return String();
    }
    return it->second->wm_class;
}

String X11Compositor::get_window_title(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return String();
    }
    return it->second->wm_name;
}

int X11Compositor::get_window_pid(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return -1;
    }
    return it->second->pid;
}

int X11Compositor::get_parent_window_id(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return -1;
    }
    return it->second->parent_window_id;
}

Vector2i X11Compositor::get_window_position(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return Vector2i(0, 0);
    }
    X11Window *window = it->second;

    // Get absolute position relative to root window using XTranslateCoordinates
    // This is more reliable than XWindowAttributes x,y which can be relative to parent
    ::Window child_return;
    int x_return, y_return;

    XTranslateCoordinates(display, window->xwindow, root_window,
                         0, 0, &x_return, &y_return, &child_return);

    UtilityFunctions::print("Window ", window_id, " position: attrs=(", window->x, ",", window->y,
                           ") absolute=(", x_return, ",", y_return, ")");

    return Vector2i(x_return, y_return);
}

// Input handling methods
void X11Compositor::send_mouse_button(int window_id, int button, bool pressed, int x, int y) {
    auto it = windows.find(window_id);
    if (it == windows.end() || !display) {
        return;
    }

    X11Window *window = it->second;

    // Get window's absolute position on the X11 screen
    ::Window child_return;
    int win_x_root, win_y_root;
    XTranslateCoordinates(display, window->xwindow, root_window,
                         0, 0, &win_x_root, &win_y_root, &child_return);

    UtilityFunctions::print("[X11] Mouse button ", pressed ? "PRESS" : "RELEASE", " to window ", window_id,
                           " (parent:", window->parent_window_id, ")",
                           " - window_pos=(", x, ",", y, ")",
                           " win_absolute=(", win_x_root, ",", win_y_root, ")",
                           " root_coords=(", win_x_root + x, ",", win_y_root + y, ")");

    XEvent event;
    memset(&event, 0, sizeof(event));

    event.type = pressed ? ButtonPress : ButtonRelease;
    event.xbutton.window = window->xwindow;
    event.xbutton.root = root_window;
    event.xbutton.subwindow = None;
    event.xbutton.time = CurrentTime;
    event.xbutton.x = x;
    event.xbutton.y = y;
    event.xbutton.x_root = win_x_root + x;  // Root coordinates = window position + window-relative coords
    event.xbutton.y_root = win_y_root + y;
    event.xbutton.state = 0;
    event.xbutton.button = button;
    event.xbutton.same_screen = True;

    XSendEvent(display, window->xwindow, True, ButtonPressMask | ButtonReleaseMask, &event);
    XFlush(display);
}

void X11Compositor::send_mouse_motion(int window_id, int x, int y) {
    auto it = windows.find(window_id);
    if (it == windows.end() || !display) {
        return;
    }

    X11Window *window = it->second;

    // Get window's absolute position on the X11 screen
    ::Window child_return;
    int win_x_root, win_y_root;
    XTranslateCoordinates(display, window->xwindow, root_window,
                         0, 0, &win_x_root, &win_y_root, &child_return);

    XEvent event;
    memset(&event, 0, sizeof(event));

    event.type = MotionNotify;
    event.xmotion.window = window->xwindow;
    event.xmotion.root = root_window;
    event.xmotion.subwindow = None;
    event.xmotion.time = CurrentTime;
    event.xmotion.x = x;
    event.xmotion.y = y;
    event.xmotion.x_root = win_x_root + x;  // Root coordinates = window position + window-relative coords
    event.xmotion.y_root = win_y_root + y;
    event.xmotion.state = 0;
    event.xmotion.is_hint = NotifyNormal;
    event.xmotion.same_screen = True;

    XSendEvent(display, window->xwindow, True, PointerMotionMask, &event);
    XFlush(display);
}

void X11Compositor::send_key_event(int window_id, int godot_keycode, bool pressed) {
    auto it = windows.find(window_id);
    if (it == windows.end() || !display) {
        return;
    }

    X11Window *window = it->second;

    // Map Godot keycodes to X11 keysyms
    // Godot KEY_* constants don't always match X11 keysyms
    KeySym keysym;

    // Special key mappings (Godot 4 KEY_* to X11 XK_*)
    // Godot 4 uses 0x400000 range for special keys
    switch (godot_keycode) {
        // Common special keys (Godot 4)
        case 4194309: keysym = XK_Return; break;         // KEY_ENTER (0x400005)
        case 4194308: keysym = XK_BackSpace; break;      // KEY_BACKSPACE (0x400004)
        case 4194305: keysym = XK_Escape; break;         // KEY_ESCAPE (0x400001)
        case 4194306: keysym = XK_Tab; break;            // KEY_TAB (0x400002)
        case 32: keysym = XK_space; break;               // KEY_SPACE (ASCII)

        // Arrow keys (Godot 4)
        case 4194319: keysym = XK_Left; break;           // KEY_LEFT (0x40000F)
        case 4194320: keysym = XK_Up; break;             // KEY_UP (0x400010)
        case 4194321: keysym = XK_Right; break;          // KEY_RIGHT (0x400011)
        case 4194322: keysym = XK_Down; break;           // KEY_DOWN (0x400012)

        // Modifiers (Godot 4)
        case 4194325: keysym = XK_Shift_L; break;        // KEY_SHIFT (0x400015)
        case 4194326: keysym = XK_Control_L; break;      // KEY_CTRL (0x400016)
        case 4194328: keysym = XK_Alt_L; break;          // KEY_ALT (0x400018)
        case 4194327: keysym = XK_Meta_L; break;         // KEY_META (0x400017)

        // Function keys (Godot 4)
        case 4194332: keysym = XK_F1; break;             // KEY_F1 (0x40001C)
        case 4194333: keysym = XK_F2; break;
        case 4194334: keysym = XK_F3; break;
        case 4194335: keysym = XK_F4; break;
        case 4194336: keysym = XK_F5; break;
        case 4194337: keysym = XK_F6; break;
        case 4194338: keysym = XK_F7; break;
        case 4194339: keysym = XK_F8; break;
        case 4194340: keysym = XK_F9; break;
        case 4194341: keysym = XK_F10; break;
        case 4194342: keysym = XK_F11; break;
        case 4194343: keysym = XK_F12; break;

        // Delete/Insert/Home/End/PageUp/PageDown (Godot 4)
        case 4194312: keysym = XK_Delete; break;         // KEY_DELETE (0x400008)
        case 4194311: keysym = XK_Insert; break;         // KEY_INSERT (0x400007)
        case 4194313: keysym = XK_Home; break;           // KEY_HOME (0x400009)
        case 4194314: keysym = XK_End; break;            // KEY_END (0x40000A)
        case 4194315: keysym = XK_Page_Up; break;        // KEY_PAGEUP (0x40000B)
        case 4194316: keysym = XK_Page_Down; break;      // KEY_PAGEDOWN (0x40000C)

        default:
            // For printable characters, Godot uses Unicode values which match ASCII for basic chars
            // Try using the keycode directly as a keysym
            keysym = godot_keycode;
            break;
    }

    // Convert keysym to keycode for this display
    KeyCode x11_keycode = XKeysymToKeycode(display, keysym);

    if (x11_keycode == 0) {
        // Keycode not found - might be an unmapped key
        UtilityFunctions::print("Warning: Cannot map Godot keycode 0x", String::num_int64(godot_keycode, 16), " (keysym 0x", String::num_int64(keysym, 16), ") to X11 keycode");
        return;
    }

    // Track modifier state (static since we need to maintain state across calls)
    static unsigned int modifier_state = 0;

    // Update modifier state based on pressed/released modifiers (Godot 4)
    if (godot_keycode == 4194325) {  // KEY_SHIFT
        if (pressed) modifier_state |= ShiftMask;
        else modifier_state &= ~ShiftMask;
    }
    else if (godot_keycode == 4194326) {  // KEY_CTRL
        if (pressed) modifier_state |= ControlMask;
        else modifier_state &= ~ControlMask;
    }
    else if (godot_keycode == 4194328 || godot_keycode == 4194327) {  // KEY_ALT or KEY_META
        if (pressed) modifier_state |= Mod1Mask;
        else modifier_state &= ~Mod1Mask;
    }

    XEvent event;
    memset(&event, 0, sizeof(event));

    event.type = pressed ? KeyPress : KeyRelease;
    event.xkey.window = window->xwindow;
    event.xkey.root = root_window;
    event.xkey.subwindow = None;
    event.xkey.time = CurrentTime;
    event.xkey.x = 0;
    event.xkey.y = 0;
    event.xkey.x_root = 0;
    event.xkey.y_root = 0;
    event.xkey.state = modifier_state;  // Include modifier state
    event.xkey.keycode = x11_keycode;
    event.xkey.same_screen = True;

    XSendEvent(display, window->xwindow, True, KeyPressMask | KeyReleaseMask, &event);
    XFlush(display);
}

void X11Compositor::set_window_focus(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end() || !display) {
        return;
    }

    X11Window *window = it->second;

    // Set input focus to this window
    XSetInputFocus(display, window->xwindow, RevertToParent, CurrentTime);

    // Raise the window to the top of the stacking order
    XRaiseWindow(display, window->xwindow);

    XFlush(display);
}

void X11Compositor::cleanup() {
    if (!initialized) {
        return;
    }

    UtilityFunctions::print("Cleaning up X11Compositor...");

    // Clean up all tracked windows
    for (auto &pair : windows) {
        X11Window *window = pair.second;
        if (damage_available && window->damage) {
            XDamageDestroy(display, window->damage);
        }
        delete window;
    }
    windows.clear();
    xwindow_to_id.clear();

    // Disable composite redirection
    if (composite_available) {
        XCompositeUnredirectSubwindows(display, root_window, CompositeRedirectAutomatic);
    }

    // Close X11 connection
    if (display) {
        XCloseDisplay(display);
        display = nullptr;
    }

    // Kill Xvfb process
    if (xephyr_pid > 0) {
        UtilityFunctions::print("Terminating Xvfb (PID ", xephyr_pid, ")");
        kill(xephyr_pid, SIGTERM);

        // Wait for it to exit (with timeout)
        for (int i = 0; i < 10; i++) {
            int status;
            if (waitpid(xephyr_pid, &status, WNOHANG) > 0) {
                break;
            }
            usleep(100000);  // 100ms
        }

        // Force kill if still running
        int status;
        if (waitpid(xephyr_pid, &status, WNOHANG) == 0) {
            UtilityFunctions::print("Force killing Xephyr");
            kill(xephyr_pid, SIGKILL);
            waitpid(xephyr_pid, &status, 0);
        }

        xephyr_pid = 0;
    }

    initialized = false;
    UtilityFunctions::print("X11Compositor cleanup complete");
}
