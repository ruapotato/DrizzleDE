extends Node

## Manages switching between 3D navigation mode and 2D desktop mode
##
## 3D Mode: Player walks through file system, sees window grid, can click to focus
## 2D Mode: Traditional desktop with panels, draggable windows, etc.

enum Mode { MODE_2D, MODE_3D }

signal mode_changed(new_mode: Mode)

var current_mode := Mode.MODE_2D  # Start in 2D mode
var player_controller: Node = null
var camera: Camera3D = null
var window_display: Node = null

# Store 2D window states when entering 3D mode
var window_2d_states := {}  # window_id -> {position: Vector2, size: Vector2, minimized: bool, maximized: bool}

func _ready():
	# Find required nodes
	player_controller = get_node_or_null("/root/Main/Player")
	camera = get_node_or_null("/root/Main/Player/Camera")
	window_display = get_node_or_null("/root/Main/WindowDisplay")

	print("ModeManager initialized")
	print("  Starting mode: ", "2D" if current_mode == Mode.MODE_2D else "3D")

func _input(event):
	# ESC key: Exit 3D mode → 2D mode
	if event.is_action_pressed("ui_cancel"):
		if current_mode == Mode.MODE_3D:
			switch_to_2d_mode()
			get_viewport().set_input_as_handled()

func switch_to_3d_mode():
	"""Enter 3D navigation mode - walk through files, see window grid"""
	if current_mode == Mode.MODE_3D:
		return  # Already in 3D mode

	print("═══════════════════════════════════")
	print("Switching to 3D MODE")
	print("═══════════════════════════════════")

	# Save current 2D window states
	save_2d_window_states()

	# Enable player controls
	if player_controller:
		player_controller.set_physics_process(true)
		player_controller.set_process_input(true)

	# Capture mouse for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Organize windows into 3D grid
	if window_display and window_display.has_method("organize_windows_3d"):
		window_display.organize_windows_3d()

	current_mode = Mode.MODE_3D
	mode_changed.emit(Mode.MODE_3D)

	print("  ✓ Player controls enabled")
	print("  ✓ Mouse captured")
	print("  ✓ Windows organized in 3D grid")

func switch_to_2d_mode():
	"""Exit to 2D desktop mode - traditional window management"""
	if current_mode == Mode.MODE_2D:
		return  # Already in 2D mode

	print("═══════════════════════════════════")
	print("Switching to 2D MODE")
	print("═══════════════════════════════════")

	# Release mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Disable player controls (can't walk in 2D mode)
	if player_controller:
		player_controller.set_physics_process(false)
		player_controller.set_process_input(false)

	# Restore windows to 2D positions
	if window_display and window_display.has_method("restore_windows_2d"):
		window_display.restore_windows_2d(window_2d_states)

	current_mode = Mode.MODE_2D
	mode_changed.emit(Mode.MODE_2D)

	print("  ✓ Mouse released")
	print("  ✓ Player controls disabled")
	print("  ✓ Windows restored to 2D")

func save_2d_window_states():
	"""Save window positions/states before entering 3D mode"""
	# TODO: Implement when we have 2D window manager
	window_2d_states.clear()
	print("  Saved 2D window states")

func is_3d_mode() -> bool:
	return current_mode == Mode.MODE_3D

func is_2d_mode() -> bool:
	return current_mode == Mode.MODE_2D
