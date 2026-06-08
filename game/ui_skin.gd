class_name UISkin
extends RefCounted

## Small data-driven UI skin layer. It keeps the current game UI replaceable
## without forcing every window/button color into World.gd.

const CONFIG_PATH := "res://assets/ui.json"

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _load_cfg()
	return _cfg


static func layout_num(key: String, fallback: float) -> float:
	return float(cfg().get("layout", {}).get(key, fallback))


static func color(key: String, fallback: Color) -> Color:
	var raw = cfg().get("colors", {}).get(key, "")
	if raw is String and raw != "":
		return Color.html(raw)
	return fallback


static func panel_style(key := "panel") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color(key, Color(0.10, 0.08, 0.06, 0.88))
	sb.border_color = color("accent", Color(0.82, 0.62, 0.24, 1.0)).darkened(0.28)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func button_style(key := "button") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color(key, Color(0.25, 0.17, 0.10, 1.0))
	sb.border_color = color("accent", Color(0.82, 0.62, 0.24, 1.0)).darkened(0.35)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	return sb


static func apply_label(label: Label, muted := false, size := 13) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color",
		color("font_muted" if muted else "font", Color.WHITE))


static func apply_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(layout_num("button_width", 96),
		layout_num("button_height", 28))
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", color("font", Color.WHITE))
	button.add_theme_stylebox_override("normal", button_style("button"))
	button.add_theme_stylebox_override("hover", button_style("button_hover"))
	button.add_theme_stylebox_override("pressed", button_style("button_pressed"))
	button.add_theme_stylebox_override("disabled", button_style("button_disabled"))


static func good_texture(good: int) -> Texture2D:
	var path := "res://assets/goods/%d.png" % good
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func _load_cfg() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
