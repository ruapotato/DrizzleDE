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
var window_2d_manager: Node = null

# Store 2D window states when entering 3D mode
var window_2d_states := {}  # window_id -> {position: Vector2, size: Vector2, minimized: bool, maximized: bool}

func _ready():
	# Find required nodes
	player_controller = get_node_or_null("/root/Main/Player")
	camera = get_node_or_null("/root/Main/Player/Camera")
	window_display = get_node_or_null("/root/Main/WindowDisplay")
	window_2d_manager = get_node_or_null("/root/Main/Window2DManager")

	print("ModeManager initialized")
	print("  Starting mode: ", "2D" if current_mode == Mode.MODE_2D else "3D")
	print("  Window2DManager found: ", window_2d_manager != null)

	# Ensure we start in clean 2D mode (wait a frame for everything to initialize)
	await get_tree().process_frame
	_initialize_2d_mode()

func _input(event):
	# ESC key: Exit 3D mode → 2D mode
	if event.is_action_pressed("ui_cancel"):
		if current_mode == Mode.MODE_3D:
			switch_to_2d_mode()
			get_viewport().set_input_as_handled()

	# In 3D mode, clicking should ensure mouse is captured
	if current_mode == Mode.MODE_3D:
		if event is InputEventMouseButton:
			var mb = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				# Ensure mouse is captured for camera movement
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
					print("  Re-captured mouse for 3D mode")

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
		# Sync mouse capture state
		player_controller.set_mouse_captured(true)

	# Capture mouse for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Force the window to grab focus to ensure input works
	get_viewport().get_window().grab_focus()

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
		# Sync mouse capture state
		player_controller.set_mouse_captured(false)

	# Restore windows to 2D positions
	if window_2d_manager and window_2d_states.size() > 0:
		window_2d_manager.restore_window_states(window_2d_states)

	current_mode = Mode.MODE_2D
	mode_changed.emit(Mode.MODE_2D)

	print("  ✓ Mouse released")
	print("  ✓ Player controls disabled")
	print("  ✓ Windows restored to 2D")

func save_2d_window_states():
	"""Save window positions/states before entering 3D mode"""
	if window_2d_manager:
		window_2d_states = window_2d_manager.save_window_states()
		print("  Saved ", window_2d_states.size(), " window states")
	else:
		window_2d_states.clear()
		print("  No Window2DManager - cleared window states")

func is_3d_mode() -> bool:
	return current_mode == Mode.MODE_3D

func is_2d_mode() -> bool:
	return current_mode == Mode.MODE_2D

func focus_window_and_enter_2d(window_id: int):
	"""Focus a specific window and switch to 2D mode"""
	# Switch to 2D mode first
	switch_to_2d_mode()

	# Focus the window
	if window_2d_manager:
		window_2d_manager.focus_window(window_id)

func _initialize_2d_mode():
	"""Ensure clean 2D mode state on startup"""
	print("  Initializing clean 2D mode...")

	# Disable player controls (use call_deferred to ensure it happens after player init)
	if player_controller:
		player_controller.call_deferred("set_physics_process", false)
		player_controller.call_deferred("set_process_input", false)
		print("    ✓ Player controls disabled")

	# Release mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("    ✓ Mouse released")

	# Hide all 3D window quads
	if window_display:
		for quad in window_display.window_quads.values():
			quad.visible = false
		print("    ✓ 3D quads hidden")

	# Verify state after a frame
	await get_tree().process_frame
	if player_controller:
		if player_controller.is_physics_processing() or player_controller.is_processing_input():
			print("    ⚠ Player controls still enabled, disabling again...")
			player_controller.set_physics_process(false)
			player_controller.set_process_input(false)
