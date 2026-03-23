extends Node
class_name MatchManager

signal score_changed(red_score: int, blue_score: int)
signal timer_changed(remaining_seconds: float)
signal announcement_requested(text: String, color: Color, duration: float)
signal pause_changed(is_paused: bool)
signal match_finished(title: String, detail: String)
signal state_updated(state_name: String)
signal lobby_state_changed(roster: Array, local_slot: String, can_assign: bool, capacity: int)

const SLOT_WAITING := "waiting"
const SLOT_RED := "red"
const SLOT_BLUE := "blue"

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
var _lobby_roster: Dictionary = {}
var _slot_assignments := {
	SLOT_RED: 1,
	SLOT_BLUE: -1
}
var _red_spawn_position := Vector2.ZERO
var _blue_spawn_position := Vector2.ZERO


func _ready() -> void:
	_players = [player_red, player_blue]
	_red_spawn_position = player_red.position
	_blue_spawn_position = player_blue.position

	for player in _players:
		player.assign_ball(ball)
	ball.register_players(_players)

	left_goal.goal_scored.connect(_on_goal_scored)
	right_goal.goal_scored.connect(_on_goal_scored)
	time_system.time_changed.connect(_on_time_changed)
	time_system.time_expired.connect(_on_time_expired)
	state_machine.state_changed.connect(_on_state_changed)

	if NetworkManager.is_online:
		NetworkManager.peer_connected.connect(_on_peer_joined_network)
		NetworkManager.peer_disconnected.connect(_on_peer_left_network)
		if NetworkManager.is_host():
			_initialize_host_lobby()
		else:
			player_red.set_field_active(false)
			player_blue.set_field_active(false)
			_emit_lobby_state_changed()
			_rpc_request_lobby_state.rpc_id(1)
	else:
		player_red.set_controller_peer_id(1)
		player_blue.set_controller_peer_id(2)
		player_red.set_field_active(true)
		player_blue.set_field_active(true)


func start_new_match() -> void:
	_flow_version += 1
	red_score = 0
	blue_score = 0
	score_changed.emit(red_score, blue_score)
	time_system.setup(match_duration_seconds)
	reset_system.reset_world(_players, ball)
	match_finished.emit("", "")
	_start_playing()
	_apply_online_slot_state()


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
	_apply_online_slot_state()


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


func assign_peer_to_red(peer_id: int) -> void:
	_assign_peer_to_slot(peer_id, SLOT_RED)


func assign_peer_to_blue(peer_id: int) -> void:
	_assign_peer_to_slot(peer_id, SLOT_BLUE)


func assign_peer_to_waiting(peer_id: int) -> void:
	_assign_peer_to_slot(peer_id, SLOT_WAITING)


func _start_playing() -> void:
	state_machine.transition_to(GameEnums.MatchState.PLAYING)
	_set_world_active(true)
	_set_goals_enabled(true)
	time_system.start()
	GameEvents.emit_match_started()


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


func _initialize_host_lobby() -> void:
	_lobby_roster = {
		1: _build_lobby_entry(1, "Host", SLOT_RED, true)
	}
	_slot_assignments[SLOT_RED] = 1
	_slot_assignments[SLOT_BLUE] = -1
	_apply_online_slot_state()


func _on_peer_joined_network(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if _lobby_roster.has(peer_id):
		return

	_lobby_roster[peer_id] = _build_lobby_entry(peer_id, "Player %d" % peer_id, SLOT_WAITING, false)
	announcement_requested.emit("Player %d joined the lobby" % peer_id, Color.WHITE, 1.6)
	_apply_online_slot_state()
	_broadcast_lobby_state()


func _on_peer_left_network(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if not _lobby_roster.has(peer_id):
		return

	_remove_peer_from_slots(peer_id)
	_lobby_roster.erase(peer_id)
	announcement_requested.emit("Player %d left the lobby" % peer_id, Color.WHITE, 1.6)
	_apply_online_slot_state()
	_broadcast_lobby_state()


func _assign_peer_to_slot(peer_id: int, slot: String) -> void:
	if not NetworkManager.is_online or not NetworkManager.is_host():
		return
	if not _lobby_roster.has(peer_id):
		return

	_remove_peer_from_slots(peer_id)

	if slot == SLOT_RED or slot == SLOT_BLUE:
		var current_peer := int(_slot_assignments.get(slot, -1))
		if current_peer >= 0 and _lobby_roster.has(current_peer):
			var current_entry: Dictionary = _lobby_roster[current_peer]
			current_entry["slot"] = SLOT_WAITING
			_lobby_roster[current_peer] = current_entry
		_slot_assignments[slot] = peer_id
	else:
		_slot_assignments[SLOT_RED] = -1 if int(_slot_assignments[SLOT_RED]) == peer_id else int(_slot_assignments[SLOT_RED])
		_slot_assignments[SLOT_BLUE] = -1 if int(_slot_assignments[SLOT_BLUE]) == peer_id else int(_slot_assignments[SLOT_BLUE])

	var entry: Dictionary = _lobby_roster[peer_id]
	entry["slot"] = slot
	_lobby_roster[peer_id] = entry

	_apply_online_slot_state()
	_reset_after_assignment_change()
	_broadcast_lobby_state()


func _remove_peer_from_slots(peer_id: int) -> void:
	for slot_name in [SLOT_RED, SLOT_BLUE]:
		if int(_slot_assignments.get(slot_name, -1)) == peer_id:
			_slot_assignments[slot_name] = -1


func _apply_online_slot_state() -> void:
	if not NetworkManager.is_online:
		return
	_apply_slot_to_player(player_red, _red_spawn_position, SLOT_RED)
	_apply_slot_to_player(player_blue, _blue_spawn_position, SLOT_BLUE)
	_sync_world_activity()
	_emit_lobby_state_changed()


func _apply_slot_to_player(player: HexPlayer, spawn_position: Vector2, slot_name: String) -> void:
	player.set_spawn_position(spawn_position)
	var peer_id := int(_slot_assignments.get(slot_name, -1))
	if peer_id < 0 or not _lobby_roster.has(peer_id):
		player.set_controller_peer_id(-1)
		player.set_display_name("%s Slot" % slot_name.capitalize())
		player.set_field_active(false)
		return

	var entry: Dictionary = _lobby_roster[peer_id]
	player.set_controller_peer_id(peer_id)
	player.set_display_name(str(entry.get("name", "Player")))
	player.set_field_active(true)
	player.reset_to_spawn()


func _sync_world_activity() -> void:
	var playing := state_machine.is_in_state(GameEnums.MatchState.PLAYING)
	_set_world_active(playing)
	_set_goals_enabled(playing)
	ball.set_ball_motion_enabled(playing)


func _reset_after_assignment_change() -> void:
	reset_system.reset_world(_players, ball)
	if state_machine.is_in_state(GameEnums.MatchState.PLAYING):
		ball.set_ball_motion_enabled(true)


func _build_lobby_entry(peer_id: int, player_name: String, slot: String, is_host_player: bool) -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": player_name,
		"slot": slot,
		"is_host": is_host_player
	}


func _emit_lobby_state_changed() -> void:
	if not NetworkManager.is_online:
		lobby_state_changed.emit([], "", false, 0)
		return

	var roster: Array = []
	var peer_ids: Array = _lobby_roster.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var entry: Dictionary = _lobby_roster[peer_id]
		roster.append(entry.duplicate(true))

	lobby_state_changed.emit(
		roster,
		_get_local_slot(),
		NetworkManager.is_host(),
		NetworkManager.get_lobby_capacity()
	)


func _get_local_slot() -> String:
	var local_id := NetworkManager.get_local_peer_id()
	for peer_id in _lobby_roster.keys():
		if int(peer_id) != local_id:
			continue
		var entry: Dictionary = _lobby_roster[peer_id]
		return str(entry.get("slot", SLOT_WAITING))
	return SLOT_WAITING


func _build_lobby_snapshot() -> Dictionary:
	var roster: Array = []
	var peer_ids: Array = _lobby_roster.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var entry: Dictionary = _lobby_roster[peer_id]
		roster.append(entry.duplicate(true))

	return {
		"roster": roster,
		"red_peer_id": int(_slot_assignments.get(SLOT_RED, -1)),
		"blue_peer_id": int(_slot_assignments.get(SLOT_BLUE, -1)),
		"capacity": NetworkManager.get_lobby_capacity()
	}


func _apply_lobby_snapshot(snapshot: Dictionary) -> void:
	_lobby_roster.clear()
	var roster: Array = snapshot.get("roster", [])
	for entry_variant in roster:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		_lobby_roster[int(entry.get("peer_id", -1))] = entry.duplicate(true)

	_slot_assignments[SLOT_RED] = int(snapshot.get("red_peer_id", -1))
	_slot_assignments[SLOT_BLUE] = int(snapshot.get("blue_peer_id", -1))
	NetworkManager.lobby_max_players = int(snapshot.get("capacity", NetworkManager.lobby_max_players))
	_apply_online_slot_state()


func _broadcast_lobby_state() -> void:
	if not NetworkManager.is_online or not NetworkManager.is_host():
		return
	var snapshot := _build_lobby_snapshot()
	for peer_id in NetworkManager.get_connected_peer_ids():
		_rpc_receive_lobby_state.rpc_id(peer_id, snapshot)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_lobby_state() -> void:
	if not NetworkManager.is_host():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0:
		return
	_rpc_receive_lobby_state.rpc_id(requester_id, _build_lobby_snapshot())


@rpc("authority", "reliable", "call_remote")
func _rpc_receive_lobby_state(snapshot: Dictionary) -> void:
	_apply_lobby_snapshot(snapshot)


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
	_apply_online_slot_state()


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
	_sync_world_activity()


func _is_flow_valid(flow_version: int) -> bool:
	return flow_version == _flow_version


func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_online:
		return
	if not NetworkManager.is_host():
		return
	var peers := NetworkManager.get_connected_peer_ids()
	if peers.is_empty():
		return
	_broadcast_state(peers)


func _broadcast_state(peers: Array[int]) -> void:
	var snapshot := {
		"p1": player_red.build_net_state(),
		"p2": player_blue.build_net_state(),
		"ball": ball.build_net_state(),
		"rs": red_score,
		"bs": blue_score,
		"timer": time_system.remaining_seconds,
		"ms": state_machine.current_state
	}
	for peer_id in peers:
		_rpc_receive_state.rpc_id(peer_id, snapshot)


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
	if not NetworkManager.is_online or not NetworkManager.is_host():
		return
	for peer_id in NetworkManager.get_connected_peer_ids():
		_rpc_receive_announcement.rpc_id(peer_id, text, color.r, color.g, color.b, duration)
