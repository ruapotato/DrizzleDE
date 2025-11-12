extends Control

## Base class for panel widgets
##
## Widgets are UI components that can be added to panels,
## such as app launchers, taskbars, system monitors, etc.

signal widget_clicked()

@export var widget_name: String = "Widget"
@export var min_width: int = 50
@export var preferred_width: int = 200
@export var expand: bool = false  # Should widget expand to fill available space?

func _ready():
	# Set size constraints
	custom_minimum_size.x = min_width

	if expand:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		custom_minimum_size.x = preferred_width

	# Enable mouse input for right-click menu
	mouse_filter = Control.MOUSE_FILTER_PASS

	_widget_ready()

func _widget_ready():
	"""Override this in child classes for initialization"""
	pass

func _gui_input(event: InputEvent):
	"""Handle right-click for widget menu"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_widget_menu(mb.global_position)
			get_viewport().set_input_as_handled()

func _show_widget_menu(at_position: Vector2):
	"""Show widget configuration menu"""
	var popup = PopupMenu.new()
	popup.add_item("Move Left", 0)
	popup.add_item("Move Right", 1)
	popup.add_separator()
	popup.add_item("Remove Widget", 2)
	popup.add_separator()
	popup.add_item("Properties...", 3)

	add_child(popup)
	popup.position = Vector2i(at_position)
	popup.popup()
	popup.id_pressed.connect(_on_widget_menu_selected.bind(popup))

func _on_widget_menu_selected(id: int, popup: PopupMenu):
	"""Handle widget menu selection"""
	# Get parent panel
	var panel = get_parent().get_parent()  # widget -> container -> panel
	if not panel or not panel.has_method("get_widget_index"):
		popup.queue_free()
		return

	match id:
		0:  # Move Left
			_move_widget(-1, panel)
		1:  # Move Right
			_move_widget(1, panel)
		2:  # Remove Widget
			_remove_widget(panel)
		3:  # Properties
			print("Widget properties (not yet implemented)")

	popup.queue_free()

func _move_widget(direction: int, panel: Control):
	"""Move widget left (-1) or right (1) in panel"""
	if not panel.has_method("move_widget"):
		print("Panel doesn't support move_widget")
		return

	panel.move_widget(self, direction)

func _remove_widget(panel: Control):
	"""Remove this widget from the panel"""
	if not panel.has_method("remove_widget"):
		print("Panel doesn't support remove_widget")
		return

	panel.remove_widget(self)

func update_widget():
	"""Override this in child classes to update widget state"""
	pass
