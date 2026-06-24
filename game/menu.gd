extends Control

## Einfaches Hauptmenü: Neues Spiel, Laden, Einstellungen, Beenden.

const WORLD_SCENE := "res://game/main.tscn"
const MENU_BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"
const UISkin := preload("res://game/ui_skin.gd")
const DEV_UNLOCK_CODE := "jobbedeluxe"
# Vorschlaege fuer die Kartengroesse — frei eingebbar bleibt das Textfeld trotzdem.
const MAP_SIZE_PRESETS := ["64x64", "96x96", "128x128", "256x128"]
const DEFAULT_SIZE_TEXT := "96x96"
# Kartentyp (#27) — Teil des Welt-Codes.
const MAP_TYPE_OPTIONS := [
	{ id = "flach", label = "Flach" },
	{ id = "fluss", label = "Flüsse" },
	{ id = "insel", label = "Inseln" },
	{ id = "zufall", label = "Zufällig" },
]

static var _open_settings_after_reload := false

var _main_page: VBoxContainer
var _new_game_panel: PanelContainer
var _settings_panel: PanelContainer
var _load_panel: PanelContainer
var _load_list: VBoxContainer
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
	var load_btn := _button(_main_page, "Spiel laden", _show_load_page)
	load_btn.disabled = SaveManager.list_saves().is_empty()
	_button(_main_page, "Einstellungen", _show_settings_page)
	_build_new_game_panel(box)
	_build_settings_panel(box)
	_build_load_panel(box)
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
	# Nebel des Krieges ist standardmäßig AN (#62) — nur durch explizites Abwählen aus.
	_checkbox(inner, "Nebel des Krieges starten", "start_fog", true)
	_checkbox(inner, "KI-Gegner aktiv", "start_ai", true)
	# Im Original gibt es keine dauerhafte Warenleiste oben — daher abwählbar (Standard: aus).
	_checkbox(inner, "Warenleiste oben anzeigen", "show_resource_bar", false)
	# Waren an Flaggen: dicht gestapelt (Original) oder als übersichtliches Raster (#38).
	_checkbox(inner, "Waren dicht stapeln (Original)", "goods_cluster_layout", true)
	# Schwierigkeits-Option (#54): kein Gold auf der Karte — Gold-Vorkommen werden Kohle.
	_checkbox(inner, "Gold durch Kohle ersetzen (schwerer)", "map_replace_gold", false)

	# Spielregeln (#67): vor dem Spiel gewählte Hausregeln. Im Spiel bleiben sie
	# umschaltbar; hier wird nur die Vorwahl für ein neues Spiel festgelegt.
	inner.add_child(HSeparator.new())
	var rules_title := Label.new()
	rules_title.text = "Spielregeln"
	UISkin.apply_label(rules_title, false, 14)
	inner.add_child(rules_title)
	_checkbox(inner, "Ressourcen-Outbox: Straßenträger holt Ware aus dem Haus", "rule_output_via_carrier", false)
	_checkbox(inner, "Minen nehmen auch Bier als Nahrung", "rule_mines_accept_beer", false)

	# Karteneinstellungen gehören nur ins "Neues Spiel"-Tab — hier raus.
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
	_checkbox(_dev_section, "Ressourcen manipulierbar", "dev_resources_editable", false)

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
		# Layout-robust: zuerst das tatsaechlich getippte Zeichen (unicode) nehmen.
		# Bei vielen Nicht-US-Layouts liefert Godot keycode == 0, dann waere
		# get_keycode_string() leer und der Code wuerde nie erkannt.
		var key := ""
		if event.unicode >= 32:
			key = String.chr(event.unicode).to_lower()
		elif event.keycode != 0:
			key = OS.get_keycode_string(event.keycode).to_lower()
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
	_ensure_seed_initialized()

	# --- Welt-Seed (teilbarer Code) + Wuerfel-Button ---
	var seed_caption := Label.new()
	seed_caption.text = "Welt-Seed (zum Teilen)  —  DEVMAP = Testkarte"
	UISkin.apply_label(seed_caption, true, 11)
	box.add_child(seed_caption)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", roundi(4.0 * UISkin.ui_scale()))
	box.add_child(seed_row)

	var seed := LineEdit.new()
	seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed.text = String(UISkin.option_value("map_seed_text", ""))
	seed.add_theme_font_size_override("font_size", maxi(9, roundi(12.0 * UISkin.ui_scale())))
	seed.text_changed.connect(func(text: String):
		UISkin.set_option_value("map_seed_text", text)
		_sync_controls_from_seed(text, seed)
	)
	seed_row.add_child(seed)
	_register_map_control("line", seed, "map_seed_text", "")

	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "Neuen Zufalls-Seed wuerfeln"
	UISkin.apply_button(dice)
	dice.custom_minimum_size = Vector2(40, 30) * UISkin.ui_scale()
	dice.pressed.connect(_on_new_seed)
	seed_row.add_child(dice)

	# --- Kartengroesse: frei eingebbar + Vorschlag-Buttons ---
	var size_caption := Label.new()
	size_caption.text = "Kartengroesse (frei, z. B. 200x100)"
	UISkin.apply_label(size_caption, true, 11)
	box.add_child(size_caption)

	var size_edit := LineEdit.new()
	size_edit.text = String(UISkin.option_value("map_size_text", DEFAULT_SIZE_TEXT))
	size_edit.placeholder_text = DEFAULT_SIZE_TEXT
	size_edit.add_theme_font_size_override("font_size", maxi(9, roundi(12.0 * UISkin.ui_scale())))
	size_edit.text_changed.connect(func(text: String):
		UISkin.set_option_value("map_size_text", text)
		_recompose_world_code(size_edit)
	)
	box.add_child(size_edit)
	_register_map_control("line", size_edit, "map_size_text", DEFAULT_SIZE_TEXT)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", roundi(4.0 * UISkin.ui_scale()))
	box.add_child(preset_row)
	for preset in MAP_SIZE_PRESETS:
		var pb := Button.new()
		pb.text = preset
		UISkin.apply_button(pb)
		pb.custom_minimum_size = Vector2(54, 26) * UISkin.ui_scale()
		pb.pressed.connect(func():
			UISkin.set_option_value("map_size_text", preset)
			_recompose_world_code()
		)
		preset_row.add_child(pb)

	# --- Kartentyp ---
	var type_caption := Label.new()
	type_caption.text = "Kartentyp"
	UISkin.apply_label(type_caption, true, 11)
	box.add_child(type_caption)
	var type_btn := OptionButton.new()
	UISkin.apply_button(type_btn)
	var cur_type := String(UISkin.option_value("map_type", MapGenerator.DEFAULT_MAP_TYPE))
	for i in MAP_TYPE_OPTIONS.size():
		var opt: Dictionary = MAP_TYPE_OPTIONS[i]
		type_btn.add_item(String(opt.label))
		if String(opt.id) == cur_type:
			type_btn.selected = i
	type_btn.item_selected.connect(func(idx: int):
		UISkin.set_option_value("map_type", String(MAP_TYPE_OPTIONS[idx].id))
		_recompose_world_code(type_btn)
	)
	box.add_child(type_btn)
	_register_map_control("option", type_btn, "map_type", "flach", MAP_TYPE_OPTIONS)

	# --- Gegnerzahl ---
	var enemies := _spin_int(box, "Gegner", "map_enemy_count", 1, 0, MapGenerator.MAP_MAX_ENEMIES)
	enemies.value_changed.connect(func(_v: float): _recompose_world_code())
	_register_map_control("spin", enemies, "map_enemy_count", 1, [], 0, MapGenerator.MAP_MAX_ENEMIES)
	_refresh_map_controls()


## Sorgt fuer einen sinnvollen Vorbelegungs-Code beim ersten Anzeigen.
func _ensure_seed_initialized() -> void:
	var raw := String(UISkin.option_value("map_seed_text", "")).strip_edges()
	var parsed := MapGenerator.parse_world_code(raw)
	if parsed.devmap:
		return
	if raw == "" or not bool(parsed.has_size):
		var size := MapGenerator.parse_size_text(
			String(UISkin.option_value("map_size_text", DEFAULT_SIZE_TEXT)))
		var enemies := clampi(int(UISkin.option_value("map_enemy_count", 1)), 0, MapGenerator.MAP_MAX_ENEMIES)
		var token := String(parsed.token)
		if token == "":
			token = MapGenerator.random_world_token()
		var code := MapGenerator.format_world_code(size.x, size.y, enemies, token, _current_map_type())
		UISkin.set_option_value("map_seed_text", code)
		UISkin.set_option_value("map_size_text", "%dx%d" % [size.x, size.y])
		UISkin.set_option_value("map_enemy_count", enemies)


## Liefert den aktuell gewählten Kartentyp (mit Validierung).
func _current_map_type() -> String:
	var mt := String(UISkin.option_value("map_type", MapGenerator.DEFAULT_MAP_TYPE))
	return mt if MapGenerator.MAP_TYPES.has(mt) else MapGenerator.DEFAULT_MAP_TYPE


## Liefert den aktuell aktiven Karten-Token (DEVMAP bleibt DEVMAP).
func _current_token() -> String:
	var parsed := MapGenerator.parse_world_code(String(UISkin.option_value("map_seed_text", "")))
	if parsed.devmap:
		return MapGenerator.DEVMAP_CODE
	var t := String(parsed.token)
	if t == "":
		t = MapGenerator.random_world_token()
	return t


## Baut den Welt-Code aus aktueller Groesse/Gegner/Token neu zusammen und zeigt ihn an.
func _recompose_world_code(skip: Control = null) -> void:
	if String(_current_token()) == MapGenerator.DEVMAP_CODE:
		return  # DEVMAP ignoriert Groesse/Gegner — Code unveraendert lassen.
	var size := MapGenerator.parse_size_text(
		String(UISkin.option_value("map_size_text", DEFAULT_SIZE_TEXT)))
	var enemies := clampi(int(UISkin.option_value("map_enemy_count", 1)), 0, MapGenerator.MAP_MAX_ENEMIES)
	var code := MapGenerator.format_world_code(size.x, size.y, enemies, _current_token(), _current_map_type())
	UISkin.set_option_value("map_seed_text", code)
	_refresh_map_controls(skip)


## Wuerfelt einen neuen Token (Groesse/Gegner bleiben).
func _on_new_seed() -> void:
	var size := MapGenerator.parse_size_text(
		String(UISkin.option_value("map_size_text", DEFAULT_SIZE_TEXT)))
	var enemies := clampi(int(UISkin.option_value("map_enemy_count", 1)), 0, MapGenerator.MAP_MAX_ENEMIES)
	var code := MapGenerator.format_world_code(
		size.x, size.y, enemies, MapGenerator.random_world_token(), _current_map_type())
	UISkin.set_option_value("map_seed_text", code)
	UISkin.set_option_value("map_size_text", "%dx%d" % [size.x, size.y])
	_refresh_map_controls()


## Tippt jemand einen vollstaendigen Code ins Seed-Feld, uebernehmen Groesse/Gegner mit.
func _sync_controls_from_seed(text: String, skip: Control) -> void:
	var parsed := MapGenerator.parse_world_code(text)
	if parsed.devmap or not bool(parsed.has_size):
		return
	UISkin.set_option_value("map_size_text", "%dx%d" % [int(parsed.width), int(parsed.height)])
	UISkin.set_option_value("map_enemy_count", clampi(int(parsed.enemies), 0, MapGenerator.MAP_MAX_ENEMIES))
	UISkin.set_option_value("map_type", String(parsed.map_type))
	_refresh_map_controls(skip)


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
	_hide_all_pages()
	if _settings_panel != null:
		_settings_panel.visible = true


func _show_new_game_page() -> void:
	_refresh_map_controls()
	_hide_all_pages()
	if _new_game_panel != null:
		_new_game_panel.visible = true


func _show_load_page() -> void:
	_hide_all_pages()
	_refresh_load_list()
	if _load_panel != null:
		_load_panel.visible = true


func _show_main_page() -> void:
	_hide_all_pages()
	if _main_page != null:
		_main_page.visible = true


func _hide_all_pages() -> void:
	if _main_page != null:
		_main_page.visible = false
	if _new_game_panel != null:
		_new_game_panel.visible = false
	if _settings_panel != null:
		_settings_panel.visible = false
	if _load_panel != null:
		_load_panel.visible = false


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


## Lade-Panel im Hauptmenü: Liste aller benannten Spielstände.
func _build_load_panel(box: Container) -> void:
	_load_panel = PanelContainer.new()
	_load_panel.visible = false
	_load_panel.custom_minimum_size = Vector2(360, 380) * UISkin.ui_scale()
	_load_panel.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	box.add_child(_load_panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(8.0 * UISkin.ui_scale()))
	_load_panel.add_child(inner)

	var title := Label.new()
	title.text = "Spiel laden"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UISkin.apply_label(title, false, 20)
	inner.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(320, 260) * UISkin.ui_scale()
	inner.add_child(scroll)
	_load_list = VBoxContainer.new()
	_load_list.add_theme_constant_override("separation", roundi(4.0 * UISkin.ui_scale()))
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_load_list)

	var back := _button(inner, "Zurueck", _show_main_page)
	back.custom_minimum_size = Vector2(160, 34) * UISkin.ui_scale()


func _refresh_load_list() -> void:
	if _load_list == null:
		return
	for c in _load_list.get_children():
		c.queue_free()
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var none := Label.new()
		none.text = "Keine Spielstände vorhanden."
		UISkin.apply_label(none, true, 12)
		_load_list.add_child(none)
		return
	for entry in saves:
		var e: Dictionary = entry
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", roundi(4.0 * UISkin.ui_scale()))
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_load_list.add_child(row)
		var label := "%s   (%s, %s)" % [
			String(e.get("name", "?")), String(e.get("size", "?")),
			SaveManager.format_date(int(e.get("saved_at", 0)))]
		var pick := _button(row, label, _start_load.bind(String(e.get("path", ""))))
		pick.custom_minimum_size = Vector2(240, 32) * UISkin.ui_scale()
		pick.clip_text = true
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _start_load(path: String) -> void:
	World.boot_load = true
	World.boot_load_path = path
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	get_tree().quit()
