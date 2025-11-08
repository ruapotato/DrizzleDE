#ifndef WAYLAND_COMPOSITOR_HPP
#define WAYLAND_COMPOSITOR_HPP

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>

// Forward declare C structures (in global namespace, outside of any extern "C")
struct wlr_backend;
struct wlr_renderer;
struct wlr_allocator;
struct wlr_compositor;
struct wlr_xdg_shell;
struct wlr_xdg_toplevel;
struct wl_display;
struct wl_event_loop;

extern "C" {
#include <wayland-server-core.h>
}

// Include our C wrapper for wlroots functions
#include "wlr_compat.h"

#include <vector>
#include <map>

namespace godot {

// Forward declarations for our internal structures
struct WaylandWindow {
    int id;
    ::wlr_xdg_toplevel *toplevel;  // Explicitly use global namespace
    int width;
    int height;

    ::wl_listener map;
    ::wl_listener unmap;
    ::wl_listener destroy;
    ::wl_listener commit;
};

class WaylandCompositor : public Node {
    GDCLASS(WaylandCompositor, Node)

private:
    // Wayland/wlroots core structures (use global namespace)
    ::wl_display *wl_display;
    ::wl_event_loop *wl_event_loop;
    ::wlr_backend *backend;
    ::wlr_renderer *renderer;
    ::wlr_allocator *allocator;
    ::wlr_compositor *compositor;
    ::wlr_xdg_shell *xdg_shell;

    // Listeners
    ::wl_listener new_xdg_surface;

    // Window tracking
    std::map<int, WaylandWindow*> windows;
    int next_window_id;

    // Initialization state
    bool initialized;
    String socket_name;

    // Helper methods
    void cleanup();
    static void handle_new_xdg_surface(struct wl_listener *listener, void *data);
    static void handle_xdg_toplevel_map(struct wl_listener *listener, void *data);
    static void handle_xdg_toplevel_unmap(struct wl_listener *listener, void *data);
    static void handle_xdg_toplevel_destroy(struct wl_listener *listener, void *data);
    static void handle_xdg_surface_commit(struct wl_listener *listener, void *data);

protected:
    static void _bind_methods();

public:
    WaylandCompositor();
    ~WaylandCompositor();

    // Godot lifecycle
    void _ready() override;
    void _process(double delta) override;
    void _exit_tree() override;

    // Public API exposed to GDScript
    bool initialize();
    TypedArray<int> get_window_ids();
    Ref<Image> get_window_buffer(int window_id);
    Vector2i get_window_size(int window_id);
    String get_socket_name();
    bool is_initialized();
};

} // namespace godot

#endif // WAYLAND_COMPOSITOR_HPP
