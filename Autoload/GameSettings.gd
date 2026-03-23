extends Node

const GAME_TITLE := "Hexball Prototype"
const FIELD_SIZE := Vector2(1600.0, 900.0)
const GOAL_MOUTH_HEIGHT := 280.0
const GOAL_DEPTH := 140.0
const WALL_THICKNESS := 40.0
const PLAYER_RADIUS := 28.0
const BALL_RADIUS := 16.0
const MATCH_DURATION_SECONDS := 120.0
const GOAL_PAUSE_DURATION := 2.0
const KICKOFF_COUNTDOWN := 3
const COUNTDOWN_STEP_DURATION := 0.75
const SETTINGS_FILE_PATH := "user://settings.cfg"
const DEFAULT_PLAYER_NAME := "Player"

const COLOR_FIELD_OUTER := Color("788f5d")
const COLOR_FIELD_DARK := Color("97bd85")
const COLOR_FIELD_LIGHT := Color("a9ce97")
const COLOR_FIELD_LINE := Color("edf8e8")
const COLOR_RED_TEAM := Color("f28c7f")
const COLOR_BLUE_TEAM := Color("8ca8f4")
const COLOR_RED_TEAM_DEEP := Color("d86d60")
const COLOR_BLUE_TEAM_DEEP := Color("6d88d9")
const COLOR_UI_BG := Color("12181d")
const COLOR_UI_PANEL := Color("1b242c")
const COLOR_UI_TEXT := Color("edf2f8")
const COLOR_UI_MUTED := Color("9fb0c2")

const INPUT_BINDINGS := {
	"p1_up": [KEY_W],
	"p1_down": [KEY_S],
	"p1_left": [KEY_A],
	"p1_right": [KEY_D],
	"p1_kick": [KEY_SPACE],
	"p1_dash": [KEY_SHIFT],
	"p2_up": [KEY_UP],
	"p2_down": [KEY_DOWN],
	"p2_left": [KEY_LEFT],
	"p2_right": [KEY_RIGHT],
	"p2_kick": [KEY_PERIOD],
	"p2_dash": [KEY_SLASH],
	"pause": [KEY_ESCAPE],
	"hard_pause": [KEY_P],
	"accept": [KEY_ENTER],
	"cancel": [KEY_BACKSPACE],
	"debug_toggle": [KEY_F3],
	"debug_reset_ball": [KEY_F5],
	"debug_reset_match": [KEY_F6],
	"debug_red_score": [KEY_F7],
	"debug_blue_score": [KEY_F8]
}

var debug_overlay_enabled := true
var player_name := ""


func _ready() -> void:
	_load_settings()
	_register_default_input_map()


func has_player_name() -> bool:
	return not player_name.strip_edges().is_empty()


func set_player_name(value: String) -> void:
	player_name = sanitize_player_name(value)
	_save_settings()


func sanitize_player_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		cleaned = DEFAULT_PLAYER_NAME
	if cleaned.length() > 18:
		cleaned = cleaned.substr(0, 18)
	return cleaned


func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_FILE_PATH)
	if error != OK:
		player_name = ""
		return
	player_name = sanitize_player_name(str(config.get_value("profile", "player_name", "")))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "player_name", player_name)
	config.save(SETTINGS_FILE_PATH)


func _register_default_input_map() -> void:
	for action_name in INPUT_BINDINGS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in INPUT_BINDINGS[action_name]:
			if _action_has_key(action_name, keycode):
				continue
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action_name, event)


func _action_has_key(action_name: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false
