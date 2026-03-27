extends Node

const MAIN_MENU_SCENE := preload("res://Scenes/Menus/MainMenu.tscn")
const WELCOME_SCENE := preload("res://Scenes/Menus/WelcomeScreen.tscn")
const NICKNAME_SCENE := preload("res://Scenes/Menus/NicknameScreen.tscn")
const MATCH_SCENE := preload("res://Scenes/Match/Match.tscn")

@onready var screen_root: Node = $ScreenRoot

var _current_screen: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SceneRouter.screen_requested.connect(_on_screen_requested)
	if GameSettings.has_profile():
		_show_screen(SceneRouter.SCREEN_MAIN_MENU, {})
	else:
		_show_screen(SceneRouter.SCREEN_WELCOME, {})


func _on_screen_requested(screen_name: String, payload: Dictionary) -> void:
	_show_screen(screen_name, payload)


func _show_screen(screen_name: String, payload: Dictionary) -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null

	match screen_name:
		SceneRouter.SCREEN_WELCOME:
			_current_screen = WELCOME_SCENE.instantiate()
		SceneRouter.SCREEN_NICKNAME:
			_current_screen = NICKNAME_SCENE.instantiate()
		SceneRouter.SCREEN_MATCH:
			_current_screen = MATCH_SCENE.instantiate()
		_:
			_current_screen = MAIN_MENU_SCENE.instantiate()

	screen_root.add_child(_current_screen)

	if payload.size() > 0 and _current_screen.has_method("apply_payload"):
		_current_screen.call("apply_payload", payload)
