extends Control

@onready var name_input: LineEdit = $Center/Card/Margin/VBox/NameInput
@onready var next_button: Button = $Center/Card/Margin/VBox/NextButton
@onready var hint_label: Label = $Center/Card/Margin/VBox/Hint


func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	name_input.text = GameSettings.player_name
	name_input.grab_focus()


func _on_next_pressed() -> void:
	_submit_name()


func _on_name_submitted(_value: String) -> void:
	_submit_name()


func _submit_name() -> void:
	var sanitized := GameSettings.sanitize_player_name(name_input.text)
	if sanitized.is_empty():
		hint_label.text = "Please enter a nickname."
		return
	GameSettings.set_player_name(sanitized)
	SceneRouter.go_to_main_menu()
