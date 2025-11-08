# Scene Setup Guide

The scripts are ready, but they need to be added to your Godot scene to work!

## Adding Window Interaction

1. **Open `demo/scenes/main.tscn` in Godot**

2. **Add WindowInteraction Node**:
   - In the Scene panel, right-click on the root node (Main)
   - Select "Add Child Node"
   - Choose **Node3D**
   - Rename it to `WindowInteraction`
   - In the Inspector, click the script icon
   - Select `demo/scripts/window_interaction.gd`

3. **Configure WindowInteraction** (in Inspector):
   - `Camera Path`: Click and select your Camera3D node
   - `Compositor Path`: Click and select X11Compositor node
   - Leave other settings at default

4. **Update FPS Camera**:
   - Select your Camera3D node
   - In Inspector, set `Window Interaction Path` to the WindowInteraction node

5. **Add InventoryMenu** (if not already added):
   - Right-click root node → Add Child Node → **CanvasLayer**
   - Rename to `InventoryMenu`
   - Attach script: `demo/scripts/inventory_menu.gd`
   - Set `Compositor Path` to X11Compositor

## Expected Scene Structure

```
Main (Node3D)
├── Camera3D (fps_camera.gd attached)
│   └── window_interaction_path → WindowInteraction
├── X11Compositor (C++ GDExtension)
├── WindowDisplay (window_display.gd attached)
│   ├── compositor_path → X11Compositor
│   └── camera_path → Camera3D
├── WindowInteraction (window_interaction.gd attached) ← ADD THIS!
│   ├── camera_path → Camera3D
│   └── compositor_path → X11Compositor
└── InventoryMenu (CanvasLayer with inventory_menu.gd)
    └── compositor_path → X11Compositor
```

## Testing

Once added, you should see in the console:

```
WindowInteraction initialized!
  Camera: Camera3D:<Camera3D#...>
  Compositor: X11Compositor:<X11Compositor#...>
Mouse sphere created and visible
```

Then when you look at a window:
```
>>> HOVERING window 1: Mozilla Firefox [firefox]
    Hover for 0.5s then click to select
Window 1 ready to select (hovered 0.501s)
  Window ready to select - GREEN
```

## Visual Feedback

- **Red glowing sphere** = Your mouse cursor (always visible)
- **Subtle blue tint** = Hovering over window
- **Green tint** = Ready to click/select (after 0.5s)
- **Cyan glowing border** = Window selected, receiving input
- **Sphere pulse** = Click registered

## Controls

- Look at window for 0.5s → turns green
- **Click** = Select window
- **Type** = Goes to selected window
- **ESC** = Deselect, return to camera mode
- **I or Tab** = Open inventory menu

## Debug

If you don't see the red sphere or any interaction:
1. Check console for "WindowInteraction initialized!" message
2. Verify the node paths are set correctly
3. Make sure Camera3D and X11Compositor exist in scene
4. Check that window_interaction.gd is attached to a Node3D
