#include "wayland_compositor.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

extern "C" {
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
}

// Only include our C wrapper - NO wlroots headers in C++
#include "wlr_compat.h"


using namespace godot;

// Static callback handlers
void WaylandCompositor::handle_new_xdg_surface(struct wl_listener *listener, void *data) {
    WaylandCompositor *comp = wl_container_of(listener, comp, new_xdg_surface);
    struct wlr_xdg_surface *xdg_surface = static_cast<struct wlr_xdg_surface*>(data);

    if (xdg_surface->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
        return;
    }

    // Create our window tracking structure
    WaylandWindow *window = new WaylandWindow();
    window->id = comp->next_window_id++;
    window->toplevel = xdg_surface->toplevel;
    window->width = 0;
    window->height = 0;

    // Set up event listeners
    window->map.notify = handle_xdg_toplevel_map;
    wl_signal_add(&xdg_surface->surface->events.map, &window->map);

    window->unmap.notify = handle_xdg_toplevel_unmap;
    wl_signal_add(&xdg_surface->surface->events.unmap, &window->unmap);

    window->destroy.notify = handle_xdg_toplevel_destroy;
    wl_signal_add(&xdg_surface->events.destroy, &window->destroy);

    window->commit.notify = handle_xdg_surface_commit;
    wl_signal_add(&xdg_surface->surface->events.commit, &window->commit);

    // Store in our map
    comp->windows[window->id] = window;

    UtilityFunctions::print("New XDG toplevel window created with ID: ", window->id);
}

void WaylandCompositor::handle_xdg_toplevel_map(struct wl_listener *listener, void *data) {
    WaylandWindow *window = wl_container_of(listener, window, map);
    UtilityFunctions::print("Window ", window->id, " mapped");
}

void WaylandCompositor::handle_xdg_toplevel_unmap(struct wl_listener *listener, void *data) {
    WaylandWindow *window = wl_container_of(listener, window, unmap);
    UtilityFunctions::print("Window ", window->id, " unmapped");
}

void WaylandCompositor::handle_xdg_toplevel_destroy(struct wl_listener *listener, void *data) {
    WaylandWindow *window = wl_container_of(listener, window, destroy);
    UtilityFunctions::print("Window ", window->id, " destroyed");

    wl_list_remove(&window->map.link);
    wl_list_remove(&window->unmap.link);
    wl_list_remove(&window->destroy.link);
    wl_list_remove(&window->commit.link);

    // Note: The compositor class will handle removing from the map
    // We can't access it directly from here
}

void WaylandCompositor::handle_xdg_surface_commit(struct wl_listener *listener, void *data) {
    WaylandWindow *window = wl_container_of(listener, window, commit);
    struct wlr_surface *surface = static_cast<struct wlr_surface*>(data);

    // Update window size from the surface
    if (surface->current.width > 0 && surface->current.height > 0) {
        window->width = surface->current.width;
        window->height = surface->current.height;
    }
}

WaylandCompositor::WaylandCompositor() :
    wl_display(nullptr),
    wl_event_loop(nullptr),
    backend(nullptr),
    renderer(nullptr),
    allocator(nullptr),
    compositor(nullptr),
    xdg_shell(nullptr),
    next_window_id(1),
    initialized(false) {
}

WaylandCompositor::~WaylandCompositor() {
    cleanup();
}

void WaylandCompositor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize"), &WaylandCompositor::initialize);
    ClassDB::bind_method(D_METHOD("get_window_ids"), &WaylandCompositor::get_window_ids);
    ClassDB::bind_method(D_METHOD("get_window_buffer", "window_id"), &WaylandCompositor::get_window_buffer);
    ClassDB::bind_method(D_METHOD("get_window_size", "window_id"), &WaylandCompositor::get_window_size);
    ClassDB::bind_method(D_METHOD("get_socket_name"), &WaylandCompositor::get_socket_name);
    ClassDB::bind_method(D_METHOD("is_initialized"), &WaylandCompositor::is_initialized);
}

void WaylandCompositor::_ready() {
    UtilityFunctions::print("WaylandCompositor ready");
}

void WaylandCompositor::_process(double delta) {
    if (!initialized) {
        return;
    }

    // Process Wayland events (non-blocking)
    wl_event_loop_dispatch(wl_event_loop, 0);
    wl_display_flush_clients(wl_display);
}

void WaylandCompositor::_exit_tree() {
    cleanup();
}

bool WaylandCompositor::initialize() {
    if (initialized) {
        UtilityFunctions::print("WaylandCompositor already initialized");
        return true;
    }

    UtilityFunctions::print("Initializing WaylandCompositor...");

    // Set wlroots logging to errors only
    wlr_log_init(WLR_ERROR, nullptr);

    // Create Wayland display
    wl_display = wl_display_create();
    if (!wl_display) {
        UtilityFunctions::printerr("Failed to create Wayland display");
        return false;
    }

    wl_event_loop = wl_display_get_event_loop(wl_display);

    // Create headless backend
    backend = wlr_headless_backend_create(wl_display);
    if (!backend) {
        UtilityFunctions::printerr("Failed to create headless backend");
        cleanup();
        return false;
    }

    // Create renderer (use wrapper to avoid C99 syntax issues)
    renderer = wlr_renderer_autocreate_wrapper(backend);
    if (!renderer) {
        UtilityFunctions::printerr("Failed to create renderer");
        cleanup();
        return false;
    }

    wlr_renderer_init_wl_display_wrapper(renderer, wl_display);

    // Create allocator
    allocator = wlr_allocator_autocreate(backend, renderer);
    if (!allocator) {
        UtilityFunctions::printerr("Failed to create allocator");
        cleanup();
        return false;
    }

    // Create compositor
    compositor = wlr_compositor_create(wl_display, 5, renderer);
    if (!compositor) {
        UtilityFunctions::printerr("Failed to create compositor");
        cleanup();
        return false;
    }

    // Create subcompositor
    wlr_subcompositor_create(wl_display);

    // Create data device manager
    wlr_data_device_manager_create(wl_display);

    // Create XDG shell
    xdg_shell = wlr_xdg_shell_create(wl_display, 3);
    if (!xdg_shell) {
        UtilityFunctions::printerr("Failed to create XDG shell");
        cleanup();
        return false;
    }

    // Set up XDG shell listener
    new_xdg_surface.notify = handle_new_xdg_surface;
    wl_signal_add(&xdg_shell->events.new_surface, &new_xdg_surface);

    // Add Wayland socket
    const char *socket = wl_display_add_socket_auto(wl_display);
    if (!socket) {
        UtilityFunctions::printerr("Failed to add Wayland socket");
        cleanup();
        return false;
    }

    socket_name = String(socket);

    // Start the backend
    if (!wlr_backend_start(backend)) {
        UtilityFunctions::printerr("Failed to start backend");
        cleanup();
        return false;
    }

    initialized = true;
    UtilityFunctions::print("WaylandCompositor initialized successfully");
    UtilityFunctions::print("Wayland socket: ", socket_name);
    UtilityFunctions::print("Set WAYLAND_DISPLAY=", socket_name, " to connect clients");

    return true;
}

TypedArray<int> WaylandCompositor::get_window_ids() {
    TypedArray<int> ids;
    for (const auto &pair : windows) {
        ids.push_back(pair.first);
    }
    return ids;
}

Ref<Image> WaylandCompositor::get_window_buffer(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        UtilityFunctions::printerr("Window ID not found: ", window_id);
        return Ref<Image>();
    }

    WaylandWindow *window = it->second;
    struct wlr_surface *surface = window->toplevel->base->surface;

    if (!surface || !surface->buffer) {
        return Ref<Image>();
    }

    // In wlroots 0.17+, surface->buffer is wlr_client_buffer
    struct wlr_buffer *buffer = &surface->buffer->base;

    // For now, we'll handle SHM buffers
    // Get buffer data
    void *data;
    uint32_t format;
    size_t stride;

    // Try to begin data access
    if (!wlr_buffer_begin_data_ptr_access(buffer, WLR_BUFFER_DATA_PTR_ACCESS_READ,
                                          &data, &format, &stride)) {
        UtilityFunctions::printerr("Failed to access buffer data for window ", window_id);
        return Ref<Image>();
    }

    // Get dimensions
    int width = window->width;
    int height = window->height;

    if (width <= 0 || height <= 0) {
        wlr_buffer_end_data_ptr_access(buffer);
        return Ref<Image>();
    }

    // Create PackedByteArray for image data
    PackedByteArray image_data;
    image_data.resize(width * height * 4); // RGBA

    // Copy and convert buffer data to RGBA8
    uint8_t *src = static_cast<uint8_t*>(data);
    uint8_t *dst = image_data.ptrw();

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int src_offset = y * stride + x * 4;
            int dst_offset = (y * width + x) * 4;

            // Most Wayland surfaces use ARGB8888 or XRGB8888
            // We need to convert to RGBA8 for Godot
            uint8_t b = src[src_offset + 0];
            uint8_t g = src[src_offset + 1];
            uint8_t r = src[src_offset + 2];
            uint8_t a = src[src_offset + 3];

            dst[dst_offset + 0] = r;
            dst[dst_offset + 1] = g;
            dst[dst_offset + 2] = b;
            dst[dst_offset + 3] = a;
        }
    }

    wlr_buffer_end_data_ptr_access(buffer);

    // Create Godot Image
    Ref<Image> image = Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, image_data);

    return image;
}

Vector2i WaylandCompositor::get_window_size(int window_id) {
    auto it = windows.find(window_id);
    if (it == windows.end()) {
        return Vector2i(0, 0);
    }

    WaylandWindow *window = it->second;
    return Vector2i(window->width, window->height);
}

String WaylandCompositor::get_socket_name() {
    return socket_name;
}

bool WaylandCompositor::is_initialized() {
    return initialized;
}

void WaylandCompositor::cleanup() {
    if (!initialized) {
        return;
    }

    UtilityFunctions::print("Cleaning up WaylandCompositor...");

    // Clean up windows
    for (auto &pair : windows) {
        delete pair.second;
    }
    windows.clear();

    // Clean up wlroots structures
    if (xdg_shell) {
        wl_list_remove(&new_xdg_surface.link);
    }

    if (allocator) {
        wlr_allocator_destroy(allocator);
        allocator = nullptr;
    }

    if (renderer) {
        wlr_renderer_destroy_wrapper(renderer);
        renderer = nullptr;
    }

    if (backend) {
        wlr_backend_destroy(backend);
        backend = nullptr;
    }

    if (wl_display) {
        wl_display_destroy(wl_display);
        wl_display = nullptr;
    }

    initialized = false;
    UtilityFunctions::print("WaylandCompositor cleanup complete");
}
