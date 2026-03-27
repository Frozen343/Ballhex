extends RefCounted
class_name BallhexUI

const COLOR_BG_TOP := Color(0.04, 0.11, 0.16, 1.0)
const COLOR_BG_BOTTOM := Color(0.02, 0.06, 0.1, 1.0)
const COLOR_SURFACE := Color(0.08, 0.13, 0.18, 0.88)
const COLOR_SURFACE_ALT := Color(0.1, 0.16, 0.22, 0.94)
const COLOR_SURFACE_SOFT := Color(0.12, 0.2, 0.26, 0.58)
const COLOR_TEXT := Color(0.95, 0.98, 1.0, 1.0)
const COLOR_MUTED := Color(0.7, 0.81, 0.88, 0.92)
const COLOR_ACCENT := Color(0.68, 0.94, 0.42, 1.0)
const COLOR_RED := Color(0.95, 0.43, 0.38, 1.0)
const COLOR_BLUE := Color(0.36, 0.66, 1.0, 1.0)
const COLOR_GOLD := Color(1.0, 0.84, 0.42, 1.0)


static func make_panel(bg: Color = COLOR_SURFACE, border: Color = Color(1, 1, 1, 0.08), radius: int = 26) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 10
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


static func make_button(variant: String = "primary") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_right = 22
	style.corner_radius_bottom_left = 22
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	match variant:
		"secondary":
			style.bg_color = Color(0.12, 0.2, 0.26, 0.92)
			style.border_color = Color(1, 1, 1, 0.08)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
		"ghost":
			style.bg_color = Color(1, 1, 1, 0.04)
			style.border_color = Color(1, 1, 1, 0.12)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
		"danger":
			style.bg_color = Color(0.74, 0.23, 0.24, 0.92)
		"blue":
			style.bg_color = Color(0.23, 0.44, 0.86, 0.96)
		"chip":
			style.bg_color = Color(1, 1, 1, 0.06)
			style.border_color = Color(1, 1, 1, 0.1)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.corner_radius_top_left = 16
			style.corner_radius_top_right = 16
			style.corner_radius_bottom_right = 16
			style.corner_radius_bottom_left = 16
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 7
			style.content_margin_bottom = 7
		_:
			style.bg_color = Color(0.43, 0.79, 0.28, 0.96)
	return style


static func style_button(button: Button, variant: String = "primary", font_size: int = 20) -> void:
	button.add_theme_stylebox_override("normal", make_button(variant))
	button.add_theme_stylebox_override("pressed", make_button(variant))
	var hover := make_button(variant)
	hover.bg_color = hover.bg_color.lightened(0.08)
	button.add_theme_stylebox_override("hover", hover)
	var disabled := make_button(variant)
	disabled.bg_color = disabled.bg_color.darkened(0.24)
	disabled.border_color = Color(1, 1, 1, 0.04)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	button.focus_mode = Control.FOCUS_NONE


static func style_panel(panel: Control, bg: Color = COLOR_SURFACE, border: Color = Color(1, 1, 1, 0.08), radius: int = 26) -> void:
	panel.add_theme_stylebox_override("panel", make_panel(bg, border, radius))


static func style_line_edit(line_edit: LineEdit, font_size: int = 20) -> void:
	var style := make_panel(Color(0.05, 0.1, 0.14, 0.96), Color(1, 1, 1, 0.08), 18)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	line_edit.add_theme_stylebox_override("normal", style)
	var focus := make_panel(Color(0.05, 0.12, 0.16, 1.0), COLOR_ACCENT, 18)
	focus.content_margin_left = 18
	focus.content_margin_right = 18
	focus.content_margin_top = 12
	focus.content_margin_bottom = 12
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_font_size_override("font_size", font_size)
	line_edit.add_theme_color_override("font_color", COLOR_TEXT)
	line_edit.add_theme_color_override("font_placeholder_color", Color(0.78, 0.84, 0.9, 0.48))


static func style_spinbox(spin_box: SpinBox) -> void:
	style_line_edit(spin_box.get_line_edit(), 18)
	spin_box.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_LEFT


static func style_label(label: Label, font_size: int, color: Color = COLOR_TEXT) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


static func avatar_color(avatar_id: int) -> Color:
	var colors := [
		Color(0.94, 0.46, 0.4, 1.0),
		Color(0.35, 0.65, 0.99, 1.0),
		Color(0.96, 0.75, 0.29, 1.0),
		Color(0.47, 0.88, 0.57, 1.0),
		Color(0.8, 0.57, 0.96, 1.0),
		Color(0.98, 0.58, 0.75, 1.0)
	]
	return colors[posmod(avatar_id, colors.size())]
