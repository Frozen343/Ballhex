extends CharacterBody2D
class_name MatchBall

@export var radius := GameSettings.BALL_RADIUS
@export var max_speed := 750.0
@export var drag := 105.0
@export var wall_bounce := 0.64
@export var player_hit_multiplier := 0.22
@export var kick_impulse_multiplier := 1.08
@export var min_contact_push := 8.0
@export var max_contact_push := 26.0
@export var player_recoil_strength := 18.0
@export var overlap_recovery_speed := 10.0
@export var carry_factor := 0.18
@export var tangent_carry_factor := 0.08

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
	collision_mask = 1 | 2
	safe_margin = 0.02
	spawn_position = position
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not active:
		return
	# Client tarafında fizik çalıştırma — state host'tan gelecek
	if NetworkManager.is_online and not NetworkManager.is_host():
		if _net_interpolating:
			var lerp_factor := clampf(NET_INTERP_SPEED * delta, 0.0, 1.0)
			position = position.lerp(_net_target_position + _net_target_velocity * delta, lerp_factor)
			velocity = velocity.lerp(_net_target_velocity, lerp_factor)
			_net_target_position += _net_target_velocity * delta
		return

	velocity = velocity.move_toward(Vector2.ZERO, drag * delta)
	velocity = velocity.limit_length(max_speed)
	_move_with_bounce(delta)
	_resolve_player_overlaps(delta)
	_constrain_ball_to_field()


func register_players(players: Array[HexPlayer]) -> void:
	_tracked_players = players


func set_ball_motion_enabled(value: bool) -> void:
	active = value
	if not active:
		velocity = Vector2.ZERO


func reset_ball(reset_position: Vector2 = Vector2.ZERO) -> void:
	self.position = reset_position
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
	velocity = direction.normalized() * minf(strength, max_speed) * kick_impulse_multiplier
	velocity = velocity.limit_length(max_speed)


func _move_with_bounce(delta: float) -> void:
	var remaining_motion := velocity * delta
	var iteration := 0
	var prev_bounce_normal := Vector2.ZERO
	while iteration < 6 and remaining_motion.length_squared() > 0.0001:
		var collision := move_and_collide(remaining_motion)
		if collision == null:
			break
		var collider := collision.get_collider()
		if collider is HexPlayer:
			var player := collider as HexPlayer
			_handle_player_collision(collision, player)
			var normal := collision.get_normal()
			if velocity.dot(normal) > 10.0:
				remaining_motion = velocity.normalized() * collision.get_remainder().length()
			else:
				remaining_motion = collision.get_remainder().slide(normal) * 0.18
			prev_bounce_normal = Vector2.ZERO
		else:
			var bounce_normal := collision.get_normal()
			# Köşe algılama: iki ardışık normal ~90° ise topu sahaya doğru it
			if prev_bounce_normal.length_squared() > 0.5 and absf(bounce_normal.dot(prev_bounce_normal)) < 0.3:
				var escape_dir := (bounce_normal + prev_bounce_normal).normalized()
				position += escape_dir * 6.0
				velocity = escape_dir * velocity.length() * wall_bounce
				prev_bounce_normal = Vector2.ZERO
				remaining_motion = velocity * delta * 0.2
			else:
				position += bounce_normal * 1.2
				velocity = velocity.bounce(bounce_normal) * wall_bounce
				prev_bounce_normal = bounce_normal
				remaining_motion = velocity * delta * 0.26
			if velocity.length() < 18.0:
				velocity = Vector2.ZERO
				break
		iteration += 1


func _resolve_player_overlaps(delta: float) -> void:
	for player in _tracked_players:
		if player == null:
			continue
		if not player.is_field_active():
			continue
		var offset := position - player.position
		var distance := offset.length()
		var minimum_distance := radius + player.body_radius
		if distance >= minimum_distance:
			continue

		var normal := Vector2.RIGHT
		if distance > 0.001:
			normal = offset / distance
		elif player.facing_direction.length_squared() > 0.0:
			normal = player.facing_direction.normalized()

		var correction := minimum_distance - distance
		var ball_pos_before := position
		position += normal * correction
		_constrain_ball_to_field()
		# Top duvar yüzünden tam correction yapamadıysa, oyuncuyu geri it
		var actual_ball_move := (position - ball_pos_before).dot(normal)
		var remaining := correction - actual_ball_move
		if remaining > 0.5:
			player.position -= normal * remaining
		var player_speed := player.velocity.length()
		var approach_speed := maxf(player.velocity.dot(normal), 0.0)
		var tangent_velocity := player.velocity - normal * player.velocity.dot(normal)
		var contact_push := clampf(min_contact_push + approach_speed * player_hit_multiplier, min_contact_push, max_contact_push)
		velocity += normal * contact_push
		velocity += tangent_velocity * tangent_carry_factor * delta * overlap_recovery_speed
		if player_speed > 0.0 and approach_speed > 0.0:
			velocity += normal * approach_speed * carry_factor * delta * 4.0
		velocity = velocity.limit_length(max_speed)


func _set_last_touch(player: HexPlayer) -> void:
	last_touch_player_id = player.player_id
	last_touch_team_id = player.team_id


func _handle_player_collision(collision: KinematicCollision2D, player: HexPlayer) -> void:
	var normal := collision.get_normal()
	var forward_speed := maxf(player.velocity.dot(normal), 0.0)
	var tangent_velocity := player.velocity - normal * player.velocity.dot(normal)
	var contact_push := clampf(min_contact_push + forward_speed * player_hit_multiplier, min_contact_push, max_contact_push)
	position += normal * 0.75
	
	var outward_speed := velocity.dot(normal)
	velocity = velocity.slide(normal) * 0.9 + normal * maxf(contact_push, outward_speed)
	
	velocity += tangent_velocity * tangent_carry_factor
	velocity = velocity.limit_length(max_speed)
	player.apply_ball_recoil(-normal * minf(contact_push, player_recoil_strength))
	_set_last_touch(player)


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

	# Üst/alt sınır: her zaman saha içinde kal
	position.y = clampf(position.y, -half_field.y + margin, half_field.y - margin)

	# Sol/sağ sınır: kale ağzı yüksekliğinde ise goal_depth kadar dışarı çıkabilir
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

	# If distance is too large (teleport/reset) or ball just became active, snap
	if position.distance_to(target_pos) > NET_SNAP_THRESHOLD or not active:
		position = target_pos
		velocity = target_vel
		_net_interpolating = false
	else:
		_net_target_position = target_pos
		_net_target_velocity = target_vel
		_net_interpolating = true
