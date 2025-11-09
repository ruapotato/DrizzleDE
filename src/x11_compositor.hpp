#ifndef X11_COMPOSITOR_HPP
#define X11_COMPOSITOR_HPP

// Include standard library headers FIRST
#include <map>
#include <vector>

// Include X11 headers BEFORE Godot to avoid name collision with godot::Window
#include <X11/Xlib.h>
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/Xdamage.h>
#include <X11/extensions/Xrender.h>
#include <X11/extensions/XTest.h>

// Typedef X11 types immediately after X11 headers, BEFORE Godot headers
typedef ::Window X11WindowHandle;
typedef ::Damage X11Damage;

// Now include Godot headers
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// Structure to track X11 windows
struct X11Window {
    int id;                          // Our internal ID
    X11WindowHandle xwindow;         // X11 window handle
    int width;
    int height;
    int x, y;                        // Window position
    X11Damage damage;                // Damage tracking
    bool mapped;                     // Is window currently mapped
    std::vector<uint8_t> image_data; // Cached window contents
    bool has_image;                  // Whether we have valid image data
    String wm_class;                 // Window class (application identifier)
    String wm_name;                  // Window title
    int pid;                         // Process ID
    int parent_window_id;            // Parent window ID (-1 if no parent)
};

class X11Compositor : public Node {
    GDCLASS(X11Compositor, Node)

private:
    // X11 connection and state
    Display *display;
    X11WindowHandle root_window;
    int screen;
    int display_number;  // Display number we're using (:1, :2, etc.)
    pid_t xephyr_pid;    // PID of our Xephyr process

    // Composite extension
    int composite_event_base;
    int composite_error_base;
    bool composite_available;

    // Damage extension
    int damage_event_base;
    int damage_error_base;
    bool damage_available;

    // XTest extension (for realistic input events)
    bool xtest_available;

    // Window tracking
    std::map<int, X11Window*> windows;
    std::map<unsigned long, int> xwindow_to_id;  // Reverse lookup (X11 Window is unsigned long)
    int next_window_id;

    // State
    bool initialized;

    // Helper methods
    void cleanup();
    int find_available_display();
    bool launch_xephyr(int display_num);
    void scan_existing_windows();
    void handle_create_notify(XCreateWindowEvent *event);
    void handle_destroy_notify(XDestroyWindowEvent *event);
    void handle_map_notify(XMapEvent *event);
    void handle_unmap_notify(XUnmapEvent *event);
    void handle_configure_notify(XConfigureEvent *event);
    void handle_damage_notify(XDamageNotifyEvent *event);
    void capture_window_contents(X11Window *window);
    void add_window(X11WindowHandle xwin);
    void remove_window(X11WindowHandle xwin);
    bool should_track_window(X11WindowHandle xwin);

protected:
    static void _bind_methods();

public:
    X11Compositor();
    ~X11Compositor();

    // Godot lifecycle
    void _ready() override;
    void _process(double delta) override;
    void _exit_tree() override;

    // Public API exposed to GDScript (matching old WaylandCompositor API)
    bool initialize();
    TypedArray<int> get_window_ids();
    Ref<Image> get_window_buffer(int window_id);
    Vector2i get_window_size(int window_id);
    String get_display_name();
    bool is_initialized();

    // Window properties for application grouping
    String get_window_class(int window_id);
    String get_window_title(int window_id);
    int get_window_pid(int window_id);
    int get_parent_window_id(int window_id);
    Vector2i get_window_position(int window_id);
    bool is_window_mapped(int window_id);

    // Input handling
    void send_mouse_button(int window_id, int button, bool pressed, int x, int y);
    void send_mouse_motion(int window_id, int x, int y);
    void send_key_event(int window_id, int keycode, bool pressed);
    void set_window_focus(int window_id);
    void release_all_keys();  // Release all currently pressed keys
};

} // namespace godot

#endif // X11_COMPOSITOR_HPP
