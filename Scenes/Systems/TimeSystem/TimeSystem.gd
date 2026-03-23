extends Node
class_name MatchTimeSystem

signal time_changed(remaining_seconds: float)
signal time_expired

var match_duration := GameSettings.MATCH_DURATION_SECONDS
var remaining_seconds := GameSettings.MATCH_DURATION_SECONDS
var running := false


func _process(delta: float) -> void:
	if not running:
		return
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	time_changed.emit(remaining_seconds)
	if remaining_seconds <= 0.0:
		running = false
		time_expired.emit()


func setup(duration_seconds: float) -> void:
	match_duration = duration_seconds
	remaining_seconds = duration_seconds
	time_changed.emit(remaining_seconds)


func start() -> void:
	running = true


func stop() -> void:
	running = false


func reset() -> void:
	remaining_seconds = match_duration
	running = false
	time_changed.emit(remaining_seconds)
