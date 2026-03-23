extends RefCounted
class_name VelocityMotor2D


static func update_velocity(current: Vector2, input_direction: Vector2, max_speed: float, acceleration: float, deceleration: float, delta: float) -> Vector2:
	if input_direction.length_squared() > 0.0:
		return current.move_toward(input_direction * max_speed, acceleration * delta)
	return current.move_toward(Vector2.ZERO, deceleration * delta)
