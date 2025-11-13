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
var SystemMonitorWidget = preload("res://shell/scripts/widgets/system_monitor_widget.gd")
var DesktopSwitcherWidget = preload("res://shell/scripts/widgets/desktop_switcher_widget.gd")

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
	"""Create the default panel layout (top and bottom panels)"""

	# Create top panel
	top_panel = create_panel(0)  # 0 = TOP position

	# Create bottom panel
	var bottom_panel = create_panel(1)  # 1 = BOTTOM position

	# Wait one frame for panels to initialize
	await get_tree().process_frame

	# === Top Panel Widgets ===
	# Add app launcher widget (start menu - far left)
	var app_launcher = Control.new()
	app_launcher.set_script(AppLauncherWidget)
	top_panel.call("add_widget", app_launcher)

	# Add system monitor widget
	var system_monitor = Control.new()
	system_monitor.set_script(SystemMonitorWidget)
	top_panel.call("add_widget", system_monitor)

	# Add spacer to push next widgets to the right
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.x = 100  # Larger minimum gap
	top_panel.call("add_widget", spacer)

	# Add mode switcher widget (3D button - far right)
	var mode_switcher = Control.new()
	mode_switcher.set_script(ModeSwitcherWidget)
	top_panel.call("add_widget", mode_switcher)

	# === Bottom Panel Widgets ===
	# Add taskbar widget (open apps - left side)
	var taskbar = Control.new()
	taskbar.set_script(TaskbarWidget)
	bottom_panel.call("add_widget", taskbar)

	# Add spacer to push desktop switcher to the right
	var bottom_spacer = Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_spacer.custom_minimum_size.x = 100  # Larger minimum gap
	bottom_panel.call("add_widget", bottom_spacer)

	# Add desktop switcher widget (far right)
	var desktop_switcher = Control.new()
	desktop_switcher.set_script(DesktopSwitcherWidget)
	bottom_panel.call("add_widget", desktop_switcher)

	print("  Created top panel with start menu, system monitor, and mode switcher")
	print("  Created bottom panel with taskbar and desktop switcher")

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
		# Update all widgets in the panel when showing
		if should_show and panel.has_method("update_all_widgets"):
			panel.update_all_widgets()

	# Backwards compatibility
	if top_panel:
		top_panel.visible = should_show
		if should_show and top_panel.has_method("update_all_widgets"):
			top_panel.update_all_widgets()
