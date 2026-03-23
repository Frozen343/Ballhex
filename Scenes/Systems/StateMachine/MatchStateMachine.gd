extends Node
class_name MatchStateMachine

signal state_changed(previous_state: int, new_state: int)

var current_state := GameEnums.MatchState.BOOT


func transition_to(new_state: int) -> void:
	if current_state == new_state:
		return
	var previous_state := current_state
	current_state = new_state
	state_changed.emit(previous_state, new_state)


func is_in_state(test_state: int) -> bool:
	return current_state == test_state


func state_name() -> String:
	return GameEnums.MatchState.keys()[current_state]
