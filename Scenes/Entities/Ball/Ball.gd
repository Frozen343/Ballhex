extends CharacterBody2D
class_name MatchBall

@export var radius := GameSettings.BALL_RADIUS
@export var max_speed := 920.0
@export var ball_mass := 3.35
@export var ground_friction := 112.0
@export var wall_bounce := 0.84
@export var player_restitution := 0.18
@export var player_contact_friction := 0.05
@export var kick_impulse_multiplier := 1.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var spawn_position := Vector2.ZERO
var last_touch_player_id := -1
var last_touch_team_id := GameEnums.TeamId.NEUTRAL
var active := false
var _tracked_players: Array[HexPlayer] = []

# Client interpolation
var _net_target_position := Vector2.ZERO
var _net_target_velocity := Vector2.ZERO
var _net_interpolating := false
const NET_INTERP_SPEED := 18.0
const NET_SNAP_THRESHOLD := 200.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	safe_margin = 0.02
	process_physics_priority = 10
	spawn_position = position
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not active:
		return
	# Client tarafinda fizik calistirma, state host'tan gelecek
	if NetworkManager.is_online and not NetworkManager.is_host():
		if _net_interpolating:
			var lerp_factor := clampf(NET_INTERP_SPEED * delta, 0.0, 1.0)
			position = position.lerp(_net_target_position + _net_target_velocity * delta, lerp_factor)
			velocity = velocity.lerp(_net_target_velocity, lerp_factor)
			_net_target_position += _net_target_velocity * delta
		return

	velocity = MomentumPhysics2D.apply_surface_friction(
		velocity,
		ground_friction,
		ball_mass,
		delta,
		0.03
	)
	velocity = MomentumPhysics2D.clamp_total_speed(velocity, max_speed)
	_move_with_bounce(delta)
	_resolve_player_collisions()
	_constrain_ball_to_field()


func register_players(players: Array[HexPlayer]) -> void:
	_tracked_players = players


func set_ball_motion_enabled(value: bool) -> void:
	active = value
	if not active:
		velocity = Vector2.ZERO


func reset_ball(reset_position: Vector2 = Vector2.ZERO) -> void:
	position = reset_position
	spawn_position = reset_position
	velocity = Vector2.ZERO
	last_touch_player_id = -1
	last_touch_team_id = GameEnums.TeamId.NEUTRAL
	active = false
	_net_interpolating = false
	_net_target_position = reset_position
	_net_target_velocity = Vector2.ZERO


func apply_kick_impulse(direction: Vector2, strength: float, player: HexPlayer) -> void:
	if direction.length_squared() <= 0.0:
		return
	_set_last_touch(player)
	var shot_impulse := direction.normalized() * strength * kick_impulse_multiplier
	velocity = MomentumPhysics2D.apply_impulse(velocity, shot_impulse, ball_mass)
	velocity = MomentumPhysics2D.clamp_total_speed(velocity, max_speed)


func apply_power_shot(direction: Vector2, player: HexPlayer) -> void:
	if direction.length_squared() <= 0.0:
		return
	_set_last_touch(player)
	var desired_velocity := direction.normalized() * max_speed
	var required_impulse := (desired_velocity - velocity) * ball_mass
	velocity = MomentumPhysics2D.apply_impulse(velocity, required_impulse, ball_mass)
	velocity = MomentumPhysics2D.clamp_total_speed(velocity, max_speed)


func _move_with_bounce(delta: float) -> void:
	var remaining_motion := velocity * delta
	var iteration := 0
	while iteration < 5 and remaining_motion.length_squared() > 0.0001:
		var collision: KinematicCollision2D = move_and_collide(remaining_motion)
		if collision == null:
			break
		var bounce_normal: Vector2 = collision.get_normal()
		position += bounce_normal * 0.8
		velocity = MomentumPhysics2D.bounce_velocity(velocity, bounce_normal, wall_bounce)
		remaining_motion = velocity * delta * 0.32
		iteration += 1


func _resolve_player_collisions() -> void:
	for player in _tracked_players:
		if player == null:
			continue
		if not player.is_field_active():
			continue
		var minimum_distance := radius + player.body_radius
		if position.distance_squared_to(player.position) >= minimum_distance * minimum_distance:
			continue

		var collision_result: MomentumPhysics2D.CollisionResult2D = MomentumPhysics2D.resolve_circle_collision(
			position,
			velocity,
			ball_mass,
			radius,
			player.position,
			player.velocity,
			player.body_mass,
			player.body_radius,
			player_restitution,
			player_contact_friction,
			0.04
		)
		if not collision_result.collided:
			continue

		position = collision_result.position_a
		velocity = MomentumPhysics2D.clamp_total_speed(collision_result.velocity_a, max_speed)
		player.position = collision_result.position_b
		player.velocity = collision_result.velocity_b
		_constrain_ball_to_field()
		_set_last_touch(player)


func _set_last_touch(player: HexPlayer) -> void:
	last_touch_player_id = player.player_id
	last_touch_team_id = player.team_id


func _draw() -> void:
	draw_circle(Vector2(0.0, 2.0), radius - 1.0, Color(0.0, 0.0, 0.0, 0.08))
	draw_circle(Vector2.ZERO, radius, Color("fbf8f2"))
	draw_circle(Vector2(-4.0, -4.0), radius * 0.34, Color(1.0, 1.0, 1.0, 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color("101010"), 2.5)


func _constrain_ball_to_field() -> void:
	var half_field := GameSettings.FIELD_SIZE * 0.5
	var goal_depth := GameSettings.GOAL_DEPTH
	var mouth_half := GameSettings.GOAL_MOUTH_HEIGHT * 0.5
	var margin := radius + 2.0

	position.y = clampf(position.y, -half_field.y + margin, half_field.y - margin)

	var in_goal_mouth := absf(position.y) < mouth_half
	if in_goal_mouth:
		position.x = clampf(position.x, -half_field.x - goal_depth + margin, half_field.x + goal_depth - margin)
	else:
		position.x = clampf(position.x, -half_field.x + margin, half_field.x - margin)


func build_net_state() -> Dictionary:
	return {
		"px": position.x,
		"py": position.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"active": active,
		"ltp": last_touch_player_id,
		"ltt": last_touch_team_id
	}


func apply_net_state(state: Dictionary) -> void:
	var target_pos := Vector2(state["px"], state["py"])
	var target_vel := Vector2(state["vx"], state["vy"])
	active = state["active"]
	last_touch_player_id = state["ltp"]
	last_touch_team_id = state["ltt"]

	if position.distance_to(target_pos) > NET_SNAP_THRESHOLD or not active:
		position = target_pos
		velocity = target_vel
		_net_interpolating = false
	else:
		_net_target_position = target_pos
		_net_target_velocity = target_vel
		_net_interpolating = true
