extends Node
class_name CooldownComponent

@export var duration := 0.3
var remaining := 0.0


func _process(delta: float) -> void:
	if remaining > 0.0:
		remaining = maxf(0.0, remaining - delta)


func is_ready() -> bool:
	return remaining <= 0.0


func trigger() -> void:
	remaining = duration


func reset() -> void:
	remaining = 0.0
