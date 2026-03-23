extends Node

@onready var world: Node2D = $World
@onready var match_manager: MatchManager = $Managers/MatchManager
@onready var match_hud: MatchHUD = $UI/MatchHUD
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var end_match_panel: Control = $UI/EndMatchPanel
@onready var debug_overlay: DebugOverlay = $Debug/DebugOverlay


func _ready() -> void:
	_center_world()
	get_viewport().size_changed.connect(_center_world)
	_connect_ui()
	pause_menu.hide_panel()
	end_match_panel.visible = false
	debug_overlay.set_visible(GameSettings.debug_overlay_enabled)
	match_manager.start_new_match()


func _process(_delta: float) -> void:
	if debug_overlay.visible:
		debug_overlay.update_snapshot(match_manager.build_debug_snapshot())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match_manager.toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("hard_pause"):
		match_manager.toggle_hard_pause()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_toggle"):
		debug_overlay.visible = not debug_overlay.visible
		GameSettings.debug_overlay_enabled = debug_overlay.visible
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_reset_ball"):
		match_manager.reset_ball_only()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_reset_match"):
		match_manager.force_full_reset()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_red_score"):
		match_manager.add_debug_score(GameEnums.TeamId.RED)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_blue_score"):
		match_manager.add_debug_score(GameEnums.TeamId.BLUE)
		get_viewport().set_input_as_handled()


func _connect_ui() -> void:
	match_manager.score_changed.connect(match_hud.update_score)
	match_manager.timer_changed.connect(match_hud.update_timer)
	match_manager.announcement_requested.connect(match_hud.show_announcement)
	match_manager.pause_changed.connect(_on_pause_changed)
	match_manager.hard_pause_changed.connect(match_hud.set_pause_overlay_visible)
	match_manager.match_finished.connect(_on_match_finished)
	match_manager.state_updated.connect(debug_overlay.set_state_name)
	match_manager.room_state_changed.connect(pause_menu.update_room_state)

	pause_menu.resume_requested.connect(match_manager.toggle_pause)
	pause_menu.restart_requested.connect(match_manager.restart_match)
	pause_menu.menu_requested.connect(_return_to_menu)
	pause_menu.assign_red_requested.connect(match_manager.assign_peer_to_red)
	pause_menu.assign_blue_requested.connect(match_manager.assign_peer_to_blue)
	pause_menu.assign_spectator_requested.connect(match_manager.assign_peer_to_waiting)
	pause_menu.kick_requested.connect(match_manager.kick_peer)
	pause_menu.ban_requested.connect(match_manager.ban_peer)
	pause_menu.toggle_admin_requested.connect(match_manager.toggle_peer_admin)


func _center_world() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var content_size := Vector2(
		GameSettings.FIELD_SIZE.x + GameSettings.GOAL_DEPTH * 2.0 + 120.0,
		GameSettings.FIELD_SIZE.y + 140.0
	)
	var scale_factor := minf(
		(viewport_size.x - 40.0) / content_size.x,
		(viewport_size.y - 60.0) / content_size.y
	)
	world.scale = Vector2.ONE * minf(scale_factor, 1.0)
	world.position = viewport_size * 0.5


func _on_pause_changed(is_paused: bool) -> void:
	if is_paused:
		pause_menu.show_panel()
	else:
		pause_menu.hide_panel()


func _on_match_finished(title: String, _detail: String) -> void:
	if title.is_empty():
		return
	pause_menu.show_panel()


func _return_to_menu() -> void:
	NetworkManager.disconnect_game()
	SceneRouter.go_to_main_menu()
