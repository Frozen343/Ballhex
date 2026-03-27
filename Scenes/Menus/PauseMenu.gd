extends Control
class_name PauseMenu

const UI := preload("res://Scripts/UI/BallhexUI.gd")

signal resume_requested
signal restart_requested
signal menu_requested
signal assign_red_requested(peer_id: int)
signal assign_blue_requested(peer_id: int)
signal assign_spectator_requested(peer_id: int)
signal kick_requested(peer_id: int)
signal ban_requested(peer_id: int)
signal toggle_admin_requested(peer_id: int)
signal chat_submitted(message: String)
signal randomize_teams_requested
signal match_rules_changed(match_duration_seconds: float, score_limit: int)

const ACTION_KICK := 1
const ACTION_BAN := 2
const ACTION_TOGGLE_ADMIN := 3

@onready var room_name_label: Label = $Backdrop/Card/Margin/Layout/TopBar/RoomName
@onready var status_label: Label = $Backdrop/Card/Margin/Layout/Body/ResultLabel
@onready var helper_label: Label = $Backdrop/Card/Margin/Layout/Bottom/HelperLabel
@onready var card: Panel = $Backdrop/Card
@onready var dim_layer: ColorRect = $Backdrop/Dim
@onready var red_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/RedColumn/RedList
@onready var spectators_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/SpectatorsColumn/SpectatorsList
@onready var blue_list: ItemList = $Backdrop/Card/Margin/Layout/Body/Columns/BlueColumn/BlueList
@onready var duration_input: SpinBox = $Backdrop/Card/Margin/Layout/Body/RulesRow/DurationInput
@onready var score_limit_input: SpinBox = $Backdrop/Card/Margin/Layout/Body/RulesRow/ScoreLimitInput
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
var _match_started := true
var _local_peer_id := 1
var _randomize_button: Button
var _updating_rule_inputs := false


func _ready() -> void:
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	send_red_button.pressed.connect(_on_send_red_pressed)
	send_spectators_button.pressed.connect(_on_send_spectators_pressed)
	send_blue_button.pressed.connect(_on_send_blue_pressed)
	duration_input.value_changed.connect(_on_duration_changed)
	score_limit_input.value_changed.connect(_on_score_limit_changed)
	red_list.item_clicked.connect(_on_item_clicked.bind("red", red_list))
	spectators_list.item_clicked.connect(_on_item_clicked.bind("spectators", spectators_list))
	blue_list.item_clicked.connect(_on_item_clicked.bind("blue", blue_list))
	context_menu.id_pressed.connect(_on_context_menu_pressed)
	_apply_styles()
	_setup_drag_drop()
	_setup_randomize_button()
	hide_panel()


func update_room_state(snapshot: Dictionary) -> void:
	room_name_label.text = str(snapshot.get("room_name", "Room"))
	_can_manage = bool(snapshot.get("can_manage", false))
	_match_over = bool(snapshot.get("match_over", false))
	_match_started = bool(snapshot.get("match_started", true))
	_local_peer_id = int(snapshot.get("local_peer_id", 1))
	_entries_by_column["red"] = snapshot.get("red", [])
	_entries_by_column["spectators"] = snapshot.get("spectators", [])
	_entries_by_column["blue"] = snapshot.get("blue", [])

	_rebuild_list(red_list, _entries_by_column["red"])
	_rebuild_list(spectators_list, _entries_by_column["spectators"])
	_rebuild_list(blue_list, _entries_by_column["blue"])
	_updating_rule_inputs = true
	duration_input.set_value_no_signal(maxf(1.0, roundf(float(snapshot.get("match_duration_seconds", GameSettings.MATCH_DURATION_SECONDS)) / 60.0)))
	score_limit_input.set_value_no_signal(int(snapshot.get("score_limit", GameSettings.DEFAULT_SCORE_LIMIT)))
	_updating_rule_inputs = false
	_refresh_result_label(snapshot)
	_refresh_button_state()


func show_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_menu.hide()


func _refresh_result_label(snapshot: Dictionary) -> void:
	var red_score := int(snapshot.get("red_score", 0))
	var blue_score := int(snapshot.get("blue_score", 0))
	var match_duration_seconds := float(snapshot.get("match_duration_seconds", GameSettings.MATCH_DURATION_SECONDS))
	var score_limit := int(snapshot.get("score_limit", GameSettings.DEFAULT_SCORE_LIMIT))
	var overtime := bool(snapshot.get("overtime", false))
	var result_title := str(snapshot.get("result_title", ""))
	var result_detail := str(snapshot.get("result_detail", ""))
	if not _match_started and not _match_over:
		status_label.text = "Room setup   Spectators join first, host starts the match"
		resume_button.text = "Close"
	elif _match_over:
		status_label.text = "%s   %s" % [result_title, result_detail]
		resume_button.text = "Close"
	elif overtime:
		status_label.text = "OVERTIME   Red %d - %d Blue   Next goal wins" % [red_score, blue_score]
		resume_button.text = "Resume"
	else:
		status_label.text = "Score: Red %d - %d Blue" % [red_score, blue_score]
		resume_button.text = "Resume"
	var manage_hint := "Drag players between lanes or use the action bar" if _can_manage else "Use ESC to check the room and jump back in."
	helper_label.text = "%s   Time: %s   Goal limit: %d" % [manage_hint, Helpers.format_match_time(match_duration_seconds), score_limit]
	restart_button.visible = _can_manage
	restart_button.disabled = not _can_manage
	restart_button.text = "Start Match" if not _match_started else "Restart"


func _refresh_button_state() -> void:
	var has_selection := _get_selected_entry().size() > 0
	var can_edit_rules := _can_manage and not _match_started
	send_red_button.visible = _can_manage
	send_spectators_button.visible = _can_manage
	send_blue_button.visible = _can_manage
	send_red_button.disabled = not (_can_manage and has_selection)
	send_spectators_button.disabled = not (_can_manage and has_selection)
	send_blue_button.disabled = not (_can_manage and has_selection)
	duration_input.editable = can_edit_rules
	score_limit_input.editable = can_edit_rules
	duration_input.modulate = Color(1.0, 1.0, 1.0, 1.0 if can_edit_rules else 0.72)
	score_limit_input.modulate = Color(1.0, 1.0, 1.0, 1.0 if can_edit_rules else 0.72)
	if _randomize_button != null:
		_randomize_button.visible = _can_manage
		_randomize_button.disabled = not _can_manage


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


func _on_duration_changed(value: float) -> void:
	if _updating_rule_inputs:
		return
	match_rules_changed.emit(value * 60.0, int(score_limit_input.value))


func _on_score_limit_changed(value: float) -> void:
	if _updating_rule_inputs:
		return
	match_rules_changed.emit(duration_input.value * 60.0, int(value))


# --- Drag and Drop ---

func _setup_drag_drop() -> void:
	red_list.set_drag_forwarding(_list_get_drag_data.bind("red"), _list_can_drop_data.bind("red"), _list_drop_data.bind("red"))
	spectators_list.set_drag_forwarding(_list_get_drag_data.bind("spectators"), _list_can_drop_data.bind("spectators"), _list_drop_data.bind("spectators"))
	blue_list.set_drag_forwarding(_list_get_drag_data.bind("blue"), _list_can_drop_data.bind("blue"), _list_drop_data.bind("blue"))


func _list_get_drag_data(at_position: Vector2, source_column: String) -> Variant:
	if not _can_manage:
		return null
	var list_control := _get_list_for_column(source_column)
	var index := list_control.get_item_at_position(at_position, true)
	if index < 0:
		return null
	var entries: Array = _entries_by_column.get(source_column, [])
	if index >= entries.size():
		return null
	var entry: Dictionary = entries[index]
	var peer_id := int(entry.get("peer_id", -1))
	if peer_id < 0:
		return null

	# Create drag preview
	var preview := Label.new()
	preview.text = _format_entry(entry)
	preview.add_theme_font_size_override("font_size", 18)
	preview.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	var preview_panel := PanelContainer.new()
	preview_panel.add_theme_stylebox_override("panel", UI.make_panel(Color(0.09, 0.15, 0.2, 0.96), Color(1, 1, 1, 0.1), 18))
	preview_panel.add_child(preview)
	set_drag_preview(preview_panel)

	return {"peer_id": peer_id, "source_column": source_column, "name": str(entry.get("name", "Player"))}


func _list_can_drop_data(_at_position: Vector2, data: Variant, target_column: String) -> bool:
	if not _can_manage:
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var source_column: String = data.get("source_column", "")
	return source_column != target_column


func _list_drop_data(_at_position: Vector2, data: Variant, target_column: String) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var peer_id := int(data.get("peer_id", -1))
	if peer_id < 0:
		return
	match target_column:
		"red":
			assign_red_requested.emit(peer_id)
		"blue":
			assign_blue_requested.emit(peer_id)
		"spectators":
			assign_spectator_requested.emit(peer_id)


func _get_list_for_column(column: String) -> ItemList:
	match column:
		"red":
			return red_list
		"blue":
			return blue_list
		_:
			return spectators_list


# --- Randomize Teams ---

func _setup_randomize_button() -> void:
	var bottom_node := $Backdrop/Card/Margin/Layout/Bottom
	_randomize_button = Button.new()
	_randomize_button.text = "Random Teams"
	_randomize_button.custom_minimum_size = Vector2(0, 44)
	_randomize_button.visible = false
	_randomize_button.pressed.connect(func() -> void: randomize_teams_requested.emit())
	bottom_node.add_child(_randomize_button)
	UI.style_button(_randomize_button, "secondary", 16)


func _apply_styles() -> void:
	UI.style_panel(card, UI.COLOR_SURFACE, Color(1, 1, 1, 0.08), 28)
	dim_layer.color = Color(0.01, 0.03, 0.05, 0.74)
	UI.style_button(resume_button, "blue", 15)
	UI.style_button(restart_button, "primary", 15)
	UI.style_button(menu_button, "danger", 15)
	UI.style_button(send_red_button, "secondary", 16)
	UI.style_button(send_spectators_button, "ghost", 16)
	UI.style_button(send_blue_button, "secondary", 16)
	UI.style_spinbox(duration_input)
	UI.style_spinbox(score_limit_input)
	UI.style_label(room_name_label, 28)
	room_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.style_label(status_label, 22)
	UI.style_label(helper_label, 15, UI.COLOR_MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_item_list(red_list, Color(0.36, 0.14, 0.15, 0.72), UI.COLOR_RED)
	_style_item_list(spectators_list, Color(0.13, 0.17, 0.21, 0.72), UI.COLOR_GOLD)
	_style_item_list(blue_list, Color(0.11, 0.18, 0.28, 0.72), UI.COLOR_BLUE)
	context_menu.add_theme_color_override("font_color", UI.COLOR_TEXT)
	context_menu.add_theme_color_override("font_hover_color", UI.COLOR_TEXT)
	context_menu.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))


func _style_item_list(list_control: ItemList, bg: Color, accent: Color) -> void:
	list_control.add_theme_font_size_override("font_size", 18)
	list_control.add_theme_color_override("font_color", UI.COLOR_TEXT)
	list_control.add_theme_color_override("font_selected_color", UI.COLOR_TEXT)
	list_control.add_theme_color_override("guide_color", Color(1, 1, 1, 0.04))
	list_control.add_theme_stylebox_override("panel", UI.make_panel(bg, Color(1, 1, 1, 0.06), 22))
	var selected := UI.make_panel(accent.darkened(0.2), accent, 20)
	list_control.add_theme_stylebox_override("selected", selected)
