extends CanvasLayer

## Window taskbar that shows running applications for the current room
## Displays at bottom of screen

@export var compositor_path: NodePath
@export var filesystem_generator_path: NodePath
@export var window_display_path: NodePath
@export var player_path: NodePath

var compositor: Node
var filesystem_generator: Node
var window_display: Node
var player: Node3D

# UI references
var taskbar_container: HBoxContainer
var panel: Panel

func _ready():
	# Find required nodes
	if compositor_path:
		compositor = get_node(compositor_path)
	else:
		compositor = get_node_or_null("/root/Main/X11Compositor")

	if filesystem_generator_path:
		filesystem_generator = get_node(filesystem_generator_path)
	else:
		filesystem_generator = get_node_or_null("/root/Main/FileSystemGenerator")

	if window_display_path:
		window_display = get_node(window_display_path)
	else:
		window_display = get_node_or_null("/root/Main/WindowDisplay")

	if player_path:
		player = get_node(player_path)
	else:
		player = get_tree().get_first_node_in_group("player")

	# Create UI
	create_taskbar_ui()

func create_taskbar_ui():
	# Create panel at bottom of screen
	panel = Panel.new()
	add_child(panel)

	# Position at bottom
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -60  # 60 pixels tall

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_width_top = 2
	style.border_color = Color(0.3, 0.5, 0.8, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	# Create horizontal container for window buttons
	taskbar_container = HBoxContainer.new()
	panel.add_child(taskbar_container)
	taskbar_container.anchor_left = 0.0
	taskbar_container.anchor_right = 1.0
	taskbar_container.anchor_top = 0.0
	taskbar_container.anchor_bottom = 1.0
	taskbar_container.offset_left = 10
	taskbar_container.offset_right = -10
	taskbar_container.offset_top = 5
	taskbar_container.offset_bottom = -5
	taskbar_container.add_theme_constant_override("separation", 10)

func _process(_delta):
	update_taskbar()

func update_taskbar():
	if not compositor or not compositor.is_initialized():
		return

	if not window_display or not filesystem_generator:
		return

	# Get current room path
	var current_room = filesystem_generator.current_room
	if not current_room:
		return

	var current_room_path = current_room.directory_path

	# Get all windows and filter by room
	var window_ids = compositor.get_window_ids()
	var room_windows = []

	for window_id in window_ids:
		# Check if window is mapped (not closed)
		if not compositor.is_window_mapped(window_id):
			continue

		# Check if window belongs to current room
		if window_display.window_quads.has(window_id):
			var quad = window_display.window_quads[window_id]
			if quad.has_meta("room_path") and quad.get_meta("room_path") == current_room_path:
				room_windows.append(window_id)

	# Update UI - only if changed
	if room_windows.size() != taskbar_container.get_child_count():
		rebuild_taskbar(room_windows)
	else:
		# Update existing buttons
		for i in range(room_windows.size()):
			var window_id = room_windows[i]
			if i < taskbar_container.get_child_count():
				var button = taskbar_container.get_child(i) as Button
				if button:
					var window_title = compositor.get_window_title(window_id)
					var window_class = compositor.get_window_class(window_id)
					button.text = window_class if window_class != "" else window_title
					button.set_meta("window_id", window_id)

func rebuild_taskbar(window_ids: Array):
	# Clear existing buttons
	for child in taskbar_container.get_children():
		child.queue_free()

	# Create button for each window
	for window_id in window_ids:
		create_window_button(window_id)

func create_window_button(window_id: int):
	var button = Button.new()
	taskbar_container.add_child(button)

	var window_title = compositor.get_window_title(window_id)
	var window_class = compositor.get_window_class(window_id)

	# Use class name for button text, fallback to title
	button.text = window_class if window_class != "" else window_title
	button.custom_minimum_size = Vector2(150, 40)
	button.tooltip_text = window_title
	button.set_meta("window_id", window_id)

	# Connect click to teleport
	button.pressed.connect(func(): teleport_to_window(window_id))

	# Style based on selection state
	var window_interaction = get_node_or_null("/root/Main/WindowInteraction")
	if window_interaction and window_interaction.get("selected_window_id") == window_id:
		# Selected window - highlight
		button.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))

func teleport_to_window(window_id: int):
	if not window_display or not player:
		return

	if not window_display.window_quads.has(window_id):
		return

	var quad = window_display.window_quads[window_id]
	var window_pos = quad.global_position

	# Get window size to calculate proper viewing distance
	var window_size = compositor.get_window_size(window_id)
	var width_world = float(window_size.x) / window_display.pixels_per_world_unit
	var height_world = float(window_size.y) / window_display.pixels_per_world_unit
	var window_diagonal = sqrt(width_world * width_world + height_world * height_world)

	# Place player at a distance where full window is visible
	# Distance = (diagonal / 2) / tan(fov/2), with some padding
	var camera = player.get_node_or_null("Camera")
	var fov_rad = deg_to_rad(75.0)  # Default FOV
	if camera:
		fov_rad = deg_to_rad(camera.fov)

	var optimal_distance = (window_diagonal / 2.0) / tan(fov_rad / 2.0) + 1.0

	# Get window normal (direction it's facing)
	var window_forward = -quad.global_transform.basis.z

	# Position player in front of window
	var target_pos = window_pos + window_forward * optimal_distance
	target_pos.y = window_pos.y  # Keep at window height

	# Teleport player
	player.global_position = target_pos

	# Face player toward window - rotate player body
	var look_direction = (window_pos - target_pos).normalized()
	player.rotation.y = atan2(look_direction.x, look_direction.z)

	# Reset camera pitch to look straight ahead (not up or down)
	if camera:
		camera.rotation.x = 0.0

	print("Teleported to window ", window_id, " at ", target_pos)
	print("  Player facing: ", rad_to_deg(player.rotation.y), "°")
	print("  Camera pitch reset to 0°")

	# Auto-select the window
	var window_interaction = get_node_or_null("/root/Main/WindowInteraction")
	if window_interaction:
		# Give it a frame to process the new position
		await get_tree().process_frame
		# Manually select the window
		window_interaction.select_window(window_id, quad)
