extends Control
class_name MatchHUD

@onready var red_score_label: Label = $Scoreboard/Panel/Margin/HBox/RedScore
@onready var timer_label: Label = $Scoreboard/Panel/Margin/HBox/Timer
@onready var blue_score_label: Label = $Scoreboard/Panel/Margin/HBox/BlueScore
@onready var announcement_label: Label = $Announcement
@onready var hint_label: Label = $Hint


func _ready() -> void:
	update_score(0, 0)
	update_timer(GameSettings.MATCH_DURATION_SECONDS)
	hint_label.text = "P1: WASD + SPACE   P2: ARROWS + .   Pause: ESC   Debug: F3"
	announcement_label.modulate.a = 0.0


func update_score(red_score: int, blue_score: int) -> void:
	red_score_label.text = "RED %d" % red_score
	blue_score_label.text = "%d BLUE" % blue_score


func update_timer(remaining_seconds: float) -> void:
	timer_label.text = Helpers.format_match_time(remaining_seconds)


func show_announcement(text: String, color: Color, duration: float) -> void:
	announcement_label.text = text
	announcement_label.modulate = color
	announcement_label.scale = Vector2.ONE * 0.8
	var tween := create_tween()
	tween.tween_property(announcement_label, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(announcement_label, "scale", Vector2.ONE, 0.12)
	tween.tween_interval(maxf(0.0, duration - 0.18))
	tween.tween_property(announcement_label, "modulate:a", 0.0, 0.18)
