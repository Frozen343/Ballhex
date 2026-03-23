extends Control
class_name EndMatchPanel

signal restart_requested
signal menu_requested

@onready var title_label: Label = $Backdrop/Panel/VBox/Title
@onready var detail_label: Label = $Backdrop/Panel/VBox/Detail
@onready var restart_button: Button = $Backdrop/Panel/VBox/RestartButton
@onready var menu_button: Button = $Backdrop/Panel/VBox/MenuButton


func _ready() -> void:
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	hide_panel()


func show_result(title: String, detail: String) -> void:
	title_label.text = title
	detail_label.text = detail
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
