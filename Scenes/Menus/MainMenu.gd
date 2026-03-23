extends Control
class_name MainMenu

@onready var play_button: Button = $Center/Panel/VBox/PlayButton
@onready var host_button: Button = $Center/Panel/VBox/HostButton
@onready var join_button: Button = $Center/Panel/VBox/JoinButton
@onready var quit_button: Button = $Center/Panel/VBox/QuitButton
@onready var ip_input: LineEdit = $Center/Panel/VBox/JoinRow/IpInput
@onready var status_label: Label = $Center/Panel/VBox/StatusLabel
@onready var join_row: HBoxContainer = $Center/Panel/VBox/JoinRow
@onready var cancel_button: Button = $Center/Panel/VBox/CancelButton
@onready var lobby_name_input: LineEdit = $Center/Panel/VBox/LobbyNameInput
@onready var lobby_controls: HBoxContainer = $Center/Panel/VBox/LobbyControls
@onready var refresh_button: Button = $Center/Panel/VBox/LobbyControls/RefreshButton
@onready var lobby_list: ItemList = $Center/Panel/VBox/LobbyList

var _displayed_lobbies: Array = []


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	ip_input.text_submitted.connect(_on_ip_submitted)
	lobby_list.item_selected.connect(_on_lobby_selected)
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobbies_updated.connect(_on_lobbies_updated)
	NetworkManager.lobby_hosted.connect(_on_lobby_hosted)
	NetworkManager.matchmaking_status_changed.connect(_on_matchmaking_status_changed)
	NetworkManager.matchmaking_failed.connect(_on_matchmaking_failed)

	status_label.text = ""
	cancel_button.visible = false
	_configure_online_ui()


func _configure_online_ui() -> void:
	var using_web_lobbies := NetworkManager.uses_web_lobbies()
	join_row.visible = false
	lobby_name_input.visible = using_web_lobbies
	lobby_controls.visible = using_web_lobbies
	lobby_list.visible = using_web_lobbies

	if using_web_lobbies:
		join_button.text = "Join Selected Lobby"
		status_label.text = "Lobby listesi yukleniyor..."
		NetworkManager.refresh_lobbies()
	else:
		join_button.text = "Join Game"


func _on_play_pressed() -> void:
	SceneRouter.go_to_match()


func _on_host_pressed() -> void:
	if NetworkManager.uses_web_lobbies():
		status_label.text = "Lobi olusturuluyor..."
		_set_buttons_enabled(false)
		cancel_button.visible = true
		NetworkManager.host_game(NetworkManager.DEFAULT_PORT, lobby_name_input.text)
		return

	var error := NetworkManager.host_game()
	if error != OK:
		status_label.text = "Host baslatilamadi!"
		return

	SceneRouter.go_to_match({"online": true})


func _on_join_pressed() -> void:
	if NetworkManager.uses_web_lobbies():
		var selected := lobby_list.get_selected_items()
		if selected.is_empty():
			status_label.text = "Once bir lobby sec."
			return

		var lobby_index: int = selected[0]
		if lobby_index < 0 or lobby_index >= _displayed_lobbies.size():
			status_label.text = "Secilen lobby bulunamadi."
			return

		var lobby: Dictionary = _displayed_lobbies[lobby_index]
		status_label.text = "Lobiye baglaniliyor..."
		_set_buttons_enabled(false)
		cancel_button.visible = true
		NetworkManager.join_game(str(lobby.get("id", "")))
		return

	join_row.visible = true
	ip_input.grab_focus()


func _on_ip_submitted(ip_text: String) -> void:
	var address := ip_text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "Baglaniliyor: %s..." % address
	_set_buttons_enabled(false)
	cancel_button.visible = true
	var error := NetworkManager.join_game(address)
	if error != OK:
		status_label.text = "Baglanti hatasi!"
		_set_buttons_enabled(true)
		cancel_button.visible = false


func _on_connection_established() -> void:
	if not NetworkManager.is_host():
		SceneRouter.go_to_match({"online": true})


func _on_connection_failed() -> void:
	status_label.text = "Baglanti basarisiz!"
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_game()
	status_label.text = ""
	_set_buttons_enabled(true)
	cancel_button.visible = false
	if NetworkManager.uses_web_lobbies():
		NetworkManager.refresh_lobbies()


func _on_refresh_pressed() -> void:
	status_label.text = "Lobby listesi yenileniyor..."
	NetworkManager.refresh_lobbies()


func _on_lobby_selected(index: int) -> void:
	if index >= 0 and index < _displayed_lobbies.size():
		var lobby: Dictionary = _displayed_lobbies[index]
		status_label.text = "Secildi: %s" % str(lobby.get("name", "Lobby"))


func _on_lobbies_updated(lobbies: Array) -> void:
	_displayed_lobbies = lobbies
	lobby_list.clear()

	for lobby_data in _displayed_lobbies:
		if typeof(lobby_data) != TYPE_DICTIONARY:
			continue
		var lobby_name := str(lobby_data.get("name", "Lobby"))
		var player_count := int(lobby_data.get("playerCount", 1))
		lobby_list.add_item("%s (%d/2)" % [lobby_name, player_count])

	if _displayed_lobbies.is_empty():
		status_label.text = "Aktif lobby yok."
	else:
		status_label.text = "%d lobby bulundu." % _displayed_lobbies.size()

	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_lobby_hosted(_lobby_id: String, lobby_name: String) -> void:
	status_label.text = "Lobby hazir: %s" % lobby_name
	SceneRouter.go_to_match({"online": true})


func _on_matchmaking_status_changed(message: String) -> void:
	if not message.is_empty():
		status_label.text = message


func _on_matchmaking_failed(message: String) -> void:
	status_label.text = message
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_buttons_enabled(enabled: bool) -> void:
	play_button.disabled = not enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	quit_button.disabled = not enabled
	refresh_button.disabled = not enabled
	lobby_name_input.editable = enabled


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
