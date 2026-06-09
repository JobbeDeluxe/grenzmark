extends Control

## Einfaches Hauptmenü: Neues Spiel, Laden, Einstellungen, Beenden.

const WORLD_SCENE := "res://game/main.tscn"
const SAVE_PATH := "user://settlers_save.dat"
const MENU_BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"
const UISkin := preload("res://game/ui_skin.gd")

static var _open_settings_after_reload := false

var _main_page: VBoxContainer
var _settings_panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_add_background()

	# CenterContainer zentriert sein Kind in jeder Fenstergröße.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(320, 330) * UISkin.ui_scale()
	box.add_theme_constant_override("separation", roundi(14.0 * UISkin.ui_scale()))
	center.add_child(box)

	_main_page = VBoxContainer.new()
	_main_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_page.add_theme_constant_override("separation", roundi(14.0 * UISkin.ui_scale()))
	box.add_child(_main_page)

	var title := Label.new()
	title.text = "GRENZMARK"
	UISkin.apply_label(title, false, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(title)

	var sub := Label.new()
	sub.text = "klassischer Aufbau auf Knoten, Flaggen und Wegen"
	UISkin.apply_label(sub, true, 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(sub)

	_button(_main_page, "Neues Spiel", _on_new)
	var load_btn := _button(_main_page, "Spiel laden", _on_load)
	load_btn.disabled = not FileAccess.file_exists(SAVE_PATH)
	_button(_main_page, "Einstellungen", _show_settings_page)
	_build_settings_panel(box)
	_button(_main_page, "Design-Editor", _on_editor)
	_button(_main_page, "Beenden", _on_quit)
	if _open_settings_after_reload:
		_open_settings_after_reload = false
		_show_settings_page()
	else:
		_show_main_page()


func _add_background() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(MENU_BACKGROUND_PATH):
		tex = load(MENU_BACKGROUND_PATH) as Texture2D
	if tex == null and FileAccess.file_exists(MENU_BACKGROUND_PATH):
		var image_data := Image.new()
		if image_data.load(MENU_BACKGROUND_PATH) == OK:
			tex = ImageTexture.create_from_image(image_data)
	if tex != null:
		var image := TextureRect.new()
		image.texture = tex
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(image)
	else:
		var fallback := ColorRect.new()
		fallback.color = Color(0.10, 0.14, 0.10)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fallback)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.018, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)


func _on_editor() -> void:
	get_tree().change_scene_to_file("res://game/design_editor.tscn")


func _button(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UISkin.apply_button(b)
	b.custom_minimum_size = Vector2(220, 40) * UISkin.ui_scale()
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _build_settings_panel(box: Container) -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	_settings_panel.custom_minimum_size = Vector2(300, 320) * UISkin.ui_scale()
	_settings_panel.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	box.add_child(_settings_panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(8.0 * UISkin.ui_scale()))
	_settings_panel.add_child(inner)

	var title := Label.new()
	title.text = "Einstellungen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UISkin.apply_label(title, false, 20)
	inner.add_child(title)

	var info := Label.new()
	info.text = "UI-Groesse: %s" % UISkin.ui_scale_name()
	UISkin.apply_label(info, true, 12)
	inner.add_child(info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(4.0 * UISkin.ui_scale()))
	inner.add_child(row)
	for choice in ["klein", "mittel", "gross"]:
		var scale_btn := _button(row, choice, _on_ui_scale.bind(choice))
		scale_btn.custom_minimum_size = Vector2(70, 32) * UISkin.ui_scale()

	var sep := HSeparator.new()
	inner.add_child(sep)

	var start_title := Label.new()
	start_title.text = "Startoptionen"
	UISkin.apply_label(start_title, false, 14)
	inner.add_child(start_title)

	_checkbox(inner, "Bauhilfe beim Start zeigen", "start_build_spots", false)
	_checkbox(inner, "Nebel des Krieges starten", "start_fog", false)
	_checkbox(inner, "KI-Gegner aktiv", "start_ai", true)

	var editor_btn := _button(inner, "Design-Editor", _on_editor)
	editor_btn.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()

	var back := _button(inner, "Zurück", _show_main_page)
	back.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()


func _show_settings_page() -> void:
	if _main_page != null:
		_main_page.visible = false
	if _settings_panel != null:
		_settings_panel.visible = true


func _show_main_page() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false
	if _main_page != null:
		_main_page.visible = true


func _checkbox(box: Container, text: String, key: String, fallback: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = UISkin.option_bool(key, fallback)
	c.add_theme_font_size_override("font_size", maxi(9, roundi(12.0 * UISkin.ui_scale())))
	c.add_theme_color_override("font_color", UISkin.color("font", Color.WHITE))
	c.toggled.connect(func(v: bool): UISkin.set_option_bool(key, v))
	box.add_child(c)
	return c


func _on_ui_scale(name: String) -> void:
	UISkin.set_ui_scale_name(name)
	_open_settings_after_reload = true
	get_tree().reload_current_scene()


func _on_new() -> void:
	World.boot_load = false
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_load() -> void:
	World.boot_load = true
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	get_tree().quit()
