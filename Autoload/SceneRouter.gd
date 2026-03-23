extends Node

signal screen_requested(screen_name: String, payload: Dictionary)

const SCREEN_MAIN_MENU := "main_menu"
const SCREEN_MATCH := "match"


func go_to_main_menu() -> void:
	screen_requested.emit(SCREEN_MAIN_MENU, {})


func go_to_match(payload: Dictionary = {}) -> void:
	screen_requested.emit(SCREEN_MATCH, payload)
