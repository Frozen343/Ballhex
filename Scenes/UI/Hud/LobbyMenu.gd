extends Control
class_name LobbyMenu

signal menu_requested

@onready var red_list: VBoxContainer = $Backdrop/Panel/HBox/RedPanel/RedList
@onready var blue_list: VBoxContainer = $Backdrop/Panel/HBox/BluePanel/BlueList
@onready var neutral_list: VBoxContainer = $Backdrop/Panel/HBox/VBox/NeutralList
@onready var menu_button: Button = $Backdrop/Panel/MenuButton
@onready var close_button: Button = $Backdrop/Panel/CloseButton
@onready var ip_label: Label = $Backdrop/Panel/IpLabel


func _ready() -> void:
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	close_button.pressed.connect(hide_panel)
	NetworkManager.lobby_updated.connect(_refresh_ui)
	hide_panel()


func show_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_ui()
	_update_ip_label()


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_ip_label() -> void:
	if not NetworkManager.is_online:
		ip_label.text = "Offline"
		return
	var addresses := IP.get_local_addresses()
	var relevant: Array[String] = []
	for addr in addresses:
		if addr.begins_with("127."): continue
		if ":" in addr: continue
		relevant.append(addr)
	var ip_text := ", ".join(relevant) if not relevant.is_empty() else "?"
	ip_label.text = "IP: %s | Port: %d" % [ip_text, NetworkManager.DEFAULT_PORT]


func _refresh_ui() -> void:
	if not visible:
		return

	for child in red_list.get_children(): child.queue_free()
	for child in blue_list.get_children(): child.queue_free()
	for child in neutral_list.get_children(): child.queue_free()

	for peer_id in NetworkManager.lobby_players:
		var pdata: Dictionary = NetworkManager.lobby_players[peer_id]
		var item := _create_player_item(peer_id, pdata["name"], pdata["team"])
		if pdata["team"] == GameEnums.TeamId.RED:
			red_list.add_child(item)
		elif pdata["team"] == GameEnums.TeamId.BLUE:
			blue_list.add_child(item)
		else:
			neutral_list.add_child(item)


func _create_player_item(peer_id: int, player_name: String, current_team: int) -> Control:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = player_name
	if peer_id == multiplayer.get_unique_id() or (peer_id == 1 and NetworkManager.is_host()):
		label.text += " (Sen)"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	if NetworkManager.is_host():
		if current_team != GameEnums.TeamId.RED:
			var btn_red := Button.new()
			btn_red.text = "Red"
			btn_red.pressed.connect(func(): NetworkManager.change_player_team(peer_id, GameEnums.TeamId.RED))
			hbox.add_child(btn_red)

		if current_team != GameEnums.TeamId.BLUE:
			var btn_blue := Button.new()
			btn_blue.text = "Blue"
			btn_blue.pressed.connect(func(): NetworkManager.change_player_team(peer_id, GameEnums.TeamId.BLUE))
			hbox.add_child(btn_blue)

		if current_team != GameEnums.TeamId.NEUTRAL:
			var btn_kick := Button.new()
			btn_kick.text = "X"
			btn_kick.pressed.connect(func(): NetworkManager.change_player_team(peer_id, GameEnums.TeamId.NEUTRAL))
			hbox.add_child(btn_kick)

	return hbox
