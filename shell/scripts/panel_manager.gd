extends CanvasLayer

## Panel Manager
##
## Sets up and manages desktop panels and widgets.
## Creates default panel layout and populates with widgets.

var mode_manager: Node = null

# Panels - track all panels by position
var panels := {}  # position -> panel_node
var top_panel: Control = null  # Keep for backwards compatibility

# Panel script
var PanelScript = preload("res://shell/scripts/panel_base.gd")

# Widget scripts
var ModeSwitcherWidget = preload("res://shell/scripts/widgets/mode_switcher_widget.gd")
var AppLauncherWidget = preload("res://shell/scripts/widgets/app_launcher_widget.gd")
var TaskbarWidget = preload("res://shell/scripts/widgets/taskbar_widget.gd")

func _ready():
	# Find mode manager
	mode_manager = get_node_or_null("/root/Main/ModeManager")

	if mode_manager:
		# Listen for mode changes to hide/show panels
		mode_manager.mode_changed.connect(_on_mode_changed)

	# Create default panel layout
	_create_default_panels()

	print("PanelManager initialized")

func _create_default_panels():
	"""Create the default panel layout (top panel for now)"""

	# Create top panel
	top_panel = create_panel(0)  # 0 = TOP position

	# Wait one frame for panel to initialize
	await get_tree().process_frame

	# Add mode switcher widget (far left)
	var mode_switcher = Control.new()
	mode_switcher.set_script(ModeSwitcherWidget)
	top_panel.call("add_widget", mode_switcher)

	# Add app launcher widget (left side)
	var app_launcher = Control.new()
	app_launcher.set_script(AppLauncherWidget)
	top_panel.call("add_widget", app_launcher)

	# Add taskbar widget (center - expands)
	var taskbar = Control.new()
	taskbar.set_script(TaskbarWidget)
	top_panel.call("add_widget", taskbar)

	print("  Created top panel with mode switcher, app launcher, and taskbar")

func create_panel(position: int, thickness: int = 40) -> Control:
	"""Create a new panel at the specified position
	position: 0=TOP, 1=BOTTOM, 2=LEFT, 3=RIGHT"""

	# Check if panel already exists at this position
	if position in panels:
		push_warning("Panel already exists at position ", position)
		return panels[position]

	# Create panel
	var panel = Control.new()
	panel.set_script(PanelScript)
	panel.panel_position = position
	panel.panel_thickness = thickness
	panel.background_color = Color(0.2, 0.2, 0.25, 0.95)
	add_child(panel)

	# Store panel reference
	panels[position] = panel

	# Update visibility based on current mode
	if mode_manager:
		panel.visible = mode_manager.is_2d_mode()

	print("  Created panel at position: ", ["TOP", "BOTTOM", "LEFT", "RIGHT"][position])
	return panel

func _on_mode_changed(new_mode):
	"""Hide panels in 3D mode, show in 2D mode"""
	if not mode_manager:
		return

	var should_show = mode_manager.is_2d_mode()

	# Update all panels
	for panel in panels.values():
		panel.visible = should_show

	# Backwards compatibility
	if top_panel:
		top_panel.visible = should_show
