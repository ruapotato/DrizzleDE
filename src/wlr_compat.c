// C wrapper for wlroots functions to avoid C99 syntax issues in C++
#define WLR_USE_UNSTABLE
#include <wlr/backend.h>
#include <wlr/backend/headless.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/allocator.h>

// Wrapper functions with C linkage
struct wlr_renderer *wlr_renderer_autocreate_wrapper(struct wlr_backend *backend) {
    return wlr_renderer_autocreate(backend);
}

void wlr_renderer_init_wl_display_wrapper(struct wlr_renderer *renderer, struct wl_display *display) {
    wlr_renderer_init_wl_display(renderer, display);
}

void wlr_renderer_destroy_wrapper(struct wlr_renderer *renderer) {
    wlr_renderer_destroy(renderer);
}
