extends Node2D
class_name IceShard

var shard_id := -1
var owner_player_id := -1
var owner_team_id := GameEnums.TeamId.NEUTRAL
var radius := 11.0
var velocity := Vector2.ZERO
var stun_duration := 1.35
var remaining_life := 0.0
var active := false

var _tracked_players: Array[HexPlayer] = []
var _simulation_enabled := true

var _net_target_position := Vector2.ZERO
var _net_target_velocity := Vector2.ZERO
var _net_interpolating := false
const NET_INTERP_SPEED := 18.0
const NET_SNAP_THRESHOLD := 180.0


func launch(owner: HexPlayer, direction: Vector2, speed: float, lifetime: float, effect_duration: float, projectile_radius: float, new_shard_id: int) -> void:
	if owner == null:
		return
	var launch_direction := direction.normalized()
	if launch_direction.length_squared() <= 0.001:
		launch_direction = owner.facing_direction.normalized()
	if launch_direction.length_squared() <= 0.001:
		launch_direction = Vector2.RIGHT
	shard_id = new_shard_id
	owner_player_id = owner.player_id
	owner_team_id = owner.team_id
	radius = projectile_radius
	stun_duration = effect_duration
	remaining_life = lifetime
	active = true
	velocity = launch_direction * speed
	position = owner.position + launch_direction * (owner.body_radius + radius + 8.0)
	_net_target_position = position
	_net_target_velocity = velocity
	queue_redraw()


func register_players(players: Array[HexPlayer]) -> void:
	_tracked_players = players


func set_simulation_enabled(value: bool) -> void:
	_simulation_enabled = value


func is_expired() -> bool:
	return not active or remaining_life <= 0.0


func _physics_process(delta: float) -> void:
	if not active:
		return
	if NetworkManager.is_online and not NetworkManager.is_host():
		if _net_interpolating:
			var lerp_factor := clampf(NET_INTERP_SPEED * delta, 0.0, 1.0)
			position = position.lerp(_net_target_position + _net_target_velocity * delta, lerp_factor)
			velocity = velocity.lerp(_net_target_velocity, lerp_factor)
			_net_target_position += _net_target_velocity * delta
		return
	if not _simulation_enabled:
		return

	remaining_life = maxf(remaining_life - delta, 0.0)
	position += velocity * delta
	_check_player_hits()
	_check_bounds()


func build_net_state() -> Dictionary:
	return {
		"id": shard_id,
		"px": position.x,
		"py": position.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"r": radius,
		"life": remaining_life,
		"dur": stun_duration,
		"owner": owner_player_id,
		"team": owner_team_id,
		"active": active
	}


func apply_net_state(state: Dictionary) -> void:
	shard_id = int(state.get("id", shard_id))
	owner_player_id = int(state.get("owner", owner_player_id))
	owner_team_id = int(state.get("team", owner_team_id)) as GameEnums.TeamId
	radius = float(state.get("r", radius))
	remaining_life = float(state.get("life", remaining_life))
	stun_duration = float(state.get("dur", stun_duration))
	active = bool(state.get("active", active))
	var target_position := Vector2(float(state.get("px", position.x)), float(state.get("py", position.y)))
	var target_velocity := Vector2(float(state.get("vx", velocity.x)), float(state.get("vy", velocity.y)))
	if not active or position.distance_to(target_position) > NET_SNAP_THRESHOLD:
		position = target_position
		velocity = target_velocity
		_net_interpolating = false
	else:
		_net_target_position = target_position
		_net_target_velocity = target_velocity
		_net_interpolating = true
	queue_redraw()


func _check_player_hits() -> void:
	for player in _tracked_players:
		if player == null or not player.is_field_active():
			continue
		if player.player_id == owner_player_id:
			continue
		var minimum_distance := radius + player.body_radius
		if position.distance_squared_to(player.position) > minimum_distance * minimum_distance:
			continue
		if player.team_id != owner_team_id and player.team_id != GameEnums.TeamId.NEUTRAL:
			player.apply_stun(stun_duration)
		active = false
		remaining_life = 0.0
		return


func _check_bounds() -> void:
	var half_field := GameSettings.FIELD_SIZE * 0.5
	var margin := 180.0
	if absf(position.x) > half_field.x + margin or absf(position.y) > half_field.y + margin:
		active = false
		remaining_life = 0.0


func _draw() -> void:
	var tip := Vector2(radius + 4.0, 0.0)
	var top := Vector2(-radius * 0.55, -radius * 0.72)
	var bottom := Vector2(-radius * 0.55, radius * 0.72)
	draw_colored_polygon(
		PackedVector2Array([tip, top, bottom]),
		Color(0.78, 0.96, 1.0, 0.95)
	)
	draw_polyline(PackedVector2Array([tip, top, bottom, tip]), Color(0.92, 1.0, 1.0, 0.95), 2.0)
	draw_circle(Vector2(-radius * 0.15, 0.0), radius * 0.28, Color(1.0, 1.0, 1.0, 0.36))
