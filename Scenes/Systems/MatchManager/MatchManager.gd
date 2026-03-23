extends Node
class_name MatchManager

signal score_changed(red_score: int, blue_score: int)
signal timer_changed(remaining_seconds: float)
signal announcement_requested(text: String, color: Color, duration: float)
signal pause_changed(is_paused: bool)
signal match_finished(title: String, detail: String)
signal state_updated(state_name: String)

@export var match_duration_seconds := GameSettings.MATCH_DURATION_SECONDS
@export var goal_pause_duration := GameSettings.GOAL_PAUSE_DURATION

@onready var state_machine: MatchStateMachine = $"../StateMachine"
@onready var reset_system: ResetSystem = $"../ResetSystem"
@onready var time_system: MatchTimeSystem = $"../TimeSystem"
@onready var ball: MatchBall = $"../../World/Entities/Ball"
@onready var player_red: HexPlayer = $"../../World/Entities/PlayerRed"
@onready var player_blue: HexPlayer = $"../../World/Entities/PlayerBlue"
@onready var left_goal: GoalZone = $"../../World/Goals/LeftGoal"
@onready var right_goal: GoalZone = $"../../World/Goals/RightGoal"

var red_score := 0
var blue_score := 0
var _players: Array[HexPlayer] = []
var _flow_version := 0


func _ready() -> void:
	_players = [player_red, player_blue]
	for player in _players:
		player.assign_ball(ball)
	ball.register_players(_players)
	left_goal.goal_scored.connect(_on_goal_scored)
	right_goal.goal_scored.connect(_on_goal_scored)
	time_system.time_changed.connect(_on_time_changed)
	time_system.time_expired.connect(_on_time_expired)
	state_machine.state_changed.connect(_on_state_changed)
	if NetworkManager.is_online and NetworkManager.is_host():
		NetworkManager.peer_connected.connect(_on_client_joined)


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


func toggle_pause() -> void:
	if state_machine.is_in_state(GameEnums.MatchState.PLAYING):
		_pause_match()
	elif state_machine.is_in_state(GameEnums.MatchState.PAUSED):
		_resume_match()


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
	return {
		"state": state_machine.state_name(),
		"timer": Helpers.format_match_time(time_system.remaining_seconds),
		"red_score": red_score,
		"blue_score": blue_score,
		"ball_speed": snapped(ball.velocity.length(), 0.1),
		"ball_velocity": ball.velocity,
		"last_touch_team": Helpers.team_name(ball.last_touch_team_id),
		"last_touch_player_id": ball.last_touch_player_id,
		"p1_velocity": player_red.velocity,
		"p2_velocity": player_blue.velocity
	}


func _start_playing() -> void:
	state_machine.transition_to(GameEnums.MatchState.PLAYING)
	_set_world_active(true)
	_set_goals_enabled(true)
	time_system.start()
	GameEvents.emit_match_started()
	# Online host: P2 başlangıçta kapalı (client gelene kadar)
	if NetworkManager.is_online and NetworkManager.is_host() and NetworkManager.remote_peer_id < 0:
		player_blue.set_input_enabled(false)
		_show_host_ip()


func _show_host_ip() -> void:
	var addresses := IP.get_local_addresses()
	var relevant: Array[String] = []
	for addr in addresses:
		if addr.begins_with("127."):
			continue
		if ":" in addr:
			continue
		relevant.append(addr)
	var ip_text := ", ".join(relevant) if not relevant.is_empty() else "?"
	announcement_requested.emit("IP: %s | Port: %d" % [ip_text, NetworkManager.DEFAULT_PORT], Color.WHITE, 5.0)


func _on_client_joined(_peer_id: int) -> void:
	player_blue.set_input_enabled(true)
	announcement_requested.emit("Player 2 joined!", GameSettings.COLOR_BLUE_TEAM, 2.0)
	_broadcast_announcement("Player 2 joined!", GameSettings.COLOR_BLUE_TEAM, 2.0)
	# Reset pozisyonları, maça yeniden başla
	reset_system.reset_world(_players, ball)
	_flow_version += 1
	red_score = 0
	blue_score = 0
	score_changed.emit(red_score, blue_score)
	time_system.setup(match_duration_seconds)
	_start_playing()


func _pause_match() -> void:
	state_machine.transition_to(GameEnums.MatchState.PAUSED)
	time_system.stop()
	_set_world_active(false)
	_set_goals_enabled(false)
	pause_changed.emit(true)
	GameEvents.emit_pause_toggled(true)


func _resume_match() -> void:
	state_machine.transition_to(GameEnums.MatchState.PLAYING)
	time_system.start()
	_set_world_active(true)
	_set_goals_enabled(true)
	pause_changed.emit(false)
	GameEvents.emit_pause_toggled(false)
	announcement_requested.emit("Resume", Color.WHITE, 0.4)


func _on_goal_scored(scoring_team: int, defending_team: int) -> void:
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
	announcement_requested.emit("%s Scores!" % Helpers.team_name(scoring_team), Helpers.team_color(scoring_team), goal_pause_duration)
	_broadcast_announcement("%s Scores!" % Helpers.team_name(scoring_team), Helpers.team_color(scoring_team), goal_pause_duration)
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
	if not state_machine.is_in_state(GameEnums.MatchState.PAUSED):
		pause_changed.emit(false)


func _is_flow_valid(flow_version: int) -> bool:
	return flow_version == _flow_version


func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_online:
		return
	if not NetworkManager.is_host():
		return
	if NetworkManager.remote_peer_id < 0:
		return
	_broadcast_state()


func _broadcast_state() -> void:
	var snapshot := {
		"p1": player_red.build_net_state(),
		"p2": player_blue.build_net_state(),
		"ball": ball.build_net_state(),
		"rs": red_score,
		"bs": blue_score,
		"timer": time_system.remaining_seconds,
		"ms": state_machine.current_state
	}
	_rpc_receive_state.rpc_id(NetworkManager.remote_peer_id, snapshot)


@rpc("authority", "unreliable", "call_remote")
func _rpc_receive_state(snapshot: Dictionary) -> void:
	player_red.apply_net_state(snapshot["p1"])
	player_blue.apply_net_state(snapshot["p2"])
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
	announcement_requested.emit(text, Color(r, g, b), duration)


func _broadcast_announcement(text: String, color: Color, duration: float) -> void:
	if NetworkManager.is_online and NetworkManager.is_host() and NetworkManager.remote_peer_id >= 0:
		_rpc_receive_announcement.rpc_id(NetworkManager.remote_peer_id, text, color.r, color.g, color.b, duration)
