extends "res://shell/scripts/widget_base.gd"

## Taskbar Widget
##
## Shows a button for each open window. Click to focus window.
## Updates when windows are created/destroyed/minimized.

var window_2d_manager: Node = null
var compositor: Node = null

# Window buttons: window_id -> Button
var window_buttons := {}

# Container for buttons
var button_container: HBoxContainer

func _widget_ready():
	widget_name = "Taskbar"
	expand = true  # Take up remaining space

	# Find managers
	window_2d_manager = get_node_or_null("/root/Main/Window2DManager")
	compositor = get_node_or_null("/root/Main/X11Compositor")

	if not window_2d_manager:
		push_error("TaskbarWidget: Window2DManager not found!")
		return

	if not compositor:
		push_error("TaskbarWidget: Compositor not found!")
		return

	# Create button container
	button_container = HBoxContainer.new()
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(button_container)

	# Listen for window changes
	window_2d_manager.window_list_changed.connect(_on_window_list_changed)

	# Initial update
	_refresh_taskbar()

	print("TaskbarWidget initialized")

func _refresh_taskbar():
	"""Rebuild the entire taskbar"""
	if not window_2d_manager or not compositor:
		return

	# Clear existing buttons
	for button in window_buttons.values():
		button.queue_free()
	window_buttons.clear()

	# Get all windows
	var window_2d_nodes = window_2d_manager.get("window_2d_nodes")
	if not window_2d_nodes:
		return

	# Create button for each window
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
