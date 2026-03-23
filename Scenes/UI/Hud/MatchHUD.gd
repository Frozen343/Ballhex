extends Control
class_name MatchHUD

signal chat_submitted(message: String)
signal chat_focus_changed(focused: bool)

const CHAT_PANEL_HEIGHT := 180.0
const SCOREBOARD_HEIGHT := 36.0
const MAX_CHAT_LINES := 50

@onready var red_score_label: Label = $Scoreboard/Panel/Margin/HBox/RedScore
@onready var timer_label: Label = $Scoreboard/Panel/Margin/HBox/Timer
@onready var blue_score_label: Label = $Scoreboard/Panel/Margin/HBox/BlueScore
@onready var announcement_label: Label = $Announcement
@onready var hint_label: Label = $Hint
@onready var pause_overlay: CanvasItem = $PauseOverlay
@onready var lobby_panel: Control = get_node_or_null("LobbyPanel")

var _chat_panel: PanelContainer
var _chat_scroll: ScrollContainer
var _chat_vbox: VBoxContainer
var _chat_input: LineEdit
var _chat_focused := false


func _ready() -> void:
	update_score(0, 0)
	update_timer(GameSettings.MATCH_DURATION_SECONDS)
	hint_label.visible = false
	announcement_label.modulate.a = 0.0
	pause_overlay.visible = false
	if lobby_panel != null:
		lobby_panel.visible = false
	_setup_chat_panel()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if _chat_input != null and not _chat_focused:
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()


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


func update_lobby_room(_roster: Array, _local_slot: String, _can_assign: bool, _capacity: int) -> void:
	hide_lobby_room()


func hide_lobby_room() -> void:
	if lobby_panel != null:
		lobby_panel.visible = false


func set_pause_overlay_visible(value: bool) -> void:
	pause_overlay.visible = value


func is_chat_focused() -> bool:
	return _chat_focused


func add_chat_line(text: String, color: Color = Color(0.93, 0.95, 0.97, 0.9)) -> void:
	if _chat_vbox == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_vbox.add_child(label)

	while _chat_vbox.get_child_count() > MAX_CHAT_LINES:
		var oldest := _chat_vbox.get_child(0)
		_chat_vbox.remove_child(oldest)
		oldest.queue_free()

	await get_tree().process_frame
	if _chat_scroll != null:
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func show_toast(text: String, color: Color = Color(0.93, 0.95, 0.97, 0.9)) -> void:
	add_chat_line(text, color)


func get_chat_panel_height() -> float:
	return CHAT_PANEL_HEIGHT


func _setup_chat_panel() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_chat_panel.offset_top = -CHAT_PANEL_HEIGHT
	_chat_panel.offset_left = 0.0
	_chat_panel.offset_right = 0.0
	_chat_panel.offset_bottom = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.11, 0.95)
	_chat_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_chat_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Scrollable chat messages
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chat_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_chat_scroll)

	_chat_vbox = VBoxContainer.new()
	_chat_vbox.add_theme_constant_override("separation", 2)
	_chat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_scroll.add_child(_chat_vbox)

	# Chat input
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Press Tab to chat..."
	_chat_input.custom_minimum_size = Vector2(0, 30)
	_chat_input.add_theme_font_size_override("font_size", 14)
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.focus_entered.connect(_on_chat_focus_entered)
	_chat_input.focus_exited.connect(_on_chat_focus_exited)
	vbox.add_child(_chat_input)

	add_child(_chat_panel)


func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	chat_submitted.emit(clean)
	_chat_input.text = ""
	# Defer grab_focus so it runs after Godot's internal Enter handling
	_chat_input.call_deferred("grab_focus")


func _on_chat_focus_entered() -> void:
	_chat_focused = true
	chat_focus_changed.emit(true)


func _on_chat_focus_exited() -> void:
	_chat_focused = false
	chat_focus_changed.emit(false)
