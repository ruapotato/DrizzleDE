extends CanvasLayer

## In-game inventory menu for launching X11 applications

@export var compositor_path: NodePath

var compositor: Node
var menu_visible := false

# Application catalog - add your favorite apps here
var applications := [
	{"name": "Terminal", "command": "xterm", "description": "X Terminal Emulator"},
	{"name": "Firefox", "command": "firefox", "description": "Web Browser"},
	{"name": "Text Editor", "command": "gedit", "description": "Simple text editor"},
	{"name": "File Manager", "command": "thunar", "description": "File browser"},
	{"name": "Calculator", "command": "gnome-calculator", "description": "Calculator app"},
	{"name": "XClock", "command": "xclock", "description": "Simple clock"},
	{"name": "XEyes", "command": "xeyes", "description": "Fun eye tracker"},
]

# UI elements
var panel: Panel
var app_list: VBoxContainer
var title_label: Label
var close_button: Button

func _ready():
	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		compositor = get_node_or_null("/root/Main/X11Compositor")

	if not compositor:
		push_error("Compositor not found for inventory menu!")
		return

	# Create UI
	create_menu_ui()
	hide_menu()

func _input(event):
	if event.is_action_pressed("ui_tab") or (event is InputEventKey and event.pressed and event.keycode == KEY_I):
		toggle_menu()
		get_viewport().set_input_as_handled()

func create_menu_ui():
	# Main panel
	panel = Panel.new()
	add_child(panel)

	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(400, 500)
	panel.position = -panel.size / 2

	# Add some style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	# Set border widths individually (Godot 4 doesn't have border_width_all)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.5, 0.8, 1.0)
	# Set corner radii individually (Godot 4 doesn't have corner_radius_all)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	# Title
	title_label = Label.new()
	panel.add_child(title_label)
	title_label.text = "Application Launcher"
	title_label.position = Vector2(20, 15)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))

	# Close button
	close_button = Button.new()
	panel.add_child(close_button)
	close_button.text = "Close (ESC)"
	close_button.position = Vector2(panel.size.x - 120, 10)
	close_button.size = Vector2(100, 30)
	close_button.pressed.connect(hide_menu)

	# Scroll container for apps
	var scroll = ScrollContainer.new()
	panel.add_child(scroll)
	scroll.position = Vector2(10, 60)
	scroll.size = Vector2(panel.size.x - 20, panel.size.y - 70)

	# App list container
	app_list = VBoxContainer.new()
	scroll.add_child(app_list)
	app_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Populate app list
	for app in applications:
		create_app_button(app)

func create_app_button(app: Dictionary):
	var button_container = HBoxContainer.new()
	app_list.add_child(button_container)
	button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Launch button
	var button = Button.new()
	button_container.add_child(button)
	button.text = app.name
	button.custom_minimum_size = Vector2(150, 40)
	button.tooltip_text = app.description
	button.pressed.connect(func(): launch_application(app.command))

	# Description label
	var desc_label = Label.new()
	button_container.add_child(desc_label)
	desc_label.text = app.description
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Spacing
	var spacer = Control.new()
	app_list.add_child(spacer)
	spacer.custom_minimum_size = Vector2(0, 5)

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
	var shell_command = "DISPLAY=%s %s &" % [display, command]
	print("Executing: ", shell_command)

	var output = []
	var exit_code = OS.execute("sh", ["-c", shell_command], output, false, false)

	if exit_code == 0:
		print("✓ Launched ", command, " successfully")
	else:
		push_error("✗ Failed to launch ", command, " (exit code: ", exit_code, ")")
		if output.size() > 0:
			print("Output: ", output)

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

func hide_menu():
	panel.visible = false
	menu_visible = false
	# Recapture mouse for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
