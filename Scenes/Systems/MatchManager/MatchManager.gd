extends Node
class_name MatchManager

signal score_changed(red_score: int, blue_score: int)
signal timer_changed(remaining_seconds: float)
signal announcement_requested(text: String, color: Color, duration: float)
signal pause_changed(is_paused: bool)
signal hard_pause_changed(is_hard_paused: bool)
signal match_finished(title: String, detail: String)
signal state_updated(state_name: String)
signal room_state_changed(snapshot: Dictionary)
signal player_joined(player_name: String)
signal player_left(player_name: String)
signal chat_message_received(sender_name: String, message: String)

const PLAYER_SCENE := preload("res://Scenes/Entities/Player/Player.tscn")
const ICE_SHARD_SCENE := preload("res://Scenes/Entities/IceShard/IceShard.tscn")
const WORLD_SYNC_INTERVAL := 0.05
const DEFAULT_GOAL_RESET_DELAY := 1.6
const LOCAL_ROOM_NAME := "Local Match"

@onready var entities_root: Node2D = $"../../World/Entities"
@onready var ball: MatchBall = $"../../World/Entities/Ball"
@onready var goals_root: Node2D = $"../../World/Goals"
@onready var state_machine: MatchStateMachine = $"../StateMachine"
@onready var reset_system: ResetSystem = $"../ResetSystem"
@onready var time_system: MatchTimeSystem = $"../TimeSystem"

var red_score := 0
var blue_score := 0
var is_paused := false

var _match_over := false
var _result_title := ""
var _result_detail := ""
var _field_players: Dictionary = {}
var _ice_shards: Dictionary = {}
var _roster: Dictionary = {}
var _banned_names: Dictionary = {}
var _goal_reset_remaining := -1.0
var _sync_accumulator := 0.0
var _state_before_pause := GameEnums.MatchState.PLAYING
var _hard_paused := false
var _last_scoring_team := GameEnums.TeamId.NEUTRAL
var _kickoff_active := false
var _overtime_active := false
var _match_started := true
var _match_duration_seconds := GameSettings.MATCH_DURATION_SECONDS
var _score_limit := GameSettings.DEFAULT_SCORE_LIMIT
var _next_ice_shard_id := 1


func _ready() -> void:
	_clear_legacy_players()
	_connect_core_signals()
	_emit_state_name()


func _process(delta: float) -> void:
	if _is_authority():
		_prune_ice_shards()

	if not _hard_paused and _goal_reset_remaining >= 0.0:
		_goal_reset_remaining -= delta
		if _goal_reset_remaining <= 0.0:
			_goal_reset_remaining = -1.0
			if _is_authority():
				force_full_reset()

	if _kickoff_active and _is_authority():
		if ball.last_touch_team_id != GameEnums.TeamId.NEUTRAL:
			_end_kickoff()

	if _kickoff_active and _is_authority():
		_enforce_kickoff_constraints()

	if NetworkManager.is_online and _is_authority():
		_sync_accumulator += delta
		if _sync_accumulator >= WORLD_SYNC_INTERVAL:
			_sync_accumulator = 0.0
			_broadcast_world_state()


func start_new_match() -> void:
	_clear_ice_shards()
	_match_started = true
	_match_over = false
	_result_title = ""
	_result_detail = ""
	_goal_reset_remaining = -1.0
	_sync_accumulator = 0.0
	red_score = 0
	blue_score = 0
	is_paused = false
	_hard_paused = false
	_last_scoring_team = GameEnums.TeamId.NEUTRAL
	_kickoff_active = false
	_overtime_active = false
	_match_duration_seconds = _resolve_match_duration_seconds()
	_score_limit = _resolve_score_limit()
	_set_state(GameEnums.MatchState.PLAYING)
	match_finished.emit("", "")
	pause_changed.emit(false)
	hard_pause_changed.emit(false)
	score_changed.emit(red_score, blue_score)
	time_system.setup(_match_duration_seconds)
	timer_changed.emit(time_system.remaining_seconds)
	_rebuild_roster_for_current_mode()
	_configure_goals(true)
	_apply_simulation_state()
	if _is_authority():
		force_full_reset()
		time_system.start()
	else:
		time_system.start()
		_submit_local_name_deferred.call_deferred()
	_broadcast_room_state()


func enter_lobby_setup() -> void:
	_clear_ice_shards()
	_match_started = false
	_match_over = false
	_result_title = ""
	_result_detail = ""
	_goal_reset_remaining = -1.0
	_sync_accumulator = 0.0
	red_score = 0
	blue_score = 0
	is_paused = true
	_hard_paused = false
	_last_scoring_team = GameEnums.TeamId.NEUTRAL
	_kickoff_active = false
	_overtime_active = false
	_match_duration_seconds = _resolve_match_duration_seconds()
	_score_limit = _resolve_score_limit()
	_state_before_pause = GameEnums.MatchState.PLAYING
	_set_state(GameEnums.MatchState.PAUSED)
	match_finished.emit("", "")
	pause_changed.emit(true)
	hard_pause_changed.emit(false)
	score_changed.emit(red_score, blue_score)
	time_system.setup(_match_duration_seconds)
	time_system.stop()
	timer_changed.emit(time_system.remaining_seconds)
	_rebuild_roster_for_current_mode()
	ball.reset_ball(Vector2.ZERO)
	_configure_goals(false)
	_apply_simulation_state()
	if not _is_authority():
		_submit_local_name_deferred.call_deferred()
	_broadcast_room_state()
	_broadcast_world_state()


func restart_match() -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_restart_match.rpc_id(1)
		return
	start_new_match()


func set_match_rules(match_duration_seconds: float, score_limit: int) -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_match_rules.rpc_id(1, match_duration_seconds, score_limit)
		return
	_apply_match_rules_authority(match_duration_seconds, score_limit)


func toggle_hard_pause() -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_toggle_hard_pause.rpc_id(1)
		return
	_set_hard_paused(not _hard_paused)


func toggle_pause() -> void:
	is_paused = not is_paused
	if is_paused:
		_state_before_pause = state_machine.current_state
		_set_state(GameEnums.MatchState.PAUSED)
	else:
		if not _match_started:
			_set_state(GameEnums.MatchState.PAUSED)
		elif _match_over:
			_set_state(GameEnums.MatchState.MATCH_ENDED)
		elif _goal_reset_remaining >= 0.0:
			_set_state(GameEnums.MatchState.GOAL_SCORED)
		elif _kickoff_active:
			_set_state(GameEnums.MatchState.KICKOFF)
		else:
			_set_state(_state_before_pause if _state_before_pause != GameEnums.MatchState.PAUSED else GameEnums.MatchState.PLAYING)
	pause_changed.emit(is_paused)


func reset_ball_only() -> void:
	if not _is_authority():
		return
	ball.reset_ball(Vector2.ZERO)
	ball.set_ball_motion_enabled(not _match_over)
	_broadcast_world_state()


func force_full_reset() -> void:
	if not _is_authority():
		return

	_clear_ice_shards()
	var active_players := _get_active_players()
	for player in active_players:
		if player == null:
			continue
		player.set_spawn_position(_get_random_spawn_position(player.team_id, player.player_id))
		player.reset_to_spawn()
		player.set_input_enabled(not _match_over and not _hard_paused)

	reset_system.reset_world(active_players, ball)
	ball.set_ball_motion_enabled(not _match_over and not _hard_paused)
	_configure_goals(not _match_over)
	if _match_over:
		_set_state(GameEnums.MatchState.MATCH_ENDED)
		_kickoff_active = false
	elif _last_scoring_team != GameEnums.TeamId.NEUTRAL:
		_kickoff_active = true
		_set_state(GameEnums.MatchState.KICKOFF)
		_apply_kickoff_constraints()
	else:
		_kickoff_active = false
		_set_state(GameEnums.MatchState.PLAYING)
	_broadcast_world_state()


func add_debug_score(team_id: int) -> void:
	if not _is_authority():
		return
	_register_goal(team_id)


func assign_peer_to_red(peer_id: int) -> void:
	_request_team_assignment(peer_id, GameEnums.TeamId.RED)


func assign_peer_to_blue(peer_id: int) -> void:
	_request_team_assignment(peer_id, GameEnums.TeamId.BLUE)


func assign_peer_to_waiting(peer_id: int) -> void:
	_request_team_assignment(peer_id, GameEnums.TeamId.NEUTRAL)


func randomize_teams() -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_randomize_teams.rpc_id(1)
		return
	_randomize_teams_authority()


func kick_peer(peer_id: int) -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_kick_peer.rpc_id(1, peer_id)
		return
	_kick_peer_authority(peer_id, false)


func ban_peer(peer_id: int) -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_ban_peer.rpc_id(1, peer_id)
		return
	_kick_peer_authority(peer_id, true)


func toggle_peer_admin(peer_id: int) -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_toggle_admin.rpc_id(1, peer_id)
		return
	_toggle_peer_admin_authority(peer_id)


func build_debug_snapshot() -> Dictionary:
	var active_players := _get_active_players()
	var first_velocity := Vector2.ZERO
	var second_velocity := Vector2.ZERO
	if active_players.size() > 0 and active_players[0] != null:
		first_velocity = active_players[0].velocity
	if active_players.size() > 1 and active_players[1] != null:
		second_velocity = active_players[1].velocity

	return {
		"timer": Helpers.format_match_time(time_system.remaining_seconds),
		"red_score": red_score,
		"blue_score": blue_score,
		"ball_speed": snappedf(ball.velocity.length(), 0.01),
		"ball_velocity": ball.velocity,
		"last_touch_team": Helpers.team_name(ball.last_touch_team_id),
		"last_touch_player_id": ball.last_touch_player_id,
		"p1_velocity": first_velocity,
		"p2_velocity": second_velocity
	}


@rpc("any_peer", "reliable", "call_remote")
func _rpc_submit_player_name(player_name: String) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	var clean_name := GameSettings.sanitize_player_name(player_name)
	if _is_banned_name(clean_name):
		_kick_peer_authority(sender_peer_id, true, "Bu odadan banlandin.")
		return

	var entry := _get_roster_entry(sender_peer_id)
	var is_new := entry.is_empty()
	if is_new:
		entry = _make_roster_entry(sender_peer_id, clean_name, GameEnums.TeamId.NEUTRAL, false, false)
	var old_name := str(entry.get("name", ""))
	entry["name"] = clean_name
	_roster[sender_peer_id] = entry
	if is_new or old_name != clean_name:
		player_joined.emit(clean_name)
		for pid in NetworkManager.get_connected_peer_ids():
			_rpc_notify_player_joined.rpc_id(pid, clean_name)
	_update_field_player_from_roster(sender_peer_id, false)
	_broadcast_room_state()
	_broadcast_world_state()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_team_assignment(peer_id: int, team_id: int) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_assign_peer_to_team_authority(peer_id, team_id)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_restart_match() -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	start_new_match()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_match_rules(match_duration_seconds: float, score_limit: int) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_apply_match_rules_authority(match_duration_seconds, score_limit)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_toggle_hard_pause() -> void:
	if not _is_authority():
		return
	_set_hard_paused(not _hard_paused)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_kick_peer(peer_id: int) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_kick_peer_authority(peer_id, false)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_ban_peer(peer_id: int) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_kick_peer_authority(peer_id, true)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_toggle_admin(peer_id: int) -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_toggle_peer_admin_authority(peer_id)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_randomize_teams() -> void:
	if not _is_authority():
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	if not _can_manage_roster(sender_peer_id):
		return
	_randomize_teams_authority()


@rpc("authority", "reliable", "call_remote")
func _rpc_receive_room_state(snapshot: Dictionary) -> void:
	if _is_authority():
		return
	_apply_room_state_snapshot(snapshot)


@rpc("authority", "unreliable", "call_remote")
func _rpc_receive_world_state(snapshot: Dictionary) -> void:
	if _is_authority():
		return
	_apply_world_state_snapshot(snapshot)


@rpc("authority", "reliable", "call_remote")
func _rpc_force_leave(reason: String) -> void:
	announcement_requested.emit(reason, Color(1.0, 0.72, 0.72, 1.0), 1.25)


@rpc("authority", "reliable", "call_remote")
func _rpc_notify_player_joined(player_name: String) -> void:
	player_joined.emit(player_name)


@rpc("authority", "reliable", "call_remote")
func _rpc_notify_player_left(player_name: String) -> void:
	player_left.emit(player_name)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_send_chat_message(message: String) -> void:
	if _is_authority():
		var sender_peer_id := multiplayer.get_remote_sender_id()
		var entry := _get_roster_entry(sender_peer_id)
		var sender_name := str(entry.get("name", "Player"))
		var clean_message := message.strip_edges().substr(0, 200)
		if clean_message.is_empty():
			return
		chat_message_received.emit(sender_name, clean_message)
		# Broadcast to all clients
		for peer_id in NetworkManager.get_connected_peer_ids():
			_rpc_receive_chat_message.rpc_id(peer_id, sender_name, clean_message)
	else:
		_rpc_send_chat_message.rpc_id(1, message)


@rpc("authority", "reliable", "call_remote")
func _rpc_receive_chat_message(sender_name: String, message: String) -> void:
	chat_message_received.emit(sender_name, message)


func send_chat(message: String) -> void:
	var clean_message := message.strip_edges().substr(0, 200)
	if clean_message.is_empty():
		return
	if not NetworkManager.is_online:
		chat_message_received.emit(GameSettings.player_name, clean_message)
		return
	if _is_authority():
		chat_message_received.emit(GameSettings.player_name, clean_message)
		for peer_id in NetworkManager.get_connected_peer_ids():
			_rpc_receive_chat_message.rpc_id(peer_id, GameSettings.player_name, clean_message)
	else:
		_rpc_send_chat_message.rpc_id(1, clean_message)


func _connect_core_signals() -> void:
	if not state_machine.state_changed.is_connected(_on_state_changed):
		state_machine.state_changed.connect(_on_state_changed)
	if not time_system.time_changed.is_connected(_on_time_changed):
		time_system.time_changed.connect(_on_time_changed)
	if not time_system.time_expired.is_connected(_on_time_expired):
		time_system.time_expired.connect(_on_time_expired)
	if not NetworkManager.peer_connected.is_connected(_on_network_peer_connected):
		NetworkManager.peer_connected.connect(_on_network_peer_connected)
	if not NetworkManager.peer_disconnected.is_connected(_on_network_peer_disconnected):
		NetworkManager.peer_disconnected.connect(_on_network_peer_disconnected)
	if not NetworkManager.server_disconnected.is_connected(_on_network_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_network_server_disconnected)

	for goal_node in goals_root.get_children():
		var goal := goal_node as GoalZone
		if goal != null and not goal.goal_scored.is_connected(_on_goal_scored):
			goal.goal_scored.connect(_on_goal_scored)


func _clear_legacy_players() -> void:
	_clear_ice_shards()
	for child in entities_root.get_children():
		if child is HexPlayer:
			child.queue_free()
	_field_players.clear()
	_refresh_ball_player_tracking()


func _rebuild_roster_for_current_mode() -> void:
	_remove_all_field_players()
	var previous_roster := _roster.duplicate(true)
	_roster.clear()

	if NetworkManager.is_online:
		if _is_authority():
			var local_peer_id := NetworkManager.get_local_peer_id()
			var prev_local_entry: Dictionary = previous_roster.get(local_peer_id, {})
			var local_team_id := int(prev_local_entry.get("team_id", GameEnums.TeamId.NEUTRAL))
			var local_name := str(prev_local_entry.get("name", GameSettings.player_name))
			var local_admin := bool(prev_local_entry.get("is_admin", true))
			_roster[local_peer_id] = _make_roster_entry(
				local_peer_id,
				local_name,
				local_team_id,
				local_admin,
				true
			)
			_update_field_player_from_roster(local_peer_id, true)

			for peer_id in NetworkManager.get_connected_peer_ids():
				if peer_id == local_peer_id:
					continue
				var prev_entry: Dictionary = previous_roster.get(peer_id, {})
				var prev_name: String = str(prev_entry.get("name", "Player %d" % peer_id))
				var prev_team: int = int(prev_entry.get("team_id", GameEnums.TeamId.NEUTRAL))
				var prev_admin: bool = bool(prev_entry.get("is_admin", false))
				_roster[peer_id] = _make_roster_entry(peer_id, prev_name, prev_team, prev_admin, false)
				_update_field_player_from_roster(peer_id, true)
		else:
			ball.reset_ball(Vector2.ZERO)
			ball.set_ball_motion_enabled(false)
	else:
		_roster[1] = _make_roster_entry(1, GameSettings.player_name, GameEnums.TeamId.RED, true, true)
		_roster[2] = _make_roster_entry(2, "Blue Player", GameEnums.TeamId.BLUE, false, false)
		_update_field_player_from_roster(1, true)
		_update_field_player_from_roster(2, true)

	_refresh_ball_player_tracking()


func _make_roster_entry(peer_id: int, player_name: String, team_id: int, is_admin: bool, is_host: bool) -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": GameSettings.sanitize_player_name(player_name),
		"team_id": team_id,
		"is_admin": is_admin,
		"is_host": is_host
	}


func _request_team_assignment(peer_id: int, team_id: int) -> void:
	if NetworkManager.is_online and not _is_authority():
		_rpc_request_team_assignment.rpc_id(1, peer_id, team_id)
		return
	_assign_peer_to_team_authority(peer_id, team_id)


func _assign_peer_to_team_authority(peer_id: int, team_id: int) -> void:
	if not _roster.has(peer_id):
		return
	var clamped_team := team_id
	if clamped_team != GameEnums.TeamId.RED and clamped_team != GameEnums.TeamId.BLUE:
		clamped_team = GameEnums.TeamId.NEUTRAL

	var entry := _get_roster_entry(peer_id)
	var previous_team := int(entry.get("team_id", GameEnums.TeamId.NEUTRAL))
	if previous_team == clamped_team and (clamped_team == GameEnums.TeamId.NEUTRAL or _field_players.has(peer_id)):
		return

	entry["team_id"] = clamped_team
	_roster[peer_id] = entry
	_update_field_player_from_roster(peer_id, previous_team != clamped_team)
	_refresh_ball_player_tracking()
	_broadcast_room_state()
	_broadcast_world_state()


func _randomize_teams_authority() -> void:
	# Collect all peer ids (spectators + existing team players)
	var all_peer_ids: Array = []
	for peer_id in _roster.keys():
		all_peer_ids.append(int(peer_id))
	all_peer_ids.shuffle()

	# Distribute evenly between red and blue
	var half := all_peer_ids.size() / 2
	for i in range(all_peer_ids.size()):
		var target_team: int
		if i < half:
			target_team = GameEnums.TeamId.RED
		else:
			target_team = GameEnums.TeamId.BLUE
		_assign_peer_to_team_authority(all_peer_ids[i], target_team)


func _toggle_peer_admin_authority(peer_id: int) -> void:
	if not _roster.has(peer_id):
		return
	var entry := _get_roster_entry(peer_id)
	if bool(entry.get("is_host", false)):
		return
	entry["is_admin"] = not bool(entry.get("is_admin", false))
	_roster[peer_id] = entry
	_broadcast_room_state()


func _kick_peer_authority(peer_id: int, ban_peer_flag: bool, leave_reason: String = "") -> void:
	if not _roster.has(peer_id):
		return
	var entry := _get_roster_entry(peer_id)
	if bool(entry.get("is_host", false)):
		return

	var reason := leave_reason
	if reason.is_empty():
		reason = "Odadan atildin."
		if ban_peer_flag:
			reason = "Odadan banlandin."

	if ban_peer_flag:
		_banned_names[_normalize_name(str(entry.get("name", "")))] = true

	_remove_field_player(peer_id)
	_roster.erase(peer_id)
	_refresh_ball_player_tracking()
	_broadcast_room_state()
	_broadcast_world_state()

	if NetworkManager.is_online:
		_rpc_force_leave.rpc_id(peer_id, reason)


func _update_field_player_from_roster(peer_id: int, reposition: bool) -> void:
	if not _roster.has(peer_id):
		_remove_field_player(peer_id)
		return

	var entry := _get_roster_entry(peer_id)
	var team_id := int(entry.get("team_id", GameEnums.TeamId.NEUTRAL))
	if team_id == GameEnums.TeamId.NEUTRAL:
		_remove_field_player(peer_id)
		return

	var player := _field_players.get(peer_id) as HexPlayer
	var created := false
	if player == null:
		player = PLAYER_SCENE.instantiate() as HexPlayer
		player.name = "Player_%d" % peer_id
		entities_root.add_child(player)
		_field_players[peer_id] = player
		player.assign_ball(ball)
		player.set_match_manager(self)
		created = true

	player.player_id = peer_id
	var previous_team := player.team_id
	player.team_id = team_id as GameEnums.TeamId
	player.set_match_manager(self)
	player.set_controller_peer_id(peer_id)
	player.set_display_name(str(entry.get("name", "Player")))
	player.set_field_active(true)
	player.visible = true
	player.facing_direction = Vector2.RIGHT if team_id == GameEnums.TeamId.RED else Vector2.LEFT
	if created or reposition:
		player.set_spawn_position(_get_random_spawn_position(team_id, peer_id))
		player.reset_to_spawn()
	player.set_input_enabled(_match_started and not _match_over and not _hard_paused)
	if created or previous_team != team_id:
		player.queue_redraw()


func _remove_field_player(peer_id: int) -> void:
	var player := _field_players.get(peer_id) as HexPlayer
	if player == null:
		return
	if player.is_inside_tree():
		player.get_parent().remove_child(player)
	player.queue_free()
	_field_players.erase(peer_id)
	_refresh_ball_player_tracking()


func _remove_all_field_players() -> void:
	for peer_id in _field_players.keys():
		var player := _field_players[peer_id] as HexPlayer
		if player != null:
			if player.is_inside_tree():
				player.get_parent().remove_child(player)
			player.queue_free()
	_field_players.clear()
	_refresh_ball_player_tracking()


func _refresh_ball_player_tracking() -> void:
	var active_players := _get_active_players()
	ball.register_players(active_players)
	for shard in _ice_shards.values():
		var ice_shard := shard as IceShard
		if ice_shard != null:
			ice_shard.register_players(active_players)


func spawn_ice_shard(owner: HexPlayer, direction: Vector2, speed: float, lifetime: float, effect_duration: float, projectile_radius: float) -> void:
	if not _is_authority() or owner == null:
		return
	var ice_shard := ICE_SHARD_SCENE.instantiate() as IceShard
	var shard_id := _next_ice_shard_id
	_next_ice_shard_id += 1
	ice_shard.name = "IceShard_%d" % shard_id
	entities_root.add_child(ice_shard)
	ice_shard.launch(owner, direction, speed, lifetime, effect_duration, projectile_radius, shard_id)
	ice_shard.register_players(_get_active_players())
	_ice_shards[shard_id] = ice_shard


func _clear_ice_shards() -> void:
	for shard_id in _ice_shards.keys():
		var shard := _ice_shards[shard_id] as IceShard
		if shard != null:
			shard.queue_free()
	_ice_shards.clear()


func _prune_ice_shards() -> void:
	var expired_ids: Array[int] = []
	for shard_id in _ice_shards.keys():
		var ice_shard := _ice_shards[shard_id] as IceShard
		if ice_shard == null or ice_shard.is_expired():
			expired_ids.append(int(shard_id))
	for shard_id in expired_ids:
		var shard := _ice_shards.get(shard_id) as IceShard
		if shard != null:
			shard.queue_free()
		_ice_shards.erase(shard_id)


func _get_active_players() -> Array[HexPlayer]:
	var players: Array[HexPlayer] = []
	var peer_ids := _field_players.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var player := _field_players[peer_id] as HexPlayer
		if player != null and player.is_inside_tree() and player.is_field_active():
			players.append(player)
	return players


func _get_roster_entry(peer_id: int) -> Dictionary:
	if _roster.has(peer_id):
		var entry: Dictionary = _roster[peer_id]
		return entry.duplicate(true)
	return {}


func _get_random_spawn_position(team_id: int, peer_id: int) -> Vector2:
	var half_field := GameSettings.FIELD_SIZE * 0.5
	var margin_x := 120.0
	var margin_y := 80.0
	var center_gap := 85.0
	var min_x := -half_field.x + margin_x
	var max_x := -center_gap
	if team_id == GameEnums.TeamId.BLUE:
		min_x = center_gap
		max_x = half_field.x - margin_x

	var best_position := Vector2(0.0, 0.0)
	for _i in range(14):
		var candidate := Vector2(
			randf_range(min_x, max_x),
			randf_range(-half_field.y + margin_y, half_field.y - margin_y)
		)
		if _is_spawn_position_free(candidate, peer_id):
			return candidate
		best_position = candidate
	return best_position


func _is_spawn_position_free(candidate: Vector2, ignored_peer_id: int) -> bool:
	for peer_id in _field_players.keys():
		if peer_id == ignored_peer_id:
			continue
		var player := _field_players[peer_id] as HexPlayer
		if player == null or not player.is_field_active():
			continue
		if player.position.distance_to(candidate) < GameSettings.PLAYER_RADIUS * 2.4:
			return false
	return candidate.distance_to(ball.position) > GameSettings.PLAYER_RADIUS * 2.2


func _configure_goals(enabled: bool) -> void:
	for goal_node in goals_root.get_children():
		var goal := goal_node as GoalZone
		if goal != null:
			goal.set_scoring_enabled(enabled)


func _configure_match_activity(active: bool) -> void:
	for player in _get_active_players():
		if player != null:
			player.set_input_enabled(active)
	ball.set_ball_motion_enabled(active)
	for shard in _ice_shards.values():
		var ice_shard := shard as IceShard
		if ice_shard != null:
			ice_shard.set_simulation_enabled(active)


func _apply_simulation_state() -> void:
	var simulation_active := _match_started and not _match_over and not _hard_paused
	_configure_match_activity(simulation_active)
	if _is_authority():
		if simulation_active and not _overtime_active:
			time_system.start()
		else:
			time_system.stop()


func _set_hard_paused(value: bool) -> void:
	if _hard_paused == value:
		return
	_hard_paused = value
	_apply_simulation_state()
	_configure_goals(not _match_over and not _hard_paused and _goal_reset_remaining < 0.0)
	hard_pause_changed.emit(_hard_paused)
	if _is_authority():
		_broadcast_world_state()


func _apply_kickoff_constraints() -> void:
	for player in _get_active_players():
		if player == null:
			continue
		player.set_kickoff_half_locked(true)
		player.set_kickoff_restricted(player.team_id == _last_scoring_team)
	_enforce_kickoff_constraints()


func _enforce_kickoff_constraints() -> void:
	if not _kickoff_active or _last_scoring_team == GameEnums.TeamId.NEUTRAL:
		return
	var center_radius := 120.0
	var margin := 2.0
	for player in _get_active_players():
		if player == null:
			continue

		var in_circle := player.position.length() < center_radius

		# Scoring team cannot enter center circle
		if player.team_id == _last_scoring_team and in_circle:
			var dist := player.position.length()
			if dist < 0.001:
				var push_dir := Vector2.LEFT if player.team_id == GameEnums.TeamId.RED else Vector2.RIGHT
				player.position = push_dir * center_radius
			else:
				player.position = player.position.normalized() * center_radius
			player.velocity = Vector2.ZERO
			in_circle = false

		# All players stay on own half, but non-scoring team can cross within center circle
		if not in_circle:
			if player.team_id == GameEnums.TeamId.RED and player.position.x > -margin:
				player.position.x = -margin
				if player.velocity.x > 0.0:
					player.velocity.x = 0.0
			elif player.team_id == GameEnums.TeamId.BLUE and player.position.x < margin:
				player.position.x = margin
				if player.velocity.x < 0.0:
					player.velocity.x = 0.0


func _end_kickoff() -> void:
	_kickoff_active = false
	for player in _get_active_players():
		if player != null:
			player.set_kickoff_restricted(false)
			player.set_kickoff_half_locked(false)
	_set_state(GameEnums.MatchState.PLAYING)
	_broadcast_world_state()


func _register_goal(scoring_team: int) -> void:
	if _match_over:
		return
	_last_scoring_team = scoring_team as GameEnums.TeamId
	if scoring_team == GameEnums.TeamId.RED:
		red_score += 1
	else:
		blue_score += 1

	score_changed.emit(red_score, blue_score)
	GameEvents.emit_goal_scored(scoring_team, ball.last_touch_player_id)
	if _overtime_active:
		_overtime_active = false
		_finish_match("Altin gol", "%s altin gol ile kazandi" % Helpers.team_name(scoring_team))
		return
	if _has_reached_score_limit():
		_finish_match("Gol limiti", "%s %d gole ulasti" % [Helpers.team_name(scoring_team), _score_limit])
		return
	_set_state(GameEnums.MatchState.GOAL_SCORED)
	_configure_goals(false)
	_goal_reset_remaining = DEFAULT_GOAL_RESET_DELAY
	var announcement_text := "%s scored" % Helpers.team_name(scoring_team)
	announcement_requested.emit(announcement_text, Helpers.team_color(scoring_team), 1.0)
	_broadcast_world_state()
	_broadcast_room_state()


func _broadcast_room_state() -> void:
	if _is_authority():
		var local_snapshot := _build_room_state_snapshot(NetworkManager.get_local_peer_id() if NetworkManager.is_online else 1)
		_apply_room_state_snapshot(local_snapshot)
		if NetworkManager.is_online:
			for peer_id in NetworkManager.get_connected_peer_ids():
				_rpc_receive_room_state.rpc_id(peer_id, _build_room_state_snapshot(peer_id))
	else:
		room_state_changed.emit(_build_room_state_snapshot(NetworkManager.get_local_peer_id()))


func _build_room_state_snapshot(viewer_peer_id: int) -> Dictionary:
	var all_entries: Array = []
	var red_entries: Array = []
	var spectator_entries: Array = []
	var blue_entries: Array = []

	var peer_ids := _roster.keys()
	peer_ids.sort_custom(Callable(self, "_sort_roster_peer_ids"))

	for peer_id in peer_ids:
		var entry := _serialize_room_entry(_get_roster_entry(int(peer_id)))
		all_entries.append(entry)
		var team_id := int(entry.get("team_id", GameEnums.TeamId.NEUTRAL))
		if team_id == GameEnums.TeamId.RED:
			red_entries.append(entry)
		elif team_id == GameEnums.TeamId.BLUE:
			blue_entries.append(entry)
		else:
			spectator_entries.append(entry)

	return {
		"room_name": _get_room_name(),
		"entries": all_entries,
		"red": red_entries,
		"spectators": spectator_entries,
		"blue": blue_entries,
		"can_manage": _can_manage_roster(viewer_peer_id),
		"match_started": _match_started,
		"match_over": _match_over,
		"overtime": _overtime_active,
		"match_duration_seconds": _match_duration_seconds,
		"score_limit": _score_limit,
		"result_title": _result_title,
		"result_detail": _result_detail,
		"red_score": red_score,
		"blue_score": blue_score,
		"local_peer_id": viewer_peer_id
	}


func _serialize_room_entry(entry: Dictionary) -> Dictionary:
	return {
		"peer_id": int(entry.get("peer_id", -1)),
		"name": str(entry.get("name", "Player")),
		"team_id": int(entry.get("team_id", GameEnums.TeamId.NEUTRAL)),
		"is_host": bool(entry.get("is_host", false)),
		"is_admin": bool(entry.get("is_admin", false))
	}


func _apply_room_state_snapshot(snapshot: Dictionary) -> void:
	var previous_match_over := _match_over
	var previous_match_started := _match_started
	_match_started = bool(snapshot.get("match_started", _match_started))
	_match_over = bool(snapshot.get("match_over", _match_over))
	_overtime_active = bool(snapshot.get("overtime", _overtime_active))
	_match_duration_seconds = float(snapshot.get("match_duration_seconds", _match_duration_seconds))
	_score_limit = int(snapshot.get("score_limit", _score_limit))
	var entries: Array = []
	var raw_entries: Variant = snapshot.get("entries", [])
	if typeof(raw_entries) == TYPE_ARRAY:
		entries = raw_entries
	if typeof(entries) == TYPE_ARRAY:
		_roster.clear()
		for entry_data in entries:
			if typeof(entry_data) != TYPE_DICTIONARY:
				continue
			var peer_id := int(entry_data.get("peer_id", -1))
			if peer_id < 0:
				continue
			_roster[peer_id] = entry_data.duplicate(true)

	for peer_id in _field_players.keys():
		var entry := _get_roster_entry(int(peer_id))
		if entry.is_empty() or int(entry.get("team_id", GameEnums.TeamId.NEUTRAL)) == GameEnums.TeamId.NEUTRAL:
			_remove_field_player(int(peer_id))
	_refresh_ball_player_tracking()
	if _match_over and not previous_match_over and not is_paused:
		is_paused = true
		pause_changed.emit(true)
	elif previous_match_over and not _match_over and is_paused:
		is_paused = false
		pause_changed.emit(false)
	elif not previous_match_started and _match_started and is_paused and not _match_over:
		is_paused = false
		pause_changed.emit(false)
	elif previous_match_started and not _match_started and is_paused:
		_set_state(GameEnums.MatchState.PAUSED)
	room_state_changed.emit(snapshot)


func _broadcast_world_state() -> void:
	if not _is_authority():
		return

	var players: Array = []
	var peer_ids := _field_players.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var player := _field_players[peer_id] as HexPlayer
		if player == null or not player.is_field_active():
			continue
		players.append({
			"peer_id": int(peer_id),
			"team_id": player.team_id,
			"name": player.display_name,
			"state": player.build_net_state()
		})

	var snapshot := {
		"players": players,
		"shards": _build_ice_shard_states(),
		"ball": ball.build_net_state(),
		"rs": red_score,
		"bs": blue_score,
		"timer": time_system.remaining_seconds,
		"ms": state_machine.current_state,
		"started": _match_started,
		"hp": _hard_paused,
		"match_over": _match_over,
		"ot": _overtime_active,
		"md": _match_duration_seconds,
		"sl": _score_limit,
		"goal_reset": _goal_reset_remaining,
		"kickoff": _kickoff_active,
		"kick_team": _last_scoring_team
	}

	if NetworkManager.is_online:
		_rpc_receive_world_state.rpc(snapshot)


func _apply_world_state_snapshot(snapshot: Dictionary) -> void:
	var prev_red := red_score
	var prev_blue := blue_score
	var prev_match_over := _match_over
	var prev_overtime := _overtime_active
	var prev_match_started := _match_started
	red_score = int(snapshot.get("rs", red_score))
	blue_score = int(snapshot.get("bs", blue_score))
	_match_started = bool(snapshot.get("started", _match_started))
	_match_over = bool(snapshot.get("match_over", false))
	_overtime_active = bool(snapshot.get("ot", false))
	_match_duration_seconds = float(snapshot.get("md", _match_duration_seconds))
	_score_limit = int(snapshot.get("sl", _score_limit))
	_goal_reset_remaining = float(snapshot.get("goal_reset", -1.0))
	_kickoff_active = bool(snapshot.get("kickoff", false))
	_last_scoring_team = int(snapshot.get("kick_team", GameEnums.TeamId.NEUTRAL)) as GameEnums.TeamId
	var hard_paused := bool(snapshot.get("hp", false))
	if hard_paused != _hard_paused:
		_hard_paused = hard_paused
		hard_pause_changed.emit(_hard_paused)
	score_changed.emit(red_score, blue_score)
	var server_timer := float(snapshot.get("timer", time_system.remaining_seconds))
	time_system.remaining_seconds = server_timer
	time_system.running = _match_started and not _match_over and not _hard_paused and not _overtime_active
	_set_state(int(snapshot.get("ms", state_machine.current_state)) as GameEnums.MatchState)
	_configure_match_activity(_match_started and not _match_over and not _hard_paused)

	# Client-side goal announcement
	if red_score > prev_red:
		announcement_requested.emit("%s scored" % Helpers.team_name(GameEnums.TeamId.RED), Helpers.team_color(GameEnums.TeamId.RED), 1.0)
	elif blue_score > prev_blue:
		announcement_requested.emit("%s scored" % Helpers.team_name(GameEnums.TeamId.BLUE), Helpers.team_color(GameEnums.TeamId.BLUE), 1.0)
	if _overtime_active and not prev_overtime:
		announcement_requested.emit("Overtime - ilk gol kazanir", Color(1.0, 0.95, 0.72, 1.0), 1.2)
	if prev_match_started and not _match_started:
		_set_state(GameEnums.MatchState.PAUSED)
	elif not prev_match_started and _match_started and is_paused and not _match_over:
		is_paused = false
		pause_changed.emit(false)

	# Client-side match end handling
	if _match_over and not prev_match_over:
		_result_title = Helpers.winner_text(red_score, blue_score)
		_result_detail = "Red %d - %d Blue" % [red_score, blue_score]
		match_finished.emit(_result_title, _result_detail)
		announcement_requested.emit("Sure bitti", Color(1.0, 0.95, 0.72, 1.0), 1.0)
		if not is_paused:
			is_paused = true
			pause_changed.emit(true)

	var players: Array = []
	var raw_players: Variant = snapshot.get("players", [])
	if typeof(raw_players) == TYPE_ARRAY:
		players = raw_players
	_reconcile_remote_players(players)

	var shards: Array = []
	var raw_shards: Variant = snapshot.get("shards", [])
	if typeof(raw_shards) == TYPE_ARRAY:
		shards = raw_shards
	_reconcile_remote_ice_shards(shards)

	var ball_state: Dictionary = {}
	var raw_ball_state: Variant = snapshot.get("ball", {})
	if typeof(raw_ball_state) == TYPE_DICTIONARY:
		ball_state = raw_ball_state
	if typeof(ball_state) == TYPE_DICTIONARY:
		ball.apply_net_state(ball_state)

	_configure_goals(not _match_over and not _hard_paused and _goal_reset_remaining < 0.0)

	# Apply kickoff restrictions on client
	if _kickoff_active and _last_scoring_team != GameEnums.TeamId.NEUTRAL:
		for player in _get_active_players():
			if player != null:
				player.set_kickoff_half_locked(true)
				player.set_kickoff_restricted(player.team_id == _last_scoring_team)
	else:
		for player in _get_active_players():
			if player != null:
				player.set_kickoff_half_locked(false)
				player.set_kickoff_restricted(false)


func _reconcile_remote_players(players: Variant) -> void:
	if typeof(players) != TYPE_ARRAY:
		return

	var active_peer_ids: Array = []
	for player_data in players:
		if typeof(player_data) != TYPE_DICTIONARY:
			continue
		var peer_id := int(player_data.get("peer_id", -1))
		if peer_id < 0:
			continue
		active_peer_ids.append(peer_id)
		var team_id := int(player_data.get("team_id", GameEnums.TeamId.NEUTRAL))
		var entry := _get_roster_entry(peer_id)
		if entry.is_empty():
			entry = _make_roster_entry(peer_id, str(player_data.get("name", "Player")), team_id, false, false)
			_roster[peer_id] = entry
		else:
			entry["team_id"] = team_id
			entry["name"] = str(player_data.get("name", entry.get("name", "Player")))
			_roster[peer_id] = entry

		_update_field_player_from_roster(peer_id, false)
		var player := _field_players.get(peer_id) as HexPlayer
		if player == null:
			continue
		var net_state: Dictionary = {}
		var raw_state: Variant = player_data.get("state", {})
		if typeof(raw_state) == TYPE_DICTIONARY:
			net_state = raw_state
		if typeof(net_state) == TYPE_DICTIONARY:
			player.team_id = team_id as GameEnums.TeamId
			player.apply_net_state(net_state)

	for peer_id in _field_players.keys():
		if not active_peer_ids.has(int(peer_id)):
			_remove_field_player(int(peer_id))

	_refresh_ball_player_tracking()


func _can_manage_roster(peer_id: int) -> bool:
	if not NetworkManager.is_online:
		return true
	var entry := _get_roster_entry(peer_id)
	return bool(entry.get("is_host", false)) or bool(entry.get("is_admin", false))


func _is_authority() -> bool:
	return not NetworkManager.is_online or NetworkManager.is_host()


func _is_banned_name(player_name: String) -> bool:
	return _banned_names.has(_normalize_name(player_name))


func _normalize_name(player_name: String) -> String:
	return player_name.strip_edges().to_lower()


func _sort_roster_peer_ids(a: Variant, b: Variant) -> bool:
	var left := _get_roster_entry(int(a))
	var right := _get_roster_entry(int(b))
	if bool(left.get("is_host", false)) != bool(right.get("is_host", false)):
		return bool(left.get("is_host", false))
	return str(left.get("name", "")).nocasecmp_to(str(right.get("name", ""))) < 0


func _get_room_name() -> String:
	if NetworkManager.active_lobby_name.is_empty():
		return LOCAL_ROOM_NAME
	return NetworkManager.active_lobby_name


func _resolve_match_duration_seconds() -> float:
	return clampf(NetworkManager.active_match_duration_seconds, GameSettings.MIN_MATCH_DURATION_SECONDS, GameSettings.MAX_MATCH_DURATION_SECONDS)


func _resolve_score_limit() -> int:
	return maxi(GameSettings.MIN_SCORE_LIMIT, mini(GameSettings.MAX_SCORE_LIMIT, NetworkManager.active_score_limit))


func _apply_match_rules_authority(match_duration_seconds: float, score_limit: int) -> void:
	_match_duration_seconds = clampf(match_duration_seconds, GameSettings.MIN_MATCH_DURATION_SECONDS, GameSettings.MAX_MATCH_DURATION_SECONDS)
	_score_limit = maxi(GameSettings.MIN_SCORE_LIMIT, mini(GameSettings.MAX_SCORE_LIMIT, score_limit))
	NetworkManager.active_match_duration_seconds = _match_duration_seconds
	NetworkManager.active_score_limit = _score_limit
	if not _match_started:
		time_system.setup(_match_duration_seconds)
		time_system.stop()
		timer_changed.emit(time_system.remaining_seconds)
	if NetworkManager.is_online and _is_authority():
		NetworkManager.update_lobby_settings(_match_duration_seconds, _score_limit)
	_broadcast_room_state()
	_broadcast_world_state()


func _submit_local_name_deferred() -> void:
	if not NetworkManager.is_online or NetworkManager.is_host():
		return
	_rpc_submit_player_name.rpc_id(1, GameSettings.player_name)


func _set_state(new_state: int) -> void:
	if state_machine.current_state == new_state:
		return
	state_machine.transition_to(new_state as GameEnums.MatchState)


func _emit_state_name() -> void:
	state_updated.emit(state_machine.state_name())


func _on_state_changed(_previous_state: int, _new_state: int) -> void:
	_emit_state_name()


func _on_time_changed(remaining_seconds: float) -> void:
	timer_changed.emit(remaining_seconds)


func _on_time_expired() -> void:
	if not _is_authority():
		return
	if red_score == blue_score:
		_overtime_active = true
		_goal_reset_remaining = -1.0
		_last_scoring_team = GameEnums.TeamId.NEUTRAL
		_set_state(GameEnums.MatchState.PLAYING)
		time_system.stop()
		announcement_requested.emit("Overtime - ilk gol kazanir", Color(1.0, 0.95, 0.72, 1.0), 1.2)
		_broadcast_room_state()
		_broadcast_world_state()
		return
	_finish_match("Sure bitti", "Sure sona erdi")


func _on_goal_scored(scoring_team: int, _defending_team: int) -> void:
	if not _is_authority():
		return
	_register_goal(scoring_team)


func _on_network_peer_connected(peer_id: int) -> void:
	if not _is_authority():
		return
	if _roster.has(peer_id):
		return
	_roster[peer_id] = _make_roster_entry(peer_id, "Player %d" % peer_id, GameEnums.TeamId.NEUTRAL, false, false)
	player_joined.emit("Player %d" % peer_id)
	_broadcast_room_state()


func _on_network_peer_disconnected(peer_id: int) -> void:
	var leaving_name := "Player"
	if _roster.has(peer_id):
		leaving_name = str(_roster[peer_id].get("name", "Player"))
	player_left.emit(leaving_name)
	if _is_authority():
		for pid in NetworkManager.get_connected_peer_ids():
			if pid != peer_id:
				_rpc_notify_player_left.rpc_id(pid, leaving_name)
	_remove_field_player(peer_id)
	if _roster.has(peer_id):
		_roster.erase(peer_id)
	_refresh_ball_player_tracking()
	if _is_authority():
		_broadcast_room_state()
		_broadcast_world_state()


func _on_network_server_disconnected() -> void:
	_clear_ice_shards()
	_remove_all_field_players()
	_roster.clear()
	_refresh_ball_player_tracking()


func _build_ice_shard_states() -> Array:
	var shard_states: Array = []
	var shard_ids := _ice_shards.keys()
	shard_ids.sort()
	for shard_id in shard_ids:
		var ice_shard := _ice_shards[shard_id] as IceShard
		if ice_shard == null or ice_shard.is_expired():
			continue
		shard_states.append(ice_shard.build_net_state())
	return shard_states


func _reconcile_remote_ice_shards(shards: Variant) -> void:
	if typeof(shards) != TYPE_ARRAY:
		return

	var active_ids: Array[int] = []
	for shard_data in shards:
		if typeof(shard_data) != TYPE_DICTIONARY:
			continue
		var shard_id := int(shard_data.get("id", -1))
		if shard_id < 0:
			continue
		active_ids.append(shard_id)
		var ice_shard := _ice_shards.get(shard_id) as IceShard
		if ice_shard == null:
			ice_shard = ICE_SHARD_SCENE.instantiate() as IceShard
			ice_shard.name = "IceShard_%d" % shard_id
			entities_root.add_child(ice_shard)
			_ice_shards[shard_id] = ice_shard
			ice_shard.register_players(_get_active_players())
		ice_shard.apply_net_state(shard_data)

	var shard_ids := _ice_shards.keys()
	for shard_id in shard_ids:
		if active_ids.has(int(shard_id)):
			continue
		var ice_shard := _ice_shards[shard_id] as IceShard
		if ice_shard != null:
			ice_shard.queue_free()
		_ice_shards.erase(shard_id)


func _has_reached_score_limit() -> bool:
	return red_score >= _score_limit or blue_score >= _score_limit


func _finish_match(detail_prefix: String, announcement_text: String) -> void:
	_match_over = true
	_overtime_active = false
	_hard_paused = false
	_clear_ice_shards()
	hard_pause_changed.emit(false)
	_result_title = Helpers.winner_text(red_score, blue_score)
	_result_detail = "Red %d - %d Blue" % [red_score, blue_score]
	if not detail_prefix.is_empty():
		_result_detail = "%s   %s" % [detail_prefix, _result_detail]
	_configure_match_activity(false)
	_configure_goals(false)
	_goal_reset_remaining = -1.0
	_set_state(GameEnums.MatchState.MATCH_ENDED)
	match_finished.emit(_result_title, _result_detail)
	if not announcement_text.is_empty():
		announcement_requested.emit(announcement_text, Color(1.0, 0.95, 0.72, 1.0), 1.0)
	if not is_paused:
		is_paused = true
		pause_changed.emit(true)
	_broadcast_room_state()
	_broadcast_world_state()
