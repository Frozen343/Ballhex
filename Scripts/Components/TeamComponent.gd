extends Node
class_name TeamComponent

@export var team_id := GameEnums.TeamId.NEUTRAL


func get_team_color() -> Color:
	return Helpers.team_color(team_id)
