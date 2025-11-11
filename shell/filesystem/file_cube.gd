extends Node3D
class_name FileCube

## Represents a file as an interactive 3D cube

signal file_clicked(file_path: String)
signal file_copied(file_path: String)

var file_path: String = ""
var file_name: String = ""
var is_executable: bool = false


func _ready():
	# Check if file is executable
	if file_path.ends_with(".desktop"):
		is_executable = true


func open_file():
	## Opens the file with the default application
	print("Opening file: ", file_path)

	if is_executable and file_path.ends_with(".desktop"):
		# Launch .desktop file as application
		var compositor = get_tree().get_first_node_in_group("compositor")
		if compositor:
			launch_desktop_file(file_path, compositor.get_display_name())
	elif OS.has_feature("linux"):
		# Use xdg-open to open file in Xvfb display
		var compositor = get_tree().get_first_node_in_group("compositor")
		if compositor:
			var display = compositor.get_display_name()
			print("Opening file with xdg-open on display: ", display)
			# Use env to set DISPLAY for xdg-open process
			OS.create_process("env", ["DISPLAY=" + display, "xdg-open", file_path])
		else:
			# Fallback to default display
			OS.execute("xdg-open", [file_path])
	else:
		# Try to open with default application
		OS.shell_open(file_path)

	file_clicked.emit(file_path)


func launch_desktop_file(desktop_file_path: String, display: String):
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
	print("Launching: ", command, " with args: ", args, " on display: ", display)
	OS.set_environment("DISPLAY", display)
	OS.create_process(command, args)


func copy_to_inventory():
	## Copies this file to the player's inventory
	print("Copying file to inventory: ", file_path)
	file_copied.emit(file_path)

	# TODO: Add to inventory system
	# For now just show a message
	var label = Label3D.new()
	label.text = "Copied!"
	label.font_size = 12
	label.position = Vector3(0, 1, 0)
	label.modulate = Color.GREEN
	add_child(label)

	# Remove label after 1 second
	await get_tree().create_timer(1.0).timeout
	label.queue_free()
