extends Node3D
class_name FileSystemGenerator

## Generates 3D rooms from file system directories
## Each directory becomes a room with files as cubes and subdirectories as hallways

const FileCube = preload("res://shell/filesystem/file_cube.gd")
const RoomNode = preload("res://shell/filesystem/room_node.gd")

## Room dimensions
const ROOM_BASE_SIZE = 10.0  # Base room size in meters
const HALLWAY_WIDTH = 3.0
const HALLWAY_HEIGHT = 3.0
const HALLWAY_LENGTH = 5.0  # How far hallways extend from the room
const FILE_CUBE_SIZE = 0.5
const FILE_SPACING = 1.0
const MAX_FILES_DISPLAY = 100  # Limit files displayed to prevent performance issues

## Currently active room
var current_room: RoomNode = null

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

	var angle_step = TAU / total_hallways
	var radius = room.room_size.x / 2.0
	var hallway_index = 0

	# Create parent directory hallway first (at the back, angle PI)
	if not is_root:
		var angle = PI  # Behind the player spawn
		var hallway = create_hallway("..", parent_path, angle, radius, true)
		room.add_child(hallway)
		room.hallways.append(hallway)
		hallway_index += 1

	# Create subdirectory hallways around the perimeter
	for i in range(subdirs.size()):
		var angle = hallway_index * angle_step
		var hallway = create_hallway(subdirs[i], dir_path.path_join(subdirs[i]), angle, radius, false)
		room.add_child(hallway)
		room.hallways.append(hallway)
		hallway_index += 1


func create_hallway(subdir_name: String, full_path: String, angle: float, room_radius: float, is_parent: bool = false) -> Node3D:
	"""Create a hallway that extends radially inward toward the room center"""
	var hallway = Node3D.new()
	hallway.name = "Hallway_" + subdir_name

	# Position OUTSIDE the room perimeter
	# The hallway extends inward, so position it one hallway-length away from edge
	var distance_from_center = room_radius + HALLWAY_LENGTH
	var x = cos(angle) * distance_from_center
	var z = sin(angle) * distance_from_center
	hallway.position = Vector3(x, 0, z)

	# Rotate to point INWARD toward room center
	# The corridor mesh extends in +Z, so we rotate +Z to point toward center
	hallway.rotation.y = angle + PI

	# Create corridor walls (left and right)
	var left_wall = create_wall_mesh(HALLWAY_LENGTH, HALLWAY_HEIGHT, 0.2, is_parent)
	left_wall.position = Vector3(-HALLWAY_WIDTH/2.0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH/2.0)
	hallway.add_child(left_wall)

	var right_wall = create_wall_mesh(HALLWAY_LENGTH, HALLWAY_HEIGHT, 0.2, is_parent)
	right_wall.position = Vector3(HALLWAY_WIDTH/2.0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH/2.0)
	hallway.add_child(right_wall)

	# Create floor
	var floor = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(HALLWAY_WIDTH, 0.2, HALLWAY_LENGTH)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, 0.1, HALLWAY_LENGTH/2.0)

	var floor_mat = StandardMaterial3D.new()
	if is_parent:
		floor_mat.albedo_color = Color(0.5, 0.4, 0.2)  # Brown for parent
	else:
		floor_mat.albedo_color = Color(0.3, 0.3, 0.4)  # Dark blue for subdirs
	floor.set_surface_override_material(0, floor_mat)
	hallway.add_child(floor)

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

	# Add trigger zone at the INNER END (room entrance)
	# Hallway points inward (+Z toward center), so inner end is at +Z
	var trigger = Area3D.new()
	trigger.name = "Trigger"
	var trigger_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(HALLWAY_WIDTH - 0.5, HALLWAY_HEIGHT, 2.0)
	trigger_shape.shape = shape
	# Position at inner end (positive Z, near room entrance)
	trigger_shape.position = Vector3(0, HALLWAY_HEIGHT/2.0, HALLWAY_LENGTH - 1.0)
	trigger.add_child(trigger_shape)
	hallway.add_child(trigger)

	# Connect transition signal
	trigger.body_entered.connect(_on_hallway_entered.bind(full_path, is_parent))

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


func _on_hallway_entered(body: Node3D, target_path: String, is_parent: bool):
	if body.name == "Player":
		# Store the source directory before transitioning
		var source_dir = current_room.directory_path if current_room else ""
		# Player entered a hallway, transition to new room
		print("Entering directory: ", target_path)
		_transition_to_room(target_path, source_dir, is_parent)


func _transition_to_room(target_path: String, source_path: String, went_to_parent: bool):
	"""Transition to a new room, placing player at the entrance"""
	# Unload old room by hiding it (keep it cached though)
	var old_room = current_room

	# Generate/load the new room
	await _generate_room_async(target_path, false)

	# Fully hide the old room now that new room is loaded
	if old_room and old_room != current_room:
		old_room.visible = false

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
			# Place player at the outer end of the entrance hallway
			var hallway_pos = entrance_hallway.position
			var hallway_angle = entrance_hallway.rotation.y

			# Hallways point inward (+Z toward room center)
			# Place player at outer end (Z=0 in hallway local space)
			var offset = Vector3(0, 0, 0.5)  # Just inside the outer entrance
			var rotated_offset = offset.rotated(Vector3.UP, hallway_angle)
			player.global_position = current_room.global_position + hallway_pos + rotated_offset + Vector3(0, 1.5, 0)

			# Optionally face the player into the room (away from hallway)
			# player.rotation.y = hallway_angle + PI

			print("Spawned at hallway: ", entrance_hallway.name, " at position: ", player.global_position)
		else:
			# Fallback: place near room center
			player.global_position = current_room.global_position + Vector3(0, 2, 0)
			print("Spawned at room center (no entrance hallway found)")


func enter_room(room: RoomNode, spawn_at_center: bool = false):
	# Hide current room
	if current_room and current_room != room:
		current_room.visible = false

	# Show new room
	current_room = room
	current_room.visible = true

	# Only move player to center on initial spawn
	if spawn_at_center:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.global_position = room.global_position + Vector3(0, 2, 0)

	print("Entered room: ", room.directory_path)
