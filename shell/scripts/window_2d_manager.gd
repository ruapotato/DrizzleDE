extends CanvasLayer

## Manages all 2D windows in desktop mode
##
## This manager creates Window2D nodes for each X11 window,
## handles Z-order (stacking), window focus, and desktop features
## like snap-to-edges and window positioning.

signal window_list_changed()

@export var compositor_path: NodePath
@export var mode_manager_path: NodePath

# Snap behavior
@export var snap_distance := 20  # pixels
@export var snap_to_edges := true
@export var snap_to_other_windows := false

var compositor: Node = null
var mode_manager: Node = null

# Window management
var window_2d_nodes := {}  # window_id -> Window2D
var window_z_order := []   # Array of window_ids, front to back

# Window2D scene to instantiate
var Window2DScene = preload("res://shell/scripts/window_2d.gd")

# Container for all windows
var container: Control = null

func _ready():
	# Create a container Control that fills the viewport
	container = Control.new()
	container.name = "WindowContainer"
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(container)

	# Find compositor
	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		compositor = get_node_or_null("/root/Main/X11Compositor")

	# Find mode manager
	if mode_manager_path:
		mode_manager = get_node(mode_manager_path)
	else:
		mode_manager = get_node_or_null("/root/Main/ModeManager")

	if not compositor:
		push_error("Window2DManager: X11Compositor not found!")
		return

	if mode_manager:
		# Listen for mode changes
		mode_manager.mode_changed.connect(_on_mode_changed)

	print("Window2DManager initialized")

func _process(_delta):
	"""Update window list and manage 2D windows"""
	if not compositor or not compositor.is_initialized():
		return

	# Only manage windows in 2D mode
	if mode_manager and mode_manager.is_3d_mode():
		return

	# Get all current window IDs
	var window_ids = compositor.get_window_ids()

	# Remove Window2D nodes for closed windows
	var ids_to_remove = []
	for window_id in window_2d_nodes.keys():
		if window_id not in window_ids:
			ids_to_remove.append(window_id)

	for window_id in ids_to_remove:
		remove_window_2d(window_id)

	# Create or update Window2D nodes for each window
	for window_id in window_ids:
		if window_id not in window_2d_nodes:
			create_window_2d(window_id)
		else:
			update_window_2d(window_id)

func create_window_2d(window_id: int):
	"""Create a new Window2D node for an X11 window"""
	if not container:
		push_error("Window2DManager: Container not initialized!")
		return

	var window_2d = Control.new()
	window_2d.set_script(Window2DScene)
	container.add_child(window_2d)

	# Set up the window
	window_2d.window_id = window_id
	window_2d.compositor = compositor

	# Get window properties from X11
	var window_title = compositor.get_window_title(window_id)
	var window_size = compositor.get_window_size(window_id)

	# Limit window size to fit on screen (account for panel)
	var viewport_size = get_viewport().get_visible_rect().size
	var panel_height = 40  # Top panel height
	var max_width = viewport_size.x - 20  # Leave 10px margin on each side
	var max_height = viewport_size.y - panel_height - 20  # Leave margin and account for panel

	var clamped_width = min(window_size.x, max_width)
	var clamped_height = min(window_size.y, max_height)

	# Set initial properties
	window_2d.set_window_title(window_title)
	window_2d.size = Vector2(clamped_width, clamped_height)

	# Position window (centered or cascaded)
	window_2d.position = get_spawn_position_2d(window_size)

	# Connect signals
	window_2d.window_focused.connect(_on_window_focused)
	window_2d.window_closed.connect(_on_window_closed)
	window_2d.window_minimized.connect(_on_window_minimized)

	# Store reference
	window_2d_nodes[window_id] = window_2d

	# Add to Z-order (new windows go on top)
	if window_id not in window_z_order:
		window_z_order.push_front(window_id)

	# Update Z-order visually
	update_z_order()

	print("Window2DManager: Created 2D window ", window_id, ": ", window_title)
	window_list_changed.emit()

func remove_window_2d(window_id: int):
	"""Remove a Window2D node"""
	if window_id not in window_2d_nodes:
		return

	var window_2d = window_2d_nodes[window_id]
	window_2d.queue_free()
	window_2d_nodes.erase(window_id)

	# Remove from Z-order
	var idx = window_z_order.find(window_id)
	if idx != -1:
		window_z_order.remove_at(idx)

	print("Window2DManager: Removed 2D window ", window_id)
	window_list_changed.emit()

func update_window_2d(window_id: int):
	"""Update an existing Window2D node"""
	if window_id not in window_2d_nodes:
		return

	var window_2d = window_2d_nodes[window_id]

	# Update window title
	var window_title = compositor.get_window_title(window_id)
	window_2d.set_window_title(window_title)

	# Check if window should be shown/hidden based on mapped state
	var is_mapped = compositor.is_window_mapped(window_id)
	if not is_mapped and not window_2d.is_minimized:
		window_2d.visible = false
	elif is_mapped and not window_2d.is_minimized:
		window_2d.visible = true

func get_spawn_position_2d(window_size: Vector2i) -> Vector2:
	"""Calculate spawn position for new window"""
	var viewport_size = get_viewport().get_visible_rect().size

	# Center the window
	var center_x = (viewport_size.x - window_size.x) / 2.0
	var center_y = (viewport_size.y - window_size.y) / 2.0

	# Add cascade offset based on number of windows
	var cascade_offset = window_2d_nodes.size() * 30
	center_x += cascade_offset
	center_y += cascade_offset

	# Clamp to viewport
	center_x = clamp(center_x, 0, viewport_size.x - window_size.x)
	center_y = clamp(center_y, 0, viewport_size.y - window_size.y)

	return Vector2(center_x, center_y)

func _on_window_focused(window_id: int):
	"""Handle window focus - bring to front"""
	bring_to_front(window_id)

	# Focus the X11 window
	if compositor:
		compositor.set_window_focus(window_id)

func _on_window_closed(window_id: int):
	"""Handle window close request"""
	# Window2D already sent close request to compositor
	# Just wait for compositor to remove the window
	pass

func _on_window_minimized(window_id: int):
	"""Handle window minimize"""
	window_list_changed.emit()

func bring_to_front(window_id: int):
	"""Bring a window to the front of the Z-order"""
	var idx = window_z_order.find(window_id)
	if idx == -1:
		return

	# Remove from current position
	window_z_order.remove_at(idx)

	# Add to front
	window_z_order.push_front(window_id)

	# Update visual Z-order
	update_z_order()

func update_z_order():
	"""Update the visual Z-order of all windows"""
	if not container:
		return

	# In Godot, child order determines drawing order
	# Earlier children are drawn first (behind), later children on top

	# Move windows in reverse Z-order (back to front)
	for i in range(window_z_order.size() - 1, -1, -1):
		var window_id = window_z_order[i]
		if window_id in window_2d_nodes:
			var window_2d = window_2d_nodes[window_id]
			container.move_child(window_2d, -1)  # Move to end (on top)

func show_all_windows():
	"""Show all windows (called when entering 2D mode)"""
	for window_id in window_2d_nodes:
		var window_2d = window_2d_nodes[window_id]
		if not window_2d.is_minimized:
			window_2d.visible = true

func hide_all_windows():
	"""Hide all windows (called when entering 3D mode)"""
	for window_id in window_2d_nodes:
		var window_2d = window_2d_nodes[window_id]
		window_2d.visible = false

func save_window_states() -> Dictionary:
	"""Save all window states for mode switching"""
	var states = {}

	for window_id in window_2d_nodes:
		var window_2d = window_2d_nodes[window_id]
		states[window_id] = {
			"position": window_2d.position,
			"size": window_2d.size,
			"minimized": window_2d.is_minimized,
			"maximized": window_2d.is_maximized,
			"fullscreen": window_2d.is_fullscreen
		}

	return states

func restore_window_states(states: Dictionary):
	"""Restore window states after mode switching"""
	for window_id in states:
		if window_id not in window_2d_nodes:
			continue

		var window_2d = window_2d_nodes[window_id]
		var state = states[window_id]

		window_2d.position = state.position
		window_2d.size = state.size
		window_2d.is_minimized = state.minimized
		window_2d.is_maximized = state.maximized
		window_2d.is_fullscreen = state.fullscreen

		# Update visibility
		window_2d.visible = not state.minimized

func get_window_count() -> int:
	"""Get total number of windows"""
	return window_2d_nodes.size()

func get_visible_window_count() -> int:
	"""Get number of visible (non-minimized) windows"""
	var count = 0
	for window_id in window_2d_nodes:
		var window_2d = window_2d_nodes[window_id]
		if not window_2d.is_minimized:
			count += 1
	return count

func focus_window(window_id: int):
	"""Focus a specific window"""
	if window_id not in window_2d_nodes:
		return

	var window_2d = window_2d_nodes[window_id]

	# Restore if minimized
	if window_2d.is_minimized:
		window_2d.restore()

	# Bring to front
	bring_to_front(window_id)

	# Focus in X11
	if compositor:
		compositor.set_window_focus(window_id)

func minimize_window(window_id: int):
	"""Minimize a specific window"""
	if window_id not in window_2d_nodes:
		return

	window_2d_nodes[window_id].minimize()

func _on_mode_changed(new_mode):
	"""Handle mode changes from ModeManager"""
	if new_mode == mode_manager.Mode.MODE_2D:
		# Entering 2D mode - show all windows
		show_all_windows()
	else:
		# Entering 3D mode - hide all windows
		hide_all_windows()
