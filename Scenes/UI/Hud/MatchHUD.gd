extends Control
class_name MatchHUD

signal chat_submitted(message: String)
signal chat_focus_changed(focused: bool)

const UI := preload("res://Scripts/UI/BallhexUI.gd")

const CHAT_PANEL_HEIGHT := 196.0
const CHAT_COMPACT_HEIGHT := 86.0
const SCOREBOARD_HEIGHT := 36.0
const MAX_CHAT_LINES := 50
const CHAT_ACTIVITY_SECONDS := 4.0

@onready var scoreboard_panel: Panel = $Scoreboard/Panel
@onready var red_score_label: Label = $Scoreboard/Panel/Margin/HBox/RedScore
@onready var timer_label: Label = $Scoreboard/Panel/Margin/HBox/Timer
@onready var blue_score_label: Label = $Scoreboard/Panel/Margin/HBox/BlueScore
@onready var mode_tag_label: Label = $ModeTag
@onready var announcement_label: Label = $Announcement
@onready var hint_label: Label = $Hint
@onready var pause_overlay: CanvasItem = $PauseOverlay
@onready var lobby_panel: Control = get_node_or_null("LobbyPanel")

var _chat_panel: PanelContainer
var _chat_scroll: ScrollContainer
var _chat_vbox: VBoxContainer
var _chat_input: LineEdit
var _chat_focused := false
var _chat_activity_timer: SceneTreeTimer
var _chat_expanded := false


func _ready() -> void:
	_apply_styles()
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
	_show_chat_activity()
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
	_show_chat_activity()
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

	_scroll_chat_to_bottom.call_deferred()


func show_toast(text: String, color: Color = Color(0.93, 0.95, 0.97, 0.9)) -> void:
	add_chat_line(text, color)


func get_chat_panel_height() -> float:
	return CHAT_PANEL_HEIGHT if _chat_expanded else CHAT_COMPACT_HEIGHT


func _setup_chat_panel() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_chat_panel.offset_top = -CHAT_COMPACT_HEIGHT
	_chat_panel.offset_left = 18.0
	_chat_panel.offset_right = -18.0
	_chat_panel.offset_bottom = -18.0
	_chat_panel.add_theme_stylebox_override("panel", UI.make_panel(Color(0.05, 0.09, 0.13, 0.74), Color(1, 1, 1, 0.08), 24))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
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
	_chat_input.custom_minimum_size = Vector2(0, 36)
	_chat_input.add_theme_font_size_override("font_size", 14)
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.focus_entered.connect(_on_chat_focus_entered)
	_chat_input.focus_exited.connect(_on_chat_focus_exited)
	UI.style_line_edit(_chat_input, 15)
	vbox.add_child(_chat_input)

	add_child(_chat_panel)
	_set_chat_expanded(false, true)


func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	chat_submitted.emit(clean)
	_chat_input.text = ""
	get_viewport().call_deferred("gui_release_focus")


func _on_chat_focus_entered() -> void:
	_chat_focused = true
	_set_chat_expanded(true)
	chat_focus_changed.emit(true)


func _on_chat_focus_exited() -> void:
	_chat_focused = false
	chat_focus_changed.emit(false)
	_show_chat_activity()


func _apply_styles() -> void:
	UI.style_panel(scoreboard_panel, Color(0.05, 0.1, 0.14, 0.86), Color(1, 1, 1, 0.08), 28)
	UI.style_label(red_score_label, 22, UI.COLOR_RED)
	UI.style_label(timer_label, 24)
	UI.style_label(blue_score_label, 22, UI.COLOR_BLUE)
	UI.style_label(mode_tag_label, 14, Color(0.86, 0.92, 0.97, 0.76))
	mode_tag_label.text = "CUSTOM ROOM" if NetworkManager.is_online else "LOCAL MATCH"
	announcement_label.add_theme_font_size_override("font_size", 56)
	announcement_label.add_theme_color_override("font_color", UI.COLOR_TEXT)
	hint_label.add_theme_color_override("font_color", UI.COLOR_MUTED)


func _show_chat_activity() -> void:
	_set_chat_expanded(true)
	if _chat_activity_timer != null and _chat_activity_timer.timeout.is_connected(_on_chat_activity_timeout):
		_chat_activity_timer.timeout.disconnect(_on_chat_activity_timeout)
	_chat_activity_timer = get_tree().create_timer(CHAT_ACTIVITY_SECONDS)
	_chat_activity_timer.timeout.connect(_on_chat_activity_timeout)


func _on_chat_activity_timeout() -> void:
	if _chat_focused:
		return
	_set_chat_expanded(false)


func _set_chat_expanded(value: bool, instant: bool = false) -> void:
	_chat_expanded = value
	if _chat_panel == null:
		return
	var target_height := CHAT_PANEL_HEIGHT if value else CHAT_COMPACT_HEIGHT
	var target_top := -target_height
	var target_alpha := 0.96 if value else 0.76
	if instant:
		_chat_panel.offset_top = target_top
		_chat_panel.modulate.a = target_alpha
	else:
		var tween := create_tween()
		tween.tween_property(_chat_panel, "offset_top", target_top, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(_chat_panel, "modulate:a", target_alpha, 0.18)


func _scroll_chat_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _chat_scroll == null:
		return
	var scroll_bar := _chat_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return
	_chat_scroll.scroll_vertical = int(scroll_bar.max_value)
