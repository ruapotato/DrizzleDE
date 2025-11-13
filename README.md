# DrizzleDE - 3D Spatial Desktop Compositor

A 3D desktop compositor that renders X11 applications as textured quads in fully navigable 3D space using Xvfb (headless X virtual framebuffer).

## Vision

Transform your Linux desktop from a flat, constrained 2D plane into an infinite 3D workspace. Applications become physical objects mounted in space, and your workflow becomes architecture.

### Core Concept

- **Dual-Mode Interface**: Seamlessly switch between 3D spatial navigation and traditional 2D desktop mode
- **Navigate Your File System**: Your file system becomes a 3D world - each directory is a circular room with files as cubes on the floor
- **Hallway Navigation**: Walk through physical hallways to enter subdirectories; each room shows subdirectories as tunnels extending from the room edge
- **Interactive Files**: Click file cubes to open them; click .desktop files to launch applications that appear as 3D windows in the current room
- **Directory-Scoped Windows**: Applications are scoped to the directory where they were launched - switch directories to switch contexts
- **2D Desktop Mode**: Full-featured traditional desktop with customizable panels, widgets, and window management
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

🚀 **Active Development** - Dual-mode 3D/2D desktop environment with full window management!

### Core Systems ✅
- ✅ GDExtension with X11/Xvfb integration
- ✅ Automatic Xvfb launching and management (headless operation)
- ✅ Window tracking and capture via Composite extension
- ✅ **Full input handling** (mouse/keyboard/keypad forwarding with XTest)

### 3D Spatial Mode ✅
- ✅ **3D File System Navigation** (directories as rooms, files as interactive cubes)
- ✅ **File Interaction System** (open files, launch .desktop applications)
- ✅ **Valheim-style building system** (foundations, walls, floors, roofs, pillars)
- ✅ **First-person physics controller** (walk, jump, sprint with ground collision)
- ✅ **Spatial window management** (popups positioned relative to parents)
- ✅ **Interactive window selection** (raycast-based with hover/select states)

### 2D Desktop Mode ✅
- ✅ **Customizable Panel System** (top/bottom/left/right panels with dynamic widgets)
- ✅ **Directory-Scoped Windows** (applications only appear in their launch directory)
- ✅ **Widget System** (app launcher, taskbar, desktop switcher, system monitor, mode switcher)
- ✅ **Right-Click Menus** (add/remove widgets and panels on the fly)
- ✅ **Window Management** (dragging, resizing, minimize/maximize/close)
- ✅ **System Monitor** (real-time CPU, RAM, disk, network graphs)

### In Progress ⏳
- ⬜ Window mounting to building surfaces
- ⬜ World save/load system
- ⬜ Panel/widget configuration persistence
- ⬜ Polish and optimization

### Recent Achievements

#### 2D Desktop Mode (NEW!)
- **Dual-Mode Interface**: Seamlessly switch between 3D spatial mode and traditional 2D desktop
  - Click "2D Mode" button or press M to enter 2D desktop mode
  - Full window management with dragging, resizing, minimize/maximize/close
  - Directory-aware: applications are scoped to their launch directory
- **Customizable Panel System**: MATE-like panel system with dynamic widget management
  - Top panel: App launcher, system monitor, mode switcher (default)
  - Bottom panel: Taskbar, desktop switcher (default)
  - Right-click panels to add/remove widgets or create new panels
  - Supports top, bottom, left, and right panel positions
- **Rich Widget System**:
  - **App Launcher**: Full application menu with search (discovers all .desktop files)
  - **Taskbar**: Shows open windows with click-to-focus (directory-filtered)
  - **Desktop Switcher**: Quick navigation between Home, Desktop, Documents, Downloads, Pictures, Videos
  - **System Monitor**: Real-time graphs for CPU, RAM, disk usage, and network activity
  - **Mode Switcher**: Toggle between 2D and 3D modes
- **Directory-Scoped Workflows**: Each directory acts as a separate workspace
  - Launch apps in Home → they only appear when viewing Home directory
  - Switch to Documents → see only apps launched in Documents
  - Perfect for separating work contexts without virtual desktops

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

#### Mode Switching
- **M key** - Toggle between 2D and 3D modes
- **Mode Switcher widget** - Click to switch modes (in 2D mode)

#### 2D Desktop Mode
- **Mouse** - Click, drag, interact with windows and widgets
- **Left click on window title bar** - Drag window
- **Left click on window edges/corners** - Resize window
- **Window buttons** - Minimize, maximize, close
- **Right click on panel** - Show panel menu (add widgets, add panels)
- **Right click on widget** - Show widget menu (move, remove)
- **Desktop Switcher** - Click directory buttons to switch workspaces
- **Taskbar** - Click window button to focus that window

#### Movement (3D Mode / First-Person)
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
│       ├── window_display.gd        # X11 window display (3D mode)
│       ├── window_interaction.gd    # Window & file interaction (3D mode)
│       ├── window_2d.gd             # 2D window with title bar and controls
│       ├── window_2d_manager.gd     # 2D window management
│       ├── panel_base.gd            # Base class for desktop panels
│       ├── panel_manager.gd         # Panel system manager
│       ├── widget_base.gd           # Base class for panel widgets
│       └── widgets/                 # Panel widgets
│           ├── app_launcher_widget.gd      # Application menu
│           ├── taskbar_widget.gd           # Window list
│           ├── desktop_switcher_widget.gd  # Directory switcher
│           ├── system_monitor_widget.gd    # Resource graphs
│           └── mode_switcher_widget.gd     # 2D/3D toggle
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
