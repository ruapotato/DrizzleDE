extends "res://shell/scripts/widget_base.gd"

## Desktop Switcher Widget
##
## Switches between different desktop directories (like workspace switcher but for folders).
## Shows buttons for: ~/Desktop, ~/, ~/Documents, ~/Videos, ~/Downloads, ~/Pictures

var filesystem_generator: Node = null
var current_directory: String = ""

# Desktop directories to switch between
var desktop_dirs := [
	{"name": "Home", "path": ""},  # Will be set to home dir
	{"name": "Desktop", "path": "Desktop"},
	{"name": "Documents", "path": "Documents"},
	{"name": "Downloads", "path": "Downloads"},
	{"name": "Pictures", "path": "Pictures"},
	{"name": "Videos", "path": "Videos"}
]

# Buttons
var buttons := []
var button_container: HBoxContainer
var current_dir_label: Label  # Shows current directory path

func _widget_ready():
	widget_name = "Desktop Switcher"

	# Find filesystem generator
	filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")
	if not filesystem_generator:
		push_error("DesktopSwitcherWidget: FileSystemGenerator not found!")
		return

	# Get home directory
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		home_dir = "/home/" + OS.get_environment("USER")

	# Set full paths
	for dir_info in desktop_dirs:
		if dir_info["path"].is_empty():
			dir_info["path"] = home_dir
		else:
			dir_info["path"] = home_dir + "/" + dir_info["path"]

	# Get current directory from filesystem generator
	if filesystem_generator.has_method("get_current_directory"):
		current_directory = filesystem_generator.get_current_directory()
	else:
		current_directory = home_dir

	# Create button container (no label)
	button_container = HBoxContainer.new()
	button_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button_container.add_theme_constant_override("separation", 4)
	add_child(button_container)

	# Create buttons for each desktop directory
	var total_width = 0
	for dir_info in desktop_dirs:
		var button = Button.new()
		button.text = dir_info["name"]
		button.pressed.connect(_on_directory_button_pressed.bind(dir_info["path"]))
		button_container.add_child(button)
		buttons.append(button)

	# Wait for buttons to be ready and calculate size
	await get_tree().process_frame

	# Calculate total width needed
	total_width = 0
	for button in buttons:
		button.reset_size()  # Ensure button calculates its size
		await get_tree().process_frame
		total_width += button.size.x

	# Add spacing between buttons (separation * (count - 1))
	total_width += 4 * (buttons.size() - 1)

	# Set our minimum size based on content
	custom_minimum_size.x = total_width + 8  # +8 for padding
	min_width = total_width + 8
	preferred_width = total_width + 8

	# Listen for directory changes from 3D mode (before initial update)
	if filesystem_generator.has_signal("directory_changed"):
		filesystem_generator.directory_changed.connect(_on_directory_changed)

	# Update button states
	current_directory = filesystem_generator.get_current_directory() if filesystem_generator.has_method("get_current_directory") else current_directory
	_update_button_states()

	print("DesktopSwitcherWidget initialized with width: ", total_width)

func _on_directory_button_pressed(directory_path: String):
	"""Switch to the selected directory"""
	print("Switching desktop to: ", directory_path)

	# Update current directory immediately
	current_directory = directory_path

	# Notify filesystem generator (for 3D mode)
	if filesystem_generator and filesystem_generator.has_method("load_directory"):
		filesystem_generator.load_directory(directory_path)

	# Manually emit directory_changed signal for 2D mode
	if filesystem_generator and filesystem_generator.has_signal("directory_changed"):
		filesystem_generator.emit_signal("directory_changed", directory_path)

	_update_button_states()

func _update_button_states():
	"""Update button visual states to show current directory"""
	for i in range(buttons.size()):
		var button = buttons[i]
		var dir_path = desktop_dirs[i]["path"]

		# Highlight current directory
		if dir_path == current_directory:
			button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))  # Yellow/gold
		else:
			button.remove_theme_color_override("font_color")

func _on_directory_changed(new_directory: String):
	"""Called when directory changes in 3D mode"""
	print("DesktopSwitcherWidget: Directory changed to: ", new_directory)
	current_directory = new_directory
	_update_button_states()

func update_widget():
	"""Update widget state - called when widget becomes visible"""
	if filesystem_generator and filesystem_generator.has_method("get_current_directory"):
		var new_dir = filesystem_generator.get_current_directory()
		if new_dir != current_directory:
			print("DesktopSwitcherWidget: update_widget detected directory change: ", new_dir)
			current_directory = new_dir
			_update_button_states()
