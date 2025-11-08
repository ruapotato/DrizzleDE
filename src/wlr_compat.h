// C wrapper header for wlroots - avoids C99 syntax issues in C++
#ifndef WLR_COMPAT_H
#define WLR_COMPAT_H

#ifdef __cplusplus
extern "C" {
#endif

struct wlr_renderer;
struct wlr_backend;
struct wl_display;

// Wrapper functions
struct wlr_renderer *wlr_renderer_autocreate_wrapper(struct wlr_backend *backend);
void wlr_renderer_init_wl_display_wrapper(struct wlr_renderer *renderer, struct wl_display *display);
void wlr_renderer_destroy_wrapper(struct wlr_renderer *renderer);

#ifdef __cplusplus
}
#endif

#endif // WLR_COMPAT_H
