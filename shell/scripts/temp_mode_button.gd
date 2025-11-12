extends CanvasLayer

## Temporary mode switcher button for testing
## Shows a button in 2D mode to enter 3D mode

var button: Button
var mode_manager: Node = null

func _ready():
	# Find mode manager
	mode_manager = get_node_or_null("/root/Main/ModeManager")

	if not mode_manager:
		push_error("TempModeButton: ModeManager not found!")
		return

	# Create button
	button = Button.new()
	button.text = "Enter 3D Mode"
	button.position = Vector2(10, 10)
	button.custom_minimum_size = Vector2(150, 40)
	button.pressed.connect(_on_button_pressed)
	add_child(button)

	# Listen for mode changes
	mode_manager.mode_changed.connect(_on_mode_changed)

	# Set initial visibility
	_update_button_visibility()

	print("TempModeButton initialized")

func _on_button_pressed():
	if mode_manager:
		mode_manager.switch_to_3d_mode()

func _on_mode_changed(new_mode):
	_update_button_visibility()

func _update_button_visibility():
	if not mode_manager or not button:
		return

	# Only show button in 2D mode
	button.visible = mode_manager.is_2d_mode()
