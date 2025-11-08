// C wrapper header for wlroots - avoids C99 syntax issues in C++
#ifndef WLR_COMPAT_H
#define WLR_COMPAT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declare all wlroots/wayland types we use
struct wlr_backend;
struct wlr_renderer;
struct wlr_allocator;
struct wlr_compositor;
struct wlr_xdg_shell;
struct wlr_xdg_surface;
struct wlr_xdg_toplevel;
struct wlr_surface;
struct wlr_buffer;
struct wl_display;
struct wl_event_loop;
struct wl_listener;
struct wl_signal;
struct wl_list;

// Enums
enum wlr_log_importance {
    WLR_SILENT = 0,
    WLR_ERROR = 1,
    WLR_INFO = 2,
    WLR_DEBUG = 3,
};

enum wlr_xdg_surface_role {
    WLR_XDG_SURFACE_ROLE_NONE = 0,
    WLR_XDG_SURFACE_ROLE_TOPLEVEL,
    WLR_XDG_SURFACE_ROLE_POPUP,
};

enum wlr_buffer_data_ptr_access_flag {
    WLR_BUFFER_DATA_PTR_ACCESS_READ = 1 << 0,
    WLR_BUFFER_DATA_PTR_ACCESS_WRITE = 1 << 1,
};

// Logging
typedef void (*wlr_log_func_t)(enum wlr_log_importance importance, const char *fmt, ...);
void wlr_log_init_wrapper(enum wlr_log_importance verbosity, wlr_log_func_t callback);

// Display functions
struct wl_display *wl_display_create_wrapper(void);
struct wl_event_loop *wl_display_get_event_loop_wrapper(struct wl_display *display);
const char *wl_display_add_socket_auto_wrapper(struct wl_display *display);
void wl_display_destroy_wrapper(struct wl_display *display);
void wl_display_flush_clients_wrapper(struct wl_display *display);

// Event loop
int wl_event_loop_dispatch_wrapper(struct wl_event_loop *loop, int timeout);

// Backend
struct wlr_backend *wlr_headless_backend_create_wrapper(struct wl_display *display);
int wlr_backend_start_wrapper(struct wlr_backend *backend);
void wlr_backend_destroy_wrapper(struct wlr_backend *backend);

// Renderer
struct wlr_renderer *wlr_renderer_autocreate_wrapper(struct wlr_backend *backend);
void wlr_renderer_init_wl_display_wrapper(struct wlr_renderer *renderer, struct wl_display *display);
void wlr_renderer_destroy_wrapper(struct wlr_renderer *renderer);

// Allocator
struct wlr_allocator *wlr_allocator_autocreate_wrapper(struct wlr_backend *backend, struct wlr_renderer *renderer);
void wlr_allocator_destroy_wrapper(struct wlr_allocator *allocator);

// Compositor
struct wlr_compositor *wlr_compositor_create_wrapper(struct wl_display *display, uint32_t version, struct wlr_renderer *renderer);
int wlr_subcompositor_create_wrapper(struct wl_display *display);

// Data device
int wlr_data_device_manager_create_wrapper(struct wl_display *display);

// XDG Shell
struct wlr_xdg_shell *wlr_xdg_shell_create_wrapper(struct wl_display *display, uint32_t version);

// XDG Surface accessors
enum wlr_xdg_surface_role wlr_xdg_surface_get_role_wrapper(struct wlr_xdg_surface *surface);
struct wlr_xdg_toplevel *wlr_xdg_surface_get_toplevel_wrapper(struct wlr_xdg_surface *surface);
struct wl_signal *wlr_xdg_surface_get_destroy_signal_wrapper(struct wlr_xdg_surface *surface);
struct wlr_surface *wlr_xdg_surface_get_surface_wrapper(struct wlr_xdg_surface *surface);

// XDG Toplevel accessors
struct wlr_xdg_surface *wlr_xdg_toplevel_get_base_wrapper(struct wlr_xdg_toplevel *toplevel);

// XDG Shell events
struct wl_signal *wlr_xdg_shell_get_new_surface_signal_wrapper(struct wlr_xdg_shell *shell);

// Surface accessors
struct wl_signal *wlr_surface_get_map_signal_wrapper(struct wlr_surface *surface);
struct wl_signal *wlr_surface_get_unmap_signal_wrapper(struct wlr_surface *surface);
struct wl_signal *wlr_surface_get_commit_signal_wrapper(struct wlr_surface *surface);
int wlr_surface_get_width_wrapper(struct wlr_surface *surface);
int wlr_surface_get_height_wrapper(struct wlr_surface *surface);
struct wlr_buffer *wlr_surface_get_buffer_wrapper(struct wlr_surface *surface);

// Buffer access
int wlr_buffer_begin_data_ptr_access_wrapper(struct wlr_buffer *buffer, uint32_t flags,
    void **data, uint32_t *format, size_t *stride);
void wlr_buffer_end_data_ptr_access_wrapper(struct wlr_buffer *buffer);

// Signal/list management
void wl_signal_add_wrapper(struct wl_signal *signal, struct wl_listener *listener);
void wl_list_remove_wrapper(struct wl_list *elm);

// Helper for container_of pattern
void *wl_container_of_wrapper(void *ptr, size_t offset);

#ifdef __cplusplus
}
#endif

#endif // WLR_COMPAT_H
