extends RefCounted
class_name MathUtils


static func safe_normalized(value: Vector2, fallback: Vector2 = Vector2.RIGHT) -> Vector2:
	if value.length_squared() <= 0.0001:
		return fallback
	return value.normalized()


static func accelerate_toward(current: Vector2, target: Vector2, amount: float) -> Vector2:
	return current.move_toward(target, amount)
