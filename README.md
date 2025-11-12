# DrizzleDE - 3D Spatial Desktop Compositor

A 3D desktop compositor that renders X11 applications as textured quads in fully navigable 3D space using Xvfb (headless X virtual framebuffer).

## Vision

Transform your Linux desktop from a flat, constrained 2D plane into an infinite 3D workspace. Applications become physical objects mounted in space, and your workflow becomes architecture.

### Core Concept

- **Navigate Your File System**: Your file system becomes a 3D world - each directory is a circular room with files as cubes on the floor
- **Hallway Navigation**: Walk through physical hallways to enter subdirectories; each room shows subdirectories as tunnels extending from the room edge
- **Interactive Files**: Click file cubes to open them; click .desktop files to launch applications that appear as 3D windows in the current room
- **2D Window Mode**: Click any window to smoothly transition to comfortable 2D interaction mode with full mouse/keyboard support
- **Build Within Your World**: Place walls, floors, and structures within the auto-generated file system rooms using Valheim-style mechanics
- **First-Person Navigation**: Walk through your workspace with standard FPS controls (WASD, jump, sprint)

### Why This Matters

Traditional desktop environments constrain you to a single flat screen. Virtual desktops add workspaces, but switching between them is disorienting and context is lost.

With 3D spatial computing, you get:

- **Infinite screen real estate** - no more Alt+Tab hell
- **Spatial memory** - your brain naturally remembers where things are in 3D space
- **Contextual workflows** - physically separate work from communication from creative tasks
- **Visual organization** - see the relationships between applications in your workspace

## Technical Overview

Built on proven technologies:

- **X11 + Xvfb** - Headless X virtual framebuffer providing safe, isolated compositor environment
- **Godot 4** - Mature 3D engine with excellent performance and editor workflow
- **GDExtension** - Native C++ integration for compositor logic
- **X11 Composite Extension** - Window content capture without client cooperation

### Architecture

```
┌─────────────────────────────────────────┐
│    Your Desktop (X11 or Wayland)        │
│  ┌────────────────────────────────────┐ │
│  │  Godot 4 (DrizzleDE)               │ │
│  │  - 3D File system navigation       │ │
│  │  - First-person controller         │ │
│  │  - Valheim-style building system   │ │
│  │  - Window & file interaction       │ │
│  │                                    │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │  X11Compositor (GDExtension) │  │ │
│  │  │  - Xvfb management           │  │ │
│  │  │  - Window tracking           │  │ │
│  │  │  - Composite/Damage          │  │ │
│  │  │  ┌────────────────────────┐  │  │ │
│  │  │  │ Xvfb :1/:2 (headless)  │  │  │ │
│  │  │  │ ┌────────┐ ┌────────┐  │  │  │ │
│  │  │  │ │ xterm  │ │firefox │  │  │  │ │
│  │  │  │ └────────┘ └────────┘  │  │  │ │
│  │  │  │ Apps captured to 3D    │  │  │ │
│  │  │  └────────────────────────┘  │  │ │
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Benefits of Xvfb Approach

- **Headless**: No visible X server window cluttering your desktop
- **Safe**: Won't interfere with your existing X11/Wayland session
- **Portable**: Works in both X11 and Wayland host environments
- **Isolated**: Runs in its own sandboxed virtual X server
- **Compatible**: Works with all X11 applications

## Current Status

🚀 **Active Development** - File system navigation implemented, core features working!

- ✅ Project architecture defined
- ✅ GDExtension with X11/Xvfb integration
- ✅ Automatic Xvfb launching and management (headless operation)
- ✅ Window tracking and capture via Composite extension
- ✅ Multiple window rendering to 3D textures
- ✅ **Full input handling** (mouse/keyboard forwarding with XTest)
- ✅ **Spatial window management** (popups positioned relative to parents)
- ✅ **Interactive window selection** (raycast-based with hover/select states)
- ✅ **3D File System Navigation** (directories as rooms, files as interactive cubes)
- ✅ **File Interaction System** (open files, launch .desktop applications)
- ✅ **Valheim-style building system** (foundations, walls, floors, roofs, pillars)
- ✅ **First-person physics controller** (walk, jump, sprint with ground collision)
- ⬜ Window mounting to building surfaces
- ⬜ World save/load system
- ⬜ Polish and optimization

### Recent Achievements

#### File System Navigation
- **3D File System**: Your file system is now a navigable 3D world! Each directory is a circular room with:
  - Files displayed as color-coded 0.5m cubes (blue for code, purple for images, green for apps, etc.)
  - Subdirectories as hallways extending radially from room edges (like clock hands)
  - Room size auto-scales based on content (prevents hallway overlap)
  - Smart hallway transitions that seamlessly load adjacent rooms
- **Interactive Files**: Click files to open them (xdg-open), click .desktop files to launch apps in the 3D space
- **Room-Based Window Management**: Applications launched from a directory stay in that room

#### Window Interaction & Usability
- **2D Interaction Mode**: Click windows to enter comfortable 2D interaction mode
  - Camera smoothly flies to window and positions for optimal viewing
  - Windows billboard (auto-rotate) to always face you when idle
  - Gravity and movement disabled during interaction for stable use
  - Title bar shows window name with exit button
  - ESC or exit button to return to 3D navigation mode
- **Full Input Support**: Complete mouse and keyboard forwarding using XTest (bypasses Firefox's synthetic event detection)
- **Popup & Dialog Support**: Menus and dialogs positioned correctly, fully interactive edges with 2560x1440 Xvfb screen

#### Building & World
- **Valheim-Style Building**: Complete building system with snap mechanics, 5 piece types, and intuitive placement
- **First-Person Controller**: Physics-based walking with gravity, jumping, sprint, and proper ground collision

#### Technical Foundation
- **Project Restructuring**: Separated demo (minimal X11 example) from shell (full application)
- **Xvfb Integration**: Headless X server with automatic display management
- **X11 Composite**: Window content capture with Damage extension for efficiency

## Requirements

### System Requirements

- Linux system with X11 support
- Xvfb (X virtual framebuffer)
- OpenGL 3.3+ compatible GPU
- 4GB+ RAM recommended

### Dependencies

#### Fedora / RHEL

```bash
sudo dnf install scons gcc-c++ pkgconfig \
    xorg-x11-server-Xvfb \
    libX11-devel libXcomposite-devel libXdamage-devel \
    libXfixes-devel libXrender-devel libXtst-devel
```

#### Ubuntu / Debian

```bash
sudo apt install scons g++ pkg-config \
    xvfb \
    libx11-dev libxcomposite-dev libxdamage-dev \
    libxfixes-dev libxrender-dev libxtst-dev
```

#### Arch Linux

```bash
sudo pacman -S scons gcc pkgconf \
    xorg-server-xvfb \
    libx11 libxcomposite libxdamage libxfixes libxrender
```

### Godot 4

Download Godot 4.4+ from [godotengine.org](https://godotengine.org/download/linux/) or use the included binary.

## Building

### Quick Start

```bash
# Clone the repository
git clone https://github.com/ruapotato/DrizzleDE
cd DrizzleDE

# Initialize submodules
git submodule update --init --recursive

# Build (debug mode)
./build.sh

# Or build release mode
./build.sh template_release
```

### Manual Build

```bash
# Debug build
scons platform=linux target=template_debug -j$(nproc)

# Release build
scons platform=linux target=template_release -j$(nproc)
```

The build process will:
1. Compile godot-cpp bindings (takes 2-3 minutes on first build)
2. Compile the X11Compositor GDExtension
3. Output library to `addons/x11_compositor/bin/`

## Running

### Launch DrizzleDE

```bash
# Using the Godot executable in this directory
./Godot_v4.4.1-stable_linux.x86_64

# Or use your system Godot
godot4
```

Watch the console output for the display number:
```
Using display number: 1
Xvfb started successfully
Connected to Xvfb display: :1
```

Xvfb runs invisibly in the background (no visible window).

### Launch Applications

Launch applications directly into the Xvfb display:

```bash
# Check console output for the display number (e.g., :1, :2)
DISPLAY=:1 xterm &
DISPLAY=:1 xclock &
DISPLAY=:1 firefox &
```

Applications will appear as textured quads in the 3D environment!

### Controls

#### Movement (First-Person)
- **WASD** - Walk forward/left/backward/right
- **Space** - Jump
- **Shift** - Sprint
- **Mouse** - Look around
- **Escape** - Release mouse capture

#### Building System
- **B** - Toggle build mode on/off
- **Tab** - Show/hide building piece menu (in build mode)
- **Q** - Cycle through snap points (when snapped to structures)
- **E** - Rotate building piece (45° increments)
- **Left Click** - Place building piece
- **Right Click** - Remove building piece
- **ESC** - Deselect current piece / exit build mode

See [BUILDING_QUICKSTART.md](BUILDING_QUICKSTART.md) for detailed building system guide.

#### Window Interaction
- **Left click on window** - Enter 2D interaction mode (camera flies to window, enables comfortable mouse interaction)
- **In 2D mode**: Full mouse and keyboard input forwarded to window, popups and dialogs fully interactive
- **ESC or Exit button** - Exit 2D mode, return to 3D navigation
- **File cubes**: Left click to open files (xdg-open) or launch .desktop applications

#### Application Launcher
- **I key** - Toggle application menu (when no window selected)
- **Search box** - Filter applications by name/description
- **Click app** - Launch into Xvfb display
- **ESC** - Close menu
- Automatically discovers all installed applications from .desktop files

## Project Structure

```
DrizzleDE/
├── addons/
│   └── x11_compositor/
│       ├── bin/                     # Compiled GDExtension libraries
│       └── x11_compositor.gdextension
├── shell/                           # Main DrizzleDE application
│   ├── filesystem/                  # File system navigation
│   │   ├── filesystem_generator.gd  # Generates rooms from directories
│   │   ├── room_node.gd             # Directory room representation
│   │   └── file_cube.gd             # Interactive file cube
│   ├── building/                    # Building system
│   │   ├── pieces/                  # Building piece scenes
│   │   ├── scripts/                 # Building system scripts
│   │   └── scenes/                  # Building UI
│   ├── scenes/
│   │   ├── main.tscn                # Main 3D scene
│   │   └── inventory_menu.tscn      # Application launcher
│   └── scripts/
│       ├── player_controller.gd     # First-person controller
│       ├── window_display.gd        # X11 window display
│       └── window_interaction.gd    # Window & file interaction
├── demo/                            # Minimal X11 compositor demo
│   └── scripts/
│       └── window_display.gd        # Basic window rendering example
├── src/                             # C++ GDExtension source
│   ├── x11_compositor.hpp
│   ├── x11_compositor.cpp
│   ├── register_types.hpp
│   └── register_types.cpp
├── godot-cpp/                       # Godot C++ bindings (submodule)
├── build.sh                         # Build script
├── SConstruct                       # SCons build configuration
└── project.godot                    # Godot project file
```

## Development

### GDExtension API

The `X11Compositor` node exposes these methods to GDScript:

```gdscript
# Initialize the compositor (called automatically in _ready)
compositor.initialize() -> bool

# Get list of tracked window IDs
compositor.get_window_ids() -> Array[int]

# Get window buffer as Godot Image
compositor.get_window_buffer(window_id: int) -> Image

# Get window size
compositor.get_window_size(window_id: int) -> Vector2i

# Get display name (e.g. ":1")
compositor.get_display_name() -> String

# Check if initialized
compositor.is_initialized() -> bool
```

### Adding to Your Scene

```gdscript
extends Node3D

var compositor: Node

func _ready():
    compositor = get_node("/root/Main/X11Compositor")

    if compositor.is_initialized():
        print("Compositor ready: ", compositor.get_display_name())

func _process(delta):
    # Get window buffers and update textures
    for window_id in compositor.get_window_ids():
        var image = compositor.get_window_buffer(window_id)
        if image:
            # Create texture from image and display
            var texture = ImageTexture.create_from_image(image)
            # ... use texture on 3D quad
```

## Troubleshooting

### Build Issues

**Error: X11 libraries not found**
```bash
# Check if X11 development libraries are installed
pkg-config --modversion x11 xcomposite xdamage

# If not, install according to your distribution (see Dependencies above)
```

**Error: godot-cpp not found**
```bash
# Initialize submodules
git submodule update --init --recursive
```

### Runtime Issues

**Xvfb not found**
```bash
# Check if Xvfb is installed
which Xvfb

# Install if missing (see Dependencies above)
```

**"No available X11 display numbers found"**
```bash
# Check for stuck X lock files
ls -la /tmp/.X11-unix/
ls -la /tmp/.X*-lock

# Remove stale locks (be careful!)
sudo rm /tmp/.X11-unix/X1  # Only if you're sure it's stale
```

**Apps don't appear**
- Verify the display number from Godot console
- Use exact display number when launching apps
- Test with simple app: `DISPLAY=:1 xclock`

**Window textures are black**
- Wait a moment for windows to be captured
- Check Godot console for capture errors
- Ensure Composite extension is available in Xvfb (enabled by default)

## Philosophy

This isn't VR (though it could support that). This is about reimagining desktop computing for the age of infinite computing resources. Why are we still constrained by metaphors from the 1980s?

Your workspace should be:

- **Unlimited** - no artificial constraints on screen space
- **Customizable** - you build it, you own it
- **Intuitive** - leverage spatial memory and 3D navigation
- **Personal** - reflects how YOU work, not someone else's workflow assumptions

## Goals

- **Practical First**: Must be genuinely useful for daily computing, not just a tech demo
- **Performant**: Smooth, responsive, efficient (targeting 60+ FPS)
- **Compatible**: Works with existing X11 applications (no special client support needed)
- **Hackable**: Open source, well-documented, extensible
- **Beautiful**: Visually compelling with customizable aesthetics

## Inspiration

- **Valheim/Minecraft**: Building mechanics and creative freedom
- **Tiling WMs (i3, Sway)**: Keyboard-driven efficiency
- **Vision Pro**: Spatial computing concept (but accessible on any Linux desktop)
- **Compiz**: The golden age of 3D desktop effects

## Contributing

This project is in early stages. Contributions, ideas, and feedback welcome!

### Areas for Contribution

- Window mounting to building surfaces (attach windows to walls/floors)
- World save/load system (persist workspace layouts)
- Custom building piece meshes (replace placeholder boxes)
- Optimized window capture using XComposite and XDamage
- Window management (focus, stacking, virtual desktops)
- Multi-monitor support
- VR headset support
- Documentation and tutorials

## License

See [LICENSE](LICENSE) for details.

## Acknowledgments

- **X.Org** - The foundation of Linux desktop graphics
- **Godot** - Powerful and accessible 3D engine
- **X11 Composite Extension** - Enabling window content capture
- **Xvfb** - Headless X virtual framebuffer for isolated operation
- The Compiz and other X11 compositor communities

---

> "Your desktop environment should be a space you inhabit, not a screen you stare at."
