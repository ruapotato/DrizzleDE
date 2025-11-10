# DrizzleDE Building System

A Valheim-style building system for constructing your 3D workspace environment.

## Overview

The building system allows you to place and arrange building pieces (walls, floors, foundations, roofs, pillars) in 3D space to create your custom workspace layout. Windows can then be mounted to these surfaces.

## Controls

### Build Mode
- **B** - Toggle build mode on/off
- **ESC** - Exit build mode
- **Tab** - Toggle building piece menu (when in build mode)

### While Building
- **Left Click** - Place selected building piece
- **Right Click** - Remove building piece under cursor
- **Q** - Rotate piece counter-clockwise (45° increments)
- **E** - Rotate piece clockwise (45° increments)
- **WASD** - Move around
- **Mouse** - Look around and aim placement

### Visual Feedback
- **Green preview** - Valid placement location
- **Red preview** - Invalid placement location
- **Snap points** - Pieces automatically snap to nearby connection points

## Building Pieces

### Foundation
- **Foundation 2x2** - Base platform for structures
- Use foundations to create the ground level of your workspace

### Walls
- **Wall 2x2** - Vertical surfaces for window mounting
- Snap to foundations and other walls

### Floors
- **Floor 2x2** - Horizontal platforms
- Create multi-level workspaces

### Roofs
- **Roof 45°** - Angled roof pieces
- Snap to wall tops

### Support
- **Pillar** - Vertical support column
- Use to create tall structures

## Workflow

1. **Enter Build Mode**
   - Press **B** to enter build mode
   - The build menu appears showing categories and pieces

2. **Select a Piece**
   - Click a category (Foundation, Walls, Floors, etc.)
   - Click a building piece from the grid
   - The menu closes and a preview appears

3. **Place Pieces**
   - Move your mouse to position the preview
   - The preview turns green when placement is valid
   - Press **Q/E** to rotate if needed
   - Left click to place
   - The preview remains active for quick placement of multiple pieces

4. **Remove Pieces**
   - Right click on any placed piece to remove it

5. **Exit Build Mode**
   - Press **ESC** to exit build mode and return to normal navigation

## Snapping System

Building pieces have snap points that automatically connect to nearby pieces:

- **Foundations**: Snap to each other on all four sides
- **Walls**: Snap to foundation tops and wall sides
- **Floors**: Snap to wall tops and other floors
- **Roofs**: Snap to wall tops
- **Pillars**: Snap to foundations and floors

When placing a piece near a snap point, it will automatically align for perfect connections.

## File Structure

```
demo/building/
├── pieces/              # Building piece scene files
│   ├── foundation_2x2.tscn
│   ├── wall_2x2.tscn
│   ├── floor_2x2.tscn
│   ├── roof_45deg.tscn
│   └── pillar.tscn
├── scripts/
│   ├── building_piece.gd      # Base class for all pieces
│   ├── building_system.gd     # Main building system manager
│   └── building_ui.gd         # Building menu UI
└── scenes/
    └── building_ui.tscn       # UI scene
```

## Customizing Building Pieces

### Replacing Placeholder Meshes

The current building pieces use simple placeholder meshes (boxes, cylinders). To replace with custom models:

1. Open a building piece scene (e.g., `demo/building/pieces/wall_2x2.tscn`)
2. Replace the `MeshInstance3D` node's mesh with your custom mesh
3. Update the `CollisionShape3D` to match the new shape
4. Ensure snap points are positioned correctly for your new mesh

### Creating New Building Pieces

1. Create a new scene inheriting from `StaticBody3D`
2. Attach the `building_piece.gd` script
3. Add a `MeshInstance3D` child with your mesh
4. Add a `CollisionShape3D` child matching your mesh shape
5. Create a `SnapPoints` Node3D child
6. Add Node3D children to `SnapPoints` and add them to the "snap_point" group
7. Set the piece name and category in the script properties
8. Register the piece in `building_system.gd`'s `_register_building_pieces()` function

### Snap Point Guidelines

- Position snap points where you want pieces to connect
- Snap points should align with the surface normal
- Use consistent spacing (e.g., 1 unit = 1 meter)
- Add to "snap_point" group for automatic detection

## Integration with Window Mounting

(Future feature)

Once you've built structures, you'll be able to:
- Select a wall surface
- Mount X11 window to the surface
- Windows stay attached to the surface
- Save/load your entire workspace layout

## Saving and Loading

(Future feature)

The building system is designed to support:
- Saving entire workspace layouts to file
- Loading previously saved layouts
- Sharing layouts with other users

## Tips

- Start with foundations to establish your ground plane
- Build walls on top of foundations
- Use pillars for tall or cantilevered structures
- Place floors between walls to create levels
- Rotate pieces to create varied layouts
- The existing ground plane is temporary - build your own foundations

## Troubleshooting

**Preview piece doesn't appear**
- Make sure you're in build mode (press B)
- Select a piece from the menu (Tab to open)

**Can't place pieces**
- Preview must be green to place
- Ensure you're not too far away (10 meter range by default)
- Check for collisions with existing pieces

**Pieces won't snap**
- Move closer to snap points (within 0.1 units)
- Snap points are on edges and corners of pieces

**Mouse look doesn't work**
- Close the build menu (Tab) while in build mode
- Exit build mode completely (ESC) to return to normal controls
