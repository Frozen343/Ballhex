extends CharacterBody2D
class_name HexPlayer

signal kick_attempted(player: HexPlayer)

@export var player_id := 1
@export var team_id := GameEnums.TeamId.RED
@export var display_name := "P1"
@export var move_speed := 138.0
@export var drive_force := 2800.0
@export var ground_friction := 138.0
@export var body_mass := 6.0
@export var body_restitution := 0.12
@export var body_contact_friction := 0.18
@export var turn_grip := 12.0
@export var facing_turn_speed := 12.0
@export var kick_strength := 840.0
@export var kick_contact_margin := 7.0
@export var body_radius := GameSettings.PLAYER_RADIUS
@export var out_of_bounds_margin := 80.0
@export var dash_impulse := 980.0
@export var dash_speed_bonus := 180.0
@export var dash_bonus_decay := 150.0
@export var power_shot_contact_bonus := 6.0
@export var magnet_radius := 158.0
@export var magnet_pull_force := 1100.0
@export var magnet_duration := 1.17
@export var grow_area_multiplier := 2.0
@export var grow_duration := 4.0
@export var grow_expand_speed := 8.5
@export var grow_shrink_speed := 2.8
@export var grow_mass_multiplier := 2.0
@export var grow_move_speed_multiplier := 0.62
@export var grow_kick_strength_multiplier := 1.3
@export var grow_drive_force_multiplier := 1.95
@export var grow_touch_impulse_multiplier := 0.4
@export var shrink_area_multiplier := 0.5
@export var shrink_duration := 4.0
@export var shrink_contract_speed := 9.5
@export var shrink_recover_speed := 4.0
@export var shrink_mass_multiplier := 0.5
@export var shrink_move_speed_multiplier := 2.0
@export var shrink_kick_strength_multiplier := 0.5
@export var shrink_drive_force_multiplier := 1.1
@export var stun_duration := 1.35
@export var stun_projectile_speed := 760.0
@export var stun_projectile_lifetime := 1.1
@export var stun_projectile_radius := 11.0
@export var stun_stop_friction_multiplier := 4.4

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var kick_cooldown: CooldownComponent = $KickCooldown
@onready var dash_cooldown: CooldownComponent = $DashCooldown
@onready var power_shot_cooldown: CooldownComponent = $PowerShotCooldown
@onready var magnet_cooldown: CooldownComponent = $MagnetCooldown
@onready var grow_cooldown: CooldownComponent = $GrowCooldown
@onready var shrink_cooldown: CooldownComponent = $ShrinkCooldown
@onready var stun_cooldown: CooldownComponent = $StunCooldown
@onready var name_label: Label = $NameLabel
@onready var initials_label: Label = $InitialsLabel

var input_enabled := false
var spawn_position := Vector2.ZERO
var facing_direction := Vector2.RIGHT
var controller_peer_id := 1
var _input_profile: Dictionary = {}
var _ball: MatchBall
var _match_manager: MatchManager
var _kick_flash_strength := 0.0
var _field_active := true
var _base_body_radius := GameSettings.PLAYER_RADIUS
var _base_body_mass := 6.0
var _base_move_speed := 138.0
var _base_kick_strength := 840.0
var _base_drive_force := 2800.0

# Network
var _remote_input_direction := Vector2.ZERO
var _remote_kick_requested := false
var _remote_dash_requested := false
var _remote_power_shot_requested := false
var _remote_magnet_requested := false
var _remote_grow_requested := false
var _remote_shrink_requested := false
var _remote_stun_requested := false
var _kickoff_restricted := false
var _kickoff_half_locked := false
var _speed_cap_bonus := 0.0
var _magnet_active_remaining := 0.0
var _grow_active_remaining := 0.0
var _shrink_active_remaining := 0.0
var _stun_remaining := 0.0
var _body_radius_scale := 1.0

# Client interpolation
var _net_target_position := Vector2.ZERO
var _net_target_velocity := Vector2.ZERO
var _net_target_facing := Vector2.RIGHT
var _net_interpolating := false
const NET_INTERP_SPEED := 15.0
const NET_SNAP_THRESHOLD := 200.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	safe_margin = 0.02
	add_to_group("players")
	_input_profile = InputProfiles.get_profile(player_id)
	controller_peer_id = player_id
	_base_body_radius = body_radius
	_base_body_mass = body_mass
	_base_move_speed = move_speed
	_base_kick_strength = kick_strength
	_base_drive_force = drive_force
	spawn_position = position
	if team_id == GameEnums.TeamId.BLUE:
		facing_direction = Vector2.LEFT
	_update_name_label()
	_update_collision_shape()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _field_active:
		return

	# Client-side online physics is host authoritative.
	if NetworkManager.is_online and not NetworkManager.is_host():
		_send_local_input_to_host()
		_kick_flash_strength = move_toward(_kick_flash_strength, 0.0, delta * 4.5)
		if _net_interpolating:
			var lerp_factor := clampf(NET_INTERP_SPEED * delta, 0.0, 1.0)
			position = position.lerp(_net_target_position + _net_target_velocity * delta, lerp_factor)
			velocity = velocity.lerp(_net_target_velocity, lerp_factor)
			var facing_lerp := clampf(10.0 * delta, 0.0, 1.0)
			var current_angle := facing_direction.angle()
			var target_angle := _net_target_facing.angle()
			facing_direction = Vector2.from_angle(lerp_angle(current_angle, target_angle, facing_lerp))
			# Advance target by velocity to predict between syncs
			_net_target_position += _net_target_velocity * delta
		queue_redraw()
		return

	var needs_redraw := false
	var previous_facing := facing_direction
	var previous_flash := _kick_flash_strength
	var previous_magnet := _magnet_active_remaining
	var previous_radius := body_radius
	var previous_stun := _stun_remaining
	_kick_flash_strength = move_toward(_kick_flash_strength, 0.0, delta * 4.5)
	_speed_cap_bonus = move_toward(_speed_cap_bonus, 0.0, dash_bonus_decay * delta)
	_magnet_active_remaining = move_toward(_magnet_active_remaining, 0.0, delta)
	_grow_active_remaining = move_toward(_grow_active_remaining, 0.0, delta)
	_shrink_active_remaining = move_toward(_shrink_active_remaining, 0.0, delta)
	_stun_remaining = move_toward(_stun_remaining, 0.0, delta)
	_update_body_radius_scale(delta)
	var input_direction := Vector2.ZERO
	var current_speed_cap := move_speed + _speed_cap_bonus

	if input_enabled:
		input_direction = _get_effective_input()
		var stunned_now := is_stunned()
		if stunned_now:
			input_direction = Vector2.ZERO
		if input_direction.length_squared() > 0.0:
			var target_facing := input_direction.normalized()
			var current_angle := facing_direction.angle()
			var target_angle := target_facing.angle()
			var new_angle := lerp_angle(current_angle, target_angle, clampf(facing_turn_speed * delta, 0.0, 1.0))
			facing_direction = Vector2.from_angle(new_angle)
		var kick_pressed := false
		var dash_pressed := false
		var power_shot_pressed := false
		var magnet_pressed := false
		var grow_pressed := false
		var shrink_pressed := false
		var stun_pressed := false
		if _is_local_player():
			var profile := _get_local_profile()
			kick_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["kick"])
			dash_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["dash"])
			power_shot_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["power_shot"])
			magnet_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["magnet"])
			grow_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["grow"])
			shrink_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["shrink"])
			stun_pressed = not GameSettings.chat_active and Input.is_action_just_pressed(profile["stun"])
		else:
			kick_pressed = _remote_kick_requested
			_remote_kick_requested = false
			dash_pressed = _remote_dash_requested
			_remote_dash_requested = false
			power_shot_pressed = _remote_power_shot_requested
			_remote_power_shot_requested = false
			magnet_pressed = _remote_magnet_requested
			_remote_magnet_requested = false
			grow_pressed = _remote_grow_requested
			_remote_grow_requested = false
			shrink_pressed = _remote_shrink_requested
			_remote_shrink_requested = false
			stun_pressed = _remote_stun_requested
			_remote_stun_requested = false
		if stunned_now:
			kick_pressed = false
			dash_pressed = false
			power_shot_pressed = false
			magnet_pressed = false
			grow_pressed = false
			shrink_pressed = false
			stun_pressed = false
		if dash_pressed:
			_attempt_dash(input_direction)
			current_speed_cap = move_speed + _speed_cap_bonus
		if power_shot_pressed:
			_trigger_kick_flash()
			_attempt_power_shot(input_direction)
		if magnet_pressed:
			_attempt_magnet()
		if grow_pressed:
			_attempt_grow()
		if shrink_pressed:
			_attempt_shrink()
		if stun_pressed:
			_attempt_stun(input_direction)
		if kick_pressed:
			_trigger_kick_flash()
			_attempt_kick(input_direction)
		velocity = MomentumPhysics2D.apply_drive_force(
			velocity,
			input_direction,
			drive_force,
			body_mass,
			delta
		)
		velocity = MomentumPhysics2D.clamp_speed_along_direction(velocity, input_direction, current_speed_cap)
		velocity = MomentumPhysics2D.clamp_total_speed(velocity, current_speed_cap)

	var friction_strength := ground_friction
	if is_stunned():
		friction_strength *= stun_stop_friction_multiplier
	velocity = MomentumPhysics2D.apply_surface_friction(
		velocity,
		friction_strength,
		body_mass,
		delta,
		0.08
	)
	if input_direction.length_squared() > 0.0:
		velocity = MomentumPhysics2D.apply_lateral_grip(velocity, input_direction, turn_grip, delta)
	if input_enabled:
		velocity = MomentumPhysics2D.clamp_total_speed(velocity, current_speed_cap)

	if velocity.length_squared() > 0.0001 or input_direction.length_squared() > 0.0:
		move_and_slide()
	_resolve_player_overlaps()
	_constrain_to_pitch()
	_constrain_to_kickoff_zone()

	if previous_facing != facing_direction or absf(previous_flash - _kick_flash_strength) > 0.001 or absf(previous_magnet - _magnet_active_remaining) > 0.001 or absf(previous_radius - body_radius) > 0.001 or absf(previous_stun - _stun_remaining) > 0.001:
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func assign_ball(ball: MatchBall) -> void:
	_ball = ball


func set_match_manager(manager: MatchManager) -> void:
	_match_manager = manager


func set_input_enabled(value: bool) -> void:
	input_enabled = value and _field_active
	if not input_enabled:
		velocity = Vector2.ZERO
		_speed_cap_bonus = 0.0
		_magnet_active_remaining = 0.0
		_grow_active_remaining = 0.0
		_shrink_active_remaining = 0.0
		_stun_remaining = 0.0


func reset_to_spawn() -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	kick_cooldown.reset()
	dash_cooldown.reset()
	power_shot_cooldown.reset()
	magnet_cooldown.reset()
	grow_cooldown.reset()
	shrink_cooldown.reset()
	stun_cooldown.reset()
	_kick_flash_strength = 0.0
	_speed_cap_bonus = 0.0
	_magnet_active_remaining = 0.0
	_grow_active_remaining = 0.0
	_shrink_active_remaining = 0.0
	_stun_remaining = 0.0
	_body_radius_scale = 1.0
	body_radius = _base_body_radius
	body_mass = _base_body_mass
	move_speed = _base_move_speed
	kick_strength = _base_kick_strength
	drive_force = _base_drive_force
	_update_collision_shape()
	_update_name_label()
	_net_interpolating = false
	_net_target_position = spawn_position
	_net_target_velocity = Vector2.ZERO
	_net_target_facing = facing_direction


func set_spawn_position(value: Vector2) -> void:
	spawn_position = value
	position = value


func get_team_color() -> Color:
	return Helpers.team_color(team_id)


func set_controller_peer_id(value: int) -> void:
	controller_peer_id = value


func set_display_name(value: String) -> void:
	display_name = value
	if is_node_ready():
		_update_name_label()


func set_field_active(value: bool) -> void:
	_field_active = value
	visible = value
	collision_shape.disabled = not value
	if not value:
		input_enabled = false
		velocity = Vector2.ZERO
		_speed_cap_bonus = 0.0
		_remote_input_direction = Vector2.ZERO
		_remote_kick_requested = false
		_remote_dash_requested = false
		_remote_power_shot_requested = false
		_remote_magnet_requested = false
		_remote_grow_requested = false
		_remote_shrink_requested = false
		_remote_stun_requested = false
		_magnet_active_remaining = 0.0
		_grow_active_remaining = 0.0
		_shrink_active_remaining = 0.0
		_stun_remaining = 0.0
		_body_radius_scale = 1.0
		body_radius = _base_body_radius
		body_mass = _base_body_mass
		move_speed = _base_move_speed
		kick_strength = _base_kick_strength
		drive_force = _base_drive_force
		_update_collision_shape()
		_update_name_label()


func is_field_active() -> bool:
	return _field_active


func _is_local_player() -> bool:
	if not NetworkManager.is_online:
		return true
	return controller_peer_id == NetworkManager.get_local_peer_id()


func _get_effective_input() -> Vector2:
	if _is_local_player():
		return _get_local_input()
	return _remote_input_direction


func _get_local_input() -> Vector2:
	if GameSettings.chat_active:
		return Vector2.ZERO
	var profile := _get_local_profile()
	var direction := Vector2(
		Input.get_action_strength(profile["right"]) - Input.get_action_strength(profile["left"]),
		Input.get_action_strength(profile["down"]) - Input.get_action_strength(profile["up"])
	)
	if direction.length_squared() > 0.0:
		return direction.normalized()
	return Vector2.ZERO


func _send_local_input_to_host() -> void:
	if not _is_local_player():
		return
	var dir := _get_local_input()
	var profile := _get_local_profile()
	var kick := not GameSettings.chat_active and Input.is_action_just_pressed(profile["kick"])
	var dash := not GameSettings.chat_active and Input.is_action_just_pressed(profile["dash"])
	var power_shot := not GameSettings.chat_active and Input.is_action_just_pressed(profile["power_shot"])
	var magnet := not GameSettings.chat_active and Input.is_action_just_pressed(profile["magnet"])
	var grow := not GameSettings.chat_active and Input.is_action_just_pressed(profile["grow"])
	var shrink := not GameSettings.chat_active and Input.is_action_just_pressed(profile["shrink"])
	var stun := not GameSettings.chat_active and Input.is_action_just_pressed(profile["stun"])
	_rpc_send_input.rpc_id(1, dir.x, dir.y, kick, dash, power_shot, magnet, grow, shrink, stun)


func _get_local_profile() -> Dictionary:
	if NetworkManager.is_online:
		return InputProfiles.get_profile(1)
	return _input_profile


@rpc("any_peer", "unreliable", "call_remote")
func _rpc_send_input(dir_x: float, dir_y: float, kick: bool, dash: bool, power_shot: bool, magnet: bool, grow: bool, shrink: bool, stun: bool) -> void:
	_remote_input_direction = Vector2(dir_x, dir_y)
	if kick:
		_remote_kick_requested = true
	if dash:
		_remote_dash_requested = true
	if power_shot:
		_remote_power_shot_requested = true
	if magnet:
		_remote_magnet_requested = true
	if grow:
		_remote_grow_requested = true
	if shrink:
		_remote_shrink_requested = true
	if stun:
		_remote_stun_requested = true


func build_net_state() -> Dictionary:
	return {
		"px": position.x,
		"py": position.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"fx": facing_direction.x,
		"fy": facing_direction.y,
		"kf": _kick_flash_strength,
		"mag": _magnet_active_remaining,
		"grow": _grow_active_remaining,
		"shrink": _shrink_active_remaining,
		"stun": _stun_remaining,
		"scale": _body_radius_scale,
		"active": _field_active,
		"owner": controller_peer_id,
		"name": display_name
	}


func apply_net_state(state: Dictionary) -> void:
	set_field_active(state.get("active", true))
	_kick_flash_strength = state["kf"]
	_magnet_active_remaining = float(state.get("mag", _magnet_active_remaining))
	_grow_active_remaining = float(state.get("grow", _grow_active_remaining))
	_shrink_active_remaining = float(state.get("shrink", _shrink_active_remaining))
	_stun_remaining = float(state.get("stun", _stun_remaining))
	_body_radius_scale = float(state.get("scale", _body_radius_scale))
	body_radius = _base_body_radius * _body_radius_scale
	_apply_grow_stat_modifiers()
	_update_collision_shape()
	_update_name_label()
	controller_peer_id = int(state.get("owner", controller_peer_id))
	set_display_name(str(state.get("name", display_name)))

	var target_pos := Vector2(state["px"], state["py"])
	var target_vel := Vector2(state["vx"], state["vy"])
	var target_face := Vector2(state["fx"], state["fy"])

	# If distance is too large (teleport/reset), snap immediately
	if position.distance_to(target_pos) > NET_SNAP_THRESHOLD:
		position = target_pos
		velocity = target_vel
		facing_direction = target_face
		_net_interpolating = false
	else:
		_net_target_position = target_pos
		_net_target_velocity = target_vel
		_net_target_facing = target_face
		_net_interpolating = true

	queue_redraw()


func _attempt_kick(input_direction: Vector2) -> void:
	if _ball == null or not kick_cooldown.is_ready():
		return

	var to_ball := _ball.position - position
	var contact_distance := body_radius + _ball.radius + kick_contact_margin
	if to_ball.length() > contact_distance:
		return

	var kick_direction := _build_shot_direction(input_direction, to_ball)
	_ball.apply_kick_impulse(kick_direction, kick_strength, self)
	kick_cooldown.trigger()
	GameEvents.emit_ball_kicked(player_id, team_id)
	kick_attempted.emit(self)


func _attempt_dash(input_direction: Vector2) -> void:
	if not dash_cooldown.is_ready():
		return
	var dash_direction := facing_direction
	if input_direction.length_squared() > 0.0:
		dash_direction = input_direction.normalized()
	elif facing_direction.length_squared() > 0.0:
		dash_direction = facing_direction.normalized()
	velocity = MomentumPhysics2D.apply_impulse(velocity, dash_direction * dash_impulse, body_mass)
	_speed_cap_bonus = maxf(_speed_cap_bonus, dash_speed_bonus)
	dash_cooldown.trigger()


func _attempt_power_shot(input_direction: Vector2) -> void:
	if _ball == null or not power_shot_cooldown.is_ready() or not kick_cooldown.is_ready():
		return
	var to_ball := _ball.position - position
	var contact_distance := body_radius + _ball.radius + kick_contact_margin + power_shot_contact_bonus
	if to_ball.length() > contact_distance:
		return
	var shot_direction := _build_shot_direction(input_direction, to_ball)
	_ball.apply_power_shot(shot_direction, self)
	power_shot_cooldown.trigger()
	kick_cooldown.trigger()
	GameEvents.emit_ball_kicked(player_id, team_id)
	kick_attempted.emit(self)


func _attempt_magnet() -> void:
	if _ball == null or not magnet_cooldown.is_ready():
		return
	_magnet_active_remaining = magnet_duration
	magnet_cooldown.trigger()


func _attempt_grow() -> void:
	if not grow_cooldown.is_ready():
		return
	_shrink_active_remaining = 0.0
	_grow_active_remaining = grow_duration
	_apply_grow_touch_impulse()
	grow_cooldown.trigger()


func _attempt_shrink() -> void:
	if not shrink_cooldown.is_ready():
		return
	_grow_active_remaining = 0.0
	_shrink_active_remaining = shrink_duration
	shrink_cooldown.trigger()


func _attempt_stun(input_direction: Vector2) -> void:
	if _match_manager == null or not stun_cooldown.is_ready():
		return
	var shot_direction := facing_direction
	if input_direction.length_squared() > 0.0:
		shot_direction = input_direction.normalized()
	elif facing_direction.length_squared() > 0.0:
		shot_direction = facing_direction.normalized()
	if shot_direction.length_squared() <= 0.001:
		shot_direction = Vector2.RIGHT
	_match_manager.spawn_ice_shard(
		self,
		shot_direction,
		stun_projectile_speed,
		stun_projectile_lifetime,
		stun_duration,
		stun_projectile_radius
	)
	stun_cooldown.trigger()


func _get_grow_radius_scale() -> float:
	return sqrt(maxf(1.0, grow_area_multiplier))


func _get_shrink_radius_scale() -> float:
	return sqrt(clampf(shrink_area_multiplier, 0.1, 1.0))


func _get_target_radius_scale() -> float:
	if _grow_active_remaining > 0.001:
		return _get_grow_radius_scale()
	if _shrink_active_remaining > 0.001:
		return _get_shrink_radius_scale()
	return 1.0


func _apply_grow_stat_modifiers() -> void:
	if _body_radius_scale > 1.001:
		var grow_progress := clampf(inverse_lerp(1.0, _get_grow_radius_scale(), _body_radius_scale), 0.0, 1.0)
		body_mass = lerpf(_base_body_mass, _base_body_mass * grow_mass_multiplier, grow_progress)
		move_speed = lerpf(_base_move_speed, _base_move_speed * grow_move_speed_multiplier, grow_progress)
		kick_strength = lerpf(_base_kick_strength, _base_kick_strength * grow_kick_strength_multiplier, grow_progress)
		drive_force = lerpf(_base_drive_force, _base_drive_force * grow_drive_force_multiplier, grow_progress)
		return
	if _body_radius_scale < 0.999:
		var shrink_progress := clampf(inverse_lerp(1.0, _get_shrink_radius_scale(), _body_radius_scale), 0.0, 1.0)
		body_mass = lerpf(_base_body_mass, _base_body_mass * shrink_mass_multiplier, shrink_progress)
		move_speed = lerpf(_base_move_speed, _base_move_speed * shrink_move_speed_multiplier, shrink_progress)
		kick_strength = lerpf(_base_kick_strength, _base_kick_strength * shrink_kick_strength_multiplier, shrink_progress)
		drive_force = lerpf(_base_drive_force, _base_drive_force * shrink_drive_force_multiplier, shrink_progress)
		return
	body_mass = _base_body_mass
	move_speed = _base_move_speed
	kick_strength = _base_kick_strength
	drive_force = _base_drive_force


func _apply_grow_touch_impulse() -> void:
	if _ball == null:
		return
	var to_ball := _ball.position - position
	var contact_distance := body_radius + _ball.radius + kick_contact_margin + 10.0
	if to_ball.length() > contact_distance:
		return
	var push_direction := to_ball.normalized() if to_ball.length_squared() > 0.001 else facing_direction.normalized()
	if push_direction.length_squared() <= 0.001:
		push_direction = Vector2.RIGHT
	_ball.apply_kick_impulse(push_direction, kick_strength * grow_touch_impulse_multiplier, self)


func _update_body_radius_scale(delta: float) -> void:
	var target_scale := _get_target_radius_scale()
	var speed := grow_shrink_speed
	if target_scale > 1.001:
		speed = grow_expand_speed if target_scale > _body_radius_scale else grow_shrink_speed
	elif target_scale < 0.999:
		speed = shrink_contract_speed if target_scale < _body_radius_scale else shrink_recover_speed
	elif _body_radius_scale < 0.999:
		speed = shrink_recover_speed
	var new_scale := move_toward(_body_radius_scale, target_scale, speed * delta)
	if absf(new_scale - _body_radius_scale) <= 0.0001:
		return
	_body_radius_scale = new_scale
	body_radius = _base_body_radius * _body_radius_scale
	_apply_grow_stat_modifiers()
	_update_collision_shape()
	_update_name_label()


func _build_shot_direction(input_direction: Vector2, to_ball: Vector2) -> Vector2:
	var shot_direction := facing_direction
	if input_direction.length_squared() > 0.0:
		shot_direction = input_direction.normalized()
	elif to_ball.length_squared() > 0.0:
		shot_direction = to_ball.normalized()
	if to_ball.length_squared() > 0.0:
		shot_direction = (shot_direction + to_ball.normalized() * 0.18).normalized()
	return shot_direction


func apply_stun(duration_seconds: float) -> void:
	_stun_remaining = maxf(_stun_remaining, duration_seconds)
	velocity = Vector2.ZERO
	_speed_cap_bonus = 0.0
	_magnet_active_remaining = 0.0
	_remote_input_direction = Vector2.ZERO
	_remote_kick_requested = false
	_remote_dash_requested = false
	_remote_power_shot_requested = false
	_remote_magnet_requested = false
	_remote_grow_requested = false
	_remote_shrink_requested = false
	_remote_stun_requested = false
	queue_redraw()


func is_stunned() -> bool:
	return _field_active and _stun_remaining > 0.001


func _update_name_label() -> void:
	name_label.text = display_name
	name_label.position = Vector2(-60.0, body_radius + 14.0)
	name_label.size = Vector2(120.0, 24.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color("f8fff4"))
	name_label.add_theme_font_size_override("font_size", 16)
	initials_label.text = _build_initials()
	initials_label.position = Vector2(-22.0, -18.0)
	initials_label.size = Vector2(44.0, 32.0)
	initials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials_label.add_theme_color_override("font_color", Color("ffffff"))
	initials_label.add_theme_font_size_override("font_size", 20)


func _update_collision_shape() -> void:
	var shape := CircleShape2D.new()
	shape.radius = body_radius
	collision_shape.shape = shape


func _draw() -> void:
	if not _field_active:
		return

	var team_color := get_team_color()
	var deep_color := GameSettings.COLOR_RED_TEAM_DEEP if team_id == GameEnums.TeamId.RED else GameSettings.COLOR_BLUE_TEAM_DEEP
	draw_circle(Vector2(0.0, 4.0), body_radius - 2.0, Color(0.0, 0.0, 0.0, 0.08))
	draw_circle(Vector2.ZERO, body_radius, team_color)
	draw_circle(Vector2(-7.0, -7.0), body_radius * 0.42, Color(1.0, 1.0, 1.0, 0.16))
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 48, Color("111111"), 3.0)
	draw_arc(Vector2.ZERO, body_radius - 5.0, 0.3, 2.4, 18, deep_color, 3.0)
	if _body_radius_scale > 1.02:
		var grow_alpha := clampf((_body_radius_scale - 1.0) / maxf(0.001, _get_grow_radius_scale() - 1.0), 0.16, 0.42)
		draw_arc(Vector2.ZERO, body_radius + 5.0, 0.0, TAU, 56, Color(1.0, 0.94, 0.72, grow_alpha), 2.0)
	elif _body_radius_scale < 0.98:
		var shrink_alpha := clampf((1.0 - _body_radius_scale) / maxf(0.001, 1.0 - _get_shrink_radius_scale()), 0.16, 0.42)
		draw_arc(Vector2.ZERO, body_radius + 4.0, 0.0, TAU, 56, Color(0.72, 0.95, 1.0, shrink_alpha), 2.0)
	var aim_end := facing_direction.normalized() * (body_radius - 5.0)
	draw_line(Vector2.ZERO, aim_end, Color(1.0, 1.0, 1.0, 0.45), 2.0)
	if is_magnet_active():
		var magnet_alpha := clampf(_magnet_active_remaining / magnet_duration, 0.18, 0.5)
		draw_arc(Vector2.ZERO, magnet_radius, 0.0, TAU, 56, Color(0.75, 0.92, 1.0, magnet_alpha), 2.0)
	if is_stunned():
		var stun_alpha := clampf(_stun_remaining / maxf(0.001, stun_duration), 0.22, 0.66)
		draw_arc(Vector2.ZERO, body_radius + 8.0, 0.0, TAU, 40, Color(0.72, 0.95, 1.0, stun_alpha), 3.0)
		draw_circle(Vector2(0.0, -body_radius - 10.0), 4.0, Color(0.86, 0.98, 1.0, stun_alpha))
	if _kick_flash_strength > 0.01:
		var glow := Color(1.0, 1.0, 1.0, 0.22 * _kick_flash_strength)
		draw_circle(Vector2.ZERO, body_radius + 7.0, glow)
		draw_arc(Vector2.ZERO, body_radius + 2.5, 0.0, TAU, 56, Color(1.0, 1.0, 1.0, 0.95 * _kick_flash_strength), 4.0)


func _build_initials() -> String:
	var cleaned := display_name.strip_edges()
	if cleaned.is_empty():
		return "P"
	var parts := cleaned.split(" ", false)
	if parts.size() >= 2:
		return "%s%s" % [parts[0].left(1).to_upper(), parts[1].left(1).to_upper()]
	return cleaned.left(2).to_upper()


func apply_ball_recoil(impulse: Vector2) -> void:
	velocity = MomentumPhysics2D.apply_impulse(velocity, impulse, body_mass)


func is_magnet_active() -> bool:
	return _field_active and _magnet_active_remaining > 0.001


func _trigger_kick_flash() -> void:
	_kick_flash_strength = 1.0
	queue_redraw()


func _resolve_player_overlaps() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as HexPlayer
		if other == null or other == self:
			continue
		if not other.is_field_active():
			continue
		if player_id > other.player_id:
			continue

		var offset := other.position - position
		var minimum_distance := body_radius + other.body_radius
		if offset.length_squared() >= minimum_distance * minimum_distance:
			continue

		var collision_result: MomentumPhysics2D.CollisionResult2D = MomentumPhysics2D.resolve_circle_collision(
			position,
			velocity,
			body_mass,
			body_radius,
			other.position,
			other.velocity,
			other.body_mass,
			other.body_radius,
			minf(body_restitution, other.body_restitution),
			maxf(body_contact_friction, other.body_contact_friction),
			0.08
		)
		if not collision_result.collided:
			continue

		position = collision_result.position_a
		velocity = collision_result.velocity_a
		other.position = collision_result.position_b
		other.velocity = collision_result.velocity_b


func set_kickoff_restricted(value: bool) -> void:
	_kickoff_restricted = value


func set_kickoff_half_locked(value: bool) -> void:
	_kickoff_half_locked = value


func _constrain_to_kickoff_zone() -> void:
	var center_radius := 120.0
	var in_circle := position.length() < center_radius

	# Scoring team cannot enter center circle
	if _kickoff_restricted and in_circle:
		var dist := position.length()
		if dist < 0.001:
			var push_dir := Vector2.LEFT if team_id == GameEnums.TeamId.RED else Vector2.RIGHT
			position = push_dir * center_radius
		else:
			position = position.normalized() * center_radius
		var to_center := -position.normalized()
		var vel_toward := velocity.dot(to_center)
		if vel_toward > 0.0:
			velocity -= to_center * vel_toward
		in_circle = false

	# Both teams stay on own half, but non-scoring team can cross within center circle
	if _kickoff_half_locked and not in_circle:
		var margin := 2.0
		if team_id == GameEnums.TeamId.RED and position.x > -margin:
			position.x = -margin
			if velocity.x > 0.0:
				velocity.x = 0.0
		elif team_id == GameEnums.TeamId.BLUE and position.x < margin:
			position.x = margin
			if velocity.x < 0.0:
				velocity.x = 0.0


func _constrain_to_pitch() -> void:
	var half_field := GameSettings.FIELD_SIZE * 0.5
	position.x = clampf(position.x, -half_field.x - out_of_bounds_margin, half_field.x + out_of_bounds_margin)
	position.y = clampf(position.y, -half_field.y - out_of_bounds_margin, half_field.y + out_of_bounds_margin)
