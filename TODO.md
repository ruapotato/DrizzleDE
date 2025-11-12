# DrizzleDE: Dual-Mode Desktop Environment - Implementation TODO

## Vision Overview

Transform DrizzleDE into a usable daily-driver desktop environment with dual modes:

**3D Mode (Navigation/Overview):**
- Walk through file system as 3D rooms/hallways
- See files as interactive cubes
- See ALL windows in organized grid (always facing player)
- Click window → enter 2D mode with that window focused/fullscreen
- Minimized windows are hidden in 3D space

**2D Mode (Work/Desktop):**
- Traditional desktop environment
- Windows have title bars (close/minimize/maximize buttons)
- Drag, resize, snap to edges
- Fullscreen apps are properly fullscreen
- Configurable panels (top/bottom/side/removable)
- Button to enter 3D mode, ESC to exit back to 2D

**Key Design Principles:**
- 3D file navigation = killer feature (keep it!)
- 2D windows = usability (windows in 3D space were unusable)
- Folder navigation = workspace switching
- Use Godot UI for all desktop elements (panels, decorations, widgets)
- Use X11 only for rendering application window contents

## Current Progress

### ✅ Completed
- [x] ModeManager created (handles 3D ↔ 2D mode switching)
- [x] ESC key exits 3D mode → 2D mode
- [x] Player controls enable/disable based on mode
- [x] Mouse capture/release logic
- [x] Mode change signal system
- [x] Window2D class (2D window with decorations, drag, resize)
- [x] Window2DManager (manages all 2D windows, Z-order, focus)
- [x] Integration between Window2DManager and ModeManager
- [x] Phase 1: 2D Window Management - COMPLETE

### 🚧 In Progress
Phase 2: 3D Window Grid Organization (NEXT)

## Remaining Implementation Tasks

### Phase 1: 2D Window Management ✅ COMPLETED

#### 1.1 Create Window2D Class (Godot Control node) ✅
**File:** `shell/scripts/window_2d.gd`

**Features implemented:**
- [x] Title bar with window name
- [x] Close button (sends X11 close request)
- [x] Minimize button (hides window, marks as minimized)
- [x] Maximize button (expands to fill screen)
- [x] Fullscreen support (no decorations, covers entire viewport)
- [x] Drag by title bar
- [x] Resize by edges/corners (8 resize handles)
- [x] Double-click title bar to maximize/restore
- [x] Update X11 texture content every frame
- [x] Handle window close events from X11
- [x] Proper cursor shapes for resize handles
- [x] Minimum window size constraints
- [x] Save/restore pre-maximize state

#### 1.2 Create Window2DManager ✅
**File:** `shell/scripts/window_2d_manager.gd`

**Features implemented:**
- [x] Create Window2D nodes for each X11 window
- [x] Track window Z-order (front to back)
- [x] Click window to bring to front
- [x] Save/restore window positions between mode switches
- [x] Handle minimized windows (hide but preserve state)
- [x] Handle maximized windows (fill screen, save restore state)
- [x] Handle fullscreen windows (no decorations, cover viewport)
- [x] Destroy Window2D nodes when X11 window closes
- [x] Window cascading on spawn
- [x] Window list change signals
- [x] Focus management

**Features deferred:**
- [ ] Snap to screen edges when dragging (Phase 4)
- [ ] Snap to other windows (Phase 4)

#### 1.3 Integration with ModeManager ✅
**File:** `shell/scripts/mode_manager.gd`

**Changes completed:**
- [x] When switching to 2D mode: tell Window2DManager to show all windows
- [x] When switching to 3D mode: tell Window2DManager to save states and hide
- [x] Added `focus_window_and_enter_2d()` method for 3D window clicks
- [x] Save/restore window states via Window2DManager

### Phase 2: 3D Window Grid Organization

#### 2.1 Update WindowDisplay for Grid Layout
**File:** `shell/scripts/window_display.gd`

```gdscript
func organize_windows_3d():
    """Arrange windows in organized grid facing player"""
    # Grid layout parameters
    var grid_spacing = 3.0  # meters between windows
    var grid_columns = 4
    var grid_start_distance = 5.0  # meters from player

    # Get player position and forward direction
    # Calculate grid positions
    # Position each window quad in grid
    # Make all windows face player (billboard style)
    # Hide minimized windows
```

**Features to implement:**
- [ ] Grid layout algorithm (configurable columns)
- [ ] Position windows in front of player
- [ ] All windows face player (billboard rotation)
- [ ] Hide minimized windows in 3D space
- [ ] Click window → focus that window and enter 2D mode
- [ ] Highlight hovered window
- [ ] Show window title on hover (3D label)

#### 2.2 Window Click to Focus
**File:** `shell/scripts/window_interaction.gd`

**Changes needed:**
- [ ] In 3D mode: click window → call `mode_manager.focus_window_and_enter_2d(window_id)`
- [ ] Disable old 2D interaction mode (camera fly-to-window)
- [ ] Remove old ESC key handling (now handled by ModeManager)

### Phase 3: Panel System

#### 3.1 Create Panel Base Class
**File:** `shell/scripts/panel_base.gd`

```gdscript
extends Control
# Base class for desktop panels (top/bottom/sides)

enum PanelPosition { TOP, BOTTOM, LEFT, RIGHT }
enum PanelAlignment { START, CENTER, END, STRETCH }

@export var panel_position: PanelPosition = PanelPosition.BOTTOM
@export var panel_height: int = 48  # pixels
@export var panel_alignment: PanelAlignment = PanelAlignment.STRETCH

# Widgets (configurable list)
var widgets := []  # Array of Control nodes
```

**Features to implement:**
- [ ] Position panel at top/bottom/left/right
- [ ] Auto-resize based on orientation (height for horizontal, width for vertical)
- [ ] Add/remove widgets dynamically
- [ ] Save/load panel configuration (JSON or .tres)
- [ ] Drag to reorder widgets
- [ ] Right-click for panel settings menu

#### 3.2 Create Widget Base Class
**File:** `shell/scripts/widget_base.gd`

```gdscript
extends Control
# Base class for panel widgets (app launcher, taskbar, system monitor, etc.)

@export var widget_name: String = "Widget"
@export var min_width: int = 50
@export var preferred_width: int = 200
```

#### 3.3 Implement Core Widgets

**3.3.1 App Launcher Widget**
**File:** `shell/scripts/widgets/app_launcher_widget.gd`
- [ ] Button with icon (or "Applications" text)
- [ ] Click → show menu with all .desktop file apps
- [ ] Search/filter apps
- [ ] Launch app on click (using compositor)

**3.3.2 Taskbar Widget**
**File:** `shell/scripts/widgets/taskbar_widget.gd`
- [ ] Show button for each open window
- [ ] Window title + icon
- [ ] Click → focus window, bring to front
- [ ] Right-click → window menu (minimize/maximize/close)
- [ ] Highlight active window
- [ ] Group windows by application (optional)
- [ ] **Movable:** can be placed on any panel

**3.3.3 System Monitor Widget**
**File:** `shell/scripts/widgets/system_monitor_widget.gd`
- [ ] Display CPU usage (%)
- [ ] Display RAM usage (MB/GB, %)
- [ ] Display disk usage (GB, %)
- [ ] Display network usage (KB/s up/down)
- [ ] Click for detailed view (optional)
- [ ] Update every 1-2 seconds

**How to get system info:**
```gdscript
# CPU usage - read /proc/stat
# RAM usage - OS.get_static_memory_usage() / OS.get_static_memory_peak_usage()
# Or read /proc/meminfo
# Disk usage - DirAccess with get_space_left()
# Network - read /proc/net/dev
```

**3.3.4 Desktop Switcher Widget**
**File:** `shell/scripts/widgets/desktop_switcher_widget.gd`
- [ ] Show buttons for Home, Desktop, Documents, Pictures (default)
- [ ] Configurable: add custom folders
- [ ] Click folder → navigate to that folder in 3D space
- [ ] Highlight current folder
- [ ] Integration with FileSystemGenerator

### Phase 4: Configuration & Polish

#### 4.1 Settings/Config System
**File:** `shell/scripts/desktop_config.gd`

```gdscript
# Save/load desktop configuration:
# - Panel positions and sizes
# - Widget list and order for each panel
# - Desktop switcher custom folders
# - Window manager settings (snap distance, etc.)
# - Keybindings

# Config file: ~/.config/drizzle-de/desktop.json
```

- [ ] Create config directory structure
- [ ] Save config on change
- [ ] Load config on startup
- [ ] Apply config to panels/widgets/window manager

#### 4.2 UI Button to Enter 3D Mode
**File:** `shell/scripts/widgets/mode_switcher_widget.gd`
- [ ] Button on panel (default: top-right corner)
- [ ] Icon: 3D cube or "3D" text
- [ ] Click → call `mode_manager.switch_to_3d_mode()`

#### 4.3 Keyboard Shortcuts
**File:** `shell/scripts/keyboard_shortcuts.gd`
- [ ] Super/Meta key → open app launcher
- [ ] Super+D → show desktop (minimize all)
- [ ] Super+Number → switch to workspace/folder N
- [ ] Super+F → toggle fullscreen
- [ ] Alt+Tab → cycle windows
- [ ] Alt+F4 → close window

#### 4.4 Visual Polish
- [ ] Panel styling (background color, transparency, border)
- [ ] Window shadow effects
- [ ] Smooth animations for minimize/maximize
- [ ] Taskbar button highlight animations
- [ ] 3D window grid fade-in effect

### Phase 5: Window State Persistence

#### 5.1 Per-Workspace Windows
**File:** `shell/scripts/workspace_manager.gd`

```gdscript
# Each folder = a workspace
# Track which windows belong to which workspace
# When switching folders (3D navigation):
#   - Hide windows from old workspace
#   - Show windows from new workspace
#   - Respect minimized state

var workspace_windows := {}  # folder_path -> [window_ids]
```

- [ ] Associate windows with current folder when launched
- [ ] Save workspace associations to config
- [ ] Show/hide windows when switching workspaces
- [ ] Taskbar only shows current workspace windows (optional setting)

## Technical Considerations

### Window Rendering Strategy
- X11 windows render to textures (already working)
- In 2D mode: Display texture in Window2D's ContentContainer (TextureRect)
- In 3D mode: Display texture on 3D quad in grid (existing code, refactored)
- Same texture used for both modes

### State Synchronization
- ModeManager knows current mode
- Window2DManager knows 2D positions/states
- WindowDisplay knows 3D positions
- Both must respect minimized/maximized states
- Share window state through signals or direct calls

### Performance
- Only update textures for visible windows
- In 3D mode: still update all window textures (for grid preview)
- In 2D mode: only update textures for non-minimized windows
- Consider texture resolution reduction for 3D previews

### File System Integration
- FileSystemGenerator already handles folder navigation
- Desktop switcher widget needs to call `filesystem_generator.navigate_to(path)`
- Listen to FileSystemGenerator signals for current folder changes
- Update desktop switcher highlight when folder changes

## Testing Checklist

### Core Functionality
- [ ] Switch to 3D mode (button)
- [ ] Walk through file system in 3D
- [ ] See windows in grid
- [ ] Click window to focus and enter 2D mode
- [ ] ESC to exit to 2D mode
- [ ] Drag windows in 2D
- [ ] Resize windows in 2D
- [ ] Minimize/maximize/close windows
- [ ] Window state persists between mode switches
- [ ] Fullscreen apps work correctly

### Panel & Widgets
- [ ] Panels appear at configured positions
- [ ] App launcher shows apps and launches them
- [ ] Taskbar shows open windows
- [ ] Click taskbar button focuses window
- [ ] System monitor displays accurate data
- [ ] Desktop switcher navigates folders
- [ ] Desktop switcher highlights current folder

### Edge Cases
- [ ] Window closed in 3D mode → removed from 2D
- [ ] Window closed in 2D mode → removed from 3D grid
- [ ] Minimized window → hidden in 3D, present in taskbar
- [ ] Maximized window → fills screen in 2D, normal size in 3D
- [ ] Multiple workspaces → windows isolated per workspace
- [ ] Empty workspace → can still launch apps
- [ ] All windows minimized → desktop visible

## Future Enhancements (Out of Scope for Now)

- [ ] Virtual desktops (separate from folders)
- [ ] Multi-monitor support
- [ ] Window tiling layouts (i3/sway style)
- [ ] Desktop icons/widgets on background
- [ ] Notification system
- [ ] System tray
- [ ] Dock (like macOS)
- [ ] Themes/color schemes
- [ ] Compiz-style window effects
- [ ] VR support

## File Structure

```
shell/
├── scripts/
│   ├── mode_manager.gd          [✅ DONE]
│   ├── window_2d.gd             [TODO]
│   ├── window_2d_manager.gd     [TODO]
│   ├── panel_base.gd            [TODO]
│   ├── widget_base.gd           [TODO]
│   ├── workspace_manager.gd     [TODO]
│   ├── desktop_config.gd        [TODO]
│   ├── keyboard_shortcuts.gd    [TODO]
│   └── widgets/
│       ├── app_launcher_widget.gd     [TODO]
│       ├── taskbar_widget.gd          [TODO - refactor existing]
│       ├── system_monitor_widget.gd   [TODO]
│       ├── desktop_switcher_widget.gd [TODO]
│       └── mode_switcher_widget.gd    [TODO]
├── scenes/
│   └── main.tscn                [Modified - added ModeManager]
```

## Current Branch Status

**Branch:** main
**Last Commit:** (pending) - "Implement Phase 1: 2D Window Management"
**Next Task:** Implement Phase 2: 3D Window Grid Organization

## Instructions for Continuing

To continue this work in a fresh context:

1. Read this TODO.md file
2. Check current branch status: `git status` and `git log --oneline -5`
3. Look at the Phase numbers to see what's next
4. Implement tasks in order (Phase 1 → Phase 2 → Phase 3 → etc.)
5. Test each phase before moving to next
6. Update this file as tasks are completed (change `[ ]` to `[x]`)
7. Commit after each major feature/phase
8. Push regularly

**Quick Start:**
```bash
# Check what's done
git log --oneline | grep -i "mode\|window\|panel"

# Start next task
# Read Phase 1.1 above and implement Window2D class
```

---
*Last Updated: 2025-11-12*
*Status: Phase 1 complete - Ready for Phase 2*
