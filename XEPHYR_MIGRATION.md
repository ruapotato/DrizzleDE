# DrizzleDE X11/Xephyr Migration Guide

## What Changed

DrizzleDE has been successfully migrated from a Wayland-based compositor to an **X11-based compositor using Xephyr** (nested X server). This approach provides several key benefits:

### ✅ Benefits

1. **Safe**: Won't interfere with your existing X11/Wayland session
2. **Portable**: Works in both X11 and Wayland host sessions
3. **Isolated**: Runs in its own sandboxed X server
4. **Compatible**: Works with all X11 applications

## Architecture

```
┌─────────────────────────────────────────┐
│    Your Desktop (X11 or Wayland)        │
│  ┌────────────────────────────────────┐ │
│  │  Godot (DrizzleDE) running         │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │  Xephyr :1 (nested X server) │  │ │
│  │  │  ┌────────┐  ┌────────┐      │  │ │
│  │  │  │ xterm  │  │firefox │      │  │ │
│  │  │  └────────┘  └────────┘      │  │ │
│  │  │  Captured & rendered in 3D   │  │ │
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## How It Works

1. **Startup**: When DrizzleDE initializes:
   - Finds an available display number (`:1`, `:2`, etc.)
   - Launches Xephyr on that display
   - Connects to it using X11 Composite extension
   - Shows Xephyr window (1280x720 by default)

2. **Running Apps**: Applications launched with the correct `DISPLAY` variable:
   - Appear in the Xephyr window
   - Are captured by the compositor
   - Rendered as 3D textured quads in Godot

3. **Cleanup**: When DrizzleDE closes:
   - Gracefully terminates Xephyr
   - Cleans up all windows

## Building

The project has been updated to use X11 libraries instead of wlroots:

```bash
# Install dependencies (if not already installed)
sudo dnf install xorg-x11-server-Xephyr  # Fedora
# OR
sudo apt install xserver-xephyr           # Ubuntu

# Build
./build.sh

# Or manual build
scons platform=linux target=template_debug -j4
```

## Running

### 1. Start DrizzleDE

```bash
./Godot_v4.4.1-stable_linux.x86_64
# OR
godot4
```

Watch the console output for the display number:
```
Using display number: 1
Xephyr started successfully
Connected to Xephyr display: :1
```

### 2. Launch Applications

In a separate terminal, use the helper script:

```bash
# Basic usage
./launch_app.sh :1 xterm

# Launch more apps
./launch_app.sh :1 xclock
./launch_app.sh :1 firefox
```

Or manually:
```bash
DISPLAY=:1 xterm &
DISPLAY=:1 firefox &
```

### 3. View in 3D

Applications will appear as textured quads in the 3D environment. Navigate using:
- **WASD**: Move
- **Space/Shift**: Up/Down
- **Mouse**: Look around
- **Esc**: Toggle mouse capture

## Key Changes from Wayland Version

| Aspect | Old (Wayland) | New (X11/Xephyr) |
|--------|---------------|------------------|
| Backend | wlroots | X11 + Xephyr |
| Display | Creates Wayland socket | Launches nested X server |
| App Launch | `WAYLAND_DISPLAY=wayland-1` | `DISPLAY=:1` |
| Compatibility | Wayland apps only | All X11 apps |
| Safety | Could interfere with WM | Completely isolated |
| Nesting | Only in Wayland | Works in X11 or Wayland |

## Dependencies

### Required
- **Xephyr**: Nested X server
- **libX11**: X11 client library
- **libXcomposite**: Composite extension
- **libXdamage**: Damage tracking
- **libXfixes**: X fixes extension
- **libXrender**: X rendering extension

### Install Commands

**Fedora/RHEL:**
```bash
sudo dnf install xorg-x11-server-Xephyr \
    libX11-devel libXcomposite-devel libXdamage-devel \
    libXfixes-devel libXrender-devel
```

**Ubuntu/Debian:**
```bash
sudo apt install xserver-xephyr \
    libx11-dev libxcomposite-dev libxdamage-dev \
    libxfixes-dev libxrender-dev
```

**Arch Linux:**
```bash
sudo pacman -S xorg-server-xephyr \
    libx11 libxcomposite libxdamage libxfixes libxrender
```

## API Changes

The `X11Compositor` class maintains API compatibility with the old `WaylandCompositor`:

```gdscript
# These methods work the same
compositor.initialize() -> bool
compositor.get_window_ids() -> Array[int]
compositor.get_window_buffer(window_id) -> Image
compositor.get_window_size(window_id) -> Vector2i
compositor.is_initialized() -> bool

# Changed method
compositor.get_display_name() -> String  # Returns ":1" instead of "wayland-1"
```

## Troubleshooting

### Xephyr not found
```bash
# Check if Xephyr is installed
which Xephyr

# Install if missing (see Dependencies above)
```

### "No available X11 display numbers found"
```
# Check for stuck X lock files
ls -la /tmp/.X11-unix/
ls -la /tmp/.X*-lock

# Remove stale locks (be careful!)
sudo rm /tmp/.X11-unix/X1  # Only if you're sure it's stale
```

### Apps don't appear
```bash
# Verify the display number from Godot console
# Use exact display number when launching apps

# Test with simple app
DISPLAY=:1 xclock
```

### "Failed to launch Xephyr"
- Check Xephyr is executable: `ls -l $(which Xephyr)`
- Check permissions
- Try running Xephyr manually: `Xephyr :99 -screen 800x600`

## Technical Details

### Window Capture Process

1. **Composite Redirection**: All windows render to off-screen buffers
2. **Damage Tracking**: Only re-capture when window content changes
3. **XGetImage**: Capture pixel data from window pixmaps
4. **Format Conversion**: Convert BGRA → RGBA for Godot
5. **Texture Upload**: Create ImageTexture and apply to 3D quad

### Performance Notes

- Xephyr runs at 1280x720 by default (configurable)
- Window capture happens on-demand (when damaged)
- Efficient change tracking via XDamage extension
- No unnecessary redraws

## Future Enhancements

- [ ] Configurable Xephyr resolution
- [ ] Multiple nested servers
- [ ] Input forwarding (mouse/keyboard to 3D windows)
- [ ] Window decorations in 3D
- [ ] DMA-BUF zero-copy (advanced)

## Files Modified

- `src/x11_compositor.{hpp,cpp}` - New X11-based compositor
- `src/register_types.cpp` - Updated GDExtension registration
- `demo/scripts/window_display.gd` - Updated for X11Compositor
- `demo/scenes/main.tscn` - Uses X11Compositor node
- `SConstruct` - Updated build dependencies
- `addons/x11_compositor/` - New addon directory

## Migration Complete! 🎉

Your DrizzleDE now runs as a safe, portable nested X compositor that works in any environment!
