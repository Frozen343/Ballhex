extends Control

const UI := preload("res://Scripts/UI/BallhexUI.gd")

@onready var hero_ball: Panel = $HeroBall
@onready var glow_ring: Panel = $HeroBall/GlowRing
@onready var title_label: Label = $Margin/Layout/Header/Title
@onready var subtitle_label: Label = $Margin/Layout/Header/Subtitle
@onready var guest_button: Button = $Margin/Layout/Footer/Actions/GuestButton
@onready var sign_in_button: Button = $Margin/Layout/Footer/Actions/SignInButton
@onready var status_label: Label = $Margin/Layout/Footer/Status


func _ready() -> void:
	UI.style_button(guest_button, "primary", 22)
	UI.style_button(sign_in_button, "secondary", 20)
	UI.style_panel(hero_ball, Color(0.08, 0.16, 0.21, 0.86), Color(1, 1, 1, 0.08), 140)
	UI.style_panel(glow_ring, Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.12), 152)
	UI.style_label(title_label, 54)
	UI.style_label(subtitle_label, 21, UI.COLOR_MUTED)
	UI.style_label(status_label, 18, UI.COLOR_MUTED)
	guest_button.pressed.connect(SceneRouter.go_to_nickname)
	sign_in_button.pressed.connect(_on_sign_in_pressed)
	_play_intro()


func _on_sign_in_pressed() -> void:
	status_label.text = "Sign-in flow coming soon. Guest profile is ready now."


func _play_intro() -> void:
	hero_ball.scale = Vector2.ONE * 0.86
	hero_ball.modulate.a = 0.0
	title_label.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(hero_ball, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(hero_ball, "modulate:a", 1.0, 0.35)
	tween.tween_property(title_label, "modulate:a", 1.0, 0.4)
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.55)
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(glow_ring, "scale", Vector2.ONE * 1.06, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(glow_ring, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
