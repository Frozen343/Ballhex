extends Control
class_name MatchHUD

signal assign_red_requested(peer_id: int)
signal assign_blue_requested(peer_id: int)
signal bench_requested(peer_id: int)

@onready var red_score_label: Label = $Scoreboard/Panel/Margin/HBox/RedScore
@onready var timer_label: Label = $Scoreboard/Panel/Margin/HBox/Timer
@onready var blue_score_label: Label = $Scoreboard/Panel/Margin/HBox/BlueScore
@onready var announcement_label: Label = $Announcement
@onready var hint_label: Label = $Hint
@onready var lobby_panel: Panel = $LobbyPanel
@onready var lobby_status_label: Label = $LobbyPanel/Margin/VBox/LobbyStatus
@onready var lobby_list: ItemList = $LobbyPanel/Margin/VBox/LobbyList
@onready var red_assign_button: Button = $LobbyPanel/Margin/VBox/Buttons/AssignRedButton
@onready var blue_assign_button: Button = $LobbyPanel/Margin/VBox/Buttons/AssignBlueButton
@onready var bench_button: Button = $LobbyPanel/Margin/VBox/Buttons/BenchButton

var _lobby_entries: Array = []


func _ready() -> void:
	update_score(0, 0)
	update_timer(GameSettings.MATCH_DURATION_SECONDS)
	hint_label.text = "P1: WASD + SPACE   P2: ARROWS + .   Pause: ESC   Debug: F3"
	announcement_label.modulate.a = 0.0
	lobby_panel.visible = false
	red_assign_button.pressed.connect(_on_assign_red_pressed)
	blue_assign_button.pressed.connect(_on_assign_blue_pressed)
	bench_button.pressed.connect(_on_bench_pressed)


func update_score(red_score: int, blue_score: int) -> void:
	red_score_label.text = "RED %d" % red_score
	blue_score_label.text = "%d BLUE" % blue_score


func update_timer(remaining_seconds: float) -> void:
	timer_label.text = Helpers.format_match_time(remaining_seconds)


func show_announcement(text: String, color: Color, duration: float) -> void:
	announcement_label.text = text
	announcement_label.modulate = color
	announcement_label.scale = Vector2.ONE * 0.8
	var tween := create_tween()
	tween.tween_property(announcement_label, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(announcement_label, "scale", Vector2.ONE, 0.12)
	tween.tween_interval(maxf(0.0, duration - 0.18))
	tween.tween_property(announcement_label, "modulate:a", 0.0, 0.18)


func update_lobby_room(roster: Array, local_slot: String, can_assign: bool, capacity: int) -> void:
	lobby_panel.visible = true
	_lobby_entries = roster
	lobby_list.clear()

	for entry in _lobby_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		lobby_list.add_item(_format_lobby_entry(entry))

	var current_count := _lobby_entries.size()
	var slot_text := "Waiting Room"
	if not local_slot.is_empty() and local_slot != "waiting":
		slot_text = "Current slot: %s" % local_slot.capitalize()
	lobby_status_label.text = "Lobby %d/%d  |  %s" % [current_count, capacity, slot_text]
	_set_assignment_buttons_enabled(can_assign)


func hide_lobby_room() -> void:
	lobby_panel.visible = false


func _format_lobby_entry(entry: Dictionary) -> String:
	var player_name := str(entry.get("name", "Player"))
	var slot := str(entry.get("slot", "waiting"))
	var suffix := "Waiting"
	if slot == "red":
		suffix = "RED"
	elif slot == "blue":
		suffix = "BLUE"
	if bool(entry.get("is_host", false)):
		player_name = "%s (Host)" % player_name
	return "%s - %s" % [player_name, suffix]


func _set_assignment_buttons_enabled(enabled: bool) -> void:
	red_assign_button.visible = enabled
	blue_assign_button.visible = enabled
	bench_button.visible = enabled
	red_assign_button.disabled = not enabled
	blue_assign_button.disabled = not enabled
	bench_button.disabled = not enabled


func _get_selected_peer_id() -> int:
	var selected := lobby_list.get_selected_items()
	if selected.is_empty():
		return -1
	var index: int = selected[0]
	if index < 0 or index >= _lobby_entries.size():
		return -1
	var entry: Dictionary = _lobby_entries[index]
	return int(entry.get("peer_id", -1))


func _on_assign_red_pressed() -> void:
	var peer_id := _get_selected_peer_id()
	if peer_id >= 0:
		assign_red_requested.emit(peer_id)


func _on_assign_blue_pressed() -> void:
	var peer_id := _get_selected_peer_id()
	if peer_id >= 0:
		assign_blue_requested.emit(peer_id)


func _on_bench_pressed() -> void:
	var peer_id := _get_selected_peer_id()
	if peer_id >= 0:
		bench_requested.emit(peer_id)
