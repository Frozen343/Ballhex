extends RefCounted
class_name MomentumPhysics2D


class CollisionResult2D:
	extends RefCounted

	var collided: bool = false
	var position_a: Vector2 = Vector2.ZERO
	var position_b: Vector2 = Vector2.ZERO
	var velocity_a: Vector2 = Vector2.ZERO
	var velocity_b: Vector2 = Vector2.ZERO


static func apply_drive_force(
	current_velocity: Vector2,
	input_direction: Vector2,
	drive_force: float,
	mass: float,
	delta: float
) -> Vector2:
	if input_direction.length_squared() <= 0.0:
		return current_velocity
	var safe_mass: float = maxf(mass, 0.001)
	var acceleration: Vector2 = input_direction.normalized() * (drive_force / safe_mass)
	return current_velocity + acceleration * delta


static func apply_surface_friction(
	current_velocity: Vector2,
	friction_strength: float,
	mass: float,
	delta: float,
	weight_friction_scale: float = 0.08
) -> Vector2:
	var speed: float = current_velocity.length()
	if speed <= 0.0001:
		return Vector2.ZERO
	var effective_friction: float = friction_strength * (1.0 + mass * weight_friction_scale)
	var new_speed: float = maxf(speed - effective_friction * delta, 0.0)
	if new_speed <= 0.0001:
		return Vector2.ZERO
	return current_velocity * (new_speed / speed)


static func clamp_speed_along_direction(
	current_velocity: Vector2,
	direction: Vector2,
	max_speed: float
) -> Vector2:
	if direction.length_squared() <= 0.0:
		return current_velocity
	var dir: Vector2 = direction.normalized()
	var forward_speed: float = current_velocity.dot(dir)
	if forward_speed <= max_speed:
		return current_velocity
	return current_velocity - dir * (forward_speed - max_speed)


static func clamp_total_speed(current_velocity: Vector2, max_speed: float) -> Vector2:
	return current_velocity.limit_length(max_speed)


static func apply_impulse(current_velocity: Vector2, impulse: Vector2, mass: float) -> Vector2:
	var safe_mass: float = maxf(mass, 0.001)
	return current_velocity + impulse / safe_mass


static func bounce_velocity(current_velocity: Vector2, normal: Vector2, restitution: float) -> Vector2:
	return current_velocity.bounce(normal.normalized()) * clampf(restitution, 0.0, 1.5)


static func resolve_circle_collision(
	position_a: Vector2,
	velocity_a: Vector2,
	mass_a: float,
	radius_a: float,
	position_b: Vector2,
	velocity_b: Vector2,
	mass_b: float,
	radius_b: float,
	restitution: float,
	contact_friction: float,
	separation_bias: float = 0.05
) -> CollisionResult2D:
	var result: CollisionResult2D = CollisionResult2D.new()
	result.position_a = position_a
	result.position_b = position_b
	result.velocity_a = velocity_a
	result.velocity_b = velocity_b

	var offset: Vector2 = position_b - position_a
	var minimum_distance: float = radius_a + radius_b
	var distance_sq: float = offset.length_squared()
	if distance_sq >= minimum_distance * minimum_distance:
		return result

	var normal: Vector2 = Vector2.RIGHT
	var distance: float = sqrt(distance_sq)
	if distance > 0.0001:
		normal = offset / distance
	elif velocity_b.length_squared() > 0.0001:
		normal = velocity_b.normalized()
	elif velocity_a.length_squared() > 0.0001:
		normal = -velocity_a.normalized()

	var safe_mass_a: float = maxf(mass_a, 0.001)
	var safe_mass_b: float = maxf(mass_b, 0.001)
	var inv_mass_a: float = 1.0 / safe_mass_a
	var inv_mass_b: float = 1.0 / safe_mass_b
	var inv_mass_sum: float = inv_mass_a + inv_mass_b
	if inv_mass_sum <= 0.0:
		return result

	var penetration: float = maxf(minimum_distance - distance, 0.0)
	if penetration > 0.0:
		var correction: Vector2 = normal * ((penetration + separation_bias) / inv_mass_sum)
		result.position_a -= correction * inv_mass_a
		result.position_b += correction * inv_mass_b

	var relative_velocity: Vector2 = result.velocity_b - result.velocity_a
	var velocity_along_normal: float = relative_velocity.dot(normal)
	if velocity_along_normal < 0.0:
		var normal_impulse_strength: float = -(1.0 + restitution) * velocity_along_normal / inv_mass_sum
		var normal_impulse: Vector2 = normal * normal_impulse_strength
		result.velocity_a -= normal_impulse * inv_mass_a
		result.velocity_b += normal_impulse * inv_mass_b

		var post_relative_velocity: Vector2 = result.velocity_b - result.velocity_a
		var tangent_velocity: Vector2 = post_relative_velocity - normal * post_relative_velocity.dot(normal)
		if tangent_velocity.length_squared() > 0.0001 and contact_friction > 0.0:
			var tangent: Vector2 = tangent_velocity.normalized()
			var tangent_impulse_strength: float = -post_relative_velocity.dot(tangent) / inv_mass_sum
			var tangent_limit: float = absf(normal_impulse_strength) * contact_friction
			tangent_impulse_strength = clampf(tangent_impulse_strength, -tangent_limit, tangent_limit)
			var tangent_impulse: Vector2 = tangent * tangent_impulse_strength
			result.velocity_a -= tangent_impulse * inv_mass_a
			result.velocity_b += tangent_impulse * inv_mass_b

	result.collided = true
	return result
