# Building System - Quick Start

## What's Fixed

1. **First-Person Controller** - Now uses proper CharacterBody3D with gravity and ground collision
   - Walk on the ground instead of flying
   - Jump with Space
   - Proper physics-based movement

2. **Build Mode Toggle** - B key now properly toggles build mode

## Controls

### Movement
- **WASD** - Walk around
- **Space** - Jump
- **Shift** - Sprint
- **Mouse** - Look around
- **ESC** - Release mouse (or exit build mode)

### Building
- **B** - Toggle build mode ON/OFF
- **Tab** - Show/hide building menu (when in build mode)
- **Q** - Cycle snap points (when snapped to existing pieces)
- **E** - Rotate building piece clockwise
- **Left Click** - Place piece
- **Right Click** - Remove piece
- **ESC** - Deselect current piece (ESC again to exit build mode)

## How to Use

1. **Start the game:**
   ```bash
   ./Godot_v4.4.1-stable_linux.x86_64
   ```

2. **Enter Build Mode:**
   - Press **B**
   - The building menu appears with categories on the left

3. **Select a Piece:**
   - Click a category (Foundation, Walls, Floors, Roofs, Support)
   - Click a building piece
   - Menu closes automatically

4. **Place Pieces:**
   - A preview appears where you're looking
   - **Green** = valid placement
   - **Red** = invalid placement
   - **You can look around freely** while holding a piece!
   - Press **E** to rotate clockwise (45° increments)
   - Pieces automatically snap to the 4 nearest corners of existing pieces
   - When snapped, press **Q** to cycle through the 4 corner options (just like Valheim!)
   - Click to place
   - **ESC** to deselect and choose a different piece

5. **Remove Pieces:**
   - Right-click on any placed piece to remove it

6. **Exit Build Mode:**
   - Press **B** or **ESC**

## Tips

- Start with foundations on the ground
- Walls snap to foundation edges
- Floors snap between walls
- Pieces automatically align to each other using snap points
- You can walk on placed floors/foundations

## Player Physics

The player now:
- Walks on solid ground (not flying)
- Has gravity
- Can jump
- Collides with placed building pieces
- Has proper first-person camera at eye level

Enjoy building your 3D workspace!
