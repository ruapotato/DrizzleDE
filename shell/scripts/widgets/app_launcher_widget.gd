extends "res://shell/scripts/widget_base.gd"

## App Launcher Widget
##
## Shows a button that opens a categorized menu to launch applications.
## Scans /usr/share/applications for .desktop files.
## Supports search, categories, and drag-to-pin functionality.

var button: Button
var launcher_window: Window
var compositor: Node = null

# Desktop files cache
var desktop_files := []  # Array of {name: String, exec: String, path: String, categories: Array, icon: String}
var categories_map := {}  # category_name -> Array of app indices

# UI elements
var search_box: LineEdit
var category_container: VBoxContainer
var category_sections := {}  # category_name -> {button: Button, apps_container: VBoxContainer, visible: bool}

# Currently dragged app (for drag-to-pin)
var dragged_app: Dictionary = {}
var drag_preview: Control = null

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

	# Create launcher window
	_create_launcher_window()

	# Scan for desktop files
	_scan_desktop_files()
	_build_category_ui()

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

	# Build categories map
	_build_categories_map()

func _parse_desktop_file(file_path: String) -> Dictionary:
	"""Parse a .desktop file to extract name, exec command, categories, and icon"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var name = ""
	var exec_cmd = ""
	var no_display = false
	var categories_str = ""
	var icon = ""
	var generic_name = ""

	while not file.eof_reached():
		var line = file.get_line().strip_edges()

		if line.begins_with("Name=") and not line.begins_with("Name["):
			name = line.substr(5)
		elif line.begins_with("GenericName=") and not line.begins_with("GenericName["):
			generic_name = line.substr(12)
		elif line.begins_with("Exec="):
			exec_cmd = line.substr(5)
		elif line.begins_with("NoDisplay=true"):
			no_display = true
		elif line.begins_with("Categories="):
			categories_str = line.substr(11)
		elif line.begins_with("Icon="):
			icon = line.substr(5)

	file.close()

	# Skip if no name, no exec, or NoDisplay=true
	if name.is_empty() or exec_cmd.is_empty() or no_display:
		return {}

	# Parse categories (semicolon-separated)
	var categories = []
	if not categories_str.is_empty():
		categories = categories_str.split(";", false)

	# If no categories, put in "Other"
	if categories.is_empty():
		categories = ["Other"]

	return {
		"name": name,
		"exec": exec_cmd,
		"path": file_path,
		"categories": categories,
		"icon": icon,
		"generic_name": generic_name
	}

func _build_categories_map():
	"""Build a map of categories to app indices"""
	categories_map.clear()

	# Map of freedesktop categories to friendly names
	var category_names = {
		"AudioVideo": "Multimedia",
		"Audio": "Multimedia",
		"Video": "Multimedia",
		"Development": "Development",
		"Education": "Education",
		"Game": "Games",
		"Graphics": "Graphics",
		"Network": "Internet",
		"Office": "Office",
		"Science": "Science",
		"Settings": "Settings",
		"System": "System",
		"Utility": "Accessories",
		"Other": "Other"
	}

	for i in range(desktop_files.size()):
		var app = desktop_files[i]
		var added = false

		# Add to all matching categories
		for cat in app.categories:
			var friendly_cat = category_names.get(cat, null)
			if friendly_cat:
				if not friendly_cat in categories_map:
					categories_map[friendly_cat] = []
				if not i in categories_map[friendly_cat]:
					categories_map[friendly_cat].append(i)
					added = true

		# If not added to any category, add to Other
		if not added:
			if not "Other" in categories_map:
				categories_map["Other"] = []
			categories_map["Other"].append(i)

func _create_launcher_window():
	"""Create the application launcher window (MATE/Windows style)"""
	launcher_window = Window.new()
	launcher_window.title = "Applications"
	launcher_window.size = Vector2i(650, 500)
	launcher_window.unresizable = false
	launcher_window.always_on_top = true
	launcher_window.close_requested.connect(_on_launcher_close)
	add_child(launcher_window)

	# Main horizontal container (categories on left, apps on right)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.offset_left = 5
	main_hbox.offset_top = 5
	main_hbox.offset_right = -5
	main_hbox.offset_bottom = -5
	launcher_window.add_child(main_hbox)

	# Left side: Category list
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size.x = 200
	main_hbox.add_child(left_vbox)

	# Search box at top
	var search_label = Label.new()
	search_label.text = "Search:"
	left_vbox.add_child(search_label)

	search_box = LineEdit.new()
	search_box.placeholder_text = "Type to search..."
	search_box.text_changed.connect(_on_search_changed)
	left_vbox.add_child(search_box)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	left_vbox.add_child(spacer)

	# Category buttons
	var cat_scroll = ScrollContainer.new()
	cat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(cat_scroll)

	category_container = VBoxContainer.new()
	category_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_scroll.add_child(category_container)

	# Right side: App list for selected category
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(right_vbox)

	var apps_label = Label.new()
	apps_label.text = "Select a category"
	apps_label.set_meta("apps_label", true)
	right_vbox.add_child(apps_label)

	var apps_scroll = ScrollContainer.new()
	apps_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(apps_scroll)

	var apps_container = VBoxContainer.new()
	apps_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apps_container.set_meta("apps_container", true)
	apps_scroll.add_child(apps_container)

	# Hide window initially
	launcher_window.hide()

func _build_category_ui():
	"""Build the category buttons in the launcher (MATE/Windows style)"""
	# Clear existing sections
	for child in category_container.get_children():
		child.queue_free()
	category_sections.clear()

	# Sort categories alphabetically
	var sorted_categories = categories_map.keys()
	sorted_categories.sort()

	# Create a button for each category
	for cat_name in sorted_categories:
		_create_category_button(cat_name)

func _create_category_button(cat_name: String):
	"""Create a button for a category"""
	var cat_button = Button.new()
	cat_button.text = cat_name + " (" + str(categories_map[cat_name].size()) + ")"
	cat_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_button.custom_minimum_size.y = 36
	cat_button.pressed.connect(_on_category_selected.bind(cat_name))
	category_container.add_child(cat_button)

	# Store button reference
	category_sections[cat_name] = {
		"button": cat_button
	}

func _create_app_button(app: Dictionary, app_idx: int) -> Button:
	"""Create a button for an application"""
	var app_button = Button.new()
	app_button.text = app.name
	app_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	app_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_button.custom_minimum_size.y = 32

	# Store app data in metadata for drag-and-drop
	app_button.set_meta("app_index", app_idx)
	app_button.set_meta("app_data", app)

	# Connect click signal
	app_button.pressed.connect(_on_app_button_pressed.bind(app))

	# Enable drag-and-drop (using _get_drag_data override)
	app_button.set_drag_forwarding(
		Callable(self, "_get_drag_data_for_app").bind(app),
		Callable(),
		Callable()
	)

	return app_button

func _get_drag_data_for_app(at_position: Vector2, app: Dictionary):
	"""Return drag data for an application"""
	# Create drag preview
	var preview = Label.new()
	preview.text = app.name
	preview.add_theme_color_override("font_color", Color.WHITE)

	# Create a ColorRect background
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.5, 0.8, 0.9)
	bg.custom_minimum_size = Vector2(150, 30)
	bg.add_child(preview)
	preview.position = Vector2(5, 5)

	set_drag_preview(bg)
	return app

func _on_category_selected(cat_name: String):
	"""Show apps for the selected category"""
	if not cat_name in categories_map:
		return

	# Find the apps container on the right side
	var apps_container = _find_apps_container()
	var apps_label = _find_apps_label()

	if not apps_container or not apps_label:
		push_error("Could not find apps container or label")
		return

	# Update label
	apps_label.text = cat_name

	# Clear existing apps
	for child in apps_container.get_children():
		child.queue_free()

	# Add apps from this category
	var app_indices = categories_map[cat_name]
	for app_idx in app_indices:
		var app = desktop_files[app_idx]
		var app_button = _create_app_button(app, app_idx)
		apps_container.add_child(app_button)

func _find_apps_container() -> VBoxContainer:
	"""Find the apps container in the right panel"""
	return _find_node_with_meta(launcher_window, "apps_container")

func _find_apps_label() -> Label:
	"""Find the apps label in the right panel"""
	return _find_node_with_meta(launcher_window, "apps_label")

func _find_node_with_meta(node: Node, meta_key: String) -> Node:
	"""Recursively find a node with specific metadata"""
	if node.has_meta(meta_key):
		return node

	for child in node.get_children():
		var result = _find_node_with_meta(child, meta_key)
		if result:
			return result

	return null

func _on_button_pressed():
	"""Show the application launcher window"""
	if launcher_window.visible:
		launcher_window.hide()
	else:
		# Position window near the button
		var button_rect = button.get_global_rect()
		launcher_window.position = Vector2i(button_rect.position.x, button_rect.position.y + button_rect.size.y + 5)
		launcher_window.show()
		search_box.grab_focus()

func _on_launcher_close():
	"""Handle launcher window close"""
	launcher_window.hide()

func _on_app_button_pressed(app: Dictionary):
	"""Launch the selected application"""
	_launch_application(app.exec)
	launcher_window.hide()

func _on_search_changed(new_text: String):
	"""Filter applications based on search text"""
	var search_lower = new_text.to_lower()

	if search_lower.is_empty():
		# Clear search results - show instruction
		var apps_container = _find_apps_container()
		var apps_label = _find_apps_label()
		if apps_container and apps_label:
			apps_label.text = "Select a category"
			for child in apps_container.get_children():
				child.queue_free()
		return

	# Find the apps container and label
	var apps_container = _find_apps_container()
	var apps_label = _find_apps_label()

	if not apps_container or not apps_label:
		return

	# Update label
	apps_label.text = "Search results for: " + new_text

	# Clear existing apps
	for child in apps_container.get_children():
		child.queue_free()

	# Search through all apps
	var match_count = 0
	for i in range(desktop_files.size()):
		var app = desktop_files[i]
		var matches = app.name.to_lower().contains(search_lower) or \
			(app.has("generic_name") and app.generic_name and app.generic_name.to_lower().contains(search_lower))

		if matches:
			var app_button = _create_app_button(app, i)
			apps_container.add_child(app_button)
			match_count += 1

	# If no matches, show a message
	if match_count == 0:
		var no_results = Label.new()
		no_results.text = "No applications found"
		apps_container.add_child(no_results)

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
