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

func _widget_ready():
	widget_name = "Desktop Switcher"
	min_width = 300
	preferred_width = 400

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

	# Create button container
	button_container = HBoxContainer.new()
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(button_container)

	# Create buttons for each desktop directory
	for dir_info in desktop_dirs:
		var button = Button.new()
		button.text = dir_info["name"]
		button.custom_minimum_size = Vector2(60, 0)
		button.pressed.connect(_on_directory_button_pressed.bind(dir_info["path"]))
		button_container.add_child(button)
		buttons.append(button)

	# Update button states
	_update_button_states()

	print("DesktopSwitcherWidget initialized")

func _on_directory_button_pressed(directory_path: String):
	"""Switch to the selected directory"""
	print("Switching desktop to: ", directory_path)

	if filesystem_generator and filesystem_generator.has_method("load_directory"):
		filesystem_generator.load_directory(directory_path)
		current_directory = directory_path
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

func update_widget():
	"""Update widget state"""
	if filesystem_generator and filesystem_generator.has_method("get_current_directory"):
		var new_dir = filesystem_generator.get_current_directory()
		if new_dir != current_directory:
			current_directory = new_dir
			_update_button_states()
