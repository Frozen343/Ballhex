extends Node

signal match_started
signal goal_scored(scoring_team: int, scoring_player_id: int)
signal match_ended(winner_team: int, red_score: int, blue_score: int)
signal pause_toggled(is_paused: bool)
signal ball_kicked(player_id: int, team_id: int)
signal countdown_tick(value: String)


func emit_match_started() -> void:
	match_started.emit()


func emit_goal_scored(scoring_team: int, scoring_player_id: int) -> void:
	goal_scored.emit(scoring_team, scoring_player_id)


func emit_match_ended(winner_team: int, red_score: int, blue_score: int) -> void:
	match_ended.emit(winner_team, red_score, blue_score)


func emit_pause_toggled(is_paused: bool) -> void:
	pause_toggled.emit(is_paused)


func emit_ball_kicked(player_id: int, team_id: int) -> void:
	ball_kicked.emit(player_id, team_id)


func emit_countdown_tick(value: String) -> void:
	countdown_tick.emit(value)
