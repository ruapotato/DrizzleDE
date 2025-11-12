extends Node3D

## Displays X11 windows on 3D quads in the scene

@export var compositor_path: NodePath
@export var camera_path: NodePath
@export var filesystem_generator_path: NodePath
@export var window_spacing := 1.5
@export var update_rate := 60.0  # Updates per second
@export var spawn_distance := 3.0  # Distance from player to spawn new windows
@export var pixels_per_world_unit := 400.0  # Conversion factor: 400 pixels = 1 world unit

var compositor: Node
var camera: Camera3D
var filesystem_generator: Node
var window_quads := {}  # Maps window_id -> MeshInstance3D
var update_timer := 0.0
var next_z_offset := 0.0  # Z offset for each window to prevent Z-fighting

# Application grouping - tracks where each app's windows are located
var app_zones := {}  # Maps app_class -> {center: Vector3, window_ids: Array}

func _ready():
	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		# Try to find X11Compositor in the scene
		compositor = get_node_or_null("/root/Main/X11Compositor")

	if camera_path:
		camera = get_node(camera_path)
	else:
		camera = get_viewport().get_camera_3d()

	if filesystem_generator_path:
		filesystem_generator = get_node(filesystem_generator_path)
	else:
		filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")

	if not compositor:
		push_error("X11Compositor not found!")
		return

	if not camera:
		push_warning("Camera not found - windows will spawn at origin")

	if not filesystem_generator:
		push_warning("FileSystemGenerator not found - room-based window tracking disabled")

	print("WindowDisplay ready, connected to compositor: ", compositor.get_display_name())

func _process(delta):
	if not compositor or not compositor.is_initialized():
		return

	update_timer += delta
	if update_timer < 1.0 / update_rate:
		return
	update_timer = 0.0

	# Get all current window IDs
	var window_ids = compositor.get_window_ids()

	# Remove quads for windows that no longer exist
	var ids_to_remove = []
	for window_id in window_quads.keys():
		if window_id not in window_ids:
			ids_to_remove.append(window_id)

	for window_id in ids_to_remove:
		remove_window_quad(window_id)

	# Get current room for filtering
	var current_room_path = ""
	if filesystem_generator and filesystem_generator.current_room:
		current_room_path = filesystem_generator.current_room.directory_path

	# Get window interaction state to check which window is selected
	var window_interaction = get_node_or_null("/root/Main/WindowInteraction")
	var selected_window_id = -1
	if window_interaction:
		selected_window_id = window_interaction.get("selected_window_id")

	# Create or update quads for each window
	for window_id in window_ids:
		var quad: MeshInstance3D

		if window_id in window_quads:
			quad = window_quads[window_id]
		else:
			quad = create_window_quad_spatial(window_id)
			window_quads[window_id] = quad

		# Check if window belongs to current room (room-based filtering)
		var window_room_path = quad.get_meta("room_path", "")
		var in_current_room = (window_room_path == current_room_path or window_room_path == "")

		# Hide unmapped windows OR windows not in current room
		var is_mapped = compositor.is_window_mapped(window_id)
		quad.visible = is_mapped and in_current_room

		# Disable collision for unmapped windows or windows not in current room
		var static_body = quad.get_node_or_null("StaticBody3D")
		if static_body:
			var should_collide = is_mapped and in_current_room
			static_body.set_collision_layer_value(1, should_collide)
			static_body.set_collision_mask_value(1, should_collide)

		# Only update texture for mapped windows in current room
		if is_mapped and in_current_room:
			update_window_texture(quad, window_id)

			# Billboard behavior: Make idle windows face the camera
			# Skip billboarding for selected windows (interaction system handles them)
			# Skip billboarding for popup windows (they follow parent orientation)
			var parent_id = compositor.get_parent_window_id(window_id)
			var is_selected = (window_id == selected_window_id)

			if not is_selected and parent_id == -1 and camera:
				# Billboard: make window face camera (Y rotation only)
				var to_camera = camera.global_position - quad.global_position
				var look_angle = atan2(to_camera.x, to_camera.z)
				quad.rotation.y = look_angle

func create_window_quad(window_id: int, index: int) -> MeshInstance3D:
	var quad = MeshInstance3D.new()
	add_child(quad)

	# Create quad mesh
	var mesh = QuadMesh.new()
	mesh.size = Vector2(1, 1)  # Will be scaled by window size
	quad.mesh = mesh

	# Create material with texture
	var material = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 1)  # White (will be modulated by texture)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Render from both sides
	quad.material_override = material

	# Add collision shape for raycasting
	var static_body = StaticBody3D.new()
	quad.add_child(static_body)

	var collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)

	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1, 1, 0.01)  # Thin box matching quad size
	collision_shape.shape = box_shape

	# Store window ID as metadata for identification
	quad.set_meta("window_id", window_id)
	static_body.set_meta("window_id", window_id)

	# Position the quad - in front of the reference plane
	# Camera is at z=3, looking at -Z. Reference plane is at z=-2.
	# Put windows at z=-1 (closer to camera than the reference plane)
	quad.position = Vector3(index * window_spacing, 1.5, -1)

	print("Created window quad ", window_id, " at position ", quad.position)

	return quad

func update_window_texture(quad: MeshInstance3D, window_id: int):
	var image = compositor.get_window_buffer(window_id)
	if not image:
		return

	var size = compositor.get_window_size(window_id)
	if size.x <= 0 or size.y <= 0:
		return

	# Update quad scale based on actual pixel size
	# Convert pixels to world units using our conversion factor
	var width_world = float(size.x) / pixels_per_world_unit
	var height_world = float(size.y) / pixels_per_world_unit
	quad.scale = Vector3(width_world, height_world, 1)

	# Update collision shape to match new size
	var static_body = quad.get_node_or_null("StaticBody3D")
	if static_body:
		var collision_shape = static_body.get_node_or_null("CollisionShape3D")
		if collision_shape and collision_shape.shape is BoxShape3D:
			var box_shape = collision_shape.shape as BoxShape3D
			# BoxShape3D size is the full size, and the quad is 1x1 before scaling
			# So the collision box should match the quad size (which is now scaled)
			box_shape.size = Vector3(1, 1, 0.01)

	# Create texture from image
	var texture = ImageTexture.create_from_image(image)

	# Update material
	var material = quad.material_override as StandardMaterial3D
	if material:
		material.albedo_texture = texture

## Spatial window management

func create_window_quad_spatial(window_id: int) -> MeshInstance3D:
	var app_class = compositor.get_window_class(window_id)
	var window_title = compositor.get_window_title(window_id)

	# Calculate spawn position based on application grouping
	var spawn_pos = get_spawn_position(window_id, app_class)

	var quad = MeshInstance3D.new()
	add_child(quad)

	# Create quad mesh
	var mesh = QuadMesh.new()
	mesh.size = Vector2(1, 1)
	quad.mesh = mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Render from both sides

	# Check if this is a popup window - give it a colored border for visibility
	var parent_id = compositor.get_parent_window_id(window_id)
	if parent_id != -1:
		# Popup window - add bright border to make it very visible
		material.albedo_color = Color(1, 1, 0.5, 1)  # Slight yellow tint
		print("  Created POPUP window material (yellow tint)")
	else:
		material.albedo_color = Color(1, 1, 1, 1)

	quad.material_override = material

	# Add collision shape for raycasting
	var static_body = StaticBody3D.new()
	static_body.name = "StaticBody3D"
	quad.add_child(static_body)

	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	static_body.add_child(collision_shape)

	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1, 1, 0.01)
	collision_shape.shape = box_shape

	# Store window ID and app class as metadata
	quad.set_meta("window_id", window_id)
	quad.set_meta("app_class", app_class)
	static_body.set_meta("window_id", window_id)

	# Store current room path for room-based filtering
	if filesystem_generator and filesystem_generator.current_room:
		quad.set_meta("room_path", filesystem_generator.current_room.directory_path)
	else:
		quad.set_meta("room_path", "")

	# Position the quad with Z offset to prevent Z-fighting
	# Ensure minimum Y height above floor (floor is at y=0, so minimum y=1.5)
	spawn_pos.y = max(spawn_pos.y, 1.5)
	quad.position = spawn_pos

	# Orient the quad to face the camera
	# For popup windows, inherit parent's rotation
	# For normal windows, face the camera's current direction
	# (parent_id already declared above for material check)
	if parent_id != -1 and parent_id in window_quads:
		# Popup window - match parent rotation (position already set by get_spawn_position)
		var parent_quad = window_quads[parent_id]
		quad.rotation = parent_quad.rotation  # Face same direction as parent
	else:
		# Normal window - use incremental offset and face camera
		quad.position.z += next_z_offset
		next_z_offset += 0.01  # Small offset for each window to prevent flickering

		# Make window face the camera (rotate to look at camera)
		if camera:
			# Get camera's yaw (Y rotation only, ignore pitch)
			var camera_yaw = camera.global_rotation.y
			# Rotate window to face camera direction
			quad.rotation.y = camera_yaw

	# Update app zone tracking
	add_window_to_zone(window_id, app_class, spawn_pos)

	print("Created window quad ", window_id, ": ", window_title, " [", app_class, "] at ", quad.position)

	return quad

func get_spawn_position(window_id: int, app_class: String) -> Vector3:
	# Check if this is a popup window (has a parent)
	var parent_id = compositor.get_parent_window_id(window_id)
	if parent_id != -1 and parent_id in window_quads:
		# This is a popup - position it relative to the parent window using actual X11 coordinates
		var parent_quad = window_quads[parent_id]
		var parent_pos_center = parent_quad.global_position
		var parent_rotation = parent_quad.rotation

		# Get parent and popup sizes
		var parent_size = compositor.get_window_size(parent_id)
		var popup_size = compositor.get_window_size(window_id)

		# Get actual X11 window positions (in pixels) - these are TOP-LEFT corners
		var popup_pos_px = compositor.get_window_position(window_id)
		var parent_pos_px = compositor.get_window_position(parent_id)

		# Calculate offset in pixels (from parent top-left to popup top-left)
		var offset_x_px = popup_pos_px.x - parent_pos_px.x
		var offset_y_px = popup_pos_px.y - parent_pos_px.y

		# Convert sizes to world units
		var parent_width_world = float(parent_size.x) / pixels_per_world_unit
		var parent_height_world = float(parent_size.y) / pixels_per_world_unit
		var popup_width_world = float(popup_size.x) / pixels_per_world_unit
		var popup_height_world = float(popup_size.y) / pixels_per_world_unit

		# Calculate offset in LOCAL parent space (as if parent was unrotated)
		# Convert pixel offset to world units
		# Y is inverted - in X11, Y increases downward, in 3D world Y increases upward
		var offset_local = Vector3(
			float(offset_x_px) / pixels_per_world_unit,
			-float(offset_y_px) / pixels_per_world_unit,
			0
		)

		# Calculate parent's top-left corner in LOCAL space (unrotated)
		# In local space: X+ = right, Y+ = up
		var parent_topleft_local = Vector3(-parent_width_world / 2, parent_height_world / 2, 0)

		# Popup's top-left in local space
		var popup_topleft_local = parent_topleft_local + offset_local

		# Popup's center in local space (relative to parent center)
		# Z=0.05 puts popup slightly in front of parent in LOCAL space (toward camera)
		var popup_center_local = popup_topleft_local + Vector3(popup_width_world / 2, -popup_height_world / 2, 0.05)

		# Apply parent's rotation to the local offset, then add to parent's position
		# NOTE: We use rotation only, NOT full transform, because we already calculated
		# the offset in world units and don't want it scaled by parent's scale
		var rotation_basis = Basis.from_euler(parent_quad.rotation)
		var rotated_offset = rotation_basis * popup_center_local
		var popup_center_world = parent_quad.global_position + rotated_offset

		# Calculate distance from camera for debugging
		var distance_from_camera = "N/A"
		if camera:
			distance_from_camera = str(camera.global_position.distance_to(popup_center_world))

		print("  Positioning popup window ", window_id, " relative to parent ", parent_id)
		print("    Parent pos (pixels): ", parent_pos_px, " size: ", parent_size)
		print("    Popup pos (pixels): ", popup_pos_px, " size: ", popup_size)
		print("    Offset (pixels): ", offset_x_px, ", ", offset_y_px)
		print("    Parent rotation: ", parent_rotation)
		print("    Parent world pos: ", parent_pos_center)
		print("    Popup center (local): ", popup_center_local)
		print("    Popup center (world): ", popup_center_world)
		print("    Popup size (world): ", popup_width_world, " x ", popup_height_world, " (", popup_size.x, "x", popup_size.y, " px)")
		print("    Distance from camera: ", distance_from_camera)

		return popup_center_world

	# If this app already has windows, spawn near them
	if app_class != "" and app_class in app_zones:
		var zone = app_zones[app_class]
		var zone_center = zone.center
		var window_count = zone.window_ids.size()

		# Spawn in a grid pattern around the zone center
		var offset_x = (window_count % 3) * window_spacing
		var offset_y = (window_count / 3) * window_spacing

		return zone_center + Vector3(offset_x - window_spacing, offset_y, 0)

	# New app - spawn where the player is looking
	if camera:
		# Raycast from camera to find spawn position
		var from = camera.global_position
		var forward = -camera.global_transform.basis.z
		var to = from + forward * 100.0  # Cast far

		var space_state = camera.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var result = space_state.intersect_ray(query)

		if result:
			# Hit something - spawn at hit point, offset slightly toward camera
			var spawn_pos = result.position + result.normal * 0.1
			# Ensure minimum Y height
			spawn_pos.y = max(spawn_pos.y, 1.5)
			print("  Spawning new window at raycast hit: ", spawn_pos)
			return spawn_pos
		else:
			# No hit - spawn at fixed distance in look direction
			var spawn_pos = from + forward * spawn_distance
			# Ensure minimum Y height
			spawn_pos.y = max(spawn_pos.y, 1.5)
			print("  Spawning new window at fixed distance: ", spawn_pos)
			return spawn_pos

	# Fallback: spawn at origin with proper height
	return Vector3(0, 1.5, -1)

func add_window_to_zone(window_id: int, app_class: String, position: Vector3):
	if app_class == "":
		return

	if app_class not in app_zones:
		# Create new zone
		app_zones[app_class] = {
			"center": position,
			"window_ids": [window_id]
		}
	else:
		# Add to existing zone
		app_zones[app_class].window_ids.append(window_id)
		update_zone_center(app_class)

func remove_window_quad(window_id: int):
	if window_id not in window_quads:
		return

	var quad = window_quads[window_id]

	# Remove from app zone tracking
	if quad.has_meta("app_class"):
		var app_class = quad.get_meta("app_class")
		remove_window_from_zone(window_id, app_class)

	# Free the quad
	quad.queue_free()
	window_quads.erase(window_id)

func remove_window_from_zone(window_id: int, app_class: String):
	if app_class == "" or app_class not in app_zones:
		return

	var zone = app_zones[app_class]
	var idx = zone.window_ids.find(window_id)
	if idx != -1:
		zone.window_ids.remove_at(idx)

	# If no more windows in this zone, remove it
	if zone.window_ids.is_empty():
		app_zones.erase(app_class)
	else:
		update_zone_center(app_class)

func update_zone_center(app_class: String):
	if app_class not in app_zones:
		return

	var zone = app_zones[app_class]
	var center = Vector3.ZERO
	var count = 0

	# Calculate average position of all windows in this zone
	for wid in zone.window_ids:
		if wid in window_quads:
			center += window_quads[wid].global_position
			count += 1

	if count > 0:
		zone.center = center / count
