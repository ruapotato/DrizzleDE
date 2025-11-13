extends "res://shell/scripts/widget_base.gd"

## Mode Switcher Widget
##
## Shows a button to switch between 2D and 3D modes.
## In 2D mode: shows "3D Mode" button
## In 3D mode: widget is hidden (panel hidden in 3D)

var button: Button
var mode_manager: Node = null

func _widget_ready():
	widget_name = "Mode Switcher"

	# Find mode manager
	mode_manager = get_node_or_null("/root/Main/ModeManager")

	if not mode_manager:
		push_error("ModeSwitcherWidget: ModeManager not found!")
		return

	# Create button with longer text to get max size
	button = Button.new()
	button.text = "3D Mode"  # Both modes are same length
	button.pressed.connect(_on_button_pressed)
	add_child(button)

	# Listen for mode changes
	mode_manager.mode_changed.connect(_on_mode_changed)

	# Wait for button to be ready and calculate size
	await get_tree().process_frame

	# Calculate size based on button
	button.reset_size()
	await get_tree().process_frame
	var button_width = button.size.x

	# Set our minimum size based on button
	custom_minimum_size.x = button_width + 8
	min_width = button_width + 8
	preferred_width = button_width + 8

	# Update button text
	_update_button_text()

	print("ModeSwitcherWidget initialized with width: ", button_width)

func _on_button_pressed():
	if not mode_manager:
		return

	if mode_manager.is_2d_mode():
		mode_manager.switch_to_3d_mode()
	else:
		# In 3D mode, ESC already handles exit, but provide button too
		mode_manager.switch_to_2d_mode()

func _on_mode_changed(new_mode):
	_update_button_text()

func _update_button_text():
	if not mode_manager or not button:
		return

	if mode_manager.is_2d_mode():
		button.text = "3D Mode"
	else:
		button.text = "2D Mode"

func update_widget():
	_update_button_text()
