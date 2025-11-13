extends "res://shell/scripts/widget_base.gd"

## App Shortcut Widget
##
## A pinned application shortcut that can be added to panels.
## Displays an app name and launches it when clicked.
## Can accept drag-and-drop from the app launcher to pin apps.

var button: Button
var compositor: Node = null

# App data
var app_data: Dictionary = {}  # {name: String, exec: String, path: String, icon: String}

func _widget_ready():
	widget_name = "App Shortcut"
	min_width = 80
	preferred_width = 100

	# Find compositor
	compositor = get_node_or_null("/root/Main/X11Compositor")

	# Create button
	button = Button.new()
	button.text = "Empty"
	button.custom_minimum_size = Vector2(80, 0)
	button.pressed.connect(_on_button_pressed)
	add_child(button)

	# Enable drag-and-drop
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_app(app: Dictionary):
	"""Set the application to launch"""
	app_data = app
	button.text = app.name
	widget_name = app.name + " Shortcut"
	print("App shortcut set to: ", app.name)

func _gui_input(event: InputEvent):
	"""Handle drag-and-drop"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Right-click menu (inherited from widget_base)
			_show_widget_menu(mb.global_position)
			get_viewport().set_input_as_handled()
			return

	# Call parent to handle other inputs
	super._gui_input(event)

func _can_drop_data(at_position: Vector2, data) -> bool:
	"""Check if we can accept the dropped data"""
	# Accept if data is a Dictionary with app info
	if data is Dictionary:
		return data.has("name") and data.has("exec")
	return false

func _drop_data(at_position: Vector2, data):
	"""Handle dropped application"""
	if data is Dictionary and data.has("name") and data.has("exec"):
		set_app(data)
		print("App dropped on shortcut: ", app_data.name)

func _find_app_launcher() -> Node:
	"""Find the app launcher widget in the scene tree"""
	var root = get_tree().root
	return _find_node_with_script(root, "app_launcher_widget.gd")

func _find_node_with_script(node: Node, script_name: String) -> Node:
	"""Recursively find a node with a specific script"""
	if node.get_script():
		var script_path = node.get_script().resource_path
		if script_path.get_file() == script_name:
			return node

	for child in node.get_children():
		var result = _find_node_with_script(child, script_name)
		if result:
			return result

	return null

func _on_button_pressed():
	"""Launch the pinned application"""
	if app_data.is_empty():
		print("No app pinned to this shortcut")
		return

	_launch_application(app_data.exec)

func _launch_application(exec_cmd: String):
	"""Launch an application"""
	print("Launching pinned application: ", exec_cmd)

	# Clean up exec command (remove field codes like %f, %F, %u, %U)
	exec_cmd = exec_cmd.replace("%f", "")
	exec_cmd = exec_cmd.replace("%F", "")
	exec_cmd = exec_cmd.replace("%u", "")
	exec_cmd = exec_cmd.replace("%U", "")
	exec_cmd = exec_cmd.strip_edges()

	# Get display from compositor
	var display = ":1"  # default
	if compositor:
		display = compositor.get_display_name()

	# Split command into parts
	var parts = exec_cmd.split(" ", false)
	if parts.is_empty():
		push_error("Invalid exec command: ", exec_cmd)
		return

	var command = parts[0]
	var args = parts.slice(1)

	# Build env command: env DISPLAY=:X command arg1 arg2...
	var env_args = []
	env_args.append("DISPLAY=" + display)
	env_args.append(command)
	env_args.append_array(args)

	print("  Command: env ", " ".join(env_args))

	# Launch via env to set DISPLAY
	OS.create_process("env", env_args)

func update_widget():
	"""Update widget state"""
	# Nothing to update for now
	pass
