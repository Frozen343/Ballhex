extends Control
class_name MainMenu

const UI := preload("res://Scripts/UI/BallhexUI.gd")

const MODE_RANKED := "ranked"
const MODE_CUSTOM := "custom"
const MODE_TRAINING := "training"

@onready var header_card: Panel = $Margin/Layout/HeaderCard
@onready var profile_badge: Panel = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/ProfileBadge
@onready var profile_initial: Label = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/ProfileBadge/ProfileInitial
@onready var nick_label: Label = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/ProfileText/NickLabel
@onready var settings_button: Button = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/HeaderActions/SettingsButton
@onready var change_nick_button: Button = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/HeaderActions/ChangeNickButton
@onready var quit_button: Button = $Margin/Layout/HeaderCard/HeaderMargin/HeaderRow/HeaderActions/QuitButton
@onready var ranked_mode_button: Button = $Margin/Layout/ModesRow/RankedModeButton
@onready var custom_mode_button: Button = $Margin/Layout/ModesRow/CustomModeButton
@onready var training_mode_button: Button = $Margin/Layout/ModesRow/TrainingModeButton
@onready var ranked_panel: Panel = $Margin/Layout/ContentStack/RankedPanel
@onready var custom_panel: Panel = $Margin/Layout/ContentStack/CustomPanel
@onready var training_panel: Panel = $Margin/Layout/ContentStack/TrainingPanel
@onready var ranked_copy_label: Label = $Margin/Layout/ContentStack/RankedPanel/RankedMargin/RankedLayout/RankedHeader/RankedCopy
@onready var ranked_solo_button: Button = $Margin/Layout/ContentStack/RankedPanel/RankedMargin/RankedLayout/RankedCards/RankedSoloButton
@onready var ranked_3v3_button: Button = $Margin/Layout/ContentStack/RankedPanel/RankedMargin/RankedLayout/RankedCards/Ranked3v3Button
@onready var ranked_5v5_button: Button = $Margin/Layout/ContentStack/RankedPanel/RankedMargin/RankedLayout/RankedCards/Ranked5v5Button
@onready var stats_label: Label = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/BrowserHeader/HeaderText/Stats
@onready var refresh_button: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/BrowserHeader/RefreshButton
@onready var status_card: Panel = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/StatusCard
@onready var status_label: Label = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/StatusCard/StatusMargin/StatusLabel
@onready var room_list: VBoxContainer = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/RoomScroll/RoomList
@onready var empty_state_label: Label = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/RoomScroll/RoomList/EmptyState
@onready var join_button: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/ActionRow/JoinButton
@onready var cancel_button: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/BrowserColumn/ActionRow/CancelButton
@onready var create_card: Panel = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard
@onready var lobby_name_input: LineEdit = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard/CreateMargin/CreateVBox/LobbyNameInput
@onready var max_players_input: SpinBox = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard/CreateMargin/CreateVBox/MaxPlayersInput
@onready var create_button: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard/CreateMargin/CreateVBox/CreateButton
@onready var chip_one: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard/CreateMargin/CreateVBox/ModeChipRow/ChipOne
@onready var chip_two: Button = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/CreateCard/CreateMargin/CreateVBox/ModeChipRow/ChipTwo
@onready var tip_card: Panel = $Margin/Layout/ContentStack/CustomPanel/CustomMargin/CustomLayout/CreateColumn/TipCard
@onready var quick_match_button: Button = $Margin/Layout/ContentStack/TrainingPanel/TrainingMargin/TrainingLayout/TrainingActionRow/QuickMatchButton
@onready var back_to_custom_button: Button = $Margin/Layout/ContentStack/TrainingPanel/TrainingMargin/TrainingLayout/TrainingActionRow/BackToCustomButton

var _displayed_lobbies: Array = []
var _selected_lobby_index := -1
var _room_buttons: Array[Button] = []
var _active_mode := MODE_CUSTOM


func _ready() -> void:
	_apply_styles()
	_update_profile_header()
	_connect_signals()
	_set_mode(MODE_CUSTOM)
	status_label.text = "Pick a room or create your own."
	cancel_button.visible = false
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()
	else:
		status_label.text = "Web room list is available in browser builds. Use local match for instant testing."
		stats_label.text = "Local flow ready"


func _apply_styles() -> void:
	UI.style_panel(header_card, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(profile_badge, UI.avatar_color(GameSettings.avatar_id), Color(1, 1, 1, 0.18), 38)
	UI.style_panel(ranked_panel, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(custom_panel, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(training_panel, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	UI.style_panel(status_card, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.08), 24)
	UI.style_panel(create_card, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.08), 24)
	UI.style_panel(tip_card, UI.COLOR_SURFACE_SOFT, Color(1, 1, 1, 0.08), 24)
	UI.style_button(settings_button, "ghost", 18)
	UI.style_button(change_nick_button, "secondary", 18)
	UI.style_button(quit_button, "danger", 18)
	UI.style_button(refresh_button, "secondary", 18)
	UI.style_button(join_button, "blue", 20)
	UI.style_button(cancel_button, "ghost", 18)
	UI.style_button(create_button, "primary", 20)
	UI.style_button(chip_one, "chip", 15)
	UI.style_button(chip_two, "chip", 15)
	UI.style_button(ranked_solo_button, "secondary", 20)
	UI.style_button(ranked_3v3_button, "secondary", 20)
	UI.style_button(ranked_5v5_button, "secondary", 20)
	UI.style_button(quick_match_button, "primary", 20)
	UI.style_button(back_to_custom_button, "secondary", 18)
	UI.style_line_edit(lobby_name_input, 20)
	UI.style_spinbox(max_players_input)
	profile_initial.add_theme_color_override("font_color", UI.COLOR_TEXT)
	_refresh_mode_buttons()


func _update_profile_header() -> void:
	var display_name := GameSettings.player_name if GameSettings.has_player_name() else "Guest Player"
	nick_label.text = "%s  -  Profile badge %d" % [display_name, GameSettings.avatar_id + 1]
	profile_initial.text = display_name.left(1).to_upper()
	UI.style_panel(profile_badge, UI.avatar_color(GameSettings.avatar_id), Color(1, 1, 1, 0.18), 38)


func _connect_signals() -> void:
	settings_button.pressed.connect(_on_settings_pressed)
	change_nick_button.pressed.connect(_on_change_nick_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	create_button.pressed.connect(_on_host_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	ranked_mode_button.pressed.connect(func() -> void: _set_mode(MODE_RANKED))
	custom_mode_button.pressed.connect(func() -> void: _set_mode(MODE_CUSTOM))
	training_mode_button.pressed.connect(func() -> void: _set_mode(MODE_TRAINING))
	ranked_solo_button.pressed.connect(func() -> void: _set_ranked_status("1v1 solo queue shell selected. Ready for real matchmaking hooks."))
	ranked_3v3_button.pressed.connect(func() -> void: _set_ranked_status("3v3 party queue shell selected. Party room visuals can plug in next."))
	ranked_5v5_button.pressed.connect(func() -> void: _set_ranked_status("5v5 party queue shell selected. Full squad flow placeholder is now visible."))
	quick_match_button.pressed.connect(_on_quick_match_pressed)
	back_to_custom_button.pressed.connect(func() -> void: _set_mode(MODE_CUSTOM))

	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobbies_updated.connect(_on_lobbies_updated)
	NetworkManager.lobby_hosted.connect(_on_lobby_hosted)
	NetworkManager.matchmaking_status_changed.connect(_on_matchmaking_status_changed)
	NetworkManager.matchmaking_failed.connect(_on_matchmaking_failed)


func _set_mode(mode_name: String) -> void:
	_active_mode = mode_name
	ranked_panel.visible = mode_name == MODE_RANKED
	custom_panel.visible = mode_name == MODE_CUSTOM
	training_panel.visible = mode_name == MODE_TRAINING
	_refresh_mode_buttons()


func _refresh_mode_buttons() -> void:
	UI.style_button(ranked_mode_button, "secondary" if _active_mode != MODE_RANKED else "blue", 21)
	UI.style_button(custom_mode_button, "secondary" if _active_mode != MODE_CUSTOM else "primary", 21)
	UI.style_button(training_mode_button, "secondary" if _active_mode != MODE_TRAINING else "ghost", 21)


func _set_ranked_status(message: String) -> void:
	ranked_copy_label.text = message


func _on_host_pressed() -> void:
	if not NetworkManager.uses_web_lobbies():
		var error := NetworkManager.host_game(
			NetworkManager.DEFAULT_PORT,
			lobby_name_input.text,
			int(max_players_input.value)
		)
		if error != OK:
			status_label.text = "Could not host room."
			return
		SceneRouter.go_to_match({"online": true})
		return

	status_label.text = "Creating room..."
	_set_buttons_enabled(false)
	cancel_button.visible = true
	NetworkManager.host_game(
		NetworkManager.DEFAULT_PORT,
		lobby_name_input.text,
		int(max_players_input.value)
	)


func _on_join_pressed() -> void:
	if not NetworkManager.uses_web_lobbies():
		status_label.text = "Room browser is only available in browser builds right now."
		return

	var lobby: Dictionary = _get_selected_lobby()
	if lobby.is_empty():
		status_label.text = "Select a lobby first."
		return

	status_label.text = "Joining room..."
	_set_buttons_enabled(false)
	cancel_button.visible = true
	NetworkManager.lobby_max_players = int(lobby.get("maxPlayers", 2))
	NetworkManager.active_match_duration_seconds = float(lobby.get("matchDurationSeconds", GameSettings.MATCH_DURATION_SECONDS))
	NetworkManager.active_score_limit = int(lobby.get("scoreLimit", GameSettings.DEFAULT_SCORE_LIMIT))
	NetworkManager.join_game(str(lobby.get("id", "")))


func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing custom lobbies..."
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()


func _on_settings_pressed() -> void:
	status_label.text = "Settings shell is ready for the next UI pass."


func _on_change_nick_pressed() -> void:
	SceneRouter.go_to_nickname()


func _on_quick_match_pressed() -> void:
	NetworkManager.disconnect_game()
	SceneRouter.go_to_match()


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_game()
	_set_buttons_enabled(true)
	cancel_button.visible = false
	status_label.text = "Cancelled."
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()


func _on_lobbies_updated(lobbies: Array) -> void:
	_displayed_lobbies = lobbies
	if _selected_lobby_index >= _displayed_lobbies.size():
		_selected_lobby_index = -1
	_rebuild_room_cards()

	var room_count := _displayed_lobbies.size()
	var players_in_rooms := 0
	for lobby_data in _displayed_lobbies:
		if typeof(lobby_data) == TYPE_DICTIONARY:
			players_in_rooms += int(lobby_data.get("playerCount", 0))

	stats_label.text = "%d players in %d rooms" % [players_in_rooms, room_count]
	status_label.text = "No open rooms right now." if room_count == 0 else "%d custom rooms ready." % room_count
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _rebuild_room_cards() -> void:
	for button in _room_buttons:
		if button != null and is_instance_valid(button):
			button.queue_free()
	_room_buttons.clear()

	empty_state_label.visible = _displayed_lobbies.is_empty()
	if _displayed_lobbies.is_empty():
		return

	for index in _displayed_lobbies.size():
		var lobby_data: Variant = _displayed_lobbies[index]
		if typeof(lobby_data) != TYPE_DICTIONARY:
			continue
		var room_data: Dictionary = lobby_data
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 88)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = _format_room_card_text(room_data)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.style_button(button, "secondary", 18)
		button.pressed.connect(_on_room_card_pressed.bind(index))
		room_list.add_child(button)
		room_list.move_child(button, room_list.get_child_count() - 1)
		_room_buttons.append(button)

	_refresh_room_selection()


func _format_room_card_text(lobby_data: Dictionary) -> String:
	var lobby_name := str(lobby_data.get("name", "Room"))
	var player_count := int(lobby_data.get("playerCount", 1))
	var max_players := int(lobby_data.get("maxPlayers", 2))
	var duration_minutes := int(round(float(lobby_data.get("matchDurationSeconds", GameSettings.MATCH_DURATION_SECONDS)) / 60.0))
	var score_limit := int(lobby_data.get("scoreLimit", GameSettings.DEFAULT_SCORE_LIMIT))
	return "%s\n%d/%d players   -   %dm match   -   %dg cap" % [lobby_name, player_count, max_players, duration_minutes, score_limit]


func _on_room_card_pressed(index: int) -> void:
	_selected_lobby_index = index
	_refresh_room_selection()
	var lobby: Dictionary = _get_selected_lobby()
	if lobby.is_empty():
		return
	status_label.text = "%s selected. Ready to join." % str(lobby.get("name", "Room"))


func _refresh_room_selection() -> void:
	for index in _room_buttons.size():
		var button := _room_buttons[index]
		if button == null or not is_instance_valid(button):
			continue
		UI.style_button(button, "blue" if index == _selected_lobby_index else "secondary", 18)


func _get_selected_lobby() -> Dictionary:
	if _selected_lobby_index < 0 or _selected_lobby_index >= _displayed_lobbies.size():
		return {}
	var lobby_data: Variant = _displayed_lobbies[_selected_lobby_index]
	if typeof(lobby_data) != TYPE_DICTIONARY:
		return {}
	var lobby: Dictionary = lobby_data
	return lobby


func _on_lobby_hosted(_lobby_id: String, lobby_name: String) -> void:
	status_label.text = "Room ready: %s" % lobby_name
	SceneRouter.go_to_match({"online": true})


func _on_matchmaking_status_changed(message: String) -> void:
	if not message.is_empty():
		if _active_mode == MODE_RANKED:
			_set_ranked_status(message)
		else:
			status_label.text = message


func _on_matchmaking_failed(message: String) -> void:
	if _active_mode == MODE_RANKED:
		_set_ranked_status(message)
	else:
		status_label.text = message
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_connection_established() -> void:
	if not NetworkManager.is_host():
		SceneRouter.go_to_match({"online": true})


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_buttons_enabled(enabled: bool) -> void:
	refresh_button.disabled = not enabled
	join_button.disabled = not enabled
	create_button.disabled = not enabled
	settings_button.disabled = not enabled
	change_nick_button.disabled = not enabled
	quit_button.disabled = not enabled
	lobby_name_input.editable = enabled
	max_players_input.editable = enabled
	for button in _room_buttons:
		if button != null and is_instance_valid(button):
			button.disabled = not enabled


func _exit_tree() -> void:
	if NetworkManager.connection_established.is_connected(_on_connection_established):
		NetworkManager.connection_established.disconnect(_on_connection_established)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.lobbies_updated.is_connected(_on_lobbies_updated):
		NetworkManager.lobbies_updated.disconnect(_on_lobbies_updated)
	if NetworkManager.lobby_hosted.is_connected(_on_lobby_hosted):
		NetworkManager.lobby_hosted.disconnect(_on_lobby_hosted)
	if NetworkManager.matchmaking_status_changed.is_connected(_on_matchmaking_status_changed):
		NetworkManager.matchmaking_status_changed.disconnect(_on_matchmaking_status_changed)
	if NetworkManager.matchmaking_failed.is_connected(_on_matchmaking_failed):
		NetworkManager.matchmaking_failed.disconnect(_on_matchmaking_failed)
