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
var mouse_sphere: MeshInstance3D = null
var click_tween: Tween = null
var last_raycast_hit := Vector3.ZERO
var last_raycast_hit_valid := false

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

	create_mouse_sphere()

	print("WindowInteraction initialized!")
	print("  Camera: ", camera)
	print("  Compositor: ", compositor)

func create_mouse_sphere():
	# Create a 3D sphere for the mouse cursor
	mouse_sphere = MeshInstance3D.new()
	add_child(mouse_sphere)

	# Create sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04
	sphere_mesh.radial_segments = 16
	sphere_mesh.rings = 8
	mouse_sphere.mesh = sphere_mesh

	# Bright material so it's always visible
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.3, 0.3, 1.0)  # Red
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.3)
	material.emission_energy_multiplier = 2.0
	mouse_sphere.material_override = material

	mouse_sphere.visible = true

	print("Mouse sphere created and visible")

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
		last_raycast_hit = result.position
		last_raycast_hit_valid = true

		# Always position mouse sphere at raycast hit
		mouse_sphere.global_position = last_raycast_hit
		mouse_sphere.visible = true

		var collider = result.collider

		# Debug what we hit
		if collider is StaticBody3D:
			if collider.has_meta("window_id"):
				var window_id = collider.get_meta("window_id")
				var quad = collider.get_parent() as MeshInstance3D

				if quad and window_id != -1:
					handle_window_raycast_hit(window_id, quad, result.position, delta)
					return
			else:
				print_debug("Hit StaticBody3D but no window_id metadata")
		else:
			print_debug("Hit non-StaticBody3D: ", collider.get_class())

	else:
		# No hit - place sphere far in front of camera
		last_raycast_hit_valid = false
		mouse_sphere.global_position = from + (-camera.global_transform.basis.z * 3.0)
		mouse_sphere.visible = true

	# No window hit - clear hover AND selection (auto-deselect when looking away)
	if current_state == WindowState.HOVERED:
		clear_hover()
	elif current_state == WindowState.SELECTED:
		deselect_window()

func handle_window_raycast_hit(window_id: int, quad: MeshInstance3D, hit_pos: Vector3, delta: float):
	# Calculate window-local mouse position
	var local_pos = quad.global_transform.affine_inverse() * hit_pos
	var window_size = compositor.get_window_size(window_id)

	if window_size.x > 0 and window_size.y > 0:
		# local_pos is in quad's local space where quad mesh is 1x1 (before scaling)
		# So local_pos.x and local_pos.y range from -0.5 to +0.5
		# Convert directly to texture coordinates
		var tex_x = (local_pos.x + 0.5) * window_size.x
		var tex_y = (-local_pos.y + 0.5) * window_size.y
		window_mouse_pos = Vector2(
			clamp(tex_x, 0, window_size.x - 1),
			clamp(tex_y, 0, window_size.y - 1)
		)

		# Debug popup window mouse coordinates with full details
		var parent_id = compositor.get_parent_window_id(window_id)
		if parent_id != -1:
			print("━━━ POPUP MOUSE DEBUG ━━━")
			print("  Window ID: ", window_id, " (parent: ", parent_id, ")")
			print("  Hit pos (world): ", hit_pos)
			print("  Quad position: ", quad.global_position)
			print("  Quad scale: ", quad.scale)
			print("  Local pos (mesh space): ", local_pos)
			print("  Window size (pixels): ", window_size)
			print("  Calculated tex coords: (", tex_x, ", ", tex_y, ")")
			print("  Sending to X11: (", int(window_mouse_pos.x), ", ", int(window_mouse_pos.y), ")")
			print("━━━━━━━━━━━━━━━━━━━━━━")

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
				print("Switched hover from window ", hovered_window_id, " to ", window_id)
				clear_hover()
				start_hover(window_id, quad)
			else:
				# Continue hovering - increment timer
				hover_timer += delta
				if hover_timer >= hover_delay and not can_select:
					can_select = true
					update_hover_visual(true)  # Show "ready to select"
					print("Window ", window_id, " ready to select (hovered ", hover_timer, "s)")

		WindowState.SELECTED:
			# If looking at a different window, auto-deselect and start hovering the new one
			if window_id != selected_window_id:
				print("Looking at different window - auto-deselecting")
				deselect_window()
				start_hover(window_id, quad)
			# Otherwise just update mouse position (already handled above)

func start_hover(window_id: int, quad: MeshInstance3D):
	current_state = WindowState.HOVERED
	hovered_window_id = window_id
	hovered_window_quad = quad
	hover_timer = 0.0
	can_select = false

	add_hover_highlight(quad)

	var window_title = compositor.get_window_title(window_id)
	var window_class = compositor.get_window_class(window_id)
	print(">>> HOVERING window ", window_id, ": ", window_title, " [", window_class, "]")
	print("    Hover for ", hover_delay, "s then click to select")

func clear_hover():
	if hovered_window_quad and current_state == WindowState.HOVERED:
		remove_hover_highlight(hovered_window_quad)

	print("Hover cleared on window ", hovered_window_id)

	current_state = WindowState.NONE
	hovered_window_id = -1
	hovered_window_quad = null
	hover_timer = 0.0
	can_select = false

func select_window(window_id: int, quad: MeshInstance3D):
	# Clear hover state completely
	if hovered_window_quad:
		remove_hover_highlight(hovered_window_quad)

	# Make sure to restore original color on the quad being selected
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")

	current_state = WindowState.SELECTED
	selected_window_id = window_id
	selected_window_quad = quad

	# Clear hover tracking
	hovered_window_id = -1
	hovered_window_quad = null
	hover_timer = 0.0
	can_select = false

	# Set X11 focus
	compositor.set_window_focus(window_id)

	# Add selection border/glow
	add_selection_glow(quad)

	var window_title = compositor.get_window_title(window_id)
	print("╔═══════════════════════════════════════╗")
	print("║ WINDOW SELECTED!                      ║")
	print(window_title)
	print("║                                       ║")
	print("║ Mouse/keyboard goes to this window    ║")
	print("║ Press ESC to release                  ║")
	print("╚═══════════════════════════════════════╝")

func deselect_window():
	if selected_window_quad:
		remove_selection_glow(selected_window_quad)

	print(">>> Window ", selected_window_id, " DESELECTED")
	print("    Camera controls restored")

	current_state = WindowState.NONE
	selected_window_id = -1
	selected_window_quad = null

func _input(event):
	# Handle mouse button events
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Only act on PRESS, not release
		if not event.pressed:
			# Forward release to selected window if any
			if current_state == WindowState.SELECTED:
				compositor.send_mouse_button(
					selected_window_id,
					event.button_index,
					false,
					int(window_mouse_pos.x),
					int(window_mouse_pos.y)
				)
				get_viewport().set_input_as_handled()
			return

		# Mouse button PRESSED
		print_debug("Mouse click PRESSED - State: ", ["NONE", "HOVERED", "SELECTED"][current_state])

		if current_state == WindowState.HOVERED and can_select:
			# Select the hovered window
			print("Click to SELECT window ", hovered_window_id)
			select_window(hovered_window_id, hovered_window_quad)
			pulse_click()
			get_viewport().set_input_as_handled()
			return

		elif current_state == WindowState.SELECTED:
			# Click on selected window - forward to X11
			print("Forwarding click to window ", selected_window_id, " at (", int(window_mouse_pos.x), ", ", int(window_mouse_pos.y), ")")
			compositor.send_mouse_button(
				selected_window_id,
				event.button_index,
				true,  # pressed
				int(window_mouse_pos.x),
				int(window_mouse_pos.y)
			)
			pulse_click()
			get_viewport().set_input_as_handled()
			return

		else:
			print("Click ignored - not ready (can_select=", can_select, ", hover_timer=", hover_timer, ")")
			return

	# Forward other mouse buttons
	if event is InputEventMouseButton:
		if current_state == WindowState.SELECTED:
			compositor.send_mouse_button(
				selected_window_id,
				event.button_index,
				event.pressed,
				int(window_mouse_pos.x),
				int(window_mouse_pos.y)
			)
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
			# ALWAYS consume the event first to prevent Godot from processing it
			get_viewport().set_input_as_handled()

			print("Forwarding key ", event.keycode, " (", event.as_text(), ") to window ", selected_window_id)
			compositor.send_key_event(
				selected_window_id,
				event.keycode,
				event.pressed
			)

func pulse_click():
	# Animate sphere pulse when clicking
	if click_tween:
		click_tween.kill()

	click_tween = create_tween()
	click_tween.tween_property(mouse_sphere, "scale", Vector3(2.0, 2.0, 2.0), 0.1)
	click_tween.tween_property(mouse_sphere, "scale", Vector3(1.0, 1.0, 1.0), 0.2)

## Visual feedback

func add_hover_highlight(quad: MeshInstance3D):
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if not quad.has_meta("original_albedo"):
			quad.set_meta("original_albedo", mat.albedo_color)
		# Subtle highlight
		mat.albedo_color = Color(0.95, 0.95, 1.0, 1.0)
		print("  Added hover highlight")

func remove_hover_highlight(quad: MeshInstance3D):
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")
		print("  Removed hover highlight")

func update_hover_visual(ready: bool):
	if not hovered_window_quad:
		return

	if hovered_window_quad.material_override and hovered_window_quad.material_override is StandardMaterial3D:
		var mat = hovered_window_quad.material_override as StandardMaterial3D
		if ready:
			# Brighter when ready to select
			mat.albedo_color = Color(0.9, 1.0, 0.9, 1.0)  # Green tint
			print("  Window ready to select - GREEN")
		else:
			mat.albedo_color = Color(0.95, 0.95, 1.0, 1.0)

func add_selection_glow(quad: MeshInstance3D):
	# Create a glowing border using a MeshInstance3D outline
	var outline = MeshInstance3D.new()
	quad.add_child(outline)
	outline.name = "SelectionGlow"

	# Create a much larger quad for a very visible border
	var outline_mesh = QuadMesh.new()
	outline_mesh.size = Vector2(1.15, 1.15)  # 15% larger for very visible border
	outline.mesh = outline_mesh

	# Bright glowing material - VERY visible cyan
	var glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.0, 1.0, 1.0, 1.0)  # Pure cyan
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.0, 1.0, 1.0)  # Pure cyan emission
	glow_mat.emission_energy_multiplier = 5.0  # Very bright
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.material_override = glow_mat

	# Position in FRONT of the window (negative Z = towards camera in local quad space)
	outline.position.z = -0.02

	print("  Added BRIGHT CYAN selection glow border (in front of window)")

func remove_selection_glow(quad: MeshInstance3D):
	var glow = quad.get_node_or_null("SelectionGlow")
	if glow:
		glow.queue_free()
		print("  Removed selection glow")

	# Restore original color
	if quad.material_override and quad.material_override is StandardMaterial3D:
		var mat = quad.material_override as StandardMaterial3D
		if quad.has_meta("original_albedo"):
			mat.albedo_color = quad.get_meta("original_albedo")
