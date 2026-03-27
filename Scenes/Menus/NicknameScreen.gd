extends Control

const UI := preload("res://Scripts/UI/BallhexUI.gd")

@onready var card: Panel = $Margin/Center/Card
@onready var avatar_frame: Panel = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarFrame
@onready var avatar_badge: Panel = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarFrame/AvatarMargin/AvatarBadge
@onready var avatar_initials: Label = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarFrame/AvatarMargin/AvatarBadge/AvatarInitials
@onready var avatar_label: Label = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarLabel
@onready var prev_avatar_button: Button = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarButtons/PrevAvatarButton
@onready var next_avatar_button: Button = $Margin/Center/Card/CardMargin/Layout/Body/AvatarColumn/AvatarButtons/NextAvatarButton
@onready var name_input: LineEdit = $Margin/Center/Card/CardMargin/Layout/Body/FormColumn/NameInput
@onready var next_button: Button = $Margin/Center/Card/CardMargin/Layout/Footer/NextButton
@onready var back_button: Button = $Margin/Center/Card/CardMargin/Layout/Footer/BackButton
@onready var hint_label: Label = $Margin/Center/Card/CardMargin/Layout/Body/FormColumn/Hint

var _avatar_id := 0


func _ready() -> void:
	UI.style_panel(card, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(avatar_frame, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(avatar_badge, UI.avatar_color(GameSettings.avatar_id), Color(1, 1, 1, 0.14), 90)
	UI.style_button(prev_avatar_button, "secondary", 18)
	UI.style_button(next_avatar_button, "secondary", 18)
	UI.style_button(next_button, "primary", 20)
	UI.style_button(back_button, "ghost", 18)
	UI.style_line_edit(name_input, 24)
	UI.style_panel($Margin/Center/Card/CardMargin/Layout/Body/FormColumn/ProfileStats/StatOne, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.06), 24)
	UI.style_panel($Margin/Center/Card/CardMargin/Layout/Body/FormColumn/ProfileStats/StatTwo, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.06), 24)

	prev_avatar_button.pressed.connect(func() -> void: _shift_avatar(-1))
	next_avatar_button.pressed.connect(func() -> void: _shift_avatar(1))
	next_button.pressed.connect(_on_next_pressed)
	back_button.pressed.connect(SceneRouter.go_to_welcome)
	name_input.text_submitted.connect(_on_name_submitted)
	name_input.text_changed.connect(func(_value: String) -> void: _refresh_avatar())

	name_input.text = GameSettings.player_name
	_avatar_id = GameSettings.avatar_id
	_refresh_avatar()
	name_input.grab_focus()


func _on_next_pressed() -> void:
	_submit_profile()


func _on_name_submitted(_value: String) -> void:
	_submit_profile()


func _shift_avatar(delta: int) -> void:
	_avatar_id = posmod(_avatar_id + delta, 6)
	_refresh_avatar()


func _refresh_avatar() -> void:
	UI.style_panel(avatar_badge, UI.avatar_color(_avatar_id), Color(1, 1, 1, 0.14), 90)
	var sample_name := GameSettings.sanitize_player_name(name_input.text)
	avatar_initials.text = sample_name.left(1).to_upper() if not sample_name.is_empty() else "P"
	avatar_label.text = "Avatar badge %d / 6" % [_avatar_id + 1]
	avatar_badge.scale = Vector2.ONE * 0.92
	var tween := create_tween()
	tween.tween_property(avatar_badge, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _submit_profile() -> void:
	var sanitized := GameSettings.sanitize_player_name(name_input.text)
	if sanitized.is_empty():
		hint_label.text = "Please enter a nickname before continuing."
		return
	GameSettings.set_avatar_id(_avatar_id)
	GameSettings.set_player_name(sanitized)
	SceneRouter.go_to_main_menu()
