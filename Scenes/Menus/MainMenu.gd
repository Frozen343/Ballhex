extends Control
class_name MainMenu

@onready var title_label: Label = $Margin/Layout/ListPanel/Margin/VBox/Header/TitleRow/Title
@onready var stats_label: Label = $Margin/Layout/ListPanel/Margin/VBox/Header/TitleRow/Stats
@onready var nick_label: Label = $Margin/Layout/ListPanel/Margin/VBox/Header/NickLabel
@onready var columns_label: Label = $Margin/Layout/ListPanel/Margin/VBox/Columns
@onready var lobby_name_input: LineEdit = $Margin/Layout/Sidebar/SidebarVBox/CreatePanel/CreateVBox/LobbyNameInput
@onready var max_players_input: SpinBox = $Margin/Layout/Sidebar/SidebarVBox/CreatePanel/CreateVBox/MaxPlayersInput
@onready var refresh_button: Button = $Margin/Layout/Sidebar/SidebarVBox/RefreshButton
@onready var join_button: Button = $Margin/Layout/Sidebar/SidebarVBox/JoinButton
@onready var create_button: Button = $Margin/Layout/Sidebar/SidebarVBox/CreateButton
@onready var settings_button: Button = $Margin/Layout/Sidebar/SidebarVBox/SettingsButton
@onready var change_nick_button: Button = $Margin/Layout/Sidebar/SidebarVBox/ChangeNickButton
@onready var quit_button: Button = $Margin/Layout/Sidebar/SidebarVBox/QuitButton
@onready var status_label: Label = $Margin/Layout/Sidebar/SidebarVBox/StatusLabel
@onready var cancel_button: Button = $Margin/Layout/Sidebar/SidebarVBox/CancelButton
@onready var lobby_list: ItemList = $Margin/Layout/ListPanel/Margin/VBox/LobbyList

var _displayed_lobbies: Array = []


func _ready() -> void:
	title_label.text = "Room list"
	columns_label.text = "Name                          Players   Rules"
	nick_label.text = "Nick: %s" % GameSettings.player_name
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	create_button.pressed.connect(_on_host_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	change_nick_button.pressed.connect(_on_change_nick_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	lobby_list.item_selected.connect(_on_lobby_selected)
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobbies_updated.connect(_on_lobbies_updated)
	NetworkManager.lobby_hosted.connect(_on_lobby_hosted)
	NetworkManager.matchmaking_status_changed.connect(_on_matchmaking_status_changed)
	NetworkManager.matchmaking_failed.connect(_on_matchmaking_failed)

	status_label.text = "Pick a room or create your own."
	cancel_button.visible = false
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()
	else:
		status_label.text = "Desktop mode uses direct IP join."


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
		status_label.text = "Web room list is only available in browser builds."
		return

	var selected := lobby_list.get_selected_items()
	if selected.is_empty():
		status_label.text = "Select a room first."
		return

	var lobby_index: int = selected[0]
	if lobby_index < 0 or lobby_index >= _displayed_lobbies.size():
		status_label.text = "Selected room could not be found."
		return

	var lobby: Dictionary = _displayed_lobbies[lobby_index]
	status_label.text = "Joining room..."
	_set_buttons_enabled(false)
	cancel_button.visible = true
	NetworkManager.lobby_max_players = int(lobby.get("maxPlayers", 2))
	NetworkManager.active_match_duration_seconds = float(lobby.get("matchDurationSeconds", GameSettings.MATCH_DURATION_SECONDS))
	NetworkManager.active_score_limit = int(lobby.get("scoreLimit", GameSettings.DEFAULT_SCORE_LIMIT))
	NetworkManager.join_game(str(lobby.get("id", "")))


func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing room list..."
	NetworkManager.refresh_lobbies()


func _on_settings_pressed() -> void:
	status_label.text = "Settings panel is not wired yet."


func _on_change_nick_pressed() -> void:
	SceneRouter.go_to_nickname()


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_game()
	_set_buttons_enabled(true)
	cancel_button.visible = false
	status_label.text = "Cancelled."
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()


func _on_lobby_selected(index: int) -> void:
	if index < 0 or index >= _displayed_lobbies.size():
		return
	var lobby: Dictionary = _displayed_lobbies[index]
	var lobby_name := str(lobby.get("name", "Room"))
	var player_count := int(lobby.get("playerCount", 1))
	var max_players := int(lobby.get("maxPlayers", 2))
	var duration_minutes := int(round(float(lobby.get("matchDurationSeconds", GameSettings.MATCH_DURATION_SECONDS)) / 60.0))
	var score_limit := int(lobby.get("scoreLimit", GameSettings.DEFAULT_SCORE_LIMIT))
	status_label.text = "%s selected (%d/%d)  %dm / %dg." % [lobby_name, player_count, max_players, duration_minutes, score_limit]


func _on_lobbies_updated(lobbies: Array) -> void:
	_displayed_lobbies = lobbies
	lobby_list.clear()

	for lobby_data in _displayed_lobbies:
		if typeof(lobby_data) != TYPE_DICTIONARY:
			continue
		lobby_list.add_item(_format_room_row(lobby_data))

	var room_count := _displayed_lobbies.size()
	var players_in_rooms := 0
	for lobby_data in _displayed_lobbies:
		if typeof(lobby_data) == TYPE_DICTIONARY:
			players_in_rooms += int(lobby_data.get("playerCount", 0))

	stats_label.text = "%d players in %d rooms" % [players_in_rooms, room_count]
	status_label.text = "No open rooms right now." if room_count == 0 else "%d rooms available." % room_count
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _format_room_row(lobby_data: Dictionary) -> String:
	var lobby_name := str(lobby_data.get("name", "Room"))
	var player_count := int(lobby_data.get("playerCount", 1))
	var max_players := int(lobby_data.get("maxPlayers", 2))
	var duration_minutes := int(round(float(lobby_data.get("matchDurationSeconds", GameSettings.MATCH_DURATION_SECONDS)) / 60.0))
	var score_limit := int(lobby_data.get("scoreLimit", GameSettings.DEFAULT_SCORE_LIMIT))
	return "%s   %d/%d   %dm/%dg" % [lobby_name, player_count, max_players, duration_minutes, score_limit]


func _on_lobby_hosted(_lobby_id: String, lobby_name: String) -> void:
	status_label.text = "Room ready: %s" % lobby_name
	SceneRouter.go_to_match({"online": true})


func _on_matchmaking_status_changed(message: String) -> void:
	if not message.is_empty():
		status_label.text = message


func _on_matchmaking_failed(message: String) -> void:
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
