class_name UISkin
extends RefCounted

## Kleine datengetriebene UI-Skin-Schicht. Hält Farben, Maße und Skins
## austauschbar, ohne jede Fenster-/Button-Optik in World.gd zu verdrahten.

const CONFIG_PATH := "res://assets/ui.json"
const USER_CONFIG_PATH := "user://ui_settings.dat"

static var _cfg := {}
static var _runtime_loaded := false
static var _ui_scale_override := 0.0
static var _ui_scale_name := ""
static var _options := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _load_cfg()
	return _cfg


static func layout_num(key: String, fallback: float) -> float:
	var v := float(cfg().get("layout", {}).get(key, fallback))
	if key == "ui_scale":
		return v
	return v * ui_scale()


static func ui_scale() -> float:
	_ensure_runtime()
	if _ui_scale_override > 0.0:
		return _ui_scale_override
	return float(cfg().get("layout", {}).get("ui_scale", 1.0))


static func ui_scale_name() -> String:
	_ensure_runtime()
	if _ui_scale_name != "":
		return _ui_scale_name
	var scale := ui_scale()
	var presets := _scale_presets()
	for k in presets:
		if absf(float(presets[k]) - scale) < 0.01:
			return String(k)
	return "mittel"


static func set_ui_scale_name(name: String) -> void:
	var key := name.to_lower()
	var presets := _scale_presets()
	if not presets.has(key):
		key = "mittel"
	_ui_scale_name = key
	_ui_scale_override = float(presets[key])
	_save_runtime()


static func option_bool(key: String, fallback: bool) -> bool:
	_ensure_runtime()
	return bool(_options.get(key, fallback))


static func set_option_bool(key: String, value: bool) -> void:
	_ensure_runtime()
	_options[key] = value
	_save_runtime()


static func option_value(key: String, fallback = null):
	_ensure_runtime()
	return _options.get(key, fallback)


static func set_option_value(key: String, value) -> void:
	_ensure_runtime()
	_options[key] = value
	_save_runtime()


static func color(key: String, fallback: Color) -> Color:
	var raw = cfg().get("colors", {}).get(key, "")
	if raw is String and raw != "":
		return Color.html(raw)
	return fallback


## Fenster-/Panel-Hintergrund. Liegt unter assets/ui/skin/ eine passende 9-Patch-PNG
## (per ui.json "skin" aktiviert), wird sie genutzt — sonst die flache Fallback-Box.
static func panel_style(key := "panel") -> StyleBox:
	var tex := _texture_box(key)
	if tex != null:
		return tex
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


## Button-Hintergrund je Zustand; 9-Patch-PNG wenn vorhanden, sonst flache Box.
static func button_style(key := "button") -> StyleBox:
	var tex := _texture_box(key)
	if tex != null:
		return tex
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


# --- Austauschbarer 9-Patch-Skin (assets/ui/skin/*.png, per ui.json steuerbar) -----

static func _skin() -> Dictionary:
	return cfg().get("skin", {})


## Lädt die Skin-Textur für einen Schlüssel (panel, button, button_hover, …), wenn der
## Skin aktiviert ist und die Datei existiert. Sonst null → Fallback greift.
static func _skin_texture(key: String) -> Texture2D:
	var sk := _skin()
	if not bool(sk.get("enabled", false)):
		return null
	var fname := String(sk.get(key, ""))
	if fname == "":
		return null
	var dir := String(sk.get("dir", "res://assets/ui/skin/"))
	var path := dir.path_join(fname)
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Baut aus der Skin-Textur eine 9-Patch-StyleBoxTexture (Ränder/Content aus ui.json).
static func _texture_box(key: String) -> StyleBoxTexture:
	var tex := _skin_texture(key)
	if tex == null:
		return null
	var sk := _skin()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(sk.get("patch_margin_left", 8))
	sb.texture_margin_top = float(sk.get("patch_margin_top", 8))
	sb.texture_margin_right = float(sk.get("patch_margin_right", 8))
	sb.texture_margin_bottom = float(sk.get("patch_margin_bottom", 8))
	var cm := float(sk.get("content_margin", 6))
	sb.content_margin_left = cm
	sb.content_margin_right = cm
	sb.content_margin_top = cm
	sb.content_margin_bottom = cm
	return sb


static func apply_label(label: Label, muted := false, size := 13) -> void:
	label.add_theme_font_size_override("font_size", maxi(8, roundi(float(size) * ui_scale())))
	label.add_theme_color_override("font_color",
		color("font_muted" if muted else "font", Color.WHITE))


static func apply_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(layout_num("button_width", 96),
		layout_num("button_height", 28))
	button.add_theme_font_size_override("font_size", maxi(8, roundi(12.0 * ui_scale())))
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


static func _scale_presets() -> Dictionary:
	var defaults := { klein = 0.72, mittel = 0.82, gross = 1.0 }
	var raw = cfg().get("scale_presets", {})
	if raw is Dictionary:
		for k in raw:
			defaults[String(k)] = float(raw[k])
	return defaults


static func _ensure_runtime() -> void:
	if _runtime_loaded:
		return
	_runtime_loaded = true
	if not FileAccess.file_exists(USER_CONFIG_PATH):
		return
	var f := FileAccess.open(USER_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var data = f.get_var(true)
	f.close()
	if data is Dictionary:
		_ui_scale_override = float(data.get("ui_scale", 0.0))
		_ui_scale_name = String(data.get("ui_scale_name", ""))
		var opts = data.get("options", {})
		if opts is Dictionary:
			_options = opts


static func _save_runtime() -> void:
	var f := FileAccess.open(USER_CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({
		ui_scale = _ui_scale_override,
		ui_scale_name = _ui_scale_name,
		options = _options,
	}, true)
	f.close()
