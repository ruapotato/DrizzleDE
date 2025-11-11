extends Node3D
class_name FileSystemGenerator

## Generates 3D rooms from file system directories
## Each directory becomes a room with files as cubes and subdirectories as hallways

const FileCube = preload("res://shell/filesystem/file_cube.gd")
const RoomNode = preload("res://shell/filesystem/room_node.gd")

## Room dimensions
const ROOM_BASE_SIZE = 20.0  # Base room size in meters (increased for hallway access)
const HALLWAY_WIDTH = 3.0
const HALLWAY_HEIGHT = 3.0
const HALLWAY_LENGTH = 10.0  # How far hallways extend from the room (increased for transition zone)
const FILE_CUBE_SIZE = 0.5
const FILE_SPACING = 1.0
const MAX_FILES_DISPLAY = 100  # Limit files displayed to prevent performance issues

## Currently active room
var current_room: RoomNode = null

## Hallway the player is currently in (null if in a room)
var current_hallway: Node3D = null

## Source room when in a hallway (to keep loaded while traversing)
var hallway_source_room: RoomNode = null

## Cache of generated rooms {path: RoomNode}
var room_cache: Dictionary = {}

## Starting directory (home by default)
var start_directory: String = ""


func _ready():
	# Start at home directory
	if start_directory.is_empty():
		start_directory = OS.get_environment("HOME")

	# Generate the starting room asynchronously (spawn at center for initial room)
	_generate_room_async(start_directory, true)


func _generate_room_async(dir_path: String, spawn_at_center: bool = false):
	"""Generate room asynchronously to avoid blocking the game loop"""
	# Check cache first
	if room_cache.has(dir_path):
		enter_room(room_cache[dir_path], spawn_at_center)
		return

	# Wait one frame before starting to ensure scene is ready
	await get_tree().process_frame

	print("Generating room for directory: ", dir_path)

	# Generate the room
	var room = await _create_room_async(dir_path)

	if room:
		# Cache and enter
		room_cache[dir_path] = room
		add_child(room)
		enter_room(room, spawn_at_center)


func _generate_room_for_transition(dir_path: String) -> RoomNode:
	"""Generate a room for transition WITHOUT entering it (for smooth hallway transitions)"""
	# Check cache first
	if room_cache.has(dir_path):
		return room_cache[dir_path]

	print("Generating room for transition: ", dir_path)

	# Generate the room
	var room = await _create_room_async(dir_path)

	if room:
		# Cache but don't enter
		room_cache[dir_path] = room
		add_child(room)
		room.visible = false  # Start hidden

	return room


func _create_room_async(dir_path: String) -> RoomNode:
	"""Create a room asynchronously, processing files in batches"""
	var room = RoomNode.new()
	room.directory_path = dir_path
	room.name = dir_path.get_file() if not dir_path.get_file().is_empty() else "root"

	# Scan directory
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open directory: " + dir_path)
		return null

	var files = []
	var subdirs = []

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = dir_path.path_join(file_name)
			if dir.current_is_dir():
				subdirs.append(file_name)
			else:
				# Limit number of files to display for performance
				if files.size() < MAX_FILES_DISPLAY:
					files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Print info if we hit the limit
	if files.size() >= MAX_FILES_DISPLAY:
		print("Note: Only showing first ", MAX_FILES_DISPLAY, " files in ", dir_path)

	# Calculate room size based on contents
	var num_items = files.size() + subdirs.size()
	var room_size = calculate_room_size(num_items)
	room.room_size = room_size

	# Generate room geometry
	generate_room_geometry(room, room_size)

	# Yield after geometry to prevent blocking
	await get_tree().process_frame

	# Place file cubes in batches
	await _place_file_cubes_async(room, files, dir_path)

	# Yield after placing files
	await get_tree().process_frame

	# Create hallways for subdirectories
	create_hallways(room, subdirs, dir_path)

	print("✓ Room generated: ", files.size(), " files, ", subdirs.size(), " subdirectories")

	return room


func _place_file_cubes_async(room: RoomNode, files: Array, dir_path: String):
	"""Place file cubes in batches to avoid blocking"""
	var grid_size = ceil(sqrt(files.size()))
	var start_x = -(grid_size * FILE_SPACING) / 2.0
	var start_z = -(grid_size * FILE_SPACING) / 2.0

	var batch_size = 20  # Process 20 files per frame

	for i in range(files.size()):
		var row = i / int(grid_size)
		var col = i % int(grid_size)

		var x = start_x + col * FILE_SPACING
		var z = start_z + row * FILE_SPACING

		var file_cube = create_file_cube(files[i], dir_path.path_join(files[i]))
		file_cube.position = Vector3(x, FILE_CUBE_SIZE / 2.0, z)
		room.add_child(file_cube)
		room.file_cubes.append(file_cube)

		# Yield every batch_size files to prevent blocking
		if i % batch_size == batch_size - 1:
			await get_tree().process_frame


func generate_and_enter_room(dir_path: String) -> RoomNode:
	# Check cache first
	if room_cache.has(dir_path):
		enter_room(room_cache[dir_path])
		return room_cache[dir_path]

	print("Generating room for directory: ", dir_path)

	# Generate new room
	var room = RoomNode.new()
	room.directory_path = dir_path
	room.name = dir_path.get_file() if not dir_path.get_file().is_empty() else "root"

	# Scan directory
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open directory: " + dir_path)
		return null

	var files = []
	var subdirs = []

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = dir_path.path_join(file_name)
			if dir.current_is_dir():
				subdirs.append(file_name)
			else:
				# Limit number of files to display for performance
				if files.size() < MAX_FILES_DISPLAY:
					files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Print info if we hit the limit
	if files.size() >= MAX_FILES_DISPLAY:
		print("Note: Only showing first ", MAX_FILES_DISPLAY, " files in ", dir_path)

	# Calculate room size based on contents
	var num_items = files.size() + subdirs.size()
	var room_size = calculate_room_size(num_items)
	room.room_size = room_size

	# Generate room geometry
	generate_room_geometry(room, room_size)

	# Place file cubes
	place_file_cubes(room, files, dir_path)

	# Create hallways for subdirectories
	create_hallways(room, subdirs, dir_path)

	# Cache and enter
	room_cache[dir_path] = room
	add_child(room)
	enter_room(room)

	print("✓ Room generated: ", files.size(), " files, ", subdirs.size(), " subdirectories")

	return room


func calculate_room_size(num_items: int) -> Vector3:
	# Calculate room dimensions based on number of items
	# More items = larger room
	var items_per_row = ceil(sqrt(num_items))
	var width = max(ROOM_BASE_SIZE, items_per_row * FILE_SPACING * 2)
	var depth = width
	var height = 4.0

	return Vector3(width, height, depth)


func calculate_room_radius_for_hallways(num_hallways: int) -> float:
	"""Calculate minimum room radius to prevent hallway overlap"""
	if num_hallways == 0:
		return ROOM_BASE_SIZE / 2.0

	# To prevent hallways from overlapping:
	# Arc length between hallways = radius * angle_between
	# angle_between = 2*PI / num_hallways
	# For no overlap: arc_length >= HALLWAY_WIDTH
	# radius * (2*PI / num_hallways) >= HALLWAY_WIDTH
	# radius >= HALLWAY_WIDTH * num_hallways / (2*PI)

	var min_radius = (HALLWAY_WIDTH * num_hallways) / TAU

	# Add some padding for visual spacing (1.5x the minimum)
	return max(ROOM_BASE_SIZE / 2.0, min_radius * 1.5)


func generate_room_geometry(room: RoomNode, size: Vector3):
	# Create floor
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(size.x, 0.2, size.z)

	var floor = MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.1, 0)
	floor.name = "Floor"

	# Create floor material
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.3, 0.3)
	floor.set_surface_override_material(0, floor_mat)

	room.add_child(floor)

	# Create collision for floor
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	floor.add_child(static_body)

	# Create walls (optional, can be added later)
	# For now just floor for openness


func place_file_cubes(room: RoomNode, files: Array, dir_path: String):
	var grid_size = ceil(sqrt(files.size()))
	var start_x = -(grid_size * FILE_SPACING) / 2.0
	var start_z = -(grid_size * FILE_SPACING) / 2.0

	for i in range(files.size()):
		var row = i / int(grid_size)
		var col = i % int(grid_size)

		var x = start_x + col * FILE_SPACING
		var z = start_z + row * FILE_SPACING

		var file_cube = create_file_cube(files[i], dir_path.path_join(files[i]))
		file_cube.position = Vector3(x, FILE_CUBE_SIZE / 2.0, z)
		room.add_child(file_cube)
		room.file_cubes.append(file_cube)


func create_file_cube(file_name: String, full_path: String) -> Node3D:
	var cube = MeshInstance3D.new()
	cube.name = file_name

	# Create cube mesh
	var mesh = BoxMesh.new()
	mesh.size = Vector3(FILE_CUBE_SIZE, FILE_CUBE_SIZE, FILE_CUBE_SIZE)
	cube.mesh = mesh

	# Create material based on file type
	var mat = StandardMaterial3D.new()
	mat.albedo_color = get_file_type_color(file_name)
	cube.set_surface_override_material(0, mat)

	# Add collision
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = mesh.size
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	cube.add_child(static_body)

	# Store file info
	cube.set_meta("file_path", full_path)
	cube.set_meta("file_name", file_name)

	# Add label
	var label = Label3D.new()
	label.text = file_name
	label.font_size = 8
	label.position = Vector3(0, FILE_CUBE_SIZE / 2.0 + 0.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cube.add_child(label)

	return cube


func get_file_type_color(file_name: String) -> Color:
	var ext = file_name.get_extension().to_lower()

	match ext:
		"gd", "py", "js", "cpp", "h", "c", "rs", "go":
			return Color(0.3, 0.7, 1.0)  # Blue for code
		"txt", "md", "doc", "pdf":
			return Color(1.0, 1.0, 0.8)  # Light yellow for documents
		"png", "jpg", "jpeg", "gif", "bmp", "svg":
			return Color(1.0, 0.5, 1.0)  # Purple for images
		"mp3", "wav", "ogg", "flac":
			return Color(1.0, 0.7, 0.3)  # Orange for audio
		"mp4", "avi", "mkv", "mov":
			return Color(0.8, 0.3, 0.3)  # Red for video
		"desktop":
			return Color(0.3, 1.0, 0.3)  # Green for applications
		_:
			return Color(0.7, 0.7, 0.7)  # Gray for others


func create_hallways(room: RoomNode, subdirs: Array, dir_path: String):
	# Add parent directory hallway (../) for non-root directories
	var parent_path = dir_path.get_base_dir()
	var is_root = (parent_path == dir_path or dir_path == "/" or parent_path.is_empty())

	# Total number of hallways including parent
	var total_hallways = subdirs.size()
	if not is_root:
		total_hallways += 1

	if total_hallways == 0:
		return  # No hallways to create

	# Calculate proper room radius to prevent hallway overlap
	var min_radius_for_hallways = calculate_room_radius_for_hallways(total_hallways)

	# Ensure room is large enough for hallways
	var current_radius = room.room_size.x / 2.0
	if current_radius < min_radius_for_hallways:
		print("  Expanding room from radius ", current_radius, " to ", min_radius_for_hallways, " for ", total_hallways, " hallways")
		room.room_size.x = min_radius_for_hallways * 2.0
		room.room_size.z = min_radius_for_hallways * 2.0
		# Regenerate floor with new size
		for child in room.get_children():
			if child.name == "Floor":
				child.queue_free()
		generate_room_geometry(room, room.room_size)

	var radius = min_radius_for_hallways
	var angle_step = TAU / total_hallways

	# Build a list of all hallways to create with their angles
	var hallways_to_create = []

	# Add parent hallway at PI (behind player spawn)
	if not is_root:
		hallways_to_create.append({"name": "..", "path": parent_path, "is_parent": true})

	# Add subdirectory hallways
	for subdir in subdirs:
		hallways_to_create.append({"name": subdir, "path": dir_path.path_join(subdir), "is_parent": false})

	# Create all hallways with evenly distributed angles
	for i in range(hallways_to_create.size()):
		var hw_data = hallways_to_create[i]
		var angle = i * angle_step
		var hallway = create_hallway(hw_data["name"], hw_data["path"], angle, radius, hw_data["is_parent"], dir_path)
		room.add_child(hallway)
		room.hallways.append(hallway)


func create_hallway(subdir_name: String, full_path: String, angle: float, room_radius: float, is_parent: bool, owner_dir_path: String) -> Node3D:
	"""Create a hallway that extends radially outward from room edge toward next room (clock-like)"""
	var hallway = Node3D.new()
	hallway.name = "Hallway_" + subdir_name

	# Position AT the room edge
	# Hallways extend outward from the perimeter like clock hands
	var x = cos(angle) * room_radius
	var z = sin(angle) * room_radius
	hallway.position = Vector3(x, 0, z)

	# CRITICAL FIX: Proper rotation calculation
	# In Godot, to point in direction (dx, 0, dz), use rotation.y = atan2(dx, dz)
	# Direction outward is (cos(angle), 0, sin(angle))
	hallway.rotation.y = atan2(cos(angle), sin(angle))

	# Create corridor walls (left and right)
	var left_wall = create_wall_mesh(HALLWAY_LENGTH, HALLWAY_HEIGHT, 0.2, is_parent)
	left_wall.position = Vector3(-HALLWAY_WIDTH/2.0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH/2.0)
	hallway.add_child(left_wall)

	var right_wall = create_wall_mesh(HALLWAY_LENGTH, HALLWAY_HEIGHT, 0.2, is_parent)
	right_wall.position = Vector3(HALLWAY_WIDTH/2.0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH/2.0)
	hallway.add_child(right_wall)

	# Create floor with collision
	var floor = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(HALLWAY_WIDTH, 0.2, HALLWAY_LENGTH)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.1, HALLWAY_LENGTH/2.0)

	var floor_mat = StandardMaterial3D.new()
	if is_parent:
		floor_mat.albedo_color = Color(0.5, 0.4, 0.2)  # Brown for parent
	else:
		floor_mat.albedo_color = Color(0.3, 0.3, 0.4)  # Dark blue for subdirs
	floor.set_surface_override_material(0, floor_mat)
	hallway.add_child(floor)

	# Add collision to floor so player can walk on it
	var floor_collision_body = StaticBody3D.new()
	var floor_collision_shape = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = floor_mesh.size
	floor_collision_shape.shape = floor_shape
	floor_collision_body.add_child(floor_collision_shape)
	floor.add_child(floor_collision_body)

	# Create ceiling for better enclosure feeling
	var ceiling = MeshInstance3D.new()
	var ceiling_mesh = BoxMesh.new()
	ceiling_mesh.size = Vector3(HALLWAY_WIDTH, 0.2, HALLWAY_LENGTH)
	ceiling.mesh = ceiling_mesh
	ceiling.position = Vector3(0, HALLWAY_HEIGHT - 0.1, HALLWAY_LENGTH/2.0)

	var ceiling_mat = StandardMaterial3D.new()
	if is_parent:
		ceiling_mat.albedo_color = Color(0.6, 0.5, 0.3, 0.8)
	else:
		ceiling_mat.albedo_color = Color(0.4, 0.4, 0.5, 0.8)
	ceiling_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ceiling.set_surface_override_material(0, ceiling_mat)
	hallway.add_child(ceiling)

	# Add label at entrance
	var label = Label3D.new()
	if is_parent:
		label.text = "⬅ BACK (.."  + ")"
	else:
		label.text = subdir_name + " ➡"
	label.font_size = 12
	label.position = Vector3(0, HALLWAY_HEIGHT - 0.5, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 4
	hallway.add_child(label)

	# Store metadata
	hallway.set_meta("directory_path", full_path)
	hallway.set_meta("directory_name", subdir_name)
	hallway.set_meta("is_parent", is_parent)

	# Store which room this hallway belongs to (for trigger filtering)
	hallway.set_meta("owner_room_path", owner_dir_path)

	# Add full-hallway Area3D trigger to detect when player is in the hallway
	var hallway_trigger = Area3D.new()
	hallway_trigger.name = "HallwayTrigger"
	hallway_trigger.monitoring = true
	var hallway_shape = CollisionShape3D.new()
	var h_shape = BoxShape3D.new()
	h_shape.size = Vector3(HALLWAY_WIDTH - 0.5, HALLWAY_HEIGHT - 0.5, HALLWAY_LENGTH)
	hallway_shape.shape = h_shape
	hallway_shape.position = Vector3(0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH/2.0)
	hallway_trigger.add_child(hallway_shape)
	hallway.add_child(hallway_trigger)

	# Connect enter/exit signals
	hallway_trigger.body_entered.connect(_on_hallway_entered.bind(hallway, full_path, owner_dir_path))
	hallway_trigger.body_exited.connect(_on_hallway_exited.bind(hallway, full_path, owner_dir_path))

	return hallway


func create_wall_mesh(length: float, height: float, thickness: float, is_parent: bool) -> MeshInstance3D:
	"""Helper to create a wall mesh for hallways"""
	var wall = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(thickness, height, length)
	wall.mesh = mesh

	var mat = StandardMaterial3D.new()
	if is_parent:
		mat.albedo_color = Color(0.7, 0.6, 0.3, 0.7)  # Gold/brown for parent
	else:
		mat.albedo_color = Color(0.4, 0.4, 0.6, 0.7)  # Blue for subdirs
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall.set_surface_override_material(0, mat)

	return wall


func _on_hallway_entered(body: Node3D, hallway: Node3D, destination_path: String, source_path: String):
	"""Called when player enters a hallway - load both rooms"""
	if body.name == "Player":
		print("Entered hallway: ", hallway.name)
		print("  Source room: ", source_path)
		print("  Destination: ", destination_path)

		# Track that we're in this hallway
		current_hallway = hallway

		# Keep source room loaded
		if current_room and current_room.directory_path == source_path:
			hallway_source_room = current_room
			print("  Keeping source room loaded: ", source_path)

		# Load and position the destination room
		var is_parent = hallway.get_meta("is_parent", false)
		_handle_hallway_transition(destination_path, source_path, is_parent)


func _handle_hallway_transition(destination_path: String, source_path: String, is_parent: bool):
	"""Async handler to load destination room when entering hallway"""
	var source_room = room_cache.get(source_path, null)
	var destination_room = await _generate_room_for_transition(destination_path)

	if destination_room and source_room:
		# Position the destination room
		_position_connected_hallways(source_room, destination_room, source_path, is_parent)

		# Make destination room current and show both rooms
		current_room = destination_room
		destination_room.visible = true
		_enable_room_triggers(destination_room)

		# Keep source room visible
		if hallway_source_room:
			hallway_source_room.visible = true

		print("  Both rooms loaded:")
		print("    Current (destination): ", destination_room.directory_path)
		print("    Source: ", hallway_source_room.directory_path if hallway_source_room else "none")


func _on_hallway_exited(body: Node3D, hallway: Node3D, destination_path: String, source_path: String):
	"""Called when player exits a hallway - determine which room to keep loaded"""
	if body.name == "Player" and current_hallway == hallway:
		print("Exited hallway: ", hallway.name)

		# Clear hallway tracking
		current_hallway = null

		# Determine which end of the hallway the player exited from
		# Hallway extends in +Z direction in local space:
		#   Z = 0: Source room end
		#   Z = HALLWAY_LENGTH: Destination room end
		var player = body
		var source_room = hallway_source_room
		var dest_room = current_room

		if source_room and dest_room:
			# Get player position in hallway local space
			var player_local = hallway.global_transform.affine_inverse() * player.global_position
			var z_position = player_local.z

			print("  Player Z in hallway: ", z_position, " (0=source, ", HALLWAY_LENGTH, "=destination)")

			if z_position < HALLWAY_LENGTH / 2.0:
				# Player exited from source end (back into source room)
				print("  Exited from source end - keeping source, unloading destination")
				current_room = source_room
				dest_room.visible = false
				_disable_room_triggers(dest_room)
			else:
				# Player exited from destination end (forward into destination room)
				print("  Exited from destination end - keeping destination, unloading source")
				# current_room is already dest_room
				source_room.visible = false
				_disable_room_triggers(source_room)

		hallway_source_room = null
		print("  Only current room loaded: ", current_room.directory_path if current_room else "none")


func _position_connected_hallways(old_room: RoomNode, new_room: RoomNode, old_room_path: String, is_parent: bool):
	"""Position and rotate new room so hallways connect perfectly (both position and rotation)"""

	# Only position the room if it hasn't been positioned yet (check if at origin)
	if new_room.global_position.length() > 0.1:
		print("Room already positioned at: ", new_room.global_position)
		return

	# Find the exit hallway in old room (the one leading to new room)
	var exit_hallway = null
	for hw in old_room.hallways:
		if hw.get_meta("directory_path", "") == new_room.directory_path:
			exit_hallway = hw
			break

	# Find the entrance hallway in new room (the one leading back to old room)
	var entrance_hallway = null
	if is_parent:
		# Going up to parent - find hallway back to child (old room)
		var old_room_name = old_room_path.get_file()
		for hw in new_room.hallways:
			if hw.get_meta("directory_name", "") == old_room_name and not hw.get_meta("is_parent", false):
				entrance_hallway = hw
				break
	else:
		# Going down to child - find parent (..) hallway
		for hw in new_room.hallways:
			if hw.get_meta("is_parent", false):
				entrance_hallway = hw
				break

	if not exit_hallway or not entrance_hallway:
		print("WARNING: Could not find hallway pair")
		return

	# CRITICAL: Rotate the new room so hallways point in OPPOSITE directions
	# Exit hallway points at world angle: old_room.rotation.y + exit_hallway.rotation.y
	# Entrance hallway should point at: exit_world_angle + PI (180° opposite)
	# Entrance hallway world angle: new_room.rotation.y + entrance_hallway.rotation.y
	# Therefore: new_room.rotation.y = old_room.rotation.y + exit_hallway.rotation.y + PI - entrance_hallway.rotation.y

	var exit_world_angle = old_room.rotation.y + exit_hallway.rotation.y
	var required_entrance_world_angle = exit_world_angle + PI
	new_room.rotation.y = required_entrance_world_angle - entrance_hallway.rotation.y

	print("Rotating new room:")
	print("  Exit hallway world angle: ", rad_to_deg(exit_world_angle), "°")
	print("  Entrance hallway should point at: ", rad_to_deg(required_entrance_world_angle), "°")
	print("  New room rotation: ", rad_to_deg(new_room.rotation.y), "°")

	# Now calculate positions with the rotation applied
	# We need to recalculate directions after rotation
	var exit_direction = Vector3(sin(exit_world_angle), 0, cos(exit_world_angle))
	var exit_end_world = old_room.global_position + exit_hallway.position.rotated(Vector3.UP, old_room.rotation.y) + exit_direction * HALLWAY_LENGTH

	# Entrance hallway direction after room rotation
	var entrance_world_angle = new_room.rotation.y + entrance_hallway.rotation.y
	var entrance_direction = Vector3(sin(entrance_world_angle), 0, cos(entrance_world_angle))
	var entrance_end_local_rotated = entrance_hallway.position.rotated(Vector3.UP, new_room.rotation.y) + entrance_direction * HALLWAY_LENGTH

	# Position new room so hallways meet end-to-end
	new_room.global_position = exit_end_world - entrance_end_local_rotated

	print("Positioned room: ", new_room.directory_path, " at ", new_room.global_position)
	print("  Hallways should now be perfectly aligned (180° opposed)")


func _transition_to_room(target_path: String, source_path: String, went_to_parent: bool):
	"""Transition to a new room, placing player at the entrance (for initial spawn or fallback)"""
	# Unload old room by hiding it (keep it cached though)
	var old_room = current_room

	# Generate/load the new room
	await _generate_room_async(target_path, false)

	# Fully hide the old room now that new room is loaded, and disable its triggers
	if old_room and old_room != current_room:
		old_room.visible = false
		_disable_room_triggers(old_room)

	# Position player at appropriate entrance
	var player = get_tree().get_first_node_in_group("player")
	if player and current_room:
		var entrance_hallway = null

		if went_to_parent:
			# We went UP to parent directory
			# Find the hallway that leads back down to the subdir we came from
			var source_dir_name = source_path.get_file()
			for hw in current_room.hallways:
				if hw.get_meta("directory_name", "") == source_dir_name and not hw.get_meta("is_parent", false):
					entrance_hallway = hw
					break
		else:
			# We went DOWN into a subdirectory
			# Spawn at the parent (..) hallway entrance
			for hw in current_room.hallways:
				if hw.get_meta("is_parent", false):
					entrance_hallway = hw
					break

		if entrance_hallway:
			# Place player at the far end of the entrance hallway (entering from outside)
			var hallway_pos = entrance_hallway.position
			var hallway_angle = entrance_hallway.rotation.y

			# Hallways now point OUTWARD from room center
			# Place player at far end (HALLWAY_LENGTH in +Z direction)
			# Then they walk back toward the room center
			var offset = Vector3(0, 0, HALLWAY_LENGTH - 0.5)  # At far end of hallway
			var rotated_offset = offset.rotated(Vector3.UP, hallway_angle)
			player.global_position = current_room.global_position + hallway_pos + rotated_offset + Vector3(0, 1.5, 0)

			# Face player toward the room (opposite of hallway direction)
			player.rotation.y = hallway_angle + PI

			print("Spawned at hallway: ", entrance_hallway.name, " at position: ", player.global_position)
		else:
			# Fallback: place near room center
			player.global_position = current_room.global_position + Vector3(0, 2, 0)
			print("Spawned at room center (no entrance hallway found)")


func _disable_room_triggers(room: RoomNode):
	"""Disable all hallway triggers in a room to prevent unwanted transitions"""
	for hallway in room.hallways:
		for child in hallway.get_children():
			if child is Area3D:
				child.monitoring = false


func _enable_room_triggers(room: RoomNode):
	"""Enable all hallway triggers in a room"""
	for hallway in room.hallways:
		for child in hallway.get_children():
			if child is Area3D:
				child.monitoring = true


func enter_room(room: RoomNode, spawn_at_center: bool = false):
	# Hide current room and disable its triggers
	if current_room and current_room != room:
		current_room.visible = false
		_disable_room_triggers(current_room)

	# Show new room and enable its triggers
	current_room = room
	current_room.visible = true
	_enable_room_triggers(current_room)

	# Only move player to center on initial spawn
	if spawn_at_center:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.global_position = room.global_position + Vector3(0, 2, 0)

	print("Entered room: ", room.directory_path)
