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
@export var hover_delay := 999.0  # Disabled - click only to select
@export var hover_switch_delay := 0.1  # Minimum time before switching hover to different window
@export var escape_key := KEY_ESCAPE

# Focus mode settings
@export var focus_distance_min := 1.0  # Minimum distance from camera
@export var focus_distance_max := 8.0  # Maximum distance from camera
@export var focus_padding := 1.2  # Padding factor (1.2 = 20% margin around window)
@export var focus_scale_multiplier := 1.5  # Scale up windows when focused
@export var focus_animation_duration := 0.3  # Seconds for smooth animation

var camera: Camera3D
var compositor: Node
var mode_manager: Node = null

# State management
var current_state := WindowState.NONE
var hovered_window_id := -1
var hovered_window_quad: MeshInstance3D = null
var selected_window_id := -1
var selected_window_quad: MeshInstance3D = null

# Timing
var hover_timer := 0.0
var hover_switch_timer := 0.0  # Prevents rapid switching between overlapping windows
var just_switched_to_parent := false  # Prevents immediate deselection after parent switch

# Mouse tracking
var window_mouse_pos := Vector2.ZERO
var mouse_sphere: MeshInstance3D = null
var click_tween: Tween = null
var last_raycast_hit := Vector3.ZERO
var last_raycast_hit_valid := false

# Focus mode animation
var focus_tween: Tween = null
var original_camera_transform := {}  # Stores camera transform for restoration
var in_2d_mode := false  # Track if we're in 2D cursor mode
var visible_popup_windows := []  # Track popup windows visible in 2D mode
var current_focus_distance := 0.0  # Current camera distance in 2D mode

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

	# Find mode manager
	mode_manager = get_node_or_null("/root/Main/ModeManager")

	create_mouse_sphere()

	print("WindowInteraction initialized!")
	print("  Camera: ", camera)
	print("  Compositor: ", compositor)
	print("  ModeManager: ", mode_manager)

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
	# Disable all window interaction in 2D mode (Window2DManager handles it)
	if mode_manager and mode_manager.is_2d_mode():
		# Hide mouse sphere
		if mouse_sphere:
			mouse_sphere.visible = false
		return
	if not camera or not compositor or not compositor.is_initialized():
		return

	# Check if selected window is still mapped (not closed)
	if current_state == WindowState.SELECTED and selected_window_id != -1:
		if not compositor.is_window_mapped(selected_window_id):
			print(">>> Selected window ", selected_window_id, " was unmapped (closed) - auto-deselecting")
			deselect_window()
			# Don't return here - continue with raycast to potentially select parent/new window

	# In 2D mode, use screen coordinates for mouse tracking
	if in_2d_mode and current_state == WindowState.SELECTED and selected_window_quad:
		update_2d_mouse_position()

		# Check for new popup windows and adjust camera distance if needed
		check_and_adjust_for_popups()

		return  # Skip raycasting when in 2D mode

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

		# Check for file cubes first (they have metadata attached to their parent mesh)
		if collider is StaticBody3D and collider.get_parent():
			var parent = collider.get_parent()
			if parent.has_meta("file_path"):
				handle_file_cube_hit(parent)
				return

		# Debug what we hit
		if collider is StaticBody3D:
			# Check if this is the exit button
			if collider.has_meta("is_exit_button"):
				handle_exit_button_hit(collider)
				return

			if collider.has_meta("window_id"):
				var window_id = collider.get_meta("window_id")
				var quad = collider.get_parent() as MeshInstance3D

				if quad and window_id != -1:
					handle_window_raycast_hit(window_id, quad, result.position, delta)
					return
			# else:
			# 	print_debug("Hit StaticBody3D but no window_id metadata")
		# else:
		# 	print_debug("Hit non-StaticBody3D: ", collider.get_class())

	else:
		# No hit - place sphere far in front of camera
		last_raycast_hit_valid = false
		mouse_sphere.global_position = from + (-camera.global_transform.basis.z * 3.0)
		mouse_sphere.visible = true

	# No window hit - clear hover only (NOT selection)
	# When SELECTED, only ESC or exit button should deselect, not looking away
	# But DON'T deselect if we just switched to parent window (give it one frame)
	if just_switched_to_parent:
		just_switched_to_parent = false
		return

	# Clear file hover
	clear_file_hover()

	# Clear exit button hover
	clear_exit_button_hover()

	if current_state == WindowState.HOVERED:
		clear_hover()
	# Don't auto-deselect when SELECTED - only ESC or exit button should deselect

func handle_exit_button_hit(button_collider: StaticBody3D):
	# User is looking at the exit button - highlight it
	var exit_button = button_collider.get_parent()
	if exit_button and exit_button.material_override:
		var mat = exit_button.material_override as StandardMaterial3D
		if mat:
			# Brighten button on hover
			mat.albedo_color = Color(1.0, 0.3, 0.3, 1.0)
			mat.emission = Color(1.0, 0.3, 0.3)

	# Store hovered button for click detection
	set_meta("hovered_exit_button", button_collider)

func handle_window_raycast_hit(window_id: int, quad: MeshInstance3D, hit_pos: Vector3, delta: float):
	# Clear file hover when looking at window
	clear_file_hover()

	# Clear exit button hover when looking at window (not button)
	clear_exit_button_hover()

	# Skip unmapped (closed) windows - don't allow hover/selection
	if not compositor.is_window_mapped(window_id):
		# Window is closed but quad still exists - treat as no hit
		if current_state == WindowState.HOVERED:
			clear_hover()
		elif current_state == WindowState.SELECTED:
			deselect_window()
		return

	# Calculate window-local mouse position
	var local_pos = quad.global_transform.affine_inverse() * hit_pos
	var window_size = compositor.get_window_size(window_id)

	if window_size.x > 0 and window_size.y > 0:
		# local_pos is in quad's local space where quad mesh is 1x1 (before scaling)
		# affine_inverse() already accounts for scale, so local_pos ranges from -0.5 to +0.5
		# Convert directly to texture coordinates
		var tex_x = (local_pos.x + 0.5) * window_size.x
		var tex_y = (-local_pos.y + 0.5) * window_size.y
		window_mouse_pos = Vector2(
			clamp(tex_x, 0, window_size.x - 1),
			clamp(tex_y, 0, window_size.y - 1)
		)

		# Debug ALL window mouse coordinates (throttled to avoid spam)
		if window_id == selected_window_id:
			var time = Time.get_ticks_msec()
			if not has_meta("last_debug_time") or time - get_meta("last_debug_time") > 500:
				set_meta("last_debug_time", time)
				var parent_id = compositor.get_parent_window_id(window_id)

				# Check collision shape size
				var static_body = quad.get_node_or_null("StaticBody3D")
				var collision_size = Vector3.ZERO
				if static_body:
					var collision_shape = static_body.get_node_or_null("CollisionShape3D")
					if collision_shape and collision_shape.shape is BoxShape3D:
						collision_size = collision_shape.shape.size

				# Calculate expected local pos range based on quad scale
				var expected_x_range = Vector2(-quad.scale.x / 2, quad.scale.x / 2)
				var expected_y_range = Vector2(-quad.scale.y / 2, quad.scale.y / 2)

				print("━━━ MOUSE DEBUG ━━━")
				print("  Window ID: ", window_id, " (parent: ", parent_id, ")")
				print("  Hit pos (world): ", hit_pos)
				print("  Quad position: ", quad.global_position)
				print("  Quad scale: ", quad.scale)
				print("  Collision box size: ", collision_size)
				print("  Expected local_pos X range: ", expected_x_range)
				print("  Expected local_pos Y range: ", expected_y_range)
				print("  Actual local pos: ", local_pos, " (Z should be ~0.005)")
				print("  Local pos in range? X:", local_pos.x >= expected_x_range.x and local_pos.x <= expected_x_range.y,
					  " Y:", local_pos.y >= expected_y_range.x and local_pos.y <= expected_y_range.y)
				print("  Window size (pixels): ", window_size)
				print("  Calculated tex coords: (", tex_x, ", ", tex_y, ")")
				print("  Sending to X11: (", int(window_mouse_pos.x), ", ", int(window_mouse_pos.y), ")")
				print("━━━━━━━━━━━━━━━━━━━━━━")

	# Forward mouse motion ONLY to selected window (not hovered)
	# This prevents accidentally closing menus by sending mouse events to parent
	if window_id != -1 and current_state == WindowState.SELECTED and window_id == selected_window_id:
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
				# Different window detected - only switch if we've been stable for a bit
				hover_switch_timer += delta
				if hover_switch_timer >= hover_switch_delay:
					# Switched to different window
					print("Switched hover from window ", hovered_window_id, " to ", window_id)
					clear_hover()
					start_hover(window_id, quad)
					hover_switch_timer = 0.0
			else:
				# Same window - reset switch timer and continue hovering
				hover_switch_timer = 0.0
				hover_timer += delta
				if hover_timer >= hover_delay:
					# Auto-select after hover delay
					print("Auto-selecting window ", window_id, " after ", hover_timer, "s hover")
					select_window(window_id, quad)

		WindowState.SELECTED:
			# When selected, stay locked on that window
			# Only ESC or exit button should deselect
			# Update mouse position (already handled above in forward mouse motion section)
			pass

func start_hover(window_id: int, quad: MeshInstance3D):
	current_state = WindowState.HOVERED
	hovered_window_id = window_id
	hovered_window_quad = quad
	hover_timer = 0.0
	hover_switch_timer = 0.0

	add_hover_highlight(quad)

	var window_title = compositor.get_window_title(window_id)
	var window_class = compositor.get_window_class(window_id)
	print(">>> HOVERING window ", window_id, ": ", window_title, " [", window_class, "]")
	print("    Click to select instantly OR hover for ", hover_delay, "s to auto-select")

func clear_hover():
	if hovered_window_quad and current_state == WindowState.HOVERED:
		remove_hover_highlight(hovered_window_quad)

	print("Hover cleared on window ", hovered_window_id)

	current_state = WindowState.NONE
	hovered_window_id = -1
	hovered_window_quad = null
	hover_timer = 0.0
	hover_switch_timer = 0.0

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

	# Set X11 focus ONLY for top-level windows (not popups)
	# Popup windows (with parent) should not steal focus from their parent
	var parent_id = compositor.get_parent_window_id(window_id)
	if parent_id == -1:
		# Top-level window - set focus normally
		compositor.set_window_focus(window_id)
	else:
		# Popup window - don't change X11 focus (keep parent focused)
		print("  Popup window - keeping parent focused")

	# Add selection border/glow
	add_selection_glow(quad)

	# Add title bar with exit button
	add_title_bar(quad, window_id)

	# Animate window to focus mode
	animate_window_to_focus(quad, window_id)

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
		remove_title_bar(selected_window_quad)
		# Restore camera to 3D mode
		restore_camera_from_focus(selected_window_id)

	# Release all keys to prevent stuck key states
	# This ensures no keys remain "pressed" when switching between windows or deselecting
	compositor.release_all_keys()

	# Check if the selected window has a parent - if so, try to switch to parent instead
	var parent_id = -1
	var window_still_mapped = false
	if selected_window_id != -1:
		parent_id = compositor.get_parent_window_id(selected_window_id)
		window_still_mapped = compositor.is_window_mapped(selected_window_id)

	print(">>> Window ", selected_window_id, " DESELECTED (mapped: ", window_still_mapped, ")")

	# If this window has a parent (e.g., popup menu/dialog) AND is still mapped,
	# switch to parent and send click to close popup
	# If window is already unmapped (closed), just clear selection - no need to click parent
	if parent_id != -1 and window_still_mapped:
		print("    Popup window still open - switching to parent and closing popup")

		# Find the parent window quad first
		var window_ids = compositor.get_window_ids()
		if parent_id in window_ids:
			var parent_quad = find_window_quad(parent_id)
			if parent_quad:
				# Move pointer to center of parent and send a click to close popup and focus parent
				var parent_size = compositor.get_window_size(parent_id)
				if parent_size.x > 0 and parent_size.y > 0:
					var center_x = parent_size.x / 2
					var center_y = parent_size.y / 2

					# Move pointer to parent center
					compositor.send_mouse_motion(parent_id, center_x, center_y)

					# Send a click to parent to close popup and restore focus
					compositor.send_mouse_button(parent_id, 1, true, center_x, center_y)  # Press
					compositor.send_mouse_button(parent_id, 1, false, center_x, center_y)  # Release

				print("    Switching selection to parent window ", parent_id)
				just_switched_to_parent = true  # Prevent immediate deselection
				select_window(parent_id, parent_quad)
				return  # Don't fully deselect, we switched to parent
	elif parent_id != -1 and not window_still_mapped:
		print("    Popup window already closed - just clearing selection")

	print("    Camera controls restored")

	current_state = WindowState.NONE
	selected_window_id = -1
	selected_window_quad = null

# Helper function to find a window quad by window ID
func handle_file_cube_hit(file_cube: Node3D):
	# Show file info when hovering
	var file_path = file_cube.get_meta("file_path", "")
	var file_name = file_cube.get_meta("file_name", "")

	# Add glow to indicate it's interactive
	if not file_cube.has_node("HoverGlow"):
		var glow = MeshInstance3D.new()
		glow.name = "HoverGlow"
		file_cube.add_child(glow)

		var outline_mesh = BoxMesh.new()
		outline_mesh.size = Vector3(0.55, 0.55, 0.55)
		glow.mesh = outline_mesh

		var glow_mat = StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.albedo_color = Color(1.0, 1.0, 0.3, 0.8)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(1.0, 1.0, 0.3)
		glow_mat.emission_energy_multiplier = 2.0
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.material_override = glow_mat

	# Store hovered file cube
	if not has_meta("hovered_file_cube") or get_meta("hovered_file_cube") != file_cube:
		# Clear previous hover
		if has_meta("hovered_file_cube"):
			var prev_cube = get_meta("hovered_file_cube")
			if prev_cube and is_instance_valid(prev_cube):
				var prev_glow = prev_cube.get_node_or_null("HoverGlow")
				if prev_glow:
					prev_glow.queue_free()

		set_meta("hovered_file_cube", file_cube)
		print("Hovering over file: ", file_name, " at ", file_path)


func clear_file_hover():
	if has_meta("hovered_file_cube"):
		var file_cube = get_meta("hovered_file_cube")
		if file_cube and is_instance_valid(file_cube):
			var glow = file_cube.get_node_or_null("HoverGlow")
			if glow:
				glow.queue_free()
		remove_meta("hovered_file_cube")

func clear_exit_button_hover():
	if has_meta("hovered_exit_button"):
		var button = get_meta("hovered_exit_button")
		if button and is_instance_valid(button):
			var exit_button = button.get_parent()
			if exit_button and exit_button.material_override:
				var mat = exit_button.material_override as StandardMaterial3D
				if mat:
					# Restore normal button color
					mat.albedo_color = Color(0.8, 0.2, 0.2, 1.0)
					mat.emission = Color(0.8, 0.2, 0.2)
		remove_meta("hovered_exit_button")


func find_window_quad(window_id: int) -> MeshInstance3D:
	# Search the WindowDisplay node for the quad
	var window_display = get_node_or_null("../WindowDisplay")
	if not window_display:
		return null

	# Iterate through children to find the quad with matching window_id metadata
	for child in window_display.get_children():
		if child is MeshInstance3D and child.has_meta("window_id"):
			if child.get_meta("window_id") == window_id:
				return child

	return null

func check_and_adjust_for_popups():
	"""Check for new popup windows and adjust camera distance to fit all visible windows"""
	if not compositor or selected_window_id == -1:
		return

	# Get all window IDs and find popups for the selected window
	var window_ids = compositor.get_window_ids()
	var current_popups = []

	for wid in window_ids:
		var parent_id = compositor.get_parent_window_id(wid)

		# Also check for logical parent (orphan dialogs associated with selected window)
		var window_display = get_node_or_null("/root/Main/WindowDisplay")
		if window_display and window_display.get("window_quads"):
			var window_quads = window_display.window_quads
			if wid in window_quads:
				var quad = window_quads[wid]
				if quad.has_meta("logical_parent_id"):
					parent_id = quad.get_meta("logical_parent_id")

		# Check if this is a popup of the selected window and is visible/mapped
		if parent_id == selected_window_id and compositor.is_window_mapped(wid):
			current_popups.append(wid)

	# Check if popup list has changed
	if current_popups == visible_popup_windows:
		return  # No changes, nothing to do

	print("  Popup windows changed: was ", visible_popup_windows, " now ", current_popups)

	# Update tracked popups
	visible_popup_windows = current_popups

	# If there are no popups, don't change anything
	# (we only zoom out for popups, never zoom back in)
	if current_popups.is_empty():
		print("  No popups visible - keeping current distance: ", current_focus_distance)
		return

	# Get window_display to access window quads
	var window_display = get_node_or_null("/root/Main/WindowDisplay")
	if not window_display or not window_display.get("window_quads"):
		return

	var window_quads = window_display.window_quads

	# Calculate optimal distance for all visible windows (parent + popups)
	var max_distance = current_focus_distance  # Start with current distance (never zoom in)

	# Calculate distance for selected parent window
	if selected_window_quad:
		var parent_distance = calculate_optimal_focus_distance(selected_window_quad)
		max_distance = max(max_distance, parent_distance)

	# Calculate distance for each popup
	for popup_id in current_popups:
		if popup_id in window_quads:
			var popup_quad = window_quads[popup_id]
			var popup_distance = calculate_optimal_focus_distance(popup_quad)
			max_distance = max(max_distance, popup_distance)
			print("  Popup ", popup_id, " requires distance: ", popup_distance)

	# If we need to zoom out (max_distance > current), animate camera
	if max_distance > current_focus_distance:
		print("  Zooming out from ", current_focus_distance, " to ", max_distance, " to fit popup(s)")
		animate_camera_zoom_out(max_distance)
	else:
		print("  All windows fit at current distance: ", current_focus_distance)

func animate_camera_zoom_out(new_distance: float):
	"""Smoothly zoom camera out to new distance"""
	if not camera or not selected_window_quad:
		return

	# Calculate new camera position at the increased distance
	var window_front = selected_window_quad.global_transform.basis.z
	var target_position = selected_window_quad.global_position + window_front * new_distance

	# Animate camera position
	if focus_tween:
		focus_tween.kill()

	focus_tween = create_tween()
	focus_tween.set_ease(Tween.EASE_OUT)
	focus_tween.set_trans(Tween.TRANS_CUBIC)
	focus_tween.tween_property(camera, "global_position", target_position, focus_animation_duration)

	# Update stored distance
	current_focus_distance = new_distance

	print("  Camera zooming out to distance: ", new_distance)

func _input(event):
	# Disable input handling in 2D mode (Window2DManager handles it)
	if mode_manager and mode_manager.is_2d_mode():
		return

	# Handle mouse button events
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Only act on PRESS, not release
		if not event.pressed:
			# Forward release to hovered window if in 2D mode, otherwise selected window
			if current_state == WindowState.SELECTED:
				var target_window_id = selected_window_id
				if in_2d_mode and has_meta("hovered_2d_window"):
					target_window_id = get_meta("hovered_2d_window")

				compositor.send_mouse_button(
					target_window_id,
					event.button_index,
					false,
					int(window_mouse_pos.x),
					int(window_mouse_pos.y)
				)
				get_viewport().set_input_as_handled()
			return

		# Mouse button PRESSED
		print_debug("Mouse click PRESSED - State: ", ["NONE", "HOVERED", "SELECTED"][current_state])

		# Check for exit button click (highest priority when window is selected)
		if has_meta("hovered_exit_button"):
			var button = get_meta("hovered_exit_button")
			if button and is_instance_valid(button):
				print("Exit button clicked - deselecting window")
				deselect_window()
				remove_meta("hovered_exit_button")
				pulse_click()
				get_viewport().set_input_as_handled()
				return

		# Check for file cube click
		if has_meta("hovered_file_cube"):
			var file_cube = get_meta("hovered_file_cube")
			if file_cube and is_instance_valid(file_cube):
				var file_path = file_cube.get_meta("file_path", "")
				print("Opening file: ", file_path)

				# Open the file
				if file_path.ends_with(".desktop"):
					# Launch application
					launch_desktop_file(file_path)
				else:
					# Open with default application in Xvfb display
					if compositor and OS.has_feature("linux"):
						var display = compositor.get_display_name()
						print("Opening file with xdg-open on display: ", display)
						# Use env to set DISPLAY for xdg-open process
						OS.create_process("env", ["DISPLAY=" + display, "xdg-open", file_path])
					else:
						# Fallback to default display
						OS.shell_open(file_path)

				pulse_click()
				get_viewport().set_input_as_handled()
				return

		if current_state == WindowState.HOVERED:
			# Check if we're in 3D mode - if so, focus window and enter 2D mode
			if mode_manager and mode_manager.is_3d_mode():
				print("Click window in 3D mode - focusing and entering 2D mode")
				mode_manager.focus_window_and_enter_2d(hovered_window_id)
				pulse_click()
				get_viewport().set_input_as_handled()
				return
			else:
				# Old behavior: Instant select on click (no hover delay required)
				print("Click to SELECT window ", hovered_window_id, " (instant)")
				select_window(hovered_window_id, hovered_window_quad)
				pulse_click()
				get_viewport().set_input_as_handled()
				return

		elif current_state == WindowState.SELECTED:
			# In 2D mode, click on whichever window is hovered (parent or popup)
			var target_window_id = selected_window_id
			if in_2d_mode and has_meta("hovered_2d_window"):
				target_window_id = get_meta("hovered_2d_window")

			print("Forwarding click to window ", target_window_id, " at (", int(window_mouse_pos.x), ", ", int(window_mouse_pos.y), ")")
			compositor.send_mouse_button(
				target_window_id,
				event.button_index,
				true,  # pressed
				int(window_mouse_pos.x),
				int(window_mouse_pos.y)
			)
			pulse_click()
			get_viewport().set_input_as_handled()
			return

		else:
			#print("Click ignored - not ready (can_select=", can_select, ", hover_timer=", hover_timer, ")")
			return

	# Forward other mouse buttons
	if event is InputEventMouseButton:
		if current_state == WindowState.SELECTED:
			var target_window_id = selected_window_id
			if in_2d_mode and has_meta("hovered_2d_window"):
				target_window_id = get_meta("hovered_2d_window")

			compositor.send_mouse_button(
				target_window_id,
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

## Focus mode animation

func calculate_optimal_focus_distance(quad: MeshInstance3D) -> float:
	"""Calculate the optimal distance to view a window based on its size"""
	if not camera:
		return focus_distance_min

	# Get window dimensions in world units (quad.scale is the actual size)
	var window_width = quad.scale.x
	var window_height = quad.scale.y

	# Get camera FOV (default Godot camera is 75 degrees)
	var fov_deg = camera.fov
	var fov_rad = deg_to_rad(fov_deg)

	# Calculate distance needed to fit height
	# visible_height = 2 * distance * tan(fov/2)
	# distance = (visible_height) / (2 * tan(fov/2))
	var half_fov = fov_rad / 2.0
	var distance_for_height = (window_height * focus_padding) / (2.0 * tan(half_fov))

	# Calculate distance needed to fit width (accounting for aspect ratio)
	# For a 16:9 viewport, horizontal FOV is wider than vertical
	var viewport = get_viewport()
	var aspect_ratio = float(viewport.size.x) / float(viewport.size.y)
	var horizontal_fov = 2.0 * atan(tan(half_fov) * aspect_ratio)
	var distance_for_width = (window_width * focus_padding) / (2.0 * tan(horizontal_fov / 2.0))

	# Use the larger distance to ensure both dimensions fit
	var optimal_distance = max(distance_for_height, distance_for_width)

	# Clamp to reasonable bounds
	optimal_distance = clamp(optimal_distance, focus_distance_min, focus_distance_max)

	print("  Window size: ", window_width, "x", window_height, " world units")
	print("  Calculated optimal distance: ", optimal_distance)

	return optimal_distance


func animate_window_to_focus(quad: MeshInstance3D, window_id: int):
	if not camera:
		return

	# Store original camera transform for restoration
	original_camera_transform[window_id] = {
		"position": camera.global_position,
		"rotation": camera.global_rotation
	}

	# Calculate optimal distance based on window size
	var optimal_distance = calculate_optimal_focus_distance(quad)
	current_focus_distance = optimal_distance
	visible_popup_windows = []  # Reset popup tracking

	# After billboarding, window's -Z points away from camera (toward window back)
	# So window's +Z points toward camera (the front face of the window)
	# We want to position camera on the FRONT side, so move along +Z
	var window_front = quad.global_transform.basis.z
	var target_position = quad.global_position + window_front * optimal_distance

	# First move camera to position without rotation
	if focus_tween:
		focus_tween.kill()

	focus_tween = create_tween()
	focus_tween.set_ease(Tween.EASE_OUT)
	focus_tween.set_trans(Tween.TRANS_CUBIC)

	# Animate position
	focus_tween.tween_property(camera, "global_position", target_position, focus_animation_duration)

	# After position animation, use look_at to face the window
	focus_tween.tween_callback(func():
		camera.look_at(quad.global_position, Vector3.UP)
		print("  Camera now looking at window at ", quad.global_position)
		print("  Camera position: ", camera.global_position)
		print("  Camera rotation: ", camera.global_rotation)
	)

	# Wait for animation to finish, then switch to 2D mode
	focus_tween.finished.connect(func(): enable_2d_mode())

	# Disable player gravity and movement
	var player = camera.get_parent()
	if player and player.has_method("set_interaction_mode"):
		player.set_interaction_mode(true)

	print("  Animating camera to window: distance=", optimal_distance)
	print("  Target position: ", target_position)
	print("  Window position: ", quad.global_position)

func restore_camera_from_focus(window_id: int):
	if window_id not in original_camera_transform or not camera:
		return

	var original = original_camera_transform[window_id]

	# Disable 2D mode first
	disable_2d_mode()

	# Animate camera back to original transform
	if focus_tween:
		focus_tween.kill()

	focus_tween = create_tween()
	focus_tween.set_parallel(true)
	focus_tween.set_ease(Tween.EASE_IN_OUT)
	focus_tween.set_trans(Tween.TRANS_CUBIC)

	focus_tween.tween_property(camera, "global_position", original.position, focus_animation_duration)
	focus_tween.tween_property(camera, "global_rotation", original.rotation, focus_animation_duration)

	# Re-enable player gravity and movement
	var player = camera.get_parent()
	if player and player.has_method("set_interaction_mode"):
		player.set_interaction_mode(false)

	# Clean up stored transform
	original_camera_transform.erase(window_id)

	print("  Restoring camera to 3D mode")

func enable_2d_mode():
	in_2d_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Hide mouse sphere in 2D mode (we use native cursor)
	if mouse_sphere:
		mouse_sphere.visible = false
	print("  Switched to 2D cursor mode")

func disable_2d_mode():
	in_2d_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Show mouse sphere in 3D mode
	if mouse_sphere:
		mouse_sphere.visible = true
	print("  Switched to 3D camera mode")

func update_2d_mouse_position():
	# Get mouse position in viewport coordinates
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size

	# Project mouse to 3D space
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * raycast_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	# Debug: Check all visible windows and their positions relative to camera
	var window_ids = compositor.get_window_ids()
	var popup_count = 0
	for wid in window_ids:
		var parent_id = compositor.get_parent_window_id(wid)
		if parent_id == selected_window_id and compositor.is_window_mapped(wid):
			popup_count += 1
			# This is a popup of the selected window
			var window_display = get_node_or_null("/root/Main/WindowDisplay")
			if window_display and wid in window_display.window_quads:
				var popup_quad = window_display.window_quads[wid]
				var dist_to_camera = camera.global_position.distance_to(popup_quad.global_position)
				var direction = (popup_quad.global_position - camera.global_position).normalized()
				var forward = -camera.global_transform.basis.z
				var dot = direction.dot(forward)
				var static_body = popup_quad.get_node_or_null("StaticBody3D")
				var has_collision = false
				if static_body:
					has_collision = static_body.get_collision_layer_value(1)
				print("  DEBUG: Popup window ", wid, " visible=", popup_quad.visible,
					  " collision=", has_collision,
					  " distance=", dist_to_camera, " in_front=", dot > 0,
					  " pos=", popup_quad.global_position)

	if popup_count > 0:
		print("  DEBUG: ", popup_count, " popup(s) exist for selected window ", selected_window_id)

	if result and result.collider is StaticBody3D:
		var collider = result.collider

		# Check if this is the exit button
		if collider.has_meta("is_exit_button"):
			handle_exit_button_hit(collider)
			return

		# Check if we hit any window (including popups)
		if collider.has_meta("window_id"):
			var window_id = collider.get_meta("window_id")
			var parent_id = compositor.get_parent_window_id(window_id)
			var window_title = compositor.get_window_title(window_id)

			# Debug output
			if parent_id != -1:
				print("  DEBUG 2D: Hit popup window ", window_id, " (parent:", parent_id, ") title:", window_title)
			else:
				print("  DEBUG 2D: Hit parent window ", window_id, " title:", window_title)

			# Find the quad for this window
			var hit_quad = collider.get_parent() as MeshInstance3D

			if hit_quad:
				# Calculate window-local coordinates
				var local_pos = hit_quad.global_transform.affine_inverse() * result.position
				var window_size = compositor.get_window_size(window_id)

				if window_size.x > 0 and window_size.y > 0:
					# Clamp local_pos to visual quad bounds [-0.5, 0.5]
					# The collision box is 4x4 but the visual quad is smaller, so hits can be outside visual bounds
					var clamped_local_pos = Vector3(
						clamp(local_pos.x, -0.5, 0.5),
						clamp(local_pos.y, -0.5, 0.5),
						local_pos.z
					)

					var tex_x = (clamped_local_pos.x + 0.5) * window_size.x
					var tex_y = (-clamped_local_pos.y + 0.5) * window_size.y

					# Debug for large windows (including dialogs)
					if window_size.x > 800 or window_size.y > 600:
						# Check if we're near edges
						var near_top = tex_y < 50
						var near_bottom = tex_y > window_size.y - 50
						var was_clamped = (local_pos.x != clamped_local_pos.x or local_pos.y != clamped_local_pos.y)
						if near_top or near_bottom or was_clamped:
							print("  EDGE CLICK: size=", window_size, " local_pos=", local_pos,
								  " clamped=", clamped_local_pos, " tex=", Vector2(tex_x, tex_y),
								  " quad.scale=", hit_quad.scale, " near_top=", near_top,
								  " near_bottom=", near_bottom, " was_clamped=", was_clamped)

					window_mouse_pos = Vector2(
						clamp(tex_x, 0, window_size.x - 1),
						clamp(tex_y, 0, window_size.y - 1)
					)

					# Send mouse motion to X11 - works for both parent and popup windows
					compositor.send_mouse_motion(
						window_id,
						int(window_mouse_pos.x),
						int(window_mouse_pos.y)
					)

					# Store which window we're currently hovering for click handling
					set_meta("hovered_2d_window", window_id)
			else:
				# Not hitting a window, clear hover
				remove_meta("hovered_2d_window")
				clear_exit_button_hover()
		else:
			# Not hitting a window, clear hover
			remove_meta("hovered_2d_window")
			clear_exit_button_hover()
	else:
		# Not hitting anything, clear exit button hover
		remove_meta("hovered_2d_window")
		clear_exit_button_hover()

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

func add_title_bar(quad: MeshInstance3D, window_id: int):
	# Create a title bar container above the window
	var title_bar = Node3D.new()
	title_bar.name = "TitleBar"
	quad.add_child(title_bar)

	# Position above the window (in local space, Y+ is up)
	title_bar.position = Vector3(0, 0.55, -0.01)

	# Title background bar
	var bg_mesh = MeshInstance3D.new()
	title_bar.add_child(bg_mesh)

	var bar_quad = QuadMesh.new()
	bar_quad.size = Vector2(1.0, 0.08)  # Full width, thin height
	bg_mesh.mesh = bar_quad

	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.2, 0.2, 0.25, 0.95)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mesh.material_override = bg_mat

	# Title text label
	var title_label = Label3D.new()
	title_bar.add_child(title_label)
	title_label.text = compositor.get_window_title(window_id)
	title_label.font_size = 16
	title_label.outline_size = 2
	title_label.modulate = Color(1, 1, 1, 1)
	title_label.position = Vector3(-0.45, 0, -0.01)  # Left side
	title_label.pixel_size = 0.0005
	title_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # Don't billboard, follow window
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Exit button on the right
	var exit_button = MeshInstance3D.new()
	title_bar.add_child(exit_button)
	exit_button.name = "ExitButton"

	var button_quad = QuadMesh.new()
	button_quad.size = Vector2(0.08, 0.08)  # Square button
	exit_button.mesh = button_quad

	var button_mat = StandardMaterial3D.new()
	button_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	button_mat.albedo_color = Color(0.8, 0.2, 0.2, 1.0)  # Red button
	button_mat.emission_enabled = true
	button_mat.emission = Color(0.8, 0.2, 0.2)
	button_mat.emission_energy_multiplier = 1.5
	exit_button.material_override = button_mat

	exit_button.position = Vector3(0.46, 0, -0.01)  # Right side

	# Add collision for exit button
	var button_body = StaticBody3D.new()
	button_body.name = "ExitButtonBody"
	exit_button.add_child(button_body)

	var button_collision = CollisionShape3D.new()
	button_body.add_child(button_collision)

	var button_shape = BoxShape3D.new()
	button_shape.size = Vector3(0.08, 0.08, 0.01)
	button_collision.shape = button_shape

	# Store metadata for exit button detection
	button_body.set_meta("is_exit_button", true)
	button_body.set_meta("window_id", window_id)

	# Add "X" label on button
	var x_label = Label3D.new()
	exit_button.add_child(x_label)
	x_label.text = "✕"
	x_label.font_size = 24
	x_label.outline_size = 3
	x_label.modulate = Color(1, 1, 1, 1)
	x_label.position = Vector3(0, 0, -0.01)
	x_label.pixel_size = 0.0004
	x_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	x_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	print("  Added title bar with exit button")

func remove_title_bar(quad: MeshInstance3D):
	var title_bar = quad.get_node_or_null("TitleBar")
	if title_bar:
		title_bar.queue_free()
		print("  Removed title bar")


func launch_desktop_file(desktop_file_path: String):
	## Parse and launch a .desktop file
	var file = FileAccess.open(desktop_file_path, FileAccess.READ)
	if not file:
		print("Failed to read .desktop file: ", desktop_file_path)
		return

	var exec_line = ""
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("Exec="):
			exec_line = line.substr(5)  # Remove "Exec="
			break

	file.close()

	if exec_line.is_empty():
		print("No Exec line found in .desktop file")
		return

	# Clean up exec line (remove %U, %F, etc.)
	exec_line = exec_line.replace("%U", "").replace("%F", "").replace("%u", "").replace("%f", "").strip_edges()

	# Parse command and arguments
	var parts = exec_line.split(" ", false)
	if parts.is_empty():
		return

	var command = parts[0]
	var args = parts.slice(1)

	# Set DISPLAY environment variable and launch
	if compositor:
		var display = compositor.get_display_name()
		print("Launching: ", command, " with args: ", args, " on display: ", display)
		OS.set_environment("DISPLAY", display)
		OS.create_process(command, args)
	else:
		print("No compositor found, cannot launch application")
