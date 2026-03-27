extends Control

const UI := preload("res://Scripts/UI/BallhexUI.gd")

@onready var logo: TextureRect = $Logo
@onready var player_anchor: Control = $PlayerAnchor
@onready var player_main: Sprite2D = $PlayerAnchor/PlayerMain
@onready var action_card: Panel = $ActionCard
@onready var guest_button: Button = $ActionCard/CardMargin/CardLayout/Actions/GuestButton
@onready var sign_in_button: Button = $ActionCard/CardMargin/CardLayout/Actions/SignInButton
@onready var status_label: Label = $ActionCard/CardMargin/CardLayout/Status


func _ready() -> void:
	UI.style_panel(action_card, Color(0.84, 0.92, 0.93, 0.22), Color(1, 1, 1, 0.34), 28)
	UI.style_button(guest_button, "blue", 20)
	UI.style_button(sign_in_button, "danger", 20)
	UI.style_label(status_label, 15, Color(0.92, 0.97, 1.0, 0.92))
	guest_button.pressed.connect(SceneRouter.go_to_nickname)
	sign_in_button.pressed.connect(_on_sign_in_pressed)
	_play_intro()


func _on_sign_in_pressed() -> void:
	status_label.text = "Sign-in flow coming soon. Continue as Guest is ready now."


func _play_intro() -> void:
	logo.modulate.a = 0.0
	player_main.modulate.a = 0.0
	action_card.modulate.a = 0.0
	logo.scale = Vector2.ONE * 0.92
	player_main.scale = Vector2.ONE * 0.86

	var intro := create_tween()
	intro.set_parallel(true)
	intro.tween_property(logo, "modulate:a", 1.0, 0.35)
	intro.tween_property(logo, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(player_main, "modulate:a", 1.0, 0.42)
	intro.tween_property(player_main, "scale", Vector2(1.02, 1.02), 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(action_card, "modulate:a", 1.0, 0.5)

	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(player_anchor, "position:y", player_anchor.position.y - 8.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(player_anchor, "position:y", player_anchor.position.y, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
