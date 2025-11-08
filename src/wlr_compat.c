// C wrapper for wlroots functions to avoid C99 syntax issues in C++
#define WLR_USE_UNSTABLE
#include <wlr/backend.h>
#include <wlr/backend/headless.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/allocator.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/util/log.h>
#include <wayland-server-core.h>

// Logging
void wlr_log_init_wrapper(enum wlr_log_importance verbosity, wlr_log_func_t callback) {
    wlr_log_init(verbosity, callback);
}

// Display functions
struct wl_display *wl_display_create_wrapper(void) {
    return wl_display_create();
}

struct wl_event_loop *wl_display_get_event_loop_wrapper(struct wl_display *display) {
    return wl_display_get_event_loop(display);
}

const char *wl_display_add_socket_auto_wrapper(struct wl_display *display) {
    return wl_display_add_socket_auto(display);
}

void wl_display_destroy_wrapper(struct wl_display *display) {
    wl_display_destroy(display);
}

void wl_display_flush_clients_wrapper(struct wl_display *display) {
    wl_display_flush_clients(display);
}

// Event loop
int wl_event_loop_dispatch_wrapper(struct wl_event_loop *loop, int timeout) {
    return wl_event_loop_dispatch(loop, timeout);
}

// Backend
struct wlr_backend *wlr_headless_backend_create_wrapper(struct wl_display *display) {
    return wlr_headless_backend_create(display);
}

int wlr_backend_start_wrapper(struct wlr_backend *backend) {
    return wlr_backend_start(backend);
}

void wlr_backend_destroy_wrapper(struct wlr_backend *backend) {
    wlr_backend_destroy(backend);
}

// Renderer
struct wlr_renderer *wlr_renderer_autocreate_wrapper(struct wlr_backend *backend) {
    return wlr_renderer_autocreate(backend);
}

void wlr_renderer_init_wl_display_wrapper(struct wlr_renderer *renderer, struct wl_display *display) {
    wlr_renderer_init_wl_display(renderer, display);
}

void wlr_renderer_destroy_wrapper(struct wlr_renderer *renderer) {
    wlr_renderer_destroy(renderer);
}

// Allocator
struct wlr_allocator *wlr_allocator_autocreate_wrapper(struct wlr_backend *backend, struct wlr_renderer *renderer) {
    return wlr_allocator_autocreate(backend, renderer);
}

void wlr_allocator_destroy_wrapper(struct wlr_allocator *allocator) {
    wlr_allocator_destroy(allocator);
}

// Compositor
struct wlr_compositor *wlr_compositor_create_wrapper(struct wl_display *display, uint32_t version, struct wlr_renderer *renderer) {
    return wlr_compositor_create(display, version, renderer);
}

int wlr_subcompositor_create_wrapper(struct wl_display *display) {
    return wlr_subcompositor_create(display) != NULL;
}

// Data device
int wlr_data_device_manager_create_wrapper(struct wl_display *display) {
    return wlr_data_device_manager_create(display) != NULL;
}

// XDG Shell
struct wlr_xdg_shell *wlr_xdg_shell_create_wrapper(struct wl_display *display, uint32_t version) {
    return wlr_xdg_shell_create(display, version);
}

// XDG Surface accessors
enum wlr_xdg_surface_role wlr_xdg_surface_get_role_wrapper(struct wlr_xdg_surface *surface) {
    return surface->role;
}

struct wlr_xdg_toplevel *wlr_xdg_surface_get_toplevel_wrapper(struct wlr_xdg_surface *surface) {
    return surface->toplevel;
}

struct wl_signal *wlr_xdg_surface_get_destroy_signal_wrapper(struct wlr_xdg_surface *surface) {
    return &surface->events.destroy;
}

struct wlr_surface *wlr_xdg_surface_get_surface_wrapper(struct wlr_xdg_surface *surface) {
    return surface->surface;
}

// XDG Toplevel accessors
struct wlr_xdg_surface *wlr_xdg_toplevel_get_base_wrapper(struct wlr_xdg_toplevel *toplevel) {
    return toplevel->base;
}

// XDG Shell events
struct wl_signal *wlr_xdg_shell_get_new_surface_signal_wrapper(struct wlr_xdg_shell *shell) {
    return &shell->events.new_surface;
}

// Surface accessors
struct wl_signal *wlr_surface_get_map_signal_wrapper(struct wlr_surface *surface) {
    return &surface->events.map;
}

struct wl_signal *wlr_surface_get_unmap_signal_wrapper(struct wlr_surface *surface) {
    return &surface->events.unmap;
}

struct wl_signal *wlr_surface_get_commit_signal_wrapper(struct wlr_surface *surface) {
    return &surface->events.commit;
}

int wlr_surface_get_width_wrapper(struct wlr_surface *surface) {
    return surface->current.width;
}

int wlr_surface_get_height_wrapper(struct wlr_surface *surface) {
    return surface->current.height;
}

struct wlr_buffer *wlr_surface_get_buffer_wrapper(struct wlr_surface *surface) {
    if (!surface->buffer) {
        return NULL;
    }
    return &surface->buffer->base;
}

// Buffer access
int wlr_buffer_begin_data_ptr_access_wrapper(struct wlr_buffer *buffer, uint32_t flags,
    void **data, uint32_t *format, size_t *stride) {
    return wlr_buffer_begin_data_ptr_access(buffer, flags, data, format, stride);
}

void wlr_buffer_end_data_ptr_access_wrapper(struct wlr_buffer *buffer) {
    wlr_buffer_end_data_ptr_access(buffer);
}

// Signal/list management
void wl_signal_add_wrapper(struct wl_signal *signal, struct wl_listener *listener) {
    wl_signal_add(signal, listener);
}

void wl_list_remove_wrapper(struct wl_list *elm) {
    wl_list_remove(elm);
}

// Helper for container_of pattern
void *wl_container_of_wrapper(void *ptr, size_t offset) {
    return (char*)ptr - offset;
}
