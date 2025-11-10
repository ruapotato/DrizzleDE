extends CanvasLayer

## Building UI for selecting and managing building pieces
## Similar to Valheim's build menu

signal piece_selected(piece_id: String)
signal build_mode_toggle_requested()

@export var building_system_path: NodePath

var building_system: BuildingSystem
var menu_visible: bool = false
var current_category: String = ""

# UI References
var category_container: VBoxContainer
var piece_container: GridContainer
var info_label: Label
var help_label: Label

func _ready():
	if building_system_path:
		building_system = get_node(building_system_path)

	# Create UI
	_create_ui()

	# Hide by default
	visible = false

	# Connect to building system
	if building_system:
		building_system.build_mode_changed.connect(_on_build_mode_changed)
		building_system.piece_selected.connect(_on_piece_selected)

func _create_ui():
	"""Create the building UI elements"""
	# Main container
	var main_container = MarginContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("margin_left", 20)
	main_container.add_theme_constant_override("margin_right", 20)
	main_container.add_theme_constant_override("margin_top", 20)
	main_container.add_theme_constant_override("margin_bottom", 20)
	add_child(main_container)

	var vbox = VBoxContainer.new()
	main_container.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "BUILD MODE"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Info label
	info_label = Label.new()
	info_label.text = "Select a building piece"
	info_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(info_label)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer1)

	# Categories and pieces in horizontal layout
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	# Category list
	var category_panel = PanelContainer.new()
	category_panel.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(category_panel)

	category_container = VBoxContainer.new()
	category_panel.add_child(category_container)

	var cat_label = Label.new()
	cat_label.text = "Categories"
	cat_label.add_theme_font_size_override("font_size", 16)
	category_container.add_child(cat_label)

	# Piece grid
	var piece_panel = PanelContainer.new()
	piece_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(piece_panel)

	var piece_scroll = ScrollContainer.new()
	piece_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piece_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	piece_panel.add_child(piece_scroll)

	piece_container = GridContainer.new()
	piece_container.columns = 4
	piece_container.add_theme_constant_override("h_separation", 10)
	piece_container.add_theme_constant_override("v_separation", 10)
	piece_scroll.add_child(piece_container)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)

	# Help text
	help_label = Label.new()
	help_label.text = "Left Click: Place | Right Click: Remove | Q: Cycle Snap | E: Rotate | ESC: Deselect/Exit"
	help_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(help_label)

	# Populate categories and pieces
	_populate_categories()

func _populate_categories():
	"""Populate category buttons"""
	if not building_system:
		return

	# Clear existing
	for child in category_container.get_children():
		if child is Button:
			child.queue_free()

	var categories = building_system.get_building_pieces_by_category()

	for category in categories.keys():
		var button = Button.new()
		button.text = category
		button.custom_minimum_size = Vector2(180, 40)
		button.pressed.connect(_on_category_selected.bind(category))
		category_container.add_child(button)

	# Select first category by default
	if not categories.is_empty():
		var first_category = categories.keys()[0]
		_on_category_selected(first_category)

func _on_category_selected(category: String):
	"""Handle category selection"""
	current_category = category
	_populate_pieces(category)

func _populate_pieces(category: String):
	"""Populate building pieces for selected category"""
	# Clear existing pieces
	for child in piece_container.get_children():
		child.queue_free()

	if not building_system:
		return

	var categories = building_system.get_building_pieces_by_category()
	if not category in categories:
		return

	var pieces = categories[category]

	for piece in pieces:
		var button = Button.new()
		button.text = piece["name"]
		button.custom_minimum_size = Vector2(120, 80)
		button.pressed.connect(_on_piece_button_pressed.bind(piece["id"]))
		piece_container.add_child(button)

func _on_piece_button_pressed(piece_id: String):
	"""Handle piece selection"""
	if building_system:
		building_system.select_piece(piece_id)

	piece_selected.emit(piece_id)

func _on_build_mode_changed(enabled: bool):
	"""Handle build mode toggle"""
	menu_visible = enabled
	visible = enabled

	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_piece_selected(piece_name: String):
	"""Handle piece selection confirmation"""
	info_label.text = "Selected: " + piece_name
	# Hide menu when piece is selected
	visible = false
	# Mouse will be re-captured by player controller automatically

func _input(event):
	if event.is_action_pressed("build_mode"):
		if building_system:
			building_system.toggle_build_mode()

	# Show/hide menu in build mode
	if building_system and building_system.build_mode:
		if event.is_action_pressed("ui_text_backspace") or event.is_action_pressed("ui_text_delete"):
			visible = not visible
			if visible:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
