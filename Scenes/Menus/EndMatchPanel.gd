extends Control
class_name EndMatchPanel

const UI := preload("res://Scripts/UI/BallhexUI.gd")

signal restart_requested
signal menu_requested

@onready var room_name_label: Label = $Backdrop/Card/Margin/VBox/TopBar/RoomName
@onready var title_label: Label = $Backdrop/Card/Margin/VBox/Body/Title
@onready var detail_label: Label = $Backdrop/Card/Margin/VBox/Body/Detail
@onready var card: Panel = $Backdrop/Card
@onready var restart_button: Button = $Backdrop/Card/Margin/VBox/TopBar/Buttons/RestartButton
@onready var menu_button: Button = $Backdrop/Card/Margin/VBox/TopBar/Buttons/MenuButton


func _ready() -> void:
	UI.style_panel(card, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_button(restart_button, "primary", 18)
	UI.style_button(menu_button, "secondary", 18)
	UI.style_label(room_name_label, 28)
	UI.style_label(title_label, 46)
	UI.style_label(detail_label, 24, UI.COLOR_MUTED)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	hide_panel()


func show_result(title: String, detail: String) -> void:
	room_name_label.text = NetworkManager.active_lobby_name if not NetworkManager.active_lobby_name.is_empty() else "Match finished"
	title_label.text = title
	detail_label.text = detail
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
