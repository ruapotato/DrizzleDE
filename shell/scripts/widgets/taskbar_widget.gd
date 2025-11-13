extends "res://shell/scripts/widget_base.gd"

## Taskbar Widget
##
## Shows a button for each open window. Click to focus window.
## Updates when windows are created/destroyed/minimized.

var window_2d_manager: Node = null
var compositor: Node = null
var filesystem_generator: Node = null

# Window buttons: window_id -> Button
var window_buttons := {}

# Container for buttons
var button_container: HBoxContainer

# Current directory filter
var current_directory: String = ""

func _widget_ready():
	widget_name = "Taskbar"
	expand = true  # Take up remaining space

	# Find managers
	window_2d_manager = get_node_or_null("/root/Main/Window2DManager")
	compositor = get_node_or_null("/root/Main/X11Compositor")
	filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")

	if not window_2d_manager:
		push_error("TaskbarWidget: Window2DManager not found!")
		return

	if not compositor:
		push_error("TaskbarWidget: Compositor not found!")
		return

	# Get current directory
	if filesystem_generator and filesystem_generator.has_method("get_current_directory"):
		current_directory = filesystem_generator.get_current_directory()
		# Listen for directory changes
		if filesystem_generator.has_signal("directory_changed"):
			filesystem_generator.directory_changed.connect(_on_directory_changed)

	# Create button container
	button_container = HBoxContainer.new()
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Allow right-clicks to pass through to panel for context menu
	button_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(button_container)

	# Add visual separator at start
	var separator = Label.new()
	separator.text = "|"
	separator.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
	button_container.add_child(separator)

	# Listen for window changes
	window_2d_manager.window_list_changed.connect(_on_window_list_changed)

	# Initial update - filter windows to current directory
	if window_2d_manager.has_method("filter_windows_by_directory") and not current_directory.is_empty():
		window_2d_manager.filter_windows_by_directory(current_directory)

	_refresh_taskbar()

	print("TaskbarWidget initialized")

func _on_directory_changed(new_directory: String):
	"""Called when directory changes - filter taskbar to current directory"""
	print("TaskbarWidget: Directory changed to: ", new_directory)
	current_directory = new_directory

	# Filter visible windows in window manager
	if window_2d_manager and window_2d_manager.has_method("filter_windows_by_directory"):
		window_2d_manager.filter_windows_by_directory(new_directory)

	# Refresh taskbar buttons
	_refresh_taskbar()

func _refresh_taskbar():
	"""Rebuild the entire taskbar"""
	if not window_2d_manager or not compositor:
		return

	# Clear existing buttons
	for button in window_buttons.values():
		button.queue_free()
	window_buttons.clear()

	# Get all windows in current directory only
	if not current_directory.is_empty() and window_2d_manager.has_method("get_windows_in_directory"):
		var window_ids = window_2d_manager.get_windows_in_directory(current_directory)
		print("TaskbarWidget: Showing ", window_ids.size(), " windows for directory: ", current_directory)

		# Debug: show all window directories
		var all_dirs = window_2d_manager.get("window_directories")
		if all_dirs:
			print("  All window directories: ", all_dirs)

		for window_id in window_ids:
			_create_window_button(window_id)
	else:
		# Fallback: show all windows if no directory filter
		print("TaskbarWidget: No directory filter, showing all windows")
		var window_2d_nodes = window_2d_manager.get("window_2d_nodes")
		if window_2d_nodes:
			for window_id in window_2d_nodes:
				_create_window_button(window_id)

func _create_window_button(window_id: int):
	"""Create a button for a window"""
	if window_id in window_buttons:
		return

	# Get window info
	var window_title = compositor.get_window_title(window_id)
	if window_title.is_empty():
		window_title = "Window " + str(window_id)

	# Truncate long titles
	if window_title.length() > 20:
		window_title = window_title.substr(0, 17) + "..."

	# Create button
	var button = Button.new()
	button.text = window_title
	button.custom_minimum_size = Vector2(120, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(_on_window_button_pressed.bind(window_id))

	# Style button
	button.tooltip_text = compositor.get_window_title(window_id)

	button_container.add_child(button)
	window_buttons[window_id] = button

func _remove_window_button(window_id: int):
	"""Remove a window button"""
	if window_id not in window_buttons:
		return

	var button = window_buttons[window_id]
	button.queue_free()
	window_buttons.erase(window_id)

func _on_window_button_pressed(window_id: int):
	"""Handle window button click - focus the window"""
	if window_2d_manager:
		window_2d_manager.focus_window(window_id)

func _on_window_list_changed():
	"""Handle window list changes"""
	_refresh_taskbar()

func update_widget():
	"""Update widget state"""
	_refresh_taskbar()
