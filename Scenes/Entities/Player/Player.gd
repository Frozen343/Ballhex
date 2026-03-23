extends CharacterBody2D
class_name HexPlayer

signal kick_attempted(player: HexPlayer)

@export var player_id := 1
@export var team_id := GameEnums.TeamId.RED
@export var display_name := "P1"
@export var move_speed := 144.0
@export var acceleration := 540.0
@export var deceleration := 340.0
@export var kick_strength := 420.0
@export var kick_contact_margin := 6.0
@export var body_push_strength := 60.0
@export var body_radius := GameSettings.PLAYER_RADIUS
@export var ball_recoil_factor := 0.1
@export var player_push_transfer := 0.88
@export var out_of_bounds_margin := 80.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var kick_cooldown: CooldownComponent = $KickCooldown
@onready var name_label: Label = $NameLabel
@onready var initials_label: Label = $InitialsLabel

var input_enabled := false
var spawn_position := Vector2.ZERO
var facing_direction := Vector2.RIGHT
var _input_profile: Dictionary = {}
var _ball: MatchBall
var _kick_flash_strength := 0.0

# Network
var _remote_input_direction := Vector2.ZERO
var _remote_kick_requested := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	safe_margin = 0.02
	add_to_group("players")
	_input_profile = InputProfiles.get_profile(player_id)
	spawn_position = position
	if team_id == GameEnums.TeamId.BLUE:
		facing_direction = Vector2.LEFT
	_update_name_label()
	_update_collision_shape()
	queue_redraw()


func _physics_process(delta: float) -> void:
	# Client tarafında fizik çalıştırma — state host'tan gelecek
	if NetworkManager.is_online and not NetworkManager.is_host():
		_send_local_input_to_host()
		_kick_flash_strength = move_toward(_kick_flash_strength, 0.0, delta * 4.5)
		queue_redraw()
		return

	var needs_redraw := false
	var previous_facing := facing_direction
	var previous_flash := _kick_flash_strength
	_kick_flash_strength = move_toward(_kick_flash_strength, 0.0, delta * 4.5)
	if input_enabled:
		var input_direction := _get_effective_input()
		if input_direction.length_squared() > 0.0:
			facing_direction = input_direction.normalized()
		velocity = VelocityMotor2D.update_velocity(
			velocity,
			input_direction,
			move_speed,
			acceleration,
			deceleration,
			delta
		)
		move_and_slide()
		_resolve_player_overlaps()
		_constrain_to_pitch()
		var kick_pressed := false
		if _is_local_player():
			kick_pressed = Input.is_action_just_pressed(_get_local_profile()["kick"])
		else:
			kick_pressed = _remote_kick_requested
			_remote_kick_requested = false
		if kick_pressed:
			_trigger_kick_flash()
			_attempt_kick(input_direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		if velocity.length_squared() > 0.001:
			move_and_slide()
			_resolve_player_overlaps()
			_constrain_to_pitch()
	if previous_facing != facing_direction or absf(previous_flash - _kick_flash_strength) > 0.001:
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func assign_ball(ball: MatchBall) -> void:
	_ball = ball


func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if not input_enabled:
		velocity = Vector2.ZERO


func reset_to_spawn() -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	kick_cooldown.reset()
	_kick_flash_strength = 0.0


func set_spawn_position(value: Vector2) -> void:
	spawn_position = value
	position = value


func get_team_color() -> Color:
	return Helpers.team_color(team_id)


func _is_local_player() -> bool:
	if not NetworkManager.is_online:
		return true
	if NetworkManager.is_host() and player_id == 1:
		return true
	if not NetworkManager.is_host() and player_id == 2:
		return true
	return false


func _get_effective_input() -> Vector2:
	if _is_local_player():
		return _get_local_input()
	else:
		return _remote_input_direction


func _get_local_input() -> Vector2:
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
	var kick := Input.is_action_just_pressed(profile["kick"])
	_rpc_send_input.rpc_id(1, dir.x, dir.y, kick)


func _get_local_profile() -> Dictionary:
	# Online modda her oyuncu kendi bilgisayarında WASD kullanır
	if NetworkManager.is_online:
		return InputProfiles.get_profile(1)
	return _input_profile


@rpc("any_peer", "unreliable", "call_remote")
func _rpc_send_input(dir_x: float, dir_y: float, kick: bool) -> void:
	_remote_input_direction = Vector2(dir_x, dir_y)
	if kick:
		_remote_kick_requested = true


func build_net_state() -> Dictionary:
	return {
		"px": position.x,
		"py": position.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"fx": facing_direction.x,
		"fy": facing_direction.y,
		"kf": _kick_flash_strength
	}


func apply_net_state(state: Dictionary) -> void:
	position = Vector2(state["px"], state["py"])
	velocity = Vector2(state["vx"], state["vy"])
	facing_direction = Vector2(state["fx"], state["fy"])
	_kick_flash_strength = state["kf"]
	queue_redraw()


func _attempt_kick(input_direction: Vector2) -> void:
	if _ball == null or not kick_cooldown.is_ready():
		return

	var to_ball := _ball.position - position
	var contact_distance := body_radius + _ball.radius + kick_contact_margin
	if to_ball.length() > contact_distance:
		return

	var kick_direction := facing_direction
	if input_direction.length_squared() > 0.0:
		kick_direction = input_direction.normalized()
	elif to_ball.length_squared() > 0.0:
		kick_direction = to_ball.normalized()

	kick_direction = (kick_direction + to_ball.normalized() * 0.65).normalized()
	_ball.apply_kick_impulse(kick_direction, kick_strength, self)
	kick_cooldown.trigger()
	GameEvents.emit_ball_kicked(player_id, team_id)
	kick_attempted.emit(self)


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
	var team_color := get_team_color()
	var deep_color := GameSettings.COLOR_RED_TEAM_DEEP if team_id == GameEnums.TeamId.RED else GameSettings.COLOR_BLUE_TEAM_DEEP
	draw_circle(Vector2(0.0, 4.0), body_radius - 2.0, Color(0.0, 0.0, 0.0, 0.08))
	draw_circle(Vector2.ZERO, body_radius, team_color)
	draw_circle(Vector2(-7.0, -7.0), body_radius * 0.42, Color(1.0, 1.0, 1.0, 0.16))
	draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 48, Color("111111"), 3.0)
	draw_arc(Vector2.ZERO, body_radius - 5.0, 0.3, 2.4, 18, deep_color, 3.0)
	var aim_end := facing_direction.normalized() * (body_radius - 5.0)
	draw_line(Vector2.ZERO, aim_end, Color(1.0, 1.0, 1.0, 0.45), 2.0)
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
	velocity += impulse * ball_recoil_factor


func _trigger_kick_flash() -> void:
	_kick_flash_strength = 1.0
	queue_redraw()


func _resolve_player_overlaps() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as HexPlayer
		if other == null or other == self:
			continue
		if player_id > other.player_id:
			continue

		var offset := other.position - position
		var distance := offset.length()
		var minimum_distance := body_radius + other.body_radius
		if distance >= minimum_distance:
			continue

		var normal := Vector2.RIGHT
		if distance > 0.001:
			normal = offset / distance
		elif other.facing_direction.length_squared() > 0.01:
			normal = other.facing_direction.normalized()

		# Pozisyon düzeltmesi — eşit olarak ayır
		var correction := (minimum_distance - distance) * 0.5
		position -= normal * correction
		other.position += normal * correction

		# Her iki oyuncunun normal eksenindeki hızını hesapla
		var self_along := velocity.dot(normal)
		var other_along := other.velocity.dot(normal)

		# İki oyuncu da birbirine doğru gidiyorsa → eşit durdurma
		var self_pushing := self_along > 0.0
		var other_pushing := other_along < 0.0

		if self_pushing and other_pushing:
			# Karşılıklı itme: ikisini de normal ekseninde durdur
			velocity -= normal * self_along
			other.velocity -= normal * other_along
		elif self_pushing:
			# Sadece self itiyor → kuvvet transferi
			var transfer := self_along * player_push_transfer
			velocity -= normal * transfer * 0.5
			other.velocity += normal * transfer * 0.5
		elif other_pushing:
			# Sadece other itiyor → kuvvet transferi
			var transfer := absf(other_along) * other.player_push_transfer
			other.velocity -= normal * (-transfer * 0.5)
			velocity -= normal * transfer * 0.5


func _constrain_to_pitch() -> void:
	var half_field := GameSettings.FIELD_SIZE * 0.5
	position.x = clampf(position.x, -half_field.x - out_of_bounds_margin, half_field.x + out_of_bounds_margin)
	position.y = clampf(position.y, -half_field.y - out_of_bounds_margin, half_field.y + out_of_bounds_margin)
