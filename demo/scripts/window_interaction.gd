extends Node3D

## Handles window selection via raycasting and input forwarding

@export var camera_path: NodePath
@export var compositor_path: NodePath
@export var raycast_distance := 100.0

var camera: Camera3D
var compositor: Node
var focused_window_id := -1
var focused_window_quad: MeshInstance3D = null

# For tracking window-local mouse position
var last_hit_pos := Vector2.ZERO

func _ready():
	if camera_path:
		camera = get_node(camera_path)
	else:
		camera = get_viewport().get_camera_3d()

	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		compositor = get_node_or_null("/root/Main/X11Compositor")

	if not camera:
		push_error("Window interaction: Camera not found!")
	if not compositor:
		push_error("Window interaction: Compositor not found!")

func _process(delta):
	if not camera or not compositor or not compositor.is_initialized():
		return

	# Raycast from camera center to detect which window we're looking at
	var from = camera.global_position
	var to = from - camera.global_transform.basis.z * raycast_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider is MeshInstance3D:
			# Check if this is a window quad
			var window_id = get_window_id_from_quad(collider)
			if window_id != -1:
				if window_id != focused_window_id:
					set_focused_window(window_id, collider)

				# Calculate local hit position on the quad
				var hit_point = result.position
				var local_pos = collider.global_transform.affine_inverse() * hit_point

				# Convert from 3D quad space to 2D texture coordinates
				# Quad is centered at origin with size (aspect, 1)
				var window_size = compositor.get_window_size(window_id)
				if window_size.x > 0 and window_size.y > 0:
					var aspect = float(window_size.x) / float(window_size.y)

					# local_pos.x ranges from -aspect/2 to aspect/2
					# local_pos.y ranges from -0.5 to 0.5
					var tex_x = (local_pos.x / aspect + 0.5) * window_size.x
					var tex_y = (-local_pos.y + 0.5) * window_size.y  # Flip Y

					last_hit_pos = Vector2(tex_x, tex_y)

				return

	# No hit, clear focus
	if focused_window_id != -1:
		clear_focused_window()

func _input(event):
	if focused_window_id == -1 or not compositor:
		return

	# Only handle input if mouse is captured (FPS mode)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	var window_size = compositor.get_window_size(focused_window_id)
	if window_size.x <= 0 or window_size.y <= 0:
		return

	# Forward mouse button events
	if event is InputEventMouseButton:
		var x = int(clamp(last_hit_pos.x, 0, window_size.x - 1))
		var y = int(clamp(last_hit_pos.y, 0, window_size.y - 1))

		compositor.send_mouse_button(
			focused_window_id,
			event.button_index,
			event.pressed,
			x,
			y
		)

		# Set focus when clicking
		if event.pressed:
			compositor.set_window_focus(focused_window_id)

	# Forward mouse motion (relative movement from FPS camera)
	elif event is InputEventMouseMotion:
		# Update position based on relative mouse movement
		# Scale mouse sensitivity to window size
		var sensitivity = 2.0  # Adjust this for mouse speed
		last_hit_pos.x += event.relative.x * sensitivity
		last_hit_pos.y += event.relative.y * sensitivity

		# Clamp to window bounds
		last_hit_pos.x = clamp(last_hit_pos.x, 0, window_size.x - 1)
		last_hit_pos.y = clamp(last_hit_pos.y, 0, window_size.y - 1)

		compositor.send_mouse_motion(
			focused_window_id,
			int(last_hit_pos.x),
			int(last_hit_pos.y)
		)

	# Forward keyboard events
	elif event is InputEventKey:
		# Don't forward camera control keys
		if event.is_action("ui_cancel") or \
		   event.is_action("move_forward") or \
		   event.is_action("move_backward") or \
		   event.is_action("move_left") or \
		   event.is_action("move_right") or \
		   event.is_action("jump") or \
		   event.is_action("crouch"):
			return

		compositor.send_key_event(
			focused_window_id,
			event.keycode,
			event.pressed
		)

func get_window_id_from_quad(quad: MeshInstance3D) -> int:
	# Check if this quad has window_id metadata
	if quad.has_meta("window_id"):
		return quad.get_meta("window_id")
	return -1

func set_focused_window(window_id: int, quad: MeshInstance3D):
	focused_window_id = window_id
	focused_window_quad = quad

	# Add visual feedback - create outline material
	add_window_highlight(quad)

	var window_class = compositor.get_window_class(window_id)
	var window_title = compositor.get_window_title(window_id)
	print("Focused window: ", window_title, " [", window_class, "]")

func clear_focused_window():
	if focused_window_quad:
		remove_window_highlight(focused_window_quad)

	focused_window_id = -1
	focused_window_quad = null

func add_window_highlight(quad: MeshInstance3D):
	# Add a subtle highlight by modulating the material
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		# Store original color if not already stored
		if not quad.has_meta("original_albedo"):
			quad.set_meta("original_albedo", mat.albedo_color)

		# Add slight blue tint to indicate focus
		mat.albedo_color = Color(0.9, 0.9, 1.0, 1.0)

func remove_window_highlight(quad: MeshInstance3D):
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")
