# DrizzleDE - Build Completion Guide

## Current Status

The C wrapper approach is working, but requires converting ALL struct member accesses in `wayland_compositor.cpp` to use wrapper functions.

## What's Done

✅ Complete C wrapper (`wlr_compat.c/h`) with all needed wlroots functions
✅ C++ code no longer includes wlroots headers directly
✅ Wrapper functions compile successfully

## What Needs Fixing

Replace all direct struct accesses in `src/wayland_compositor.cpp` with wrapper function calls.

### Pattern to Follow

**Before (direct access - CAUSES ERRORS):**
```cpp
if (xdg_surface->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
    return;
}
window->toplevel = xdg_surface->toplevel;
wl_signal_add(&xdg_surface->surface->events.map, &window->map);
```

**After (use wrappers - WORKS):**
```cpp
if (wlr_xdg_surface_get_role_wrapper(xdg_surface) != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
    return;
}
window->toplevel = wlr_xdg_surface_get_toplevel_wrapper(xdg_surface);
struct wlr_surface *surface = wlr_xdg_surface_get_surface_wrapper(xdg_surface);
wl_signal_add_wrapper(wlr_surface_get_map_signal_wrapper(surface), &window->map);
```

### Required Changes in `wayland_compositor.cpp`

Line numbers from recent build errors:

1. **Line 23**: `xdg_surface->role` → `wlr_xdg_surface_get_role_wrapper(xdg_surface)`

2. **Line 30**: `xdg_surface->toplevel` → `wlr_xdg_surface_get_toplevel_wrapper(xdg_surface)`

3. **Lines 36,39,42,45**: Replace signal accesses:
   ```cpp
   // Get surface first
   struct wlr_surface *surface = wlr_xdg_surface_get_surface_wrapper(xdg_surface);

   // Then use signal wrappers
   wl_signal_add_wrapper(wlr_surface_get_map_signal_wrapper(surface), &window->map);
   wl_signal_add_wrapper(wlr_surface_get_unmap_signal_wrapper(surface), &window->unmap);
   wl_signal_add_wrapper(wlr_xdg_surface_get_destroy_signal_wrapper(xdg_surface), &window->destroy);
   wl_signal_add_wrapper(wlr_surface_get_commit_signal_wrapper(surface), &window->commit);
   ```

4. **Lines 64-65, 81-83**: Surface dimension access:
   ```cpp
   int width = wlr_surface_get_width_wrapper(surface);
   int height = wlr_surface_get_height_wrapper(surface);
   ```

5. **Line 139**: `wlr_log_init` → `wlr_log_init_wrapper`

6. **Line 125-131**: Display functions already have wrappers, replace:
   ```cpp
   wl_display = wl_display_create_wrapper();
   wl_event_loop = wl_display_get_event_loop_wrapper(wl_display);
   ```

7. **Line 134**: `wlr_headless_backend_create` → `wlr_headless_backend_create_wrapper`

8. **Line 152**: `wlr_allocator_autocreate` → `wlr_allocator_autocreate_wrapper`

9. **Line 160**: `wlr_compositor_create` → `wlr_compositor_create_wrapper`

10. **Lines 168, 171**: `wlr_subcompositor_create` → `wlr_subcompositor_create_wrapper`, etc.

11. **Line 174**: `wlr_xdg_shell_create` → `wlr_xdg_shell_create_wrapper`

12. **Line 183**: `&xdg_shell->events.new_surface` → `wlr_xdg_shell_get_new_surface_signal_wrapper(xdg_shell)`

13. **Line 186**: `wl_display_add_socket_auto` → `wl_display_add_socket_auto_wrapper`

14. **Line 196**: `wlr_backend_start` → `wlr_backend_start_wrapper`

15. **Line 226**: `window->toplevel->base->surface` →
    ```cpp
    struct wlr_xdg_surface *base = wlr_xdg_toplevel_get_base_wrapper(window->toplevel);
    struct wlr_surface *surface = wlr_xdg_surface_get_surface_wrapper(base);
    ```

16. **Line 228-233**: Surface/buffer access:
    ```cpp
    struct wlr_buffer *buffer = wlr_surface_get_buffer_wrapper(surface);
    if (!surface || !buffer) {
        return Ref<Image>();
    }
    ```

17. **Lines 242, 253, 284**: `wlr_buffer_*` → `wlr_buffer_*_wrapper`

18. **Lines 325, 329, 339, 344**: List/signal/destroy functions:
    ```cpp
    wl_list_remove_wrapper(&new_xdg_surface.link);
    wlr_allocator_destroy_wrapper(allocator);
    wlr_backend_destroy_wrapper(backend);
    wl_display_destroy_wrapper(wl_display);
    ```

19. **Lines 67-70**: `wl_list_remove` → `wl_list_remove_wrapper`

20. **Lines 105-106**: Event loop wrappers:
    ```cpp
    wl_event_loop_dispatch_wrapper(wl_event_loop, 0);
    wl_display_flush_clients_wrapper(wl_display);
    ```

21. **Line 20**: `wl_container_of` → needs special handling (see below)

### Special Case: wl_container_of

The `wl_container_of` macro needs to be replaced with:
```cpp
// Calculate offset
size_t offset = offsetof(WaylandCompositor, new_xdg_surface);
WaylandCompositor *comp = static_cast<WaylandCompositor*>(
    wl_container_of_wrapper(listener, offset)
);
```

Or simpler - for each listener callback, manually calculate and use the offset.

## Alternative: Semi-Automated Fix

Create a search-and-replace script:

```bash
#!/bin/bash
# Replace common patterns
sed -i 's/wlr_log_init(/wlr_log_init_wrapper(/g' src/wayland_compositor.cpp
sed -i 's/wl_display_create(/wl_display_create_wrapper(/g' src/wayland_compositor.cpp
sed -i 's/wl_display_get_event_loop(/wl_display_get_event_loop_wrapper(/g' src/wayland_compositor.cpp
# ... etc for all functions
```

## Easiest Alternative

Instead of this massive refactor, consider:

### Option A: Use wlroots 0.16
```bash
sudo dnf remove wlroots-devel
# Download and install wlroots 0.16 which doesn't have C99 VLA syntax
```

### Option B: Patch wlroots Headers Locally
```bash
# Remove [static N] from headers
sudo sed -i 's/\[static [0-9]*\]/\[\]/g' /usr/include/wlr/render/wlr_renderer.h
```

### Option C: Two-Process Architecture
Run compositor as separate C process, communicate via shared memory/Unix sockets with Godot GDExtension.

## Recommendation

Given the tedious nature of this refactoring, I recommend **Option B** (patch headers) for quick testing, then proper wrapper completion for production.

The wrapper approach is architecturally sound and will work long-term, but requires methodically replacing ~50+ struct accesses.
