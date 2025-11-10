extends Node3D
class_name RoomNode

## Represents a directory as a 3D room

## Path to the directory this room represents
var directory_path: String = ""

## Size of the room
var room_size: Vector3 = Vector3.ZERO

## File cubes in this room
var file_cubes: Array[Node3D] = []

## Hallways to subdirectories
var hallways: Array[Node3D] = []

## Whether this room has been fully generated
var fully_generated: bool = false


func _ready():
	pass


func get_directory_name() -> String:
	return directory_path.get_file() if not directory_path.get_file().is_empty() else "root"
