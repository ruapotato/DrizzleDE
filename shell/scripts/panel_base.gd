extends Control

## Base class for desktop panels (top/bottom/left/right)
##
## Panels can contain widgets and are configurable for position,
## size, and alignment. Supports dynamic widget addition/removal.

enum PanelPosition { TOP, BOTTOM, LEFT, RIGHT }
enum PanelAlignment { START, CENTER, END, STRETCH }

signal widget_added(widget: Control)
signal widget_removed(widget: Control)

@export var panel_position: PanelPosition = PanelPosition.BOTTOM
@export var panel_thickness: int = 48  # pixels (height for horizontal, width for vertical)
@export var panel_alignment: PanelAlignment = PanelAlignment.STRETCH
@export var background_color: Color = Color(0.15, 0.15, 0.18, 0.95)
@export var margin: int = 0  # margin from screen edges

# Widget container
var widget_container: HBoxContainer
var panel_background: PanelContainer

# Widgets list
var widgets := []  # Array of Control nodes

func _ready():
	# Set up panel based on position
	_setup_panel()

	# Create background
	_create_background()

	# Create widget container
	_create_widget_container()

	# Enable input for right-click menu
	mouse_filter = Control.MOUSE_FILTER_PASS

	print("Panel initialized at position: ", ["TOP", "BOTTOM", "LEFT", "RIGHT"][panel_position])

func _gui_input(event: InputEvent):
	"""Handle right-click for panel menu"""
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_panel_menu(mb.global_position)
			get_viewport().set_input_as_handled()

func _show_panel_menu(at_position: Vector2):
	"""Show panel configuration menu"""
	var popup = PopupMenu.new()
	popup.add_item("Add Widget...", 0)
	popup.add_item("Remove Panel", 1)
	popup.add_separator()
	popup.add_item("Panel Properties...", 2)

	add_child(popup)
	popup.position = Vector2i(at_position)
	popup.popup()
	popup.id_pressed.connect(_on_panel_menu_selected.bind(popup))

func _on_panel_menu_selected(id: int, popup: PopupMenu):
	"""Handle panel menu selection"""
	match id:
		0:  # Add Widget
			_show_add_widget_dialog()
		1:  # Remove Panel
			print("Remove panel (not yet implemented)")
		2:  # Panel Properties
			print("Panel properties (not yet implemented)")

	popup.queue_free()

func _show_add_widget_dialog():
	"""Show dialog to add a widget"""
	var popup = PopupMenu.new()
	popup.add_item("Mode Switcher", 0)
	popup.add_item("App Launcher", 1)
	popup.add_item("Taskbar", 2)
	popup.add_separator()
	popup.add_item("Cancel", 3)

	add_child(popup)
	popup.position = Vector2i(get_global_mouse_position())
	popup.popup()
	popup.id_pressed.connect(_on_add_widget_selected.bind(popup))

func _on_add_widget_selected(id: int, popup: PopupMenu):
	"""Handle widget addition"""
	match id:
		0:  # Mode Switcher
			var widget = Control.new()
			widget.set_script(load("res://shell/scripts/widgets/mode_switcher_widget.gd"))
			add_widget(widget)
		1:  # App Launcher
			var widget = Control.new()
			widget.set_script(load("res://shell/scripts/widgets/app_launcher_widget.gd"))
			add_widget(widget)
		2:  # Taskbar
			var widget = Control.new()
			widget.set_script(load("res://shell/scripts/widgets/taskbar_widget.gd"))
			add_widget(widget)
		3:  # Cancel
			pass

	popup.queue_free()

func _setup_panel():
	"""Setup panel anchors and size based on position"""
	mouse_filter = Control.MOUSE_FILTER_PASS

	match panel_position:
		PanelPosition.TOP:
			anchor_left = 0.0
			anchor_right = 1.0
			anchor_top = 0.0
			anchor_bottom = 0.0
			offset_left = margin
			offset_right = -margin
			offset_top = margin
			offset_bottom = panel_thickness + margin

		PanelPosition.BOTTOM:
			anchor_left = 0.0
			anchor_right = 1.0
			anchor_top = 1.0
			anchor_bottom = 1.0
			offset_left = margin
			offset_right = -margin
			offset_top = -panel_thickness - margin
			offset_bottom = -margin

		PanelPosition.LEFT:
			anchor_left = 0.0
			anchor_right = 0.0
			anchor_top = 0.0
			anchor_bottom = 1.0
			offset_left = margin
			offset_right = panel_thickness + margin
			offset_top = margin
			offset_bottom = -margin

		PanelPosition.RIGHT:
			anchor_left = 1.0
			anchor_right = 1.0
			anchor_top = 0.0
			anchor_bottom = 1.0
			offset_left = -panel_thickness - margin
			offset_right = -margin
			offset_top = margin
			offset_bottom = -margin

func _create_background():
	"""Create the panel background"""
	panel_background = PanelContainer.new()
	panel_background.name = "PanelBackground"
	panel_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let clicks through to panel
	add_child(panel_background)

	# Fill the panel
	panel_background.anchor_right = 1.0
	panel_background.anchor_bottom = 1.0

	# Create stylebox
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = background_color
	stylebox.set_corner_radius_all(0)
	panel_background.add_theme_stylebox_override("panel", stylebox)

func _create_widget_container():
	"""Create the container that holds widgets"""
	# Use HBoxContainer for horizontal panels, VBoxContainer for vertical
	if panel_position == PanelPosition.TOP or panel_position == PanelPosition.BOTTOM:
		widget_container = HBoxContainer.new()
	else:
		widget_container = HBoxContainer.new()  # TODO: VBoxContainer for vertical panels

	widget_container.name = "WidgetContainer"
	panel_background.add_child(widget_container)

	# Set alignment
	match panel_alignment:
		PanelAlignment.START:
			widget_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		PanelAlignment.CENTER:
			widget_container.alignment = BoxContainer.ALIGNMENT_CENTER
		PanelAlignment.END:
			widget_container.alignment = BoxContainer.ALIGNMENT_END
		PanelAlignment.STRETCH:
			widget_container.alignment = BoxContainer.ALIGNMENT_BEGIN

func add_widget(widget: Control):
	"""Add a widget to the panel"""
	if widget in widgets:
		push_warning("Widget already in panel")
		return

	widgets.append(widget)
	widget_container.add_child(widget)
	widget_added.emit(widget)

	print("  Added widget: ", widget.name)

func remove_widget(widget: Control):
	"""Remove a widget from the panel"""
	var idx = widgets.find(widget)
	if idx == -1:
		push_warning("Widget not found in panel")
		return

	widgets.remove_at(idx)
	widget_container.remove_child(widget)
	widget_removed.emit(widget)

	print("  Removed widget: ", widget.name)

func clear_widgets():
	"""Remove all widgets"""
	for widget in widgets.duplicate():
		remove_widget(widget)

func get_widget_count() -> int:
	"""Get number of widgets in panel"""
	return widgets.size()
