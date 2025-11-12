extends Control

## Represents a 2D window with title bar, decorations, and X11 content
##
## This Control node displays an X11 window in traditional 2D desktop mode
## with title bar, close/minimize/maximize buttons, and drag/resize support.

signal window_focused(window_id: int)
signal window_closed(window_id: int)
signal window_minimized(window_id: int)
signal window_maximized(window_id: int)
signal window_restored(window_id: int)

var window_id: int = -1
var is_minimized: bool = false
var is_maximized: bool = false
var is_fullscreen: bool = false

# Store pre-maximize/fullscreen state for restoration
var restore_position: Vector2 = Vector2.ZERO
var restore_size: Vector2 = Vector2(800, 600)

# Dragging state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Resizing state
enum ResizeMode { NONE, TOP, BOTTOM, LEFT, RIGHT, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }
var resize_mode: ResizeMode = ResizeMode.NONE
var resize_start_position: Vector2 = Vector2.ZERO
var resize_start_size: Vector2 = Vector2.ZERO

# Window constraints
const MIN_WINDOW_SIZE := Vector2(200, 150)
const TITLE_BAR_HEIGHT := 32
const RESIZE_HANDLE_SIZE := 8

# Child nodes (created in _ready)
var title_bar: PanelContainer
var title_label: Label
var minimize_button: Button
var maximize_button: Button
var close_button: Button
var content_container: TextureRect
var resize_handle_top: Control
var resize_handle_bottom: Control
var resize_handle_left: Control
var resize_handle_right: Control
var resize_handle_top_left: Control
var resize_handle_top_right: Control
var resize_handle_bottom_left: Control
var resize_handle_bottom_right: Control

# Compositor reference (set by Window2DManager)
var compositor: Node = null

func _ready():
	# Set up the window container
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true

	# Create title bar
	create_title_bar()

	# Create content area
	create_content_area()

	# Create resize handles
	create_resize_handles()

	# Connect signals
	if title_bar:
		title_bar.gui_input.connect(_on_title_bar_input)

	# Start with default size
	custom_minimum_size = MIN_WINDOW_SIZE
	size = restore_size

func create_title_bar():
	"""Create the title bar with buttons"""
	title_bar = PanelContainer.new()
	title_bar.name = "TitleBar"
	add_child(title_bar)

	# Style the title bar
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	stylebox.set_content_margin_all(4)
	title_bar.add_theme_stylebox_override("panel", stylebox)

	# Title bar layout
	var hbox = HBoxContainer.new()
	title_bar.add_child(hbox)

	# Window title
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Window"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title_label)

	# Minimize button
	minimize_button = Button.new()
	minimize_button.name = "MinimizeButton"
	minimize_button.text = "_"
	minimize_button.custom_minimum_size = Vector2(32, 0)
	minimize_button.pressed.connect(_on_minimize_pressed)
	hbox.add_child(minimize_button)

	# Maximize button
	maximize_button = Button.new()
	maximize_button.name = "MaximizeButton"
	maximize_button.text = "□"
	maximize_button.custom_minimum_size = Vector2(32, 0)
	maximize_button.pressed.connect(_on_maximize_pressed)
	hbox.add_child(maximize_button)

	# Close button
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 0)
	close_button.pressed.connect(_on_close_pressed)
	hbox.add_child(close_button)

	# Position title bar at top
	title_bar.anchor_right = 1.0
	title_bar.size.y = TITLE_BAR_HEIGHT

func create_content_area():
	"""Create the content container for X11 window texture"""
	content_container = TextureRect.new()
	content_container.name = "ContentContainer"
	add_child(content_container)

	content_container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	content_container.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	content_container.mouse_filter = Control.MOUSE_FILTER_PASS

	# Position below title bar
	content_container.anchor_right = 1.0
	content_container.anchor_bottom = 1.0
	content_container.offset_top = TITLE_BAR_HEIGHT

func create_resize_handles():
	"""Create 8 resize handles (corners and edges)"""

	# Top edge
	resize_handle_top = create_resize_handle("Top", ResizeMode.TOP)
	resize_handle_top.anchor_right = 1.0
	resize_handle_top.size.y = RESIZE_HANDLE_SIZE

	# Bottom edge
	resize_handle_bottom = create_resize_handle("Bottom", ResizeMode.BOTTOM)
	resize_handle_bottom.anchor_top = 1.0
	resize_handle_bottom.anchor_right = 1.0
	resize_handle_bottom.anchor_bottom = 1.0
	resize_handle_bottom.offset_top = -RESIZE_HANDLE_SIZE

	# Left edge
	resize_handle_left = create_resize_handle("Left", ResizeMode.LEFT)
	resize_handle_left.anchor_bottom = 1.0
	resize_handle_left.size.x = RESIZE_HANDLE_SIZE

	# Right edge
	resize_handle_right = create_resize_handle("Right", ResizeMode.RIGHT)
	resize_handle_right.anchor_left = 1.0
	resize_handle_right.anchor_right = 1.0
	resize_handle_right.anchor_bottom = 1.0
	resize_handle_right.offset_left = -RESIZE_HANDLE_SIZE

	# Top-left corner
	resize_handle_top_left = create_resize_handle("TopLeft", ResizeMode.TOP_LEFT)
	resize_handle_top_left.size = Vector2(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)

	# Top-right corner
	resize_handle_top_right = create_resize_handle("TopRight", ResizeMode.TOP_RIGHT)
	resize_handle_top_right.anchor_left = 1.0
	resize_handle_top_right.anchor_right = 1.0
	resize_handle_top_right.offset_left = -RESIZE_HANDLE_SIZE
	resize_handle_top_right.size.y = RESIZE_HANDLE_SIZE

	# Bottom-left corner
	resize_handle_bottom_left = create_resize_handle("BottomLeft", ResizeMode.BOTTOM_LEFT)
	resize_handle_bottom_left.anchor_top = 1.0
	resize_handle_bottom_left.anchor_bottom = 1.0
	resize_handle_bottom_left.offset_top = -RESIZE_HANDLE_SIZE
	resize_handle_bottom_left.size.x = RESIZE_HANDLE_SIZE

	# Bottom-right corner
	resize_handle_bottom_right = create_resize_handle("BottomRight", ResizeMode.BOTTOM_RIGHT)
	resize_handle_bottom_right.anchor_left = 1.0
	resize_handle_bottom_right.anchor_right = 1.0
	resize_handle_bottom_right.anchor_top = 1.0
	resize_handle_bottom_right.anchor_bottom = 1.0
	resize_handle_bottom_right.offset_left = -RESIZE_HANDLE_SIZE
	resize_handle_bottom_right.offset_top = -RESIZE_HANDLE_SIZE

func create_resize_handle(handle_name: String, mode: ResizeMode) -> Control:
	"""Helper to create a single resize handle"""
	var handle = Control.new()
	handle.name = "ResizeHandle" + handle_name
	handle.mouse_filter = Control.MOUSE_FILTER_PASS
	handle.mouse_default_cursor_shape = get_cursor_for_resize_mode(mode)
	add_child(handle)

	# Connect input events
	handle.gui_input.connect(_on_resize_handle_input.bind(mode))

	return handle

func get_cursor_for_resize_mode(mode: ResizeMode) -> Control.CursorShape:
	"""Get appropriate cursor shape for resize mode"""
	match mode:
		ResizeMode.TOP, ResizeMode.BOTTOM:
			return Control.CURSOR_VSIZE
		ResizeMode.LEFT, ResizeMode.RIGHT:
			return Control.CURSOR_HSIZE
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			return Control.CURSOR_FDIAGSIZE
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			return Control.CURSOR_BDIAGSIZE
		_:
			return Control.CURSOR_ARROW

func _process(_delta):
	"""Update window texture and handle dragging/resizing"""
	# Update X11 texture
	if compositor and window_id >= 0 and not is_minimized:
		update_texture()

	# Handle dragging
	if is_dragging:
		var mouse_pos = get_viewport().get_mouse_position()
		position = mouse_pos - drag_offset

	# Handle resizing
	if resize_mode != ResizeMode.NONE:
		handle_resize()

func update_texture():
	"""Update the texture from X11 compositor"""
	if not compositor or window_id < 0:
		return

	var image = compositor.get_window_buffer(window_id)
	if not image:
		return

	var texture = ImageTexture.create_from_image(image)
	if content_container:
		content_container.texture = texture

func _on_title_bar_input(event: InputEvent):
	"""Handle title bar interactions (dragging, double-click to maximize)"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start dragging
				is_dragging = true
				drag_offset = mb.position
				window_focused.emit(window_id)

				# Check for double-click to maximize
				if mb.double_click:
					_on_maximize_pressed()
			else:
				# Stop dragging
				is_dragging = false

func _on_resize_handle_input(event: InputEvent, mode: ResizeMode):
	"""Handle resize handle interactions"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start resizing
				resize_mode = mode
				resize_start_position = position
				resize_start_size = size
				window_focused.emit(window_id)
			else:
				# Stop resizing
				resize_mode = ResizeMode.NONE

func handle_resize():
	"""Handle active window resizing"""
	var mouse_pos = get_viewport().get_mouse_position()
	var delta = mouse_pos - (resize_start_position + resize_start_size / 2)

	match resize_mode:
		ResizeMode.TOP:
			var new_y = resize_start_position.y + delta.y
			var new_height = resize_start_size.y - delta.y
			if new_height >= MIN_WINDOW_SIZE.y:
				position.y = new_y
				size.y = new_height

		ResizeMode.BOTTOM:
			var new_height = resize_start_size.y + delta.y
			size.y = max(new_height, MIN_WINDOW_SIZE.y)

		ResizeMode.LEFT:
			var new_x = resize_start_position.x + delta.x
			var new_width = resize_start_size.x - delta.x
			if new_width >= MIN_WINDOW_SIZE.x:
				position.x = new_x
				size.x = new_width

		ResizeMode.RIGHT:
			var new_width = resize_start_size.x + delta.x
			size.x = max(new_width, MIN_WINDOW_SIZE.x)

		ResizeMode.TOP_LEFT:
			var new_pos = resize_start_position + delta
			var new_size = resize_start_size - delta
			if new_size.x >= MIN_WINDOW_SIZE.x and new_size.y >= MIN_WINDOW_SIZE.y:
				position = new_pos
				size = new_size

		ResizeMode.TOP_RIGHT:
			var new_y = resize_start_position.y + delta.y
			var new_height = resize_start_size.y - delta.y
			var new_width = resize_start_size.x + delta.x
			if new_height >= MIN_WINDOW_SIZE.y and new_width >= MIN_WINDOW_SIZE.x:
				position.y = new_y
				size = Vector2(new_width, new_height)

		ResizeMode.BOTTOM_LEFT:
			var new_x = resize_start_position.x + delta.x
			var new_width = resize_start_size.x - delta.x
			var new_height = resize_start_size.y + delta.y
			if new_width >= MIN_WINDOW_SIZE.x and new_height >= MIN_WINDOW_SIZE.y:
				position.x = new_x
				size = Vector2(new_width, new_height)

		ResizeMode.BOTTOM_RIGHT:
			var new_size = resize_start_size + delta
			if new_size.x >= MIN_WINDOW_SIZE.x and new_size.y >= MIN_WINDOW_SIZE.y:
				size = new_size

func _on_minimize_pressed():
	"""Handle minimize button click"""
	is_minimized = true
	visible = false
	window_minimized.emit(window_id)

func _on_maximize_pressed():
	"""Handle maximize/restore button click"""
	if is_maximized:
		# Restore
		position = restore_position
		size = restore_size
		is_maximized = false
		maximize_button.text = "□"
		window_restored.emit(window_id)
	else:
		# Maximize
		restore_position = position
		restore_size = size

		# Fill the entire viewport (will be adjusted by Window2DManager)
		var viewport_size = get_viewport().get_visible_rect().size
		position = Vector2.ZERO
		size = viewport_size

		is_maximized = true
		maximize_button.text = "◱"
		window_maximized.emit(window_id)

func _on_close_pressed():
	"""Handle close button click"""
	# Send close request to X11 window
	if compositor and window_id >= 0:
		compositor.close_window(window_id)

	window_closed.emit(window_id)

func set_window_title(title: String):
	"""Update the window title"""
	if title_label:
		title_label.text = title

func set_fullscreen(enabled: bool):
	"""Set fullscreen mode (no decorations)"""
	is_fullscreen = enabled

	if title_bar:
		title_bar.visible = not enabled

	# Hide resize handles in fullscreen
	if resize_handle_top:
		resize_handle_top.visible = not enabled
		resize_handle_bottom.visible = not enabled
		resize_handle_left.visible = not enabled
		resize_handle_right.visible = not enabled
		resize_handle_top_left.visible = not enabled
		resize_handle_top_right.visible = not enabled
		resize_handle_bottom_left.visible = not enabled
		resize_handle_bottom_right.visible = not enabled

	if enabled:
		# Fill entire viewport
		var viewport_size = get_viewport().get_visible_rect().size
		position = Vector2.ZERO
		size = viewport_size
		content_container.offset_top = 0
	else:
		# Restore decorations
		content_container.offset_top = TITLE_BAR_HEIGHT

func minimize():
	"""Minimize the window (called externally)"""
	_on_minimize_pressed()

func restore():
	"""Restore a minimized window"""
	is_minimized = false
	visible = true
	window_restored.emit(window_id)
