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

	_widget_ready()

func _widget_ready():
	"""Override this in child classes for initialization"""
	pass

func update_widget():
	"""Override this in child classes to update widget state"""
	pass
