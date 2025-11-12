extends "res://shell/scripts/widget_base.gd"

## App Launcher Widget
##
## Shows a button that opens a menu to launch applications.
## Scans /usr/share/applications for .desktop files.

var button: Button
var popup_menu: PopupMenu
var compositor: Node = null

# Desktop files cache
var desktop_files := []  # Array of {name: String, exec: String, path: String}

func _widget_ready():
	widget_name = "App Launcher"
	min_width = 100
	preferred_width = 120

	# Find compositor
	compositor = get_node_or_null("/root/Main/X11Compositor")

	# Create button
	button = Button.new()
	button.text = "Applications"
	button.custom_minimum_size = Vector2(100, 0)
	button.pressed.connect(_on_button_pressed)
	add_child(button)

	# Create popup menu
	popup_menu = PopupMenu.new()
	popup_menu.id_pressed.connect(_on_menu_item_selected)
	add_child(popup_menu)

	# Scan for desktop files
	_scan_desktop_files()

	print("AppLauncherWidget initialized with ", desktop_files.size(), " applications")

func _scan_desktop_files():
	"""Scan /usr/share/applications for .desktop files"""
	desktop_files.clear()

	var apps_dir = "/usr/share/applications"
	var dir = DirAccess.open(apps_dir)

	if not dir:
		push_warning("AppLauncherWidget: Cannot open ", apps_dir)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".desktop"):
			var file_path = apps_dir + "/" + file_name
			var app_info = _parse_desktop_file(file_path)
			if app_info:
				desktop_files.append(app_info)

		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by name
	desktop_files.sort_custom(func(a, b): return a.name < b.name)

func _parse_desktop_file(file_path: String) -> Dictionary:
	"""Parse a .desktop file to extract name and exec command"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var name = ""
	var exec_cmd = ""
	var no_display = false

	while not file.eof_reached():
		var line = file.get_line().strip_edges()

		if line.begins_with("Name="):
			name = line.substr(5)
		elif line.begins_with("Exec="):
			exec_cmd = line.substr(5)
		elif line.begins_with("NoDisplay=true"):
			no_display = true

	file.close()

	# Skip if no name, no exec, or NoDisplay=true
	if name.is_empty() or exec_cmd.is_empty() or no_display:
		return {}

	return {
		"name": name,
		"exec": exec_cmd,
		"path": file_path
	}

func _on_button_pressed():
	"""Show the application menu"""
	# Clear menu
	popup_menu.clear()

	# Add applications to menu
	for i in range(desktop_files.size()):
		var app = desktop_files[i]
		popup_menu.add_item(app.name, i)

	# Position menu below button
	var button_rect = button.get_global_rect()
	popup_menu.position = Vector2i(button_rect.position.x, button_rect.position.y + button_rect.size.y)
	popup_menu.popup()

func _on_menu_item_selected(id: int):
	"""Launch the selected application"""
	if id < 0 or id >= desktop_files.size():
		return

	var app = desktop_files[id]
	_launch_application(app.exec)

func _launch_application(exec_cmd: String):
	"""Launch an application"""
	print("Launching application: ", exec_cmd)

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
	"""Rescan desktop files"""
	_scan_desktop_files()
