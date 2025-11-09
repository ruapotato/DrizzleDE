extends CanvasLayer

## In-game inventory menu for launching X11 applications
## Dynamically loads applications from .desktop files

@export var compositor_path: NodePath
@export var window_interaction_path: NodePath

var compositor: Node
var window_interaction: Node
var menu_visible := false

# Parsed applications from .desktop files
var applications := []
var filtered_applications := []

# UI element references (from scene)
@onready var panel = $Panel
@onready var app_list = $Panel/MarginContainer/VBoxContainer/ScrollContainer/AppList
@onready var search_box = $Panel/MarginContainer/VBoxContainer/SearchBox
@onready var status_label = $Panel/MarginContainer/VBoxContainer/StatusLabel

# Standard .desktop file locations
var desktop_file_paths := [
	"/usr/share/applications/",
	"/usr/local/share/applications/",
	OS.get_environment("HOME") + "/.local/share/applications/"
]

func _ready():
	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		compositor = get_node_or_null("/root/Main/X11Compositor")

	if window_interaction_path:
		window_interaction = get_node(window_interaction_path)
	else:
		window_interaction = get_node_or_null("/root/Main/WindowInteraction")

	if not compositor:
		push_error("Compositor not found for inventory menu!")
		return

	# Style the panel
	style_panel()

	# Load applications from .desktop files
	load_desktop_files()

	# Initially hide
	hide_menu()

func _input(event):
	# Don't open menu if a window is selected
	if window_interaction and window_interaction.current_state == window_interaction.WindowState.SELECTED:
		return

	if event.is_action_pressed("ui_tab") or (event is InputEventKey and event.pressed and event.keycode == KEY_I):
		toggle_menu()
		get_viewport().set_input_as_handled()

	# ESC to close menu
	if menu_visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_menu()
		get_viewport().set_input_as_handled()

func style_panel():
	# Add some style to the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.5, 0.8, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

func load_desktop_files():
	print("Loading .desktop files from system...")
	applications.clear()

	var file_count = 0
	for dir_path in desktop_file_paths:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue

		var dir = DirAccess.open(dir_path)
		if not dir:
			continue

		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			if file_name.ends_with(".desktop"):
				var full_path = dir_path + file_name
				var app_info = parse_desktop_file(full_path)
				if app_info:
					applications.append(app_info)
					file_count += 1

			file_name = dir.get_next()

		dir.list_dir_end()

	# Sort alphabetically by name
	applications.sort_custom(func(a, b): return a.name < b.name)

	print("Loaded ", file_count, " applications from .desktop files")
	status_label.text = str(file_count) + " applications available"

	# Populate UI
	filtered_applications = applications.duplicate()
	populate_app_list()

func parse_desktop_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var app_info = {}
	var in_desktop_entry = false

	while not file.eof_reached():
		var line = file.get_line().strip_edges()

		# Check if we're in [Desktop Entry] section
		if line == "[Desktop Entry]":
			in_desktop_entry = true
			continue
		elif line.begins_with("[") and line.ends_with("]"):
			in_desktop_entry = false
			continue

		if not in_desktop_entry or line.is_empty() or line.begins_with("#"):
			continue

		# Parse key=value pairs
		var parts = line.split("=", false, 1)
		if parts.size() != 2:
			continue

		var key = parts[0].strip_edges()
		var value = parts[1].strip_edges()

		match key:
			"Name":
				app_info["name"] = value
			"Exec":
				# Clean up the Exec field (remove %u, %f, etc.)
				app_info["exec"] = clean_exec_command(value)
			"Comment":
				app_info["description"] = value
			"Icon":
				app_info["icon"] = value
			"NoDisplay":
				if value.to_lower() == "true":
					file.close()
					return {}  # Skip apps that shouldn't be displayed
			"Type":
				if value != "Application":
					file.close()
					return {}  # Only show applications
			"Categories":
				app_info["categories"] = value

	file.close()

	# Only return if we have at least a name and exec command
	if app_info.has("name") and app_info.has("exec"):
		if not app_info.has("description"):
			app_info["description"] = ""
		if not app_info.has("icon"):
			app_info["icon"] = ""
		if not app_info.has("categories"):
			app_info["categories"] = ""
		return app_info

	return {}

func clean_exec_command(exec_string: String) -> String:
	# Remove field codes like %f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m
	var cleaned = exec_string
	var field_codes = ["%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"]
	for code in field_codes:
		cleaned = cleaned.replace(code, "")

	# Remove quotes if present
	cleaned = cleaned.replace("\"", "")

	# Remove extra spaces
	cleaned = cleaned.strip_edges()

	return cleaned

func populate_app_list():
	# Clear existing buttons
	for child in app_list.get_children():
		child.queue_free()

	# Create button for each app
	for app in filtered_applications:
		create_app_button(app)

	# Update status
	if filtered_applications.size() == 0:
		status_label.text = "No applications found"
	elif filtered_applications.size() != applications.size():
		status_label.text = str(filtered_applications.size()) + " / " + str(applications.size()) + " applications"
	else:
		status_label.text = str(applications.size()) + " applications available"

func create_app_button(app: Dictionary):
	var button_container = HBoxContainer.new()
	app_list.add_child(button_container)
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Launch button
	var button = Button.new()
	button_container.add_child(button)
	button.text = app.name
	button.custom_minimum_size = Vector2(200, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = app.description if app.description != "" else app.exec
	button.pressed.connect(func(): launch_application(app.exec))

	# Description label
	if app.description != "":
		var desc_label = Label.new()
		button_container.add_child(desc_label)
		desc_label.text = app.description
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _on_search_changed(new_text: String):
	# Filter applications based on search text
	if new_text.is_empty():
		filtered_applications = applications.duplicate()
	else:
		filtered_applications.clear()
		var search_lower = new_text.to_lower()
		for app in applications:
			if app.name.to_lower().contains(search_lower) or \
			   app.description.to_lower().contains(search_lower) or \
			   app.exec.to_lower().contains(search_lower):
				filtered_applications.append(app)

	populate_app_list()

func launch_application(command: String):
	if not compositor or not compositor.is_initialized():
		push_error("Cannot launch app: compositor not ready")
		return

	var display = compositor.get_display_name()
	if display == "":
		push_error("Cannot launch app: no display available")
		return

	print("═══════════════════════════════════════")
	print("Launching ", command, " on display ", display)

	# Launch using shell with DISPLAY environment variable
	# Use sh -c to properly handle the DISPLAY variable and background the process
	var shell_command = "DISPLAY=%s %s &" % [display, command]
	print("Executing: ", shell_command)

	# Use OS.create_process for non-blocking launch (Godot 4)
	# This launches the process in the background without freezing Godot
	var pid = OS.create_process("sh", ["-c", shell_command])

	if pid > 0:
		print("✓ Launched ", command, " successfully (PID: ", pid, ")")
	else:
		push_error("✗ Failed to launch ", command)

	print("═══════════════════════════════════════")

	# Hide menu after launching
	hide_menu()

func toggle_menu():
	if menu_visible:
		hide_menu()
	else:
		show_menu()

func show_menu():
	panel.visible = true
	menu_visible = true
	# Release mouse capture so user can click menu
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Focus search box
	search_box.grab_focus()

func hide_menu():
	panel.visible = false
	menu_visible = false
	# Clear search
	search_box.text = ""
	# Recapture mouse for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
