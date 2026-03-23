extends Control
class_name DebugOverlay

@onready var state_label: Label = $Panel/Margin/VBox/State
@onready var body_label: Label = $Panel/Margin/VBox/Body

var _state_name := "BOOT"


func set_state_name(value: String) -> void:
	_state_name = value


func update_snapshot(snapshot: Dictionary) -> void:
	state_label.text = "State: %s" % _state_name
	var lines := PackedStringArray([
		"Timer: %s" % snapshot.get("timer", "--:--"),
		"Score: Red %s / Blue %s" % [snapshot.get("red_score", 0), snapshot.get("blue_score", 0)],
		"Ball Speed: %s" % snapshot.get("ball_speed", 0.0),
		"Ball Velocity: %s" % str(snapshot.get("ball_velocity", Vector2.ZERO)),
		"Last Touch: %s / P%s" % [snapshot.get("last_touch_team", "Neutral"), snapshot.get("last_touch_player_id", -1)],
		"P1 Velocity: %s" % str(snapshot.get("p1_velocity", Vector2.ZERO)),
		"P2 Velocity: %s" % str(snapshot.get("p2_velocity", Vector2.ZERO)),
		"Shortcuts: F5 ball, F6 match, F7 red, F8 blue"
	])
	body_label.text = "\n".join(lines)
