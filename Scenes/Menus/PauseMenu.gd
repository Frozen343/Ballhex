extends Control
class_name PauseMenu

signal resume_requested
signal restart_requested
signal menu_requested
signal assign_red_requested(peer_id: int)
signal assign_blue_requested(peer_id: int)
signal assign_spectator_requested(peer_id: int)
signal kick_requested(peer_id: int)
signal ban_requested(peer_id: int)
signal toggle_admin_requested(peer_id: int)

const ACTION_KICK := 1
const ACTION_BAN := 2
const ACTION_TOGGLE_ADMIN := 3

@onready var room_name_label: Label = $Backdrop/Card/Margin/Layout/TopBar/RoomName
@onready var status_label: Label = $Backdrop/Card/Margin/Layout/Body/ResultLabel
@onready var helper_label: Label = $Backdrop/Card/Margin/Layout/Bottom/HelperLabel
@onready var red_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/RedColumn/RedList
@onready var spectators_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/SpectatorsColumn/SpectatorsList
@onready var blue_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/BlueColumn/BlueList
@onready var resume_button: Button = $Backdrop/Card/Margin/Layout/TopBar/Buttons/ResumeButton
@onready var restart_button: Button = $Backdrop/Card/Margin/Layout/TopBar/Buttons/RestartButton
@onready var menu_button: Button = $Backdrop/Card/Margin/Layout/TopBar/Buttons/MenuButton
@onready var send_red_button: Button = $Backdrop/Card/Margin/Layout/Bottom/ManageRow/SendRedButton
@onready var send_spectators_button: Button = $Backdrop/Card/Margin/Layout/Bottom/ManageRow/SendSpectatorsButton
@onready var send_blue_button: Button = $Backdrop/Card/Margin/Layout/Bottom/ManageRow/SendBlueButton
@onready var context_menu: PopupMenu = $ContextMenu

var _entries_by_column := {
	"red": [],
	"spectators": [],
	"blue": []
}
var _selected_peer_id := -1
var _can_manage := false
var _match_over := false
var _local_peer_id := 1


func _ready() -> void:
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	send_red_button.pressed.connect(_on_send_red_pressed)
	send_spectators_button.pressed.connect(_on_send_spectators_pressed)
	send_blue_button.pressed.connect(_on_send_blue_pressed)
	red_list.item_clicked.connect(_on_item_clicked.bind("red", red_list))
	spectators_list.item_clicked.connect(_on_item_clicked.bind("spectators", spectators_list))
	blue_list.item_clicked.connect(_on_item_clicked.bind("blue", blue_list))
	context_menu.id_pressed.connect(_on_context_menu_pressed)
	hide_panel()


func update_room_state(snapshot: Dictionary) -> void:
	room_name_label.text = str(snapshot.get("room_name", "Room"))
	_can_manage = bool(snapshot.get("can_manage", false))
	_match_over = bool(snapshot.get("match_over", false))
	_local_peer_id = int(snapshot.get("local_peer_id", 1))
	_entries_by_column["red"] = snapshot.get("red", [])
	_entries_by_column["spectators"] = snapshot.get("spectators", [])
	_entries_by_column["blue"] = snapshot.get("blue", [])

	_rebuild_list(red_list, _entries_by_column["red"])
	_rebuild_list(spectators_list, _entries_by_column["spectators"])
	_rebuild_list(blue_list, _entries_by_column["blue"])
	_refresh_result_label(snapshot)
	_refresh_button_state()


func show_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_menu.hide()


func _refresh_result_label(snapshot: Dictionary) -> void:
	var red_score := int(snapshot.get("red_score", 0))
	var blue_score := int(snapshot.get("blue_score", 0))
	var result_title := str(snapshot.get("result_title", ""))
	var result_detail := str(snapshot.get("result_detail", ""))
	if _match_over:
		status_label.text = "%s   %s" % [result_title, result_detail]
		resume_button.text = "Close"
	else:
		status_label.text = "Score: Red %d - %d Blue" % [red_score, blue_score]
		resume_button.text = "Resume"
	helper_label.text = "Left click: select player   Right click: admin actions" if _can_manage else "ESC ile odayi acip kapatabilirsin."
	restart_button.visible = _can_manage
	restart_button.disabled = not _can_manage


func _refresh_button_state() -> void:
	var has_selection := _get_selected_entry().size() > 0
	send_red_button.visible = _can_manage
	send_spectators_button.visible = _can_manage
	send_blue_button.visible = _can_manage
	send_red_button.disabled = not (_can_manage and has_selection)
	send_spectators_button.disabled = not (_can_manage and has_selection)
	send_blue_button.disabled = not (_can_manage and has_selection)


func _rebuild_list(list_control: ItemList, entries: Array) -> void:
	list_control.clear()
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		list_control.add_item(_format_entry(entry))


func _format_entry(entry: Dictionary) -> String:
	var name_text := str(entry.get("name", "Player"))
	if bool(entry.get("is_host", false)):
		name_text += " [Host]"
	if bool(entry.get("is_admin", false)) and not bool(entry.get("is_host", false)):
		name_text += " [Admin]"
	return name_text


func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int, column: String, list_control: ItemList) -> void:
	if index < 0:
		return
	_select_entry(column, index)
	if mouse_button_index == MOUSE_BUTTON_RIGHT and _can_manage:
		var entry := _get_selected_entry()
		if entry.is_empty():
			return
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id < 0 or peer_id == _local_peer_id:
			return
		_rebuild_context_menu()
		var popup_rect := Rect2i(
			Vector2i(list_control.get_screen_position() + list_control.get_local_mouse_position()),
			Vector2i.ZERO
		)
		context_menu.popup(popup_rect)


func _select_entry(column: String, index: int) -> void:
	var entries: Array = _entries_by_column.get(column, [])
	if index < 0 or index >= entries.size():
		_selected_peer_id = -1
		_refresh_button_state()
		return
	_selected_peer_id = int(entries[index].get("peer_id", -1))

	if column != "red":
		red_list.deselect_all()
	if column != "spectators":
		spectators_list.deselect_all()
	if column != "blue":
		blue_list.deselect_all()
	_refresh_button_state()


func _get_selected_entry() -> Dictionary:
	if _selected_peer_id < 0:
		return {}
	for column in ["red", "spectators", "blue"]:
		var entries: Array = _entries_by_column.get(column, [])
		for entry in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if int(entry.get("peer_id", -1)) == _selected_peer_id:
				return entry
	return {}


func _rebuild_context_menu() -> void:
	context_menu.clear()
	context_menu.add_item("Kick", ACTION_KICK)
	context_menu.add_item("Ban", ACTION_BAN)
	var entry := _get_selected_entry()
	var admin_text := "Grant Admin"
	if bool(entry.get("is_admin", false)):
		admin_text = "Remove Admin"
	context_menu.add_item(admin_text, ACTION_TOGGLE_ADMIN)


func _on_context_menu_pressed(action_id: int) -> void:
	if _selected_peer_id < 0:
		return
	match action_id:
		ACTION_KICK:
			kick_requested.emit(_selected_peer_id)
		ACTION_BAN:
			ban_requested.emit(_selected_peer_id)
		ACTION_TOGGLE_ADMIN:
			toggle_admin_requested.emit(_selected_peer_id)


func _on_send_red_pressed() -> void:
	if _selected_peer_id >= 0:
		assign_red_requested.emit(_selected_peer_id)


func _on_send_spectators_pressed() -> void:
	if _selected_peer_id >= 0:
		assign_spectator_requested.emit(_selected_peer_id)


func _on_send_blue_pressed() -> void:
	if _selected_peer_id >= 0:
		assign_blue_requested.emit(_selected_peer_id)
