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
var resize_start_mouse_position: Vector2 = Vector2.ZERO

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

	# Set minimum size (actual size will be set by Window2DManager via set_deferred)
	custom_minimum_size = MIN_WINDOW_SIZE
	print("  [DEBUG] Window2D _ready() complete. Size: ", size, ", custom_minimum_size: ", custom_minimum_size)

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
	title_bar.custom_minimum_size.y = TITLE_BAR_HEIGHT
	title_bar.size.y = TITLE_BAR_HEIGHT

func create_content_area():
	"""Create the content container for X11 window texture"""
	content_container = TextureRect.new()
	content_container.name = "ContentContainer"
	add_child(content_container)

	content_container.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	content_container.stretch_mode = TextureRect.STRETCH_KEEP
	content_container.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture input to forward to X11
	content_container.focus_mode = Control.FOCUS_ALL  # Allow keyboard focus

	# Position below title bar
	content_container.anchor_right = 1.0
	content_container.anchor_bottom = 1.0
	content_container.offset_top = TITLE_BAR_HEIGHT

	# Connect input events to forward to X11 window
	content_container.gui_input.connect(_on_content_input)

func create_resize_handles():
	"""Create 8 resize handles (corners and edges)"""

	# Top edge
	resize_handle_top = create_resize_handle("Top", ResizeMode.TOP)
	resize_handle_top.anchor_right = 1.0
	resize_handle_top.custom_minimum_size.y = RESIZE_HANDLE_SIZE

	# Bottom edge
	resize_handle_bottom = create_resize_handle("Bottom", ResizeMode.BOTTOM)
	resize_handle_bottom.anchor_top = 1.0
	resize_handle_bottom.anchor_right = 1.0
	resize_handle_bottom.anchor_bottom = 1.0
	resize_handle_bottom.offset_top = -RESIZE_HANDLE_SIZE

	# Left edge
	resize_handle_left = create_resize_handle("Left", ResizeMode.LEFT)
	resize_handle_left.anchor_bottom = 1.0
	resize_handle_left.custom_minimum_size.x = RESIZE_HANDLE_SIZE

	# Right edge
	resize_handle_right = create_resize_handle("Right", ResizeMode.RIGHT)
	resize_handle_right.anchor_left = 1.0
	resize_handle_right.anchor_right = 1.0
	resize_handle_right.anchor_bottom = 1.0
	resize_handle_right.offset_left = -RESIZE_HANDLE_SIZE

	# Top-left corner
	resize_handle_top_left = create_resize_handle("TopLeft", ResizeMode.TOP_LEFT)
	resize_handle_top_left.custom_minimum_size = Vector2(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)

	# Top-right corner
	resize_handle_top_right = create_resize_handle("TopRight", ResizeMode.TOP_RIGHT)
	resize_handle_top_right.anchor_left = 1.0
	resize_handle_top_right.anchor_right = 1.0
	resize_handle_top_right.offset_left = -RESIZE_HANDLE_SIZE
	resize_handle_top_right.custom_minimum_size.y = RESIZE_HANDLE_SIZE

	# Bottom-left corner
	resize_handle_bottom_left = create_resize_handle("BottomLeft", ResizeMode.BOTTOM_LEFT)
	resize_handle_bottom_left.anchor_top = 1.0
	resize_handle_bottom_left.anchor_bottom = 1.0
	resize_handle_bottom_left.offset_top = -RESIZE_HANDLE_SIZE
	resize_handle_bottom_left.custom_minimum_size.x = RESIZE_HANDLE_SIZE

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

var _debug_size_set := false

func _process(_delta):
	"""Update window texture and handle dragging/resizing"""
	# Debug: Log size once after it's been set via set_deferred
	if not _debug_size_set and size.x > 0 and size.y > 0:
		_debug_size_set = true
		print("  [DEBUG] Window2D size after set_deferred: ", size)
		print("  [DEBUG] Content container size: ", content_container.size if content_container else Vector2.ZERO)

	# Update X11 texture
	if compositor and window_id >= 0 and not is_minimized:
		update_texture()

	# Handle dragging
	if is_dragging:
		var new_position = get_global_mouse_position() - drag_offset

		# Clamp position to keep title bar visible and below panel
		var viewport_size = get_viewport().get_visible_rect().size
		var panel_height = 40  # Top panel height

		# Minimum Y to keep title bar below panel
		var min_y = panel_height
		# Maximum Y to keep at least title bar visible
		var max_y = viewport_size.y - TITLE_BAR_HEIGHT
		# Maximum X to keep at least part of window visible
		var max_x = viewport_size.x - 100  # Keep at least 100px visible
		var min_x = -size.x + 100  # Allow dragging mostly off left side, but keep 100px visible

		new_position.x = clamp(new_position.x, min_x, max_x)
		new_position.y = clamp(new_position.y, min_y, max_y)

		global_position = new_position

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

func _gui_input(event: InputEvent):
	"""Handle window clicks for focus"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			window_focused.emit(window_id)
			get_viewport().set_input_as_handled()

func _on_content_input(event: InputEvent):
	"""Forward input events to the X11 window"""
	if not compositor or window_id < 0:
		return

	# Get mouse position relative to content container
	var mouse_pos = content_container.get_local_mouse_position()
	var x = int(mouse_pos.x)
	var y = int(mouse_pos.y)

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton

		# Focus window and grab keyboard focus on any click
		window_focused.emit(window_id)
		content_container.grab_focus()

		# Forward mouse button event to X11
		# Godot uses MOUSE_BUTTON_LEFT=1, MOUSE_BUTTON_RIGHT=2, MOUSE_BUTTON_MIDDLE=3
		# X11 uses Button1=1 (left), Button2=2 (middle), Button3=3 (right)
		var x11_button = mb.button_index
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			x11_button = 3
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			x11_button = 2

		compositor.send_mouse_button(window_id, x11_button, mb.pressed, x, y)
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		# Forward mouse motion to X11
		compositor.send_mouse_motion(window_id, x, y)

	elif event is InputEventKey:
		var key = event as InputEventKey
		# Forward keyboard event to X11
		compositor.send_key_event(window_id, int(key.keycode), key.pressed)
		get_viewport().set_input_as_handled()

func _on_title_bar_input(event: InputEvent):
	"""Handle title bar interactions (dragging, double-click to maximize)"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Check if this is a popup window - if so, delegate dragging to root window
				var root_window = _get_root_window()
				if root_window and root_window != self:
					# This is a popup - start dragging the root window instead
					root_window.is_dragging = true
					root_window.drag_offset = get_global_mouse_position() - root_window.global_position
					root_window.window_focused.emit(root_window.window_id)
					get_viewport().set_input_as_handled()
				else:
					# Normal window - drag this window
					is_dragging = true
					drag_offset = get_global_mouse_position() - global_position
					window_focused.emit(window_id)
					get_viewport().set_input_as_handled()
			else:
				# Stop dragging (check if we're dragging root)
				var root_window = _get_root_window()
				if root_window and root_window != self:
					root_window.is_dragging = false
				else:
					is_dragging = false
				get_viewport().set_input_as_handled()

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
				resize_start_mouse_position = get_viewport().get_mouse_position()
				window_focused.emit(window_id)
			else:
				# Stop resizing
				resize_mode = ResizeMode.NONE

func handle_resize():
	"""Handle active window resizing"""
	var mouse_pos = get_viewport().get_mouse_position()
	var delta = mouse_pos - resize_start_mouse_position

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

	# Resize the actual X11 window to match the content area (size minus title bar)
	if compositor and window_id >= 0:
		var content_width = int(size.x)
		var content_height = int(size.y) - TITLE_BAR_HEIGHT
		if content_height > 0:
			compositor.resize_window(window_id, content_width, content_height)

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

func _get_root_window():
	"""Find the root (top-level) window by walking up the parent chain"""
	if not compositor or window_id < 0:
		return self

	# Get the Window2DManager
	var window_manager = get_node_or_null("/root/Main/Window2DManager")
	if not window_manager:
		return self

	# Walk up the parent chain to find the root window
	var current_id = window_id
	var root_id = current_id

	# Limit iterations to prevent infinite loops
	var max_iterations = 10
	var iterations = 0

	while iterations < max_iterations:
		var parent_id = compositor.get_parent_window_id(current_id)
		if parent_id == -1:
			# No parent - this is the root
			break

		# Check if parent exists in window manager
		if window_manager.has_method("get") and parent_id in window_manager.get("window_2d_nodes"):
			root_id = parent_id
			current_id = parent_id
		else:
			# Parent doesn't exist in 2D manager - current is root
			break

		iterations += 1

	# Get the root window node
	if root_id != window_id and window_manager.has_method("get"):
		var window_2d_nodes = window_manager.get("window_2d_nodes")
		if window_2d_nodes and root_id in window_2d_nodes:
			return window_2d_nodes[root_id]

	return self

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
