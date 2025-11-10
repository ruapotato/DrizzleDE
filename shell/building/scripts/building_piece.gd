extends StaticBody3D
class_name BuildingPiece

## Base class for all building pieces
## Handles placement validation, snapping, and visual feedback

@export var piece_name: String = "Building Piece"
@export var piece_category: String = "Misc"
@export var can_snap: bool = true
@export var snap_distance: float = 0.1
@export_flags_3d_physics var placement_collision_mask: int = 1

var is_preview: bool = false
var is_valid_placement: bool = true
var snap_points: Array[Node3D] = []
var snapped_to: Node3D = null

# Materials for visual feedback
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D
var normal_materials: Array[Material] = []

func _ready():
	# Setup materials for placement preview
	valid_material = StandardMaterial3D.new()
	valid_material.albedo_color = Color(0.5, 1.0, 0.5, 0.5)
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color(1.0, 0.5, 0.5, 0.5)
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Find all snap points in children
	_find_snap_points(self)

	if not is_preview:
		# Store normal materials
		_store_normal_materials(self)

func _find_snap_points(node: Node):
	"""Recursively find all nodes marked as snap points"""
	for child in node.get_children():
		if child.is_in_group("snap_point"):
			snap_points.append(child)
		_find_snap_points(child)

func _store_normal_materials(node: Node):
	"""Store original materials from MeshInstance3D nodes"""
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if mat:
				normal_materials.append(mat)
	for child in node.get_children():
		_store_normal_materials(child)

func set_preview_mode(preview: bool):
	"""Enable/disable preview mode with visual feedback"""
	is_preview = preview

	if preview:
		# Disable collision in preview mode
		collision_layer = 0
		collision_mask = 0
	else:
		# Restore collision
		collision_layer = 1
		collision_mask = placement_collision_mask

func update_placement_validity(valid: bool):
	"""Update visual feedback based on placement validity"""
	is_valid_placement = valid

	if not is_preview:
		return

	var material = valid_material if valid else invalid_material
	_apply_preview_material(self, material)

func _apply_preview_material(node: Node, material: Material):
	"""Apply preview material to all mesh instances"""
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, material)

	for child in node.get_children():
		_apply_preview_material(child, material)

func restore_normal_materials():
	"""Restore original materials after preview"""
	_restore_materials(self, 0)

var _material_index = 0
func _restore_materials(node: Node, start_index: int) -> int:
	"""Recursively restore materials"""
	var index = start_index

	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			if index < normal_materials.size():
				node.set_surface_override_material(i, normal_materials[index])
				index += 1

	for child in node.get_children():
		index = _restore_materials(child, index)

	return index

func check_placement_validity(position: Vector3, normal: Vector3) -> bool:
	"""Check if piece can be placed at given position"""
	# Override in subclasses for specific placement rules
	return true

func get_snap_point_at(local_pos: Vector3) -> Node3D:
	"""Find snap point closest to local position"""
	var closest: Node3D = null
	var closest_dist = snap_distance

	for point in snap_points:
		var dist = point.position.distance_to(local_pos)
		if dist < closest_dist:
			closest = point
			closest_dist = dist

	return closest

func get_all_snap_points() -> Array[Node3D]:
	"""Get all snap points for this piece"""
	return snap_points
