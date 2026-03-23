extends Node
class_name ResetSystem


func reset_world(players: Array[HexPlayer], ball: MatchBall) -> void:
	for player in players:
		if player != null:
			player.reset_to_spawn()
	if ball != null:
		ball.reset_ball(Vector2.ZERO)
