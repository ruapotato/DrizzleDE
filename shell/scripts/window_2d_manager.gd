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
var window_directories := {}  # window_id -> directory path where window was created
var current_filter_directory := ""  # Current directory filter (empty = show all)

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

	# Add title bar height to window size (Window2D = title bar + content)
	var title_bar_height = 32  # Must match TITLE_BAR_HEIGHT in window_2d.gd
	var total_width = window_size.x
	var total_height = window_size.y + title_bar_height

	var clamped_width = min(total_width, max_width)
	var clamped_height = min(total_height, max_height)

	# Set initial properties
	window_2d.set_window_title(window_title)

	# Use set_deferred to set size after _ready() completes to avoid anchor conflicts
	print("  [DEBUG] Requesting window size: ", Vector2(clamped_width, clamped_height), " (X11 size: ", window_size, ", +title bar)")
	window_2d.set_deferred("size", Vector2(clamped_width, clamped_height))

	# Position window
	var window_position: Vector2i

	# Check if this window is a popup (has a parent window)
	var parent_window_id = compositor.get_parent_window_id(window_id)
	if parent_window_id != -1 and parent_window_id in window_2d_nodes:
		# This is a popup - position it relative to parent window
		var parent_window_2d = window_2d_nodes[parent_window_id]
		var popup_x11_pos = compositor.get_window_position(window_id)
		var parent_x11_pos = compositor.get_window_position(parent_window_id)

		# Calculate offset from parent window in X11 space
		var offset_x = popup_x11_pos.x - parent_x11_pos.x
		var offset_y = popup_x11_pos.y - parent_x11_pos.y

		# Apply offset to parent's 2D position
		# Note: parent 2D position includes the title bar, so we need to account for that
		# Title bar height = 32 (must match TITLE_BAR_HEIGHT in window_2d.gd)
		window_position = Vector2i(
			parent_window_2d.position.x + offset_x,
			parent_window_2d.position.y + offset_y + 32
		)
		print("  [DEBUG] Popup window ", window_id, " - parent: ", parent_window_id)
		print("    Popup X11 pos: ", popup_x11_pos, ", Parent X11 pos: ", parent_x11_pos)
		print("    Offset: (", offset_x, ", ", offset_y, "), Parent 2D pos: ", parent_window_2d.position)
		print("    Final popup pos: ", window_position)
	else:
		# Normal window - use cascaded/centered positioning
		window_position = get_spawn_position_2d(Vector2i(clamped_width, clamped_height))

	window_2d.set_deferred("position", window_position)

	# Connect signals
	window_2d.window_focused.connect(_on_window_focused)
	window_2d.window_closed.connect(_on_window_closed)
	window_2d.window_minimized.connect(_on_window_minimized)

	# Store reference
	window_2d_nodes[window_id] = window_2d

	# Store which directory this window was created in
	var filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")
	var current_dir = ""

	if filesystem_generator and filesystem_generator.has_method("get_current_directory"):
		current_dir = filesystem_generator.get_current_directory()

	# If empty (in 2D mode), try to get from desktop switcher widget
	if current_dir.is_empty():
		var panel_manager = get_node_or_null("/root/Main/PanelManager")
		if panel_manager:
			# Try to find desktop switcher widget to get current directory
			for panel in panel_manager.get("panels").values():
				for widget in panel.get("widgets"):
					if widget.has_method("get") and widget.get("current_directory"):
						current_dir = widget.get("current_directory")
						break
				if not current_dir.is_empty():
					break

	# Still empty? Default to home
	if current_dir.is_empty():
		current_dir = OS.get_environment("HOME")
		if current_dir.is_empty():
			current_dir = "/home/" + OS.get_environment("USER")

	window_directories[window_id] = current_dir
	print("Window2DManager: Window ", window_id, " created in directory: ", current_dir)

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
	window_directories.erase(window_id)  # Remove directory tracking

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

	# Check if window should be shown/hidden based on mapped state AND directory filter
	var is_mapped = compositor.is_window_mapped(window_id)
	var window_dir = window_directories.get(window_id, "")

	# Respect directory filtering
	var passes_directory_filter = true
	if not current_filter_directory.is_empty():
		passes_directory_filter = (window_dir == current_filter_directory)

	# Only show if: mapped AND not minimized AND passes directory filter
	if not is_mapped or window_2d.is_minimized or not passes_directory_filter:
		window_2d.visible = false
	else:
		window_2d.visible = true

	# Update popup position if this is a popup window (follows parent)
	var parent_window_id = compositor.get_parent_window_id(window_id)
	if parent_window_id != -1 and parent_window_id in window_2d_nodes:
		var parent_window_2d = window_2d_nodes[parent_window_id]

		# Don't update position if parent (or any ancestor) is being dragged
		if not _is_window_or_ancestor_dragging(parent_window_id):
			var popup_x11_pos = compositor.get_window_position(window_id)
			var parent_x11_pos = compositor.get_window_position(parent_window_id)

			# Calculate offset from parent window in X11 space
			var offset_x = popup_x11_pos.x - parent_x11_pos.x
			var offset_y = popup_x11_pos.y - parent_x11_pos.y

			# Apply offset to parent's 2D position
			# Title bar height = 32 (must match TITLE_BAR_HEIGHT in window_2d.gd)
			var new_position = Vector2(
				parent_window_2d.position.x + offset_x,
				parent_window_2d.position.y + offset_y + 32
			)

			# Only update if position changed significantly (avoid jitter)
			if window_2d.position.distance_to(new_position) > 1.0:
				window_2d.position = new_position

func _is_window_or_ancestor_dragging(window_id: int) -> bool:
	"""Check if this window or any of its ancestors is being dragged"""
	var current_id = window_id
	var max_iterations = 10
	var iterations = 0

	while iterations < max_iterations:
		if current_id in window_2d_nodes:
			var window_2d = window_2d_nodes[current_id]
			if "is_dragging" in window_2d and window_2d.is_dragging:
				return true

		# Check parent
		var parent_id = compositor.get_parent_window_id(current_id)
		if parent_id == -1:
			break

		current_id = parent_id
		iterations += 1

	return false

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

	# Build a list that ensures popups are always above their parents
	var ordered_windows = _build_z_order_with_popups()

	# Move windows in the computed order (back to front)
	for window_id in ordered_windows:
		if window_id in window_2d_nodes:
			var window_2d = window_2d_nodes[window_id]
			container.move_child(window_2d, -1)  # Move to end (on top)

func _build_z_order_with_popups() -> Array:
	"""Build Z-order list ensuring popups are above their parents"""
	var result = []
	var processed = {}

	# Helper function to add a window and all its popups recursively
	var add_window_with_popups = func(window_id, _add_func_ref):
		if window_id in processed:
			return
		processed[window_id] = true
		result.append(window_id)

		# Add all popup children of this window
		for child_id in window_2d_nodes:
			var parent_id = compositor.get_parent_window_id(child_id)
			if parent_id == window_id:
				_add_func_ref.call(child_id, _add_func_ref)

	# Process windows in reverse Z-order (back to front)
	for i in range(window_z_order.size() - 1, -1, -1):
		var window_id = window_z_order[i]
		# Only add root windows (windows without parents or whose parents aren't tracked)
		var parent_id = compositor.get_parent_window_id(window_id)
		if parent_id == -1 or parent_id not in window_2d_nodes:
			add_window_with_popups.call(window_id, add_window_with_popups)

	return result

func show_all_windows():
	"""Show all windows (called when entering 2D mode)"""
	# Clear directory filter
	current_filter_directory = ""

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

func get_window_directory(window_id: int) -> String:
	"""Get the directory where a window was created"""
	return window_directories.get(window_id, "")

func get_windows_in_directory(directory: String) -> Array:
	"""Get all window IDs that were created in a specific directory"""
	var windows = []
	for window_id in window_directories:
		if window_directories[window_id] == directory:
			windows.append(window_id)
	return windows

func filter_windows_by_directory(directory: String):
	"""Show only windows from the specified directory, hide others"""
	print("Window2DManager: Filtering windows for directory: ", directory)

	# Store current filter directory
	current_filter_directory = directory

	for window_id in window_2d_nodes:
		var window_2d = window_2d_nodes[window_id]
		var window_dir = window_directories.get(window_id, "")

		if window_dir == directory:
			# Show window if not minimized
			if not window_2d.is_minimized:
				window_2d.visible = true
				print("  Showing window ", window_id, " (from ", window_dir, ")")
		else:
			# Hide window (it's from a different directory)
			window_2d.visible = false
			print("  Hiding window ", window_id, " (from ", window_dir, ")")

func _on_mode_changed(new_mode):
	"""Handle mode changes from ModeManager"""
	if new_mode == mode_manager.Mode.MODE_2D:
		# Entering 2D mode - restore directory filtering
		var filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")
		if filesystem_generator and filesystem_generator.has_method("get_current_directory"):
			var current_dir = filesystem_generator.get_current_directory()
			if not current_dir.is_empty():
				# Filter windows to current directory
				filter_windows_by_directory(current_dir)
			else:
				# No directory context, show all windows
				show_all_windows()
		else:
			# Fallback: show all windows
			show_all_windows()
	else:
		# Entering 3D mode - hide all windows
		hide_all_windows()
