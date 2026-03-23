extends Control
class_name MainMenu

@onready var play_button: Button = $Center/Panel/VBox/PlayButton
@onready var host_button: Button = $Center/Panel/VBox/HostButton
@onready var join_button: Button = $Center/Panel/VBox/JoinButton
@onready var quit_button: Button = $Center/Panel/VBox/QuitButton
@onready var name_input: LineEdit = $Center/Panel/VBox/NameInput
@onready var ip_input: LineEdit = $Center/Panel/VBox/JoinRow/IpInput
@onready var status_label: Label = $Center/Panel/VBox/StatusLabel
@onready var join_row: HBoxContainer = $Center/Panel/VBox/JoinRow
@onready var cancel_button: Button = $Center/Panel/VBox/CancelButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	ip_input.text_submitted.connect(_on_ip_submitted)
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	status_label.text = ""
	cancel_button.visible = false
	name_input.text = GameSettings.player_name


func _save_player_name() -> void:
	var pname := name_input.text.strip_edges()
	if pname.is_empty():
		pname = "Player"
	GameSettings.player_name = pname


func _on_play_pressed() -> void:
	_save_player_name()
	SceneRouter.go_to_match()


func _on_host_pressed() -> void:
	_save_player_name()
	var error := NetworkManager.host_game()
	if error != OK:
		status_label.text = "Host başlatılamadı!"
		return
	SceneRouter.go_to_match({"online": true})


func _on_join_pressed() -> void:
	_save_player_name()
	join_row.visible = true
	ip_input.grab_focus()


func _on_ip_submitted(ip_text: String) -> void:
	var address := ip_text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "Bağlanılıyor: %s..." % address
	_set_buttons_enabled(false)
	cancel_button.visible = true
	var error := NetworkManager.join_game(address)
	if error != OK:
		status_label.text = "Bağlantı hatası!"
		_set_buttons_enabled(true)
		cancel_button.visible = false


func _on_connection_established() -> void:
	if not NetworkManager.is_host():
		SceneRouter.go_to_match({"online": true})


func _on_connection_failed() -> void:
	status_label.text = "Bağlantı başarısız!"
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_game()
	status_label.text = ""
	_set_buttons_enabled(true)
	cancel_button.visible = false


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_buttons_enabled(enabled: bool) -> void:
	play_button.disabled = not enabled
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	quit_button.disabled = not enabled


func _exit_tree() -> void:
	if NetworkManager.connection_established.is_connected(_on_connection_established):
		NetworkManager.connection_established.disconnect(_on_connection_established)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
