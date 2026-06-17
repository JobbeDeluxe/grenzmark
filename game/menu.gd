extends Control

## Einfaches Hauptmenü: Neues Spiel, Laden, Einstellungen, Beenden.

const WORLD_SCENE := "res://game/main.tscn"
const SAVE_PATH := "user://settlers_save.dat"
const MENU_BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"
const UISkin := preload("res://game/ui_skin.gd")
const DEV_UNLOCK_CODE := "jobbedeluxe"
const MAP_SOURCE_OPTIONS := [
	{ id = "random", label = "Zufall / Seed" },
	{ id = "devmap", label = "DEVMAP" },
]
const MAP_SIZE_OPTIONS := [
	{ id = "small", label = "Klein 64x64", w = 64, h = 64 },
	{ id = "medium", label = "Mittel 96x96", w = 96, h = 96 },
	{ id = "large", label = "Gross 128x128", w = 128, h = 128 },
]

static var _open_settings_after_reload := false

var _main_page: VBoxContainer
var _new_game_panel: PanelContainer
var _settings_panel: PanelContainer
var _dev_section: VBoxContainer
var _dev_unlock_buffer := ""
var _map_controls: Array = []


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

	_button(_main_page, "Neues Spiel", _show_new_game_page)
	var load_btn := _button(_main_page, "Spiel laden", _on_load)
	load_btn.disabled = not FileAccess.file_exists(SAVE_PATH)
	_button(_main_page, "Einstellungen", _show_settings_page)
	_build_new_game_panel(box)
	_build_settings_panel(box)
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


func _build_new_game_panel(box: Container) -> void:
	_new_game_panel = PanelContainer.new()
	_new_game_panel.visible = false
	_new_game_panel.custom_minimum_size = Vector2(360, 380) * UISkin.ui_scale()
	_new_game_panel.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	box.add_child(_new_game_panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(8.0 * UISkin.ui_scale()))
	_new_game_panel.add_child(inner)

	var title := Label.new()
	title.text = "Neues Spiel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UISkin.apply_label(title, false, 20)
	inner.add_child(title)

	var hint := Label.new()
	hint.text = "Seed, Groesse und Gegnerzahl bestimmen den Welt-Hash."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(hint, true, 11)
	inner.add_child(hint)

	_add_map_settings_controls(inner)

	var start := _button(inner, "Spiel starten", _on_new)
	start.custom_minimum_size = Vector2(180, 36) * UISkin.ui_scale()

	var back := _button(inner, "Zurueck", _show_main_page)
	back.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()


func _build_settings_panel(box: Container) -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	_settings_panel.custom_minimum_size = Vector2(360, 520) * UISkin.ui_scale()
	_settings_panel.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	box.add_child(_settings_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_panel.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(8.0 * UISkin.ui_scale()))
	scroll.add_child(inner)

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
	# Im Original gibt es keine dauerhafte Warenleiste oben — daher abwählbar (Standard: aus).
	_checkbox(inner, "Warenleiste oben anzeigen", "show_resource_bar", false)
	# Waren an Flaggen: dicht gestapelt (Original) oder als übersichtliches Raster (#38).
	_checkbox(inner, "Waren dicht stapeln (Original)", "goods_cluster_layout", true)

	inner.add_child(HSeparator.new())
	var map_title := Label.new()
	map_title.text = "Karteneinstellungen"
	UISkin.apply_label(map_title, false, 14)
	inner.add_child(map_title)
	_add_map_settings_controls(inner)

	inner.add_child(HSeparator.new())
	_dev_section = VBoxContainer.new()
	_dev_section.add_theme_constant_override("separation", roundi(6.0 * UISkin.ui_scale()))
	_dev_section.visible = UISkin.option_bool("dev_menu_unlocked", false)
	inner.add_child(_dev_section)
	var dev_title := Label.new()
	dev_title.text = "Dev/Test"
	UISkin.apply_label(dev_title, false, 14)
	_dev_section.add_child(dev_title)
	_checkbox(_dev_section, "Startterritorium = ganze Karte", "dev_full_territory", false)
	_checkbox(_dev_section, "Erze sichtbar", "dev_show_ore", false)
	_checkbox(_dev_section, "Alles aufgedeckt", "dev_reveal_all", false)

	var editor_btn := _button(inner, "Design-Editor", _on_editor)
	editor_btn.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()

	var back := _button(inner, "Zurück", _show_main_page)
	back.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()


func _input(event: InputEvent) -> void:
	if _settings_panel == null or not _settings_panel.visible:
		return
	if UISkin.option_bool("dev_menu_unlocked", false):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := OS.get_keycode_string(event.keycode).to_lower()
		if key.length() != 1:
			return
		_dev_unlock_buffer += key
		if _dev_unlock_buffer.length() > DEV_UNLOCK_CODE.length():
			_dev_unlock_buffer = _dev_unlock_buffer.substr(_dev_unlock_buffer.length() - DEV_UNLOCK_CODE.length())
		if _dev_unlock_buffer.ends_with(DEV_UNLOCK_CODE):
			UISkin.set_option_bool("dev_menu_unlocked", true)
			if _dev_section != null:
				_dev_section.visible = true


func _add_map_settings_controls(box: Container) -> void:
	var source := _option_button(box, "Kartenquelle", "map_source", "random", MAP_SOURCE_OPTIONS)
	_register_map_control("option", source, "map_source", "random", MAP_SOURCE_OPTIONS)
	var seed := _line_edit(box, "Seed (leer = zufaellig)", "map_seed_text", "")
	_register_map_control("line", seed, "map_seed_text", "")
	var size := _option_button(box, "Kartengroesse", "map_size", "medium", MAP_SIZE_OPTIONS)
	_register_map_control("option", size, "map_size", "medium", MAP_SIZE_OPTIONS)
	var enemies := _spin_int(box, "Gegner", "map_enemy_count", 1, 0, 5)
	_register_map_control("spin", enemies, "map_enemy_count", 1, [], 0, 5)
	_refresh_map_controls()


func _register_map_control(kind: String, control: Control, key: String, fallback,
		choices: Array = [], min_value: int = 0, max_value: int = 0) -> void:
	_map_controls.append({
		"kind": kind,
		"control": control,
		"key": key,
		"fallback": fallback,
		"choices": choices,
		"min": min_value,
		"max": max_value,
	})


func _choice_index(choices: Array, current: String) -> int:
	for i in choices.size():
		var choice: Dictionary = choices[i]
		if String(choice.id) == current:
			return i
	return 0


func _refresh_map_controls(skip_control: Control = null) -> void:
	for entry in _map_controls:
		var control: Control = entry.control
		if control == skip_control or not is_instance_valid(control):
			continue
		control.set_block_signals(true)
		var key := String(entry.key)
		match String(entry.kind):
			"option":
				var option := control as OptionButton
				if option != null:
					var current := String(UISkin.option_value(key, entry.fallback))
					option.selected = _choice_index(entry.choices, current)
			"line":
				var edit := control as LineEdit
				if edit != null:
					edit.text = String(UISkin.option_value(key, entry.fallback))
			"spin":
				var spin := control as SpinBox
				if spin != null:
					spin.value = clampi(int(UISkin.option_value(key, entry.fallback)), int(entry.min), int(entry.max))
		control.set_block_signals(false)


func _option_button(box: Container, label: String, key: String, fallback: String, choices: Array) -> OptionButton:
	var caption := Label.new()
	caption.text = label
	UISkin.apply_label(caption, true, 11)
	box.add_child(caption)
	var btn := OptionButton.new()
	UISkin.apply_button(btn)
	var current := String(UISkin.option_value(key, fallback))
	var selected := 0
	for i in choices.size():
		var choice: Dictionary = choices[i]
		btn.add_item(String(choice.label))
		if String(choice.id) == current:
			selected = i
	btn.selected = selected
	btn.item_selected.connect(func(idx: int):
		var choice: Dictionary = choices[idx]
		UISkin.set_option_value(key, String(choice.id))
		_refresh_map_controls(btn)
	)
	box.add_child(btn)
	return btn


func _line_edit(box: Container, label: String, key: String, fallback: String) -> LineEdit:
	var caption := Label.new()
	caption.text = label
	UISkin.apply_label(caption, true, 11)
	box.add_child(caption)
	var edit := LineEdit.new()
	edit.text = String(UISkin.option_value(key, fallback))
	edit.placeholder_text = fallback
	edit.add_theme_font_size_override("font_size", maxi(9, roundi(12.0 * UISkin.ui_scale())))
	edit.text_changed.connect(func(text: String):
		UISkin.set_option_value(key, text)
		_refresh_map_controls(edit)
	)
	box.add_child(edit)
	return edit


func _spin_int(box: Container, label: String, key: String, fallback: int,
		min_value: int, max_value: int) -> SpinBox:
	var caption := Label.new()
	caption.text = label
	UISkin.apply_label(caption, true, 11)
	box.add_child(caption)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = clampi(int(UISkin.option_value(key, fallback)), min_value, max_value)
	spin.add_theme_font_size_override("font_size", maxi(9, roundi(12.0 * UISkin.ui_scale())))
	spin.value_changed.connect(func(value: float):
		UISkin.set_option_value(key, clampi(int(round(value)), min_value, max_value))
		_refresh_map_controls(spin)
	)
	box.add_child(spin)
	return spin


func _show_settings_page() -> void:
	_refresh_map_controls()
	if _main_page != null:
		_main_page.visible = false
	if _new_game_panel != null:
		_new_game_panel.visible = false
	if _settings_panel != null:
		_settings_panel.visible = true


func _show_new_game_page() -> void:
	_refresh_map_controls()
	if _main_page != null:
		_main_page.visible = false
	if _settings_panel != null:
		_settings_panel.visible = false
	if _new_game_panel != null:
		_new_game_panel.visible = true


func _show_main_page() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false
	if _new_game_panel != null:
		_new_game_panel.visible = false
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
