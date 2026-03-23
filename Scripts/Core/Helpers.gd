extends RefCounted
class_name Helpers


static func format_match_time(seconds: float) -> String:
	var clamped_seconds := maxi(0, int(ceil(seconds)))
	var minutes := int(floor(float(clamped_seconds) / 60.0))
	var remaining_seconds := clamped_seconds % 60
	return "%02d:%02d" % [minutes, remaining_seconds]


static func team_name(team_id: int) -> String:
	match team_id:
		GameEnums.TeamId.RED:
			return "Red"
		GameEnums.TeamId.BLUE:
			return "Blue"
		_:
			return "Neutral"


static func team_color(team_id: int) -> Color:
	match team_id:
		GameEnums.TeamId.RED:
			return GameSettings.COLOR_RED_TEAM
		GameEnums.TeamId.BLUE:
			return GameSettings.COLOR_BLUE_TEAM
		_:
			return Color.WHITE


static func winner_text(red_score: int, blue_score: int) -> String:
	if red_score > blue_score:
		return "Red Team Wins"
	if blue_score > red_score:
		return "Blue Team Wins"
	return "Draw"
