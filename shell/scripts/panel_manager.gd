extends CanvasLayer

## Panel Manager
##
## Sets up and manages desktop panels and widgets.
## Creates default panel layout and populates with widgets.

var mode_manager: Node = null

# Panels
var top_panel: Control = null

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
	top_panel = Control.new()
	top_panel.set_script(preload("res://shell/scripts/panel_base.gd"))
	top_panel.panel_position = 0  # TOP
	top_panel.panel_thickness = 40
	top_panel.background_color = Color(0.2, 0.2, 0.25, 0.95)
	add_child(top_panel)

	# Wait one frame for panel to initialize
	await get_tree().process_frame

	# Add app launcher widget (left side)
	var app_launcher = Control.new()
	app_launcher.set_script(AppLauncherWidget)
	top_panel.call("add_widget", app_launcher)

	# Add taskbar widget (center - expands)
	var taskbar = Control.new()
	taskbar.set_script(TaskbarWidget)
	top_panel.call("add_widget", taskbar)

	# Add mode switcher widget (right side)
	var mode_switcher = Control.new()
	mode_switcher.set_script(ModeSwitcherWidget)
	top_panel.call("add_widget", mode_switcher)

	print("  Created top panel with app launcher, taskbar, and mode switcher")

func _on_mode_changed(new_mode):
	"""Hide panels in 3D mode, show in 2D mode"""
	if not mode_manager:
		return

	var should_show = mode_manager.is_2d_mode()

	if top_panel:
		top_panel.visible = should_show
