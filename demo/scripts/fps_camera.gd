extends Camera3D

## Simple FPS camera controller for navigating the 3D workspace
## Automatically disables when a window is selected

@export var mouse_sensitivity := 0.002
@export var move_speed := 5.0
@export var sprint_multiplier := 2.0
@export var window_interaction_path: NodePath

var _mouse_captured := false
var window_interaction: Node = null
var inventory_menu: Node = null

func _ready():
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    _mouse_captured = true

    # Find window interaction node
    if window_interaction_path:
        window_interaction = get_node(window_interaction_path)
    else:
        # Try to find it in the scene
        window_interaction = get_node_or_null("/root/Main/WindowInteraction")

    # Find inventory menu
    inventory_menu = get_node_or_null("/root/Main/InventoryMenu")

func _input(event):
    # Don't process camera input when inventory menu is open
    if inventory_menu and inventory_menu.menu_visible:
        return

    if event is InputEventMouseMotion and _mouse_captured:
        rotate_y(-event.relative.x * mouse_sensitivity)

        var camera_rot = rotation
        camera_rot.x -= event.relative.y * mouse_sensitivity
        camera_rot.x = clamp(camera_rot.x, -PI/2, PI/2)
        rotation = camera_rot

    if event.is_action_pressed("ui_cancel"):
        if _mouse_captured:
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
            _mouse_captured = false
        else:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
            _mouse_captured = true

func _process(delta):
    # Don't move if a window is selected - player must look away to deselect
    if window_interaction and window_interaction.current_state == window_interaction.WindowState.SELECTED:
        return

    var velocity = Vector3.ZERO

    if Input.is_action_pressed("move_forward"):
        velocity -= transform.basis.z
    if Input.is_action_pressed("move_backward"):
        velocity += transform.basis.z
    if Input.is_action_pressed("move_left"):
        velocity -= transform.basis.x
    if Input.is_action_pressed("move_right"):
        velocity += transform.basis.x

    var speed = move_speed
    if Input.is_action_pressed("ui_shift"):
        speed *= sprint_multiplier

    if Input.is_action_pressed("jump"):
        velocity.y += 1.0
    if Input.is_action_pressed("crouch"):
        velocity.y -= 1.0

    if velocity.length() > 0:
        velocity = velocity.normalized() * speed
        global_position += velocity * delta
