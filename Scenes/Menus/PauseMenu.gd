extends Control
class_name PauseMenu

signal resume_requested
signal menu_requested

@onready var resume_button: Button = $Backdrop/Panel/VBox/ResumeButton
@onready var menu_button: Button = $Backdrop/Panel/VBox/MenuButton


func _ready() -> void:
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	hide_panel()


func show_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
