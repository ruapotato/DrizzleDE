extends Node3D

## Handles window selection via raycasting and input forwarding
##
## States:
## - NONE: Not looking at any window
## - HOVERED: Looking at window (can select after delay)
## - SELECTED: Window is focused, receiving all input

enum WindowState { NONE, HOVERED, SELECTED }

@export var camera_path: NodePath
@export var compositor_path: NodePath
@export var raycast_distance := 100.0
@export var hover_delay := 0.5  # Seconds to hover before can select
@export var escape_key := KEY_ESCAPE

var camera: Camera3D
var compositor: Node

# State management
var current_state := WindowState.NONE
var hovered_window_id := -1
var hovered_window_quad: MeshInstance3D = null
var selected_window_id := -1
var selected_window_quad: MeshInstance3D = null

# Timing
var hover_timer := 0.0
var can_select := false

# Mouse tracking
var window_mouse_pos := Vector2.ZERO
var mouse_cursor: Sprite3D = null

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

	create_mouse_cursor()

func create_mouse_cursor():
	# Create a 3D sprite for the mouse cursor
	mouse_cursor = Sprite3D.new()
	add_child(mouse_cursor)

	# Create a simple cursor texture (white circle with black outline)
	var cursor_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	cursor_img.fill(Color(0, 0, 0, 0))

	# Draw a simple arrow cursor
	for y in range(16):
		for x in range(16):
			if x < 8 and y < 12 and x <= y:
				if x == 0 or y == 0 or x == y:
					cursor_img.set_pixel(x, y, Color.BLACK)
				else:
					cursor_img.set_pixel(x, y, Color.WHITE)

	var cursor_texture = ImageTexture.create_from_image(cursor_img)
	mouse_cursor.texture = cursor_texture
	mouse_cursor.pixel_size = 0.01
	mouse_cursor.billboard = SpriteBase3D.BILLBOARD_DISABLED
	mouse_cursor.visible = false
	mouse_cursor.render_priority = 10  # Draw on top

func _process(delta):
	if not camera or not compositor or not compositor.is_initialized():
		return

	# Raycast from camera center
	var from = camera.global_position
	var to = from - camera.global_transform.basis.z * raycast_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider is StaticBody3D and collider.has_meta("window_id"):
			var window_id = collider.get_meta("window_id")
			var quad = collider.get_parent() as MeshInstance3D

			if quad and window_id != -1:
				handle_window_raycast_hit(window_id, quad, result.position, delta)
				return

	# No hit - clear hover state (but keep selection)
	if current_state == WindowState.HOVERED:
		clear_hover()

func handle_window_raycast_hit(window_id: int, quad: MeshInstance3D, hit_pos: Vector3, delta: float):
	# Calculate window-local mouse position
	var local_pos = quad.global_transform.affine_inverse() * hit_pos
	var window_size = compositor.get_window_size(window_id)

	if window_size.x > 0 and window_size.y > 0:
		var aspect = float(window_size.x) / float(window_size.y)
		var tex_x = (local_pos.x / aspect + 0.5) * window_size.x
		var tex_y = (-local_pos.y + 0.5) * window_size.y
		window_mouse_pos = Vector2(
			clamp(tex_x, 0, window_size.x - 1),
			clamp(tex_y, 0, window_size.y - 1)
		)

		# Update cursor position
		update_cursor_position(quad, local_pos)

	# Forward mouse motion to window
	if window_id != -1:
		compositor.send_mouse_motion(
			window_id,
			int(window_mouse_pos.x),
			int(window_mouse_pos.y)
		)

	# State machine
	match current_state:
		WindowState.NONE:
			# Start hovering
			start_hover(window_id, quad)

		WindowState.HOVERED:
			if window_id != hovered_window_id:
				# Switched to different window
				clear_hover()
				start_hover(window_id, quad)
			else:
				# Continue hovering - increment timer
				hover_timer += delta
				if hover_timer >= hover_delay:
					can_select = true
					update_hover_visual(true)  # Show "ready to select"

		WindowState.SELECTED:
			# Already selected, just update mouse position
			# Selected window doesn't change on hover
			pass

func update_cursor_position(quad: MeshInstance3D, local_pos: Vector3):
	if mouse_cursor:
		# Position cursor on the quad surface
		mouse_cursor.global_position = quad.global_transform * local_pos
		mouse_cursor.global_position += quad.global_transform.basis.z * -0.01  # Offset slightly forward
		mouse_cursor.visible = (current_state == WindowState.HOVERED)

func start_hover(window_id: int, quad: MeshInstance3D):
	current_state = WindowState.HOVERED
	hovered_window_id = window_id
	hovered_window_quad = quad
	hover_timer = 0.0
	can_select = false

	add_hover_highlight(quad)

	var window_title = compositor.get_window_title(window_id)
	var window_class = compositor.get_window_class(window_id)
	print("Hovering: ", window_title, " [", window_class, "]")

func clear_hover():
	if hovered_window_quad and current_state == WindowState.HOVERED:
		remove_hover_highlight(hovered_window_quad)

	current_state = WindowState.NONE
	hovered_window_id = -1
	hovered_window_quad = null
	hover_timer = 0.0
	can_select = false

	if mouse_cursor:
		mouse_cursor.visible = false

func select_window(window_id: int, quad: MeshInstance3D):
	# Clear hover state
	if hovered_window_quad:
		remove_hover_highlight(hovered_window_quad)

	current_state = WindowState.SELECTED
	selected_window_id = window_id
	selected_window_quad = quad

	# Set X11 focus
	compositor.set_window_focus(window_id)

	# Add selection border/glow
	add_selection_glow(quad)

	var window_title = compositor.get_window_title(window_id)
	print("SELECTED: ", window_title, " - Press ESC to release")

func deselect_window():
	if selected_window_quad:
		remove_selection_glow(selected_window_quad)

	current_state = WindowState.NONE
	selected_window_id = -1
	selected_window_quad = null

	print("Window deselected")

func _input(event):
	# Handle selection toggle
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if current_state == WindowState.HOVERED and can_select:
			# Select the hovered window
			select_window(hovered_window_id, hovered_window_quad)
			get_viewport().set_input_as_handled()
			return
		elif current_state == WindowState.SELECTED:
			# Click on selected window - forward to X11
			compositor.send_mouse_button(
				selected_window_id,
				event.button_index,
				event.pressed,
				int(window_mouse_pos.x),
				int(window_mouse_pos.y)
			)
			get_viewport().set_input_as_handled()
			return

	# Forward mouse buttons to hovered/selected window
	if event is InputEventMouseButton:
		var target_id = selected_window_id if current_state == WindowState.SELECTED else hovered_window_id
		if target_id != -1:
			compositor.send_mouse_button(
				target_id,
				event.button_index,
				event.pressed,
				int(window_mouse_pos.x),
				int(window_mouse_pos.y)
			)
			if current_state == WindowState.SELECTED:
				get_viewport().set_input_as_handled()
			return

	# Keyboard input - only forward when SELECTED
	if event is InputEventKey:
		# Check for escape to deselect
		if current_state == WindowState.SELECTED and event.keycode == escape_key and event.pressed:
			deselect_window()
			get_viewport().set_input_as_handled()
			return

		# Forward all keyboard input to selected window
		if current_state == WindowState.SELECTED:
			# Don't forward camera controls
			if event.is_action("move_forward") or event.is_action("move_backward") or \
			   event.is_action("move_left") or event.is_action("move_right") or \
			   event.is_action("jump") or event.is_action("crouch"):
				return

			compositor.send_key_event(
				selected_window_id,
				event.keycode,
				event.pressed
			)
			get_viewport().set_input_as_handled()

## Visual feedback

func add_hover_highlight(quad: MeshInstance3D):
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if not quad.has_meta("original_albedo"):
			quad.set_meta("original_albedo", mat.albedo_color)
		# Subtle highlight
		mat.albedo_color = Color(0.95, 0.95, 1.0, 1.0)

func remove_hover_highlight(quad: MeshInstance3D):
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")

func update_hover_visual(ready: bool):
	if not hovered_window_quad:
		return

	if hovered_window_quad.material_override and hovered_window_quad.material_override is StandardMaterial3D:
		var mat = hovered_window_quad.material_override as StandardMaterial3D
		if ready:
			# Brighter when ready to select
			mat.albedo_color = Color(0.9, 1.0, 0.9, 1.0)  # Green tint
		else:
			mat.albedo_color = Color(0.95, 0.95, 1.0, 1.0)

func add_selection_glow(quad: MeshInstance3D):
	# Create a glowing border using a MeshInstance3D outline
	var outline = MeshInstance3D.new()
	quad.add_child(outline)
	outline.name = "SelectionGlow"

	# Create a slightly larger quad for the border
	var outline_mesh = QuadMesh.new()
	outline_mesh.size = Vector2(1.05, 1.05)  # 5% larger
	outline.mesh = outline_mesh

	# Glowing material
	var glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.3, 0.8, 1.0, 1.0)  # Cyan glow
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.3, 0.8, 1.0)
	glow_mat.emission_energy_multiplier = 2.0
	outline.material_override = glow_mat

	# Position slightly behind the window
	outline.position.z = 0.001

func remove_selection_glow(quad: MeshInstance3D):
	var glow = quad.get_node_or_null("SelectionGlow")
	if glow:
		glow.queue_free()

	# Restore original color
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")
