extends Node
class_name MatchManager

signal score_changed(red_score: int, blue_score: int)
signal timer_changed(remaining_seconds: float)
signal announcement_requested(text: String, color: Color, duration: float)
signal match_finished(title: String, detail: String)
signal state_updated(state_name: String)

@export var match_duration_seconds := GameSettings.MATCH_DURATION_SECONDS
@export var goal_pause_duration := GameSettings.GOAL_PAUSE_DURATION

var PlayerScene = preload("res://Scenes/Entities/Player/Player.tscn")

@onready var state_machine: MatchStateMachine = $"../StateMachine"
@onready var reset_system: ResetSystem = $"../ResetSystem"
@onready var time_system: MatchTimeSystem = $"../TimeSystem"

@onready var entities_layer: Node2D = $"../../World/Entities"
@onready var ball: MatchBall = $"../../World/Entities/Ball"
@onready var left_goal: GoalZone = $"../../World/Goals/LeftGoal"
@onready var right_goal: GoalZone = $"../../World/Goals/RightGoal"

var red_score := 0
var blue_score := 0
var _players: Array[HexPlayer] = []
var _flow_version := 0


func _ready() -> void:
	left_goal.goal_scored.connect(_on_goal_scored)
	right_goal.goal_scored.connect(_on_goal_scored)
	time_system.time_changed.connect(_on_time_changed)
	time_system.time_expired.connect(_on_time_expired)
	state_machine.state_changed.connect(_on_state_changed)

	if NetworkManager.is_online:
		NetworkManager.lobby_updated.connect(_sync_players_from_lobby)
		_sync_players_from_lobby()
	else:
		_spawn_offline_players()


func _spawn_offline_players() -> void:
	var p1 = _create_player(1, GameEnums.TeamId.RED, "Player 1")
	var p2 = _create_player(2, GameEnums.TeamId.BLUE, "Player 2")
	_players = [p1, p2]
	_setup_player_refs()


func _create_player(id: int, team: int, pname: String) -> HexPlayer:
	var p = PlayerScene.instantiate() as HexPlayer
	p.name = "Player_%d" % id
	p.player_id = id
	p.team_id = team
	p.display_name = pname
	# Spawn position based on team
	if team == GameEnums.TeamId.RED:
		p.position = Vector2(-290, 0)
	else:
		p.position = Vector2(290, 0)
	entities_layer.add_child(p)
	return p


func _sync_players_from_lobby() -> void:
	var active_peers: Array[int] = []

	for peer_id in NetworkManager.lobby_players:
		var pdata: Dictionary = NetworkManager.lobby_players[peer_id]
		var team: int = pdata["team"]

		if team == GameEnums.TeamId.RED or team == GameEnums.TeamId.BLUE:
			active_peers.append(peer_id)
			var existing = _get_player_by_id(peer_id)
			if not existing:
				var p = _create_player(peer_id, team, pdata["name"])
				_players.append(p)
				p.assign_ball(ball)
				ball.register_players(_players)
				if state_machine.is_in_state(GameEnums.MatchState.PLAYING):
					p.set_input_enabled(true)
				announcement_requested.emit("%s joined!" % pdata["name"], Helpers.team_color(team), 2.0)
			else:
				if existing.team_id != team:
					existing.team_id = team
					if team == GameEnums.TeamId.RED:
						existing.position = Vector2(-290, 0)
					else:
						existing.position = Vector2(290, 0)
					existing.queue_redraw()
				existing.display_name = pdata["name"]

	# Remove players no longer in active teams
	var i := _players.size() - 1
	while i >= 0:
		var p = _players[i]
		if p.player_id not in active_peers:
			p.queue_free()
			_players.remove_at(i)
		i -= 1

	ball.register_players(_players)


func _setup_player_refs() -> void:
	for p in _players:
		p.assign_ball(ball)
	ball.register_players(_players)


func _get_player_by_id(id: int) -> HexPlayer:
	for p in _players:
		if p.player_id == id:
			return p
	return null


func start_new_match() -> void:
	_flow_version += 1
	red_score = 0
	blue_score = 0
	score_changed.emit(red_score, blue_score)
	time_system.setup(match_duration_seconds)
	reset_system.reset_world(_players, ball)
	match_finished.emit("", "")
	_start_playing()


func restart_match() -> void:
	start_new_match()


func add_debug_score(team_id: int) -> void:
	if team_id == GameEnums.TeamId.RED:
		red_score += 1
	else:
		blue_score += 1
	score_changed.emit(red_score, blue_score)


func reset_ball_only() -> void:
	ball.reset_ball(Vector2.ZERO)
	if state_machine.is_in_state(GameEnums.MatchState.PLAYING):
		ball.set_ball_motion_enabled(true)


func force_full_reset() -> void:
	_flow_version += 1
	reset_system.reset_world(_players, ball)
	time_system.setup(match_duration_seconds)
	_start_playing()


func build_debug_snapshot() -> Dictionary:
	var snapshot := {
		"state": state_machine.state_name(),
		"timer": Helpers.format_match_time(time_system.remaining_seconds),
		"red_score": red_score,
		"blue_score": blue_score,
		"ball_speed": snapped(ball.velocity.length(), 0.1),
		"ball_velocity": ball.velocity,
		"last_touch_team": Helpers.team_name(ball.last_touch_team_id),
		"last_touch_player_id": ball.last_touch_player_id
	}
	return snapshot


func _start_playing() -> void:
	state_machine.transition_to(GameEnums.MatchState.PLAYING)
	_set_world_active(true)
	_set_goals_enabled(true)
	time_system.start()
	GameEvents.emit_match_started()


func _on_goal_scored(scoring_team: int, _defending_team: int) -> void:
	if not state_machine.is_in_state(GameEnums.MatchState.PLAYING):
		return

	state_machine.transition_to(GameEnums.MatchState.GOAL_SCORED)
	_set_goals_enabled(false)
	time_system.stop()

	if scoring_team == GameEnums.TeamId.RED:
		red_score += 1
	else:
		blue_score += 1

	score_changed.emit(red_score, blue_score)
	var scorer_id := ball.last_touch_player_id
	GameEvents.emit_goal_scored(scoring_team, scorer_id)

	var msg := "%s Scores!" % Helpers.team_name(scoring_team)
	var col := Helpers.team_color(scoring_team)
	announcement_requested.emit(msg, col, goal_pause_duration)

	if NetworkManager.is_online and NetworkManager.is_host():
		_rpc_receive_announcement.rpc(msg, col.r, col.g, col.b, goal_pause_duration)

	_schedule_post_goal_flow()


func _schedule_post_goal_flow() -> void:
	_flow_version += 1
	_schedule_post_goal_flow_async(_flow_version)


func _schedule_post_goal_flow_async(flow_version: int) -> void:
	await get_tree().create_timer(goal_pause_duration).timeout
	if not _is_flow_valid(flow_version):
		return
	reset_system.reset_world(_players, ball)
	_start_playing()


func _on_time_changed(remaining_seconds: float) -> void:
	timer_changed.emit(remaining_seconds)


func _on_time_expired() -> void:
	if state_machine.is_in_state(GameEnums.MatchState.MATCH_ENDED):
		return
	_flow_version += 1
	state_machine.transition_to(GameEnums.MatchState.MATCH_ENDED)
	_set_world_active(false)
	_set_goals_enabled(false)
	var winner_title := Helpers.winner_text(red_score, blue_score)
	var detail := "Red %d - %d Blue" % [red_score, blue_score]
	match_finished.emit(winner_title, detail)
	GameEvents.emit_match_ended(_winner_team_id(), red_score, blue_score)


func _winner_team_id() -> int:
	if red_score > blue_score:
		return GameEnums.TeamId.RED
	if blue_score > red_score:
		return GameEnums.TeamId.BLUE
	return GameEnums.TeamId.NEUTRAL


func _set_world_active(active: bool) -> void:
	for player in _players:
		player.set_input_enabled(active)
	ball.set_ball_motion_enabled(active)


func _set_goals_enabled(active: bool) -> void:
	left_goal.set_scoring_enabled(active)
	right_goal.set_scoring_enabled(active)


func _on_state_changed(_previous_state: int, _new_state: int) -> void:
	state_updated.emit(state_machine.state_name())


func _is_flow_valid(flow_version: int) -> bool:
	return flow_version == _flow_version


# ─── Network State Sync ───

func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_online or not NetworkManager.is_host():
		return
	_broadcast_state()


func _broadcast_state() -> void:
	var player_states := {}
	for p in _players:
		player_states[p.player_id] = p.build_net_state()

	var snapshot := {
		"ps": player_states,
		"ball": ball.build_net_state(),
		"rs": red_score,
		"bs": blue_score,
		"timer": time_system.remaining_seconds,
		"ms": state_machine.current_state
	}
	_rpc_receive_state.rpc(snapshot)


@rpc("authority", "unreliable", "call_remote")
func _rpc_receive_state(snapshot: Dictionary) -> void:
	var player_states: Dictionary = snapshot["ps"]
	for pid in player_states:
		var p = _get_player_by_id(pid)
		if p:
			p.apply_net_state(player_states[pid])

	ball.apply_net_state(snapshot["ball"])

	if red_score != snapshot["rs"] or blue_score != snapshot["bs"]:
		red_score = snapshot["rs"]
		blue_score = snapshot["bs"]
		score_changed.emit(red_score, blue_score)

	timer_changed.emit(snapshot["timer"])

	var remote_match_state: int = snapshot["ms"]
	if not state_machine.is_in_state(remote_match_state):
		state_machine.transition_to(remote_match_state)


@rpc("authority", "reliable", "call_remote")
func _rpc_receive_announcement(text: String, r: float, g: float, b: float, duration: float) -> void:
	if not NetworkManager.is_host():
		announcement_requested.emit(text, Color(r, g, b), duration)
