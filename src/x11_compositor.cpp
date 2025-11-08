#include "x11_compositor.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <X11/Xutil.h>
#include <X11/Xatom.h>
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
    UtilityFunctions::print("Launching Xephyr on display :", disp_num);

    pid_t pid = fork();

    if (pid < 0) {
        UtilityFunctions::printerr("Failed to fork for Xephyr");
        return false;
    }

    if (pid == 0) {
        // Child process - launch Xephyr
        char display_arg[32];
        snprintf(display_arg, sizeof(display_arg), ":%d", disp_num);

        // Launch Xephyr with reasonable defaults
        // -ac = disable access control (allow all connections)
        // -screen = set screen size
        // -resizeable = allow window resizing
        execlp("Xephyr", "Xephyr",
               display_arg,
               "-ac",
               "-screen", "1280x720",
               "-resizeable",
               nullptr);

        // If execlp returns, it failed
        _exit(1);
    }

    // Parent process
    xephyr_pid = pid;

    // Wait a bit for Xephyr to start
    UtilityFunctions::print("Waiting for Xephyr to start...");

    // Try to connect for up to 5 seconds
    for (int attempts = 0; attempts < 50; attempts++) {
        usleep(100000);  // 100ms

        char display_str[32];
        snprintf(display_str, sizeof(display_str), ":%d", disp_num);
        Display *test_display = XOpenDisplay(display_str);

        if (test_display) {
            XCloseDisplay(test_display);
            UtilityFunctions::print("Xephyr started successfully");
            return true;
        }

        // Check if Xephyr process died
        int status;
        if (waitpid(pid, &status, WNOHANG) > 0) {
            UtilityFunctions::printerr("Xephyr process died");
            xephyr_pid = 0;
            return false;
        }
    }

    UtilityFunctions::printerr("Timeout waiting for Xephyr to start");

    // Kill the Xephyr process
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

    // Launch Xephyr on that display
    if (!launch_xephyr(display_number)) {
        UtilityFunctions::printerr("Failed to launch Xephyr");
        return false;
    }

    // Connect to our Xephyr display
    char display_str[32];
    snprintf(display_str, sizeof(display_str), ":%d", display_number);
    display = XOpenDisplay(display_str);
    if (!display) {
        UtilityFunctions::printerr("Failed to connect to Xephyr display");
        cleanup();
        return false;
    }

    screen = DefaultScreen(display);
    root_window = RootWindow(display, screen);

    UtilityFunctions::print("Connected to Xephyr display: ", DisplayString(display));

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

    // Skip windows that are too small (likely not real application windows)
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

    // Also track mapped windows without WM_STATE
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

    // Set up damage tracking if available
    if (damage_available) {
        window->damage = XDamageCreate(display, xwin, XDamageReportNonEmpty);
    }

    // Select events for this window
    XSelectInput(display, xwin, StructureNotifyMask);

    // Store in our maps
    windows[window->id] = window;
    xwindow_to_id[xwin] = window->id;

    // Get window name for debugging
    char *window_name = nullptr;
    XFetchName(display, xwin, &window_name);
    UtilityFunctions::print("Tracking window ", window->id, ": ",
                           window_name ? String(window_name) : String("(unnamed)"),
                           " (", window->width, "x", window->height, ")");
    if (window_name) XFree(window_name);
}

void X11Compositor::remove_window(X11WindowHandle xwin) {
    auto it = xwindow_to_id.find(xwin);
    if (it == xwindow_to_id.end()) {
        return;
    }

    int window_id = it->second;
    X11Window *window = windows[window_id];

    UtilityFunctions::print("Removing window ", window_id);

    // Clean up damage tracking
    if (damage_available && window->damage) {
        XDamageDestroy(display, window->damage);
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
        for (int y = 0; y < window->height; y++) {
            for (int x = 0; x < window->width; x++) {
                unsigned long pixel = XGetPixel(image, x, y);

                size_t idx = (y * window->width + x) * 4;

                // Extract RGB components from X11 pixel format (typically BGRA: 0xAARRGGBB)
                uint8_t b = (pixel >> 0) & 0xFF;
                uint8_t g = (pixel >> 8) & 0xFF;
                uint8_t r = (pixel >> 16) & 0xFF;
                uint8_t a = (pixel >> 24) & 0xFF;

                // Convert to RGBA for Godot
                window->image_data[idx + 0] = r;
                window->image_data[idx + 1] = g;
                window->image_data[idx + 2] = b;
                window->image_data[idx + 3] = (a == 0) ? 255 : a;  // Default to opaque if no alpha
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

    // Kill Xephyr process
    if (xephyr_pid > 0) {
        UtilityFunctions::print("Terminating Xephyr (PID ", xephyr_pid, ")");
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
