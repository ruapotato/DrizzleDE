extends Node3D
class_name BuildingSystem

## Valheim-style building system
## Handles piece selection, placement preview, snapping, and building

signal build_mode_changed(enabled: bool)
signal piece_placed(piece: BuildingPiece)
signal piece_selected(piece_name: String)

@export var camera_path: NodePath
@export var placement_range: float = 5.0
@export var rotation_snap_angle: float = 45.0  # Degrees

var camera: Camera3D
var build_mode: bool = false
var current_piece_scene: PackedScene = null
var preview_piece: BuildingPiece = null
var placed_pieces: Array[BuildingPiece] = []

# Available building pieces
var building_pieces: Dictionary = {}

# Placement state
var placement_position: Vector3
var placement_normal: Vector3
var placement_valid: bool = false
var current_rotation: float = 0.0

# Snap state
var available_snap_targets: Array = []  # Array of {point: Node3D, piece: BuildingPiece}
var current_snap_index: int = 0
var is_snapped: bool = false
var last_snap_position: Vector3 = Vector3.ZERO
var snap_stability_threshold: float = 0.3  # Minimum distance to switch snap targets

# Raycast for placement
var raycast_query: PhysicsRayQueryParameters3D
var space_state: PhysicsDirectSpaceState3D

func _ready():
	if camera_path:
		camera = get_node(camera_path)
	else:
		camera = get_viewport().get_camera_3d()

	space_state = get_world_3d().direct_space_state

	# Register building pieces
	_register_building_pieces()

func _register_building_pieces():
	"""Register all available building pieces"""
	# These will be loaded from the pieces directory
	building_pieces = {
		"foundation_2x2": {
			"scene": "res://shell/building/pieces/foundation_2x2.tscn",
			"name": "Foundation 2x2",
			"category": "Foundation"
		},
		"wall_2x2": {
			"scene": "res://shell/building/pieces/wall_2x2.tscn",
			"name": "Wall 2x2",
			"category": "Walls"
		},
		"floor_2x2": {
			"scene": "res://shell/building/pieces/floor_2x2.tscn",
			"name": "Floor 2x2",
			"category": "Floors"
		},
		"roof_45deg": {
			"scene": "res://shell/building/pieces/roof_45deg.tscn",
			"name": "Roof 45°",
			"category": "Roofs"
		},
		"pillar": {
			"scene": "res://shell/building/pieces/pillar.tscn",
			"name": "Pillar",
			"category": "Support"
		}
	}

func _input(event):
	if not build_mode:
		return

	# ESC - deselect current piece or exit build mode
	if event.is_action_pressed("ui_cancel"):
		if preview_piece:
			# Deselect current piece
			print("Deselecting piece - press B to exit build mode")
			preview_piece.queue_free()
			preview_piece = null
			current_piece_scene = null
			get_viewport().set_input_as_handled()
		else:
			# No piece selected, exit build mode
			toggle_build_mode()
		return

	# Rotate piece or cycle snap points
	if event.is_action_pressed("rotate_left"):
		# If snapped, cycle through snap points
		if is_snapped and available_snap_targets.size() > 1:
			cycle_snap_target(-1)
		else:
			rotate_preview(-rotation_snap_angle)
	elif event.is_action_pressed("rotate_right"):
		rotate_preview(rotation_snap_angle)

	# Place piece
	if event.is_action_pressed("click") and preview_piece and placement_valid:
		place_current_piece()

	# Remove piece (right click)
	if event.is_action_pressed("right_click"):
		remove_piece_at_cursor()

func _process(delta):
	if not build_mode or not preview_piece:
		return

	# Update placement preview
	update_placement_preview()

func toggle_build_mode():
	"""Toggle building mode on/off"""
	build_mode = not build_mode
	build_mode_changed.emit(build_mode)

	if build_mode:
		# Capture mouse for building
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# Clean up preview
		if preview_piece:
			preview_piece.queue_free()
			preview_piece = null

func select_piece(piece_id: String):
	"""Select a building piece to place"""
	if not piece_id in building_pieces:
		push_error("Unknown building piece: " + piece_id)
		return

	var piece_data = building_pieces[piece_id]

	# Load the scene
	current_piece_scene = load(piece_data["scene"])
	if not current_piece_scene:
		push_error("Failed to load building piece scene: " + piece_data["scene"])
		return

	# Remove old preview
	if preview_piece:
		preview_piece.queue_free()

	# Create new preview
	preview_piece = current_piece_scene.instantiate()
	add_child(preview_piece)
	preview_piece.set_preview_mode(true)

	piece_selected.emit(piece_data["name"])

func update_placement_preview():
	"""Update the position and validity of the placement preview"""
	if not preview_piece or not camera:
		return

	# Raycast from camera
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * placement_range)

	raycast_query = PhysicsRayQueryParameters3D.create(from, to)
	raycast_query.collision_mask = 1  # Collide with placed pieces and environment

	var result = space_state.intersect_ray(raycast_query)

	if result.is_empty():
		# No valid placement
		placement_valid = false
		preview_piece.visible = false
		is_snapped = false
		available_snap_targets.clear()
		return

	# Update placement position
	placement_position = result["position"]
	placement_normal = result["normal"]

	# Find all nearby snap targets
	_find_all_snap_targets(result)

	# Use current snap target if available
	if available_snap_targets.size() > 0:
		var snap_data = available_snap_targets[current_snap_index]
		var target_snap_point = snap_data.point
		placement_normal = target_snap_point.global_transform.basis.y
		is_snapped = true

		# Find which corner of our preview piece should connect to this snap point
		# Use the closest preview snap point in current orientation
		var preview_snap_points = preview_piece.get_all_snap_points()
		if preview_snap_points.size() > 0:
			# Find the closest snap point on our preview to the target
			# This creates more stable, predictable snapping
			var best_preview_snap = preview_snap_points[0]
			var min_dist = INF

			for snap_point in preview_snap_points:
				var world_pos = preview_piece.global_position + preview_piece.global_transform.basis * snap_point.position
				var dist = world_pos.distance_to(target_snap_point.global_position)
				if dist < min_dist:
					min_dist = dist
					best_preview_snap = snap_point

			# Calculate position so our snap point aligns with target snap point
			var snap_offset_world = preview_piece.global_transform.basis * best_preview_snap.position
			placement_position = target_snap_point.global_position - snap_offset_world

			# Store this position for stability checking
			last_snap_position = placement_position
		else:
			placement_position = target_snap_point.global_position
	else:
		is_snapped = false
		placement_position = result["position"]

	# Position the preview
	preview_piece.visible = true
	preview_piece.global_position = placement_position

	# Align to surface normal
	var up_direction = placement_normal
	var look_direction = Vector3.FORWARD
	if abs(up_direction.dot(Vector3.FORWARD)) > 0.99:
		look_direction = Vector3.RIGHT

	preview_piece.global_transform.basis = Basis.looking_at(look_direction, up_direction)

	# Apply rotation
	preview_piece.rotate_object_local(Vector3.UP, deg_to_rad(current_rotation))

	# Check placement validity
	placement_valid = _check_placement_validity()
	preview_piece.update_placement_validity(placement_valid)

func _find_all_snap_targets(raycast_result: Dictionary):
	"""Find all nearby snap points from placed pieces"""
	var hit_position = raycast_result["position"]

	# If we have existing snap targets and haven't moved much, keep them (stability)
	if not available_snap_targets.is_empty():
		var current_closest = available_snap_targets[0]
		var dist_from_last = hit_position.distance_to(current_closest.point.global_position)

		# Only recalculate if we've moved significantly
		if dist_from_last < snap_stability_threshold:
			return

	available_snap_targets.clear()
	current_snap_index = 0

	# Check all placed pieces for nearby snap points
	for piece in placed_pieces:
		if not piece:
			continue

		var snap_points = piece.get_all_snap_points()
		for snap_point in snap_points:
			var world_pos = snap_point.global_position
			var distance = world_pos.distance_to(hit_position)

			# Check if this snap point is close enough
			if distance < 1.5:  # 1.5 meter snap range
				available_snap_targets.append({
					"point": snap_point,
					"piece": piece,
					"distance": distance
				})

	# Sort by distance (closest first)
	available_snap_targets.sort_custom(func(a, b): return a.distance < b.distance)

	# Limit to closest 4 snap points (one per corner)
	if available_snap_targets.size() > 4:
		available_snap_targets.resize(4)

func _check_placement_validity() -> bool:
	"""Check if current placement is valid"""
	if not preview_piece:
		return false

	# Basic validity check - can be extended
	# Check for overlaps with other pieces
	var shape_owners = preview_piece.get_shape_owners()
	if shape_owners.is_empty():
		return true

	# For now, just return true - collision detection will prevent invalid placements
	return true

func cycle_snap_target(direction: int):
	"""Cycle through available snap points"""
	if available_snap_targets.is_empty():
		return

	current_snap_index += direction
	if current_snap_index < 0:
		current_snap_index = available_snap_targets.size() - 1
	elif current_snap_index >= available_snap_targets.size():
		current_snap_index = 0

	print("Cycled to snap point ", current_snap_index + 1, " of ", available_snap_targets.size())

func rotate_preview(degrees: float):
	"""Rotate the preview piece"""
	current_rotation += degrees
	if current_rotation >= 360:
		current_rotation -= 360
	elif current_rotation < 0:
		current_rotation += 360

func place_current_piece():
	"""Place the current preview piece"""
	if not preview_piece or not placement_valid:
		return

	# Create actual piece
	var new_piece = current_piece_scene.instantiate()
	add_child(new_piece)

	# Copy transform from preview
	new_piece.global_transform = preview_piece.global_transform
	new_piece.set_preview_mode(false)

	# Add to placed pieces
	placed_pieces.append(new_piece)

	piece_placed.emit(new_piece)

	# Create new preview
	var old_scene = current_piece_scene
	preview_piece.queue_free()
	preview_piece = old_scene.instantiate()
	add_child(preview_piece)
	preview_piece.set_preview_mode(true)

func remove_piece_at_cursor():
	"""Remove a building piece under the cursor"""
	if not camera:
		return

	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * placement_range)

	raycast_query = PhysicsRayQueryParameters3D.create(from, to)
	raycast_query.collision_mask = 1

	var result = space_state.intersect_ray(raycast_query)

	if result.is_empty():
		return

	var collider = result.get("collider")
	if collider and collider is BuildingPiece:
		# Find parent BuildingPiece if we hit a child collider
		var piece = collider
		while piece and not piece is BuildingPiece:
			piece = piece.get_parent()

		if piece and piece in placed_pieces:
			placed_pieces.erase(piece)
			piece.queue_free()

func get_building_pieces_by_category() -> Dictionary:
	"""Get building pieces organized by category"""
	var by_category = {}

	for piece_id in building_pieces:
		var piece_data = building_pieces[piece_id]
		var category = piece_data["category"]

		if not category in by_category:
			by_category[category] = []

		by_category[category].append({
			"id": piece_id,
			"name": piece_data["name"]
		})

	return by_category

func save_build(file_path: String) -> bool:
	"""Save current build to file"""
	# TODO: Implement save system
	return false

func load_build(file_path: String) -> bool:
	"""Load build from file"""
	# TODO: Implement load system
	return false
