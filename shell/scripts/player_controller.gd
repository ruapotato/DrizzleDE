extends CharacterBody3D

## First-person player controller with ground walking
## Uses CharacterBody3D for proper physics-based movement

@export var mouse_sensitivity := 0.002
@export var walk_speed := 5.0
@export var sprint_speed := 10.0  # 2x walk speed
@export var jump_velocity := 4.5
@export var gravity := 15.0

var camera: Camera3D
var _mouse_captured := false
var inventory_menu: Node = null
var building_system: Node = null
var window_interaction: Node = null
var in_interaction_mode := false  # Disables gravity and movement when true

func _ready():
	# Find camera child
	camera = get_node_or_null("Camera")
	if not camera:
		push_error("Player controller requires a Camera3D child node named 'Camera'")

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

	# Find inventory menu
	inventory_menu = get_node_or_null("/root/Main/InventoryMenu")

	# Find building system
	building_system = get_node_or_null("/root/Main/BuildingSystem")

	# Find window interaction
	window_interaction = get_node_or_null("/root/Main/WindowInteraction")

func _input(event):
	# Don't process camera input when in interaction mode (window selected)
	if in_interaction_mode:
		return

	# Don't process camera input when inventory menu is open
	if inventory_menu and inventory_menu.get("menu_visible"):
		# Ensure mouse is visible
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_mouse_captured = false
		return

	# Only block camera if building UI menu is visible (not when just holding a piece)
	var building_ui = get_node_or_null("/root/Main/BuildingUI")
	if building_ui and building_ui.visible:
		# Menu is open - ensure mouse is visible
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_mouse_captured = false
		return

	if event is InputEventMouseMotion and _mouse_captured:
		# Rotate player body on Y axis
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Rotate camera on X axis (pitch)
		if camera:
			camera.rotation.x -= event.relative.y * mouse_sensitivity
			camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

	if event.is_action_pressed("ui_cancel"):
		# Don't handle ESC here if in build mode - let building system handle it
		if building_system and building_system.build_mode:
			return

		if _mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_mouse_captured = false
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_mouse_captured = true

func _physics_process(delta):
	# Don't move if in interaction mode (window selected)
	if in_interaction_mode:
		# Freeze in place, no gravity or movement
		velocity = Vector3.ZERO
		return

	# Don't move if inventory menu is open
	if inventory_menu and inventory_menu.get("menu_visible"):
		return

	# Only block movement if building UI menu is visible (not when just holding a piece)
	var building_ui = get_node_or_null("/root/Main/BuildingUI")
	if building_ui and building_ui.visible:
		return

	# Always keep mouse captured when not in a menu
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_mouse_captured = true
	else:
		_mouse_captured = true

	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump (but not when a window is selected)
	var window_selected = window_interaction and window_interaction.get("selected_window_id") != -1
	if Input.is_action_just_pressed("jump") and is_on_floor() and not window_selected:
		velocity.y = jump_velocity

	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Calculate movement direction relative to player rotation
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Determine speed
	var speed = sprint_speed if Input.is_action_pressed("ui_shift") else walk_speed

	# Apply movement
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func set_interaction_mode(enabled: bool):
	in_interaction_mode = enabled
	if enabled:
		print("Player: Interaction mode enabled (gravity/movement disabled)")
	else:
		print("Player: Interaction mode disabled (gravity/movement restored)")
