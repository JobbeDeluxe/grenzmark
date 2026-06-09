class_name World
extends Node2D

## Aufbau der Welt, Bau-Modi, Eingabe, HUD/Menü/Minikarte und Speichern/Laden.
## Verbindet die reine Logik (WorldState/Economy) mit Darstellung und Kamera.

const UISkin := preload("res://game/ui_skin.gd")
const MAP_W := 96
const MAP_H := 96
const MAP_SEED := 1337
const TICK_HZ := 30.0
const SAVE_PATH := "user://settlers_save.dat"

enum { MODE_SELECT, MODE_FLAG, MODE_ROAD, MODE_BUILD, MODE_DELETE }

var map: MapData
var state: WorldState
var economy: Economy
var renderer: MapRenderer
var unit_renderer: UnitRenderer
var camera: CameraController
var minimap: MiniMap

var mode := MODE_SELECT
var build_def_id := ""
var ai_list: Array = []
var ai_choice := 0
var hover := Vector2i(-1, -1)
var road_start := Vector2i(-1, -1)

var _tick_accum := 0.0
var sim_speed := 1.0
var paused := false
var _mode_label: Label
var _info_label: Label
var _stock_label: Label
var _stock_counts: Dictionary = {}
var _selection_panel: PanelContainer
var _sel_label: Label
var _sel_title_label: Label
var _sel_icon: TextureRect
var _sel_btn_stop: Button
var _sel_btn_goto: Button
var _sel_btn_demolish: Button
var _sel_btn_attack: Button
var _status_label: Label
var _build_panel: PanelContainer
var _build_action_row: HBoxContainer
var _build_group_row: HBoxContainer
var _build_scroll: ScrollContainer
var _build_row: GridContainer
var _build_caption: Label
var _build_group_buttons := {}
var _economy_panel: PanelContainer
var _mainsel_panel: PanelContainer
var _buildings_panel: PanelContainer
var _buildings_label: Label
var _stats_panel: PanelContainer
var _stats_label: Label
var _settings_panel: PanelContainer
var _settings_body: Label
var _minimap_panel: PanelContainer
var _flag_menu: PanelContainer
var _flag_menu_pos := Vector2i(-1, -1)
var _building_windows := {}
var _ui_root: Control
var ui_category := "hut"
var build_filter_bq := -1
var build_window_spot := Vector2i(-1, -1)
var selected: WorldState.Building

## Wird vom Hauptmenü gesetzt: true = beim Start Spielstand laden.
static var boot_load := false


func _ready() -> void:
	if boot_load:
		boot_load = false
		_new_game()   # Grundgerüst, dann laden
		_load_game()
	else:
		_new_game()


func _new_game() -> void:
	selected = null
	paused = false
	map = MapGenerator.generate(MAP_W, MAP_H, MAP_SEED)
	state = WorldState.new(map)
	economy = Economy.new(state)
	_wire_world()
	_apply_ai()
	_apply_start_options()
	var hq := _place_headquarters()
	_ensure_test_pond_near(hq)
	_place_enemy(hq)
	economy.resync()
	camera.position = map.node_world(hq.x, hq.y) if hq.x >= 0 \
		else map.node_world(MAP_W / 2, MAP_H / 2)
	renderer.queue_redraw()
	_update_labels()


## Renderer/Kamera/UI erzeugen (einmal, bzw. bei Laden neu verbinden).
func _wire_world() -> void:
	for c in get_children():
		c.queue_free()
	renderer = MapRenderer.new()
	renderer.setup(state)
	add_child(renderer)

	unit_renderer = UnitRenderer.new()
	unit_renderer.setup(economy)
	add_child(unit_renderer)

	camera = CameraController.new()
	camera.zoom = Vector2(1.5, 1.5)
	add_child(camera)

	_build_ui()


func _place_headquarters() -> Vector2i:
	var hq_def := BuildingCatalog.get_def("hq")
	var cx := MAP_W / 2
	var cy := MAP_H / 2
	for r in range(0, maxi(MAP_W, MAP_H)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if state.can_place_building(x, y, WorldState.BQ_CASTLE):
					var b := state.place_building(x, y, WorldState.BQ_CASTLE, true,
						"hq", int(hq_def.get("influence", 9)), false)
					b.garrison = 6
					b.capacity = 6
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Testteich im Startgebiet: klein genug, um Bauland nicht zu ruinieren, nah genug
## fuer Fischerhuetten-Tests ohne an den Kartenrand laufen zu muessen.
func _ensure_test_pond_near(hq: Vector2i) -> void:
	if hq.x < 0:
		return
	var candidates := [
		hq + Vector2i(7, 1),
		hq + Vector2i(-7, 1),
		hq + Vector2i(6, -5),
		hq + Vector2i(-6, -5),
	]
	var center := Vector2i(-1, -1)
	for p in candidates:
		if map.in_bounds(p.x - 4, p.y - 4) and map.in_bounds(p.x + 4, p.y + 4) \
				and WorldState.hex_distance(hq, p) >= 6:
			center = p
			break
	if center.x < 0:
		return
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var p := center + Vector2i(dx, dy)
			if not map.in_bounds(p.x, p.y):
				continue
			if state._occ(p.x, p.y) != WorldState.OBJ_NONE:
				continue
			var d := WorldState.hex_distance(center, p)
			if d <= 2:
				map.set_height(p.x, p.y, 2)
				map.set_tri(p, Grid.TRI_R, Terrain.WATER)
				map.set_tri(p, Grid.TRI_D, Terrain.WATER)
				map.clear_map_object(p.x, p.y)
			elif d == 3:
				map.set_height(p.x, p.y, 4)
				map.set_tri(p, Grid.TRI_R, Terrain.SAND)
				map.set_tri(p, Grid.TRI_D, Terrain.SAND)
				map.clear_map_object(p.x, p.y)


## Gewählte Gegner-KI auf die Economy anwenden.
func _apply_ai() -> void:
	if ai_list.is_empty():
		ai_list = AIRegistry.list()
	ai_choice = clampi(ai_choice, 0, ai_list.size() - 1)
	economy.ai = AIRegistry.create(ai_list[ai_choice])


func _apply_start_options() -> void:
	if renderer != null:
		renderer.show_build_spots = UISkin.option_bool("start_build_spots", false)
		renderer.fog_enabled = UISkin.option_bool("start_fog", false)
		renderer.queue_redraw()
	if economy != null:
		economy.ai_enabled = UISkin.option_bool("start_ai", true)


func _cycle_ai() -> void:
	if ai_list.is_empty():
		ai_list = AIRegistry.list()
	ai_choice = (ai_choice + 1) % ai_list.size()
	economy.ai = AIRegistry.create(ai_list[ai_choice])
	_flash("Gegner-KI: " + String(ai_list[ai_choice].name))
	_update_labels()


## Gegner-HQ auf dem weitest entfernten Burg-Platz vom Spieler (immer auf Land).
func _place_enemy(player_hq: Vector2i) -> void:
	var spot := _farthest_castle_spot(player_hq)
	if spot.x < 0:
		return
	_add_building_raw(spot, WorldState.BQ_CASTLE, "hq", 9, 1, 6, 6, true)
	# Nur EIN Start-Wachhaus — den Rest baut die KI selbst auf (sichtbarer Aufbau).
	for off in [Vector2i(3, 2), Vector2i(-3, 3)]:
		var p: Vector2i = spot + off
		if map.in_bounds(p.x, p.y) and state.compute_bq(p.x, p.y) >= WorldState.BQ_HUT \
				and state._occ(p.x, p.y) == WorldState.OBJ_NONE:
			_add_building_raw(p, WorldState.BQ_HUT, "guardhouse", 5, 1, 2, 2, false)
			break


func _farthest_castle_spot(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1
	for y in range(2, MAP_H - 2):
		for x in range(2, MAP_W - 2):
			if state._occ(x, y) != WorldState.OBJ_NONE:
				continue
			if state.compute_bq(x, y) < WorldState.BQ_CASTLE:
				continue
			var d := WorldState.hex_distance(Vector2i(x, y), from) if from.x >= 0 else 0
			if d > best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


func _add_building_raw(pos: Vector2i, size: int, def_id: String, infl: int,
		owner: int, gar: int, cap: int, is_hq: bool) -> void:
	var b := state.place_building(pos.x, pos.y, size, is_hq, def_id, infl, false, owner)
	if b == null:
		return
	b.garrison = gar
	b.capacity = cap
	state.recompute_territory()
	if not is_hq:
		_connect_new_building_to_owner_network(b)


func _connect_new_building_to_owner_network(b: WorldState.Building) -> void:
	var hq := _owner_hq_flag_pos(b.owner)
	if hq.x < 0:
		return
	var best_from := Vector2i(-1, -1)
	var best_len := 1 << 30
	for fi in state.flags:
		var f: WorldState.Flag = state.flags[fi]
		if f.owner != b.owner or f.pos == b.flag_pos:
			continue
		if f.pos != hq and state.find_route(hq, f.pos).size() < 2:
			continue
		var path := state.plan_road(f.pos, b.flag_pos, b.owner)
		if path.is_empty():
			continue
		if path.size() < best_len:
			best_len = path.size()
			best_from = f.pos
	if best_from.x >= 0:
		state.build_road(best_from, b.flag_pos, b.owner)


func _owner_hq_flag_pos(owner: int) -> Vector2i:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq and b.owner == owner:
			return b.flag_pos
	return Vector2i(-1, -1)


func _process(delta: float) -> void:
	if not paused:
		_tick_accum += delta
		var step := (1.0 / TICK_HZ) / sim_speed
		var guard := 0
		while _tick_accum >= step and guard < 16:
			economy.tick()
			_tick_accum -= step
			guard += 1
	if economy.dirty:
		economy.dirty = false
		renderer.queue_redraw()
		if unit_renderer != null:
			unit_renderer.invalidate_occluders()  # Bau/Abriss/Baum → Occluder neu
	if not _stock_counts.is_empty():
		_update_stock()
	_update_building_windows()
	_check_game_over()


func _check_game_over() -> void:
	if _status_label == null or _status_label.text != "":
		return
	var player_hq := false
	var enemy_hq := false
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq:
			if b.owner == 0: player_hq = true
			else: enemy_hq = true
	if not player_hq:
		_status_label.text = "NIEDERLAGE"
		paused = true
	elif not enemy_hq:
		_status_label.text = "SIEG!"
		paused = true


# --------------------------------------------------------------------------
#  UI: Bau-Menü, Statusleiste, Vorrats-Anzeige, Minikarte
# --------------------------------------------------------------------------

const BUILD_GROUPS := [
	["Bergwerk", "mine", "mine"],
	["Klein", "hut", "hut"],
	["Mittel", "house", "house"],
	["Groß", "castle", "castle"],
]
const BUILD_MIN_PANEL_SIZE := Vector2(280, 172)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var edge := UISkin.layout_num("edge_margin", 8)
	var top_h := UISkin.layout_num("top_bar_height", 72)
	var right_w := UISkin.layout_num("right_panel_width", 286)
	var bottom_h := UISkin.layout_num("bottom_bar_height", 138)
	var mini_size := UISkin.layout_num("minimap_size", 188)
	var build_w := UISkin.layout_num("build_panel_width", 850)
	var build_h := UISkin.layout_num("build_panel_height", 170)

	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Wichtig: der bildschirmfuellende Wurzel-Control darf KEINE Maus-Events
	# schlucken, sonst erreicht das Kamera-Schwenken (rechte/mittlere Taste)
	# und Welt-Klicks nie _unhandled_input. Die echten Panels (PanelContainer)
	# behalten ihren eigenen STOP-Filter und fangen ihre Klicks weiterhin ab.
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui_root)

	# Oben: kompakte Statuszeile + kleine Waren-Iconleiste.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.anchor_right = 1.0
	top.anchor_bottom = 0.0
	top.offset_left = edge
	top.offset_top = edge
	top.offset_right = -edge
	top.offset_bottom = edge + top_h
	_ui_root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top.add_child(top_row)
	var top_text := VBoxContainer.new()
	top_text.custom_minimum_size = Vector2(320, top_h - 8)
	top_row.add_child(top_text)
	_mode_label = Label.new()
	UISkin.apply_label(_mode_label, false, 11)
	top_text.add_child(_mode_label)
	_info_label = Label.new()
	UISkin.apply_label(_info_label, true, 10)
	top_text.add_child(_info_label)
	var stock_grid := GridContainer.new()
	stock_grid.columns = Goods.COUNT
	stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(stock_grid)
	_build_stock_cells(stock_grid)

	# Gebäudefenster werden beim Anklicken dynamisch erzeugt und bleiben parallel offen.

	_minimap_panel = _floating_panel(Vector2(1, 1), Vector2(-mini_size - edge, -mini_size - edge),
		Vector2(-edge, -edge))
	minimap = MiniMap.new()
	minimap.custom_minimum_size = Vector2(mini_size - 12, mini_size - 12)
	minimap.size = Vector2(mini_size - 12, mini_size - 12)
	minimap.setup(state, economy, camera)
	_minimap_panel.add_child(minimap)

	# Unten: nur drei Hauptzugriffe. Alles Weitere sind Fenster, wie im S2-Vorbild.
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 0.0
	bar.anchor_bottom = 1.0
	bar.offset_left = edge
	bar.offset_top = -bottom_h - edge
	bar.offset_right = edge + 292
	bar.offset_bottom = -edge
	_ui_root.add_child(bar)
	var main_buttons := HBoxContainer.new()
	main_buttons.add_theme_constant_override("separation", 4)
	bar.add_child(main_buttons)
	_tbutton(main_buttons, "Bauen", _toggle_build_panel)
	_tbutton(main_buttons, "Verwaltung", _toggle_mainsel)
	_tbutton(main_buttons, "System", _toggle_settings)

	_build_panel = _floating_panel(Vector2(0, 1), Vector2(edge, -bottom_h - build_h - edge * 2.0),
		Vector2(edge + build_w, -bottom_h - edge * 2.0))
	_build_panel.visible = false
	_build_panel.resized.connect(_refresh_build_panel_layout)
	var build_box := _add_window_chrome(_build_panel, "Bauen", _toggle_build_panel)
	_build_caption = Label.new()
	UISkin.apply_label(_build_caption, true, 12)
	build_box.add_child(_build_caption)
	_build_action_row = HBoxContainer.new()
	_build_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_action_row.add_theme_constant_override("separation", 5)
	build_box.add_child(_build_action_row)
	_build_icon_button(_build_action_row, "", _set_mode.bind(MODE_FLAG), "Flagge setzen",
		GameTheme.build_spot_texture("flag"), Vector2(42, 34))
	_build_icon_button(_build_action_row, "", _set_mode.bind(MODE_ROAD), "Straße bauen",
		GameTheme.build_spot_texture("road_flag"), Vector2(42, 34))
	_build_icon_button(_build_action_row, "X", _set_mode.bind(MODE_DELETE), "Abriss",
		null, Vector2(42, 34))
	_build_icon_button(_build_action_row, "?", _toggle_build_spots, "Bauhilfe ein/aus",
		null, Vector2(42, 34))
	_build_group_row = HBoxContainer.new()
	_build_group_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_group_row.add_theme_constant_override("separation", 5)
	build_box.add_child(_build_group_row)
	_build_group_buttons.clear()
	for c in BUILD_GROUPS:
		var cat_btn := _build_icon_button(_build_group_row, String(c[0]), _show_category.bind(c[1]),
			_group_label(c[1]), GameTheme.build_spot_texture(String(c[2])), Vector2(88, 44))
		cat_btn.toggle_mode = true
		_build_group_buttons[c[1]] = cat_btn
	_build_scroll = ScrollContainer.new()
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_scroll.custom_minimum_size = Vector2(0, 112.0 * UISkin.ui_scale())
	build_box.add_child(_build_scroll)
	_build_row = GridContainer.new()
	_build_row.columns = 4
	_build_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_row.add_theme_constant_override("h_separation", 5)
	_build_row.add_theme_constant_override("v_separation", 5)
	_build_scroll.add_child(_build_row)
	_show_category(ui_category)

	_economy_panel = _floating_panel(Vector2(0, 1), Vector2(edge + 304, -bottom_h - 250 - edge * 2.0),
		Vector2(edge + 604, -bottom_h - edge * 2.0))
	_economy_panel.visible = false
	var economy_box := _add_window_chrome(_economy_panel, "Inventur", _toggle_economy_panel)
	_stock_label = Label.new()
	_stock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_stock_label, true, 11)
	_stock_label.mouse_filter = Control.MOUSE_FILTER_PASS
	economy_box.add_child(_stock_label)

	# Hauptauswahl (S2-artig): öffnet die Verwaltungsfenster.
	_mainsel_panel = _floating_panel(Vector2(0, 1), Vector2(edge, -bottom_h - 250 - edge * 2.0),
		Vector2(edge + 200, -bottom_h - edge * 2.0))
	_mainsel_panel.visible = false
	var mainsel_box := _add_window_chrome(_mainsel_panel, "Verwaltung", _toggle_mainsel)
	_tbutton(mainsel_box, "Inventur", _open_inventory)
	_tbutton(mainsel_box, "Gebaeude", _open_buildings)
	_tbutton(mainsel_box, "Statistik", _open_stats)
	for stub in ["Verteilung", "Transport", "Werkzeuge", "Produktivitaet", "Militaer"]:
		var sb := _tbutton(mainsel_box, stub, _noop)
		sb.disabled = true
		sb.tooltip_text = "Noch nicht implementiert"

	# Gebäude-Übersicht (Anzahl je Typ).
	_buildings_panel = _floating_panel(Vector2(0, 1), Vector2(edge + 224, -bottom_h - 300 - edge * 2.0),
		Vector2(edge + 524, -bottom_h - edge * 2.0))
	_buildings_panel.visible = false
	var buildings_box := _add_window_chrome(_buildings_panel, "Gebaeude", _open_buildings)
	_buildings_label = Label.new()
	_buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_buildings_label, true, 11)
	_buildings_label.mouse_filter = Control.MOUSE_FILTER_PASS
	buildings_box.add_child(_buildings_label)

	# Statistik (Kennzahlen).
	_stats_panel = _floating_panel(Vector2(0, 1), Vector2(edge + 224, -bottom_h - 220 - edge * 2.0),
		Vector2(edge + 484, -bottom_h - edge * 2.0))
	_stats_panel.visible = false
	var stats_box := _add_window_chrome(_stats_panel, "Statistik", _open_stats)
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_stats_label, true, 11)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_box.add_child(_stats_label)

	_settings_panel = _floating_panel(Vector2(0.5, 0.5), Vector2(-260, -180), Vector2(260, 180))
	_settings_panel.visible = false
	var settings_box := _add_window_chrome(_settings_panel, "Einstellungen & Design", _toggle_settings)
	_settings_body = Label.new()
	_settings_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_settings_body, true, 12)
	_settings_body.mouse_filter = Control.MOUSE_FILTER_PASS
	settings_box.add_child(_settings_body)
	var settings_actions := HBoxContainer.new()
	settings_actions.add_theme_constant_override("separation", 4)
	settings_box.add_child(settings_actions)
	_tbutton(settings_actions, "Bauplaetze", _toggle_build_spots)
	_tbutton(settings_actions, "Nebel", _toggle_fog)
	_tbutton(settings_actions, "KI", _toggle_ai)
	_tbutton(settings_actions, "Pause", _toggle_pause)
	var scale_actions := HBoxContainer.new()
	scale_actions.add_theme_constant_override("separation", 4)
	settings_box.add_child(scale_actions)
	_tbutton(scale_actions, "UI klein", _set_ui_scale.bind("klein"))
	_tbutton(scale_actions, "UI mittel", _set_ui_scale.bind("mittel"))
	_tbutton(scale_actions, "UI gross", _set_ui_scale.bind("gross"))
	_update_settings_text()

	# Flaggen-Kontextmenü (S2-artig): erscheint an der angeklickten Flagge.
	_flag_menu = _floating_panel(Vector2(0, 0), Vector2(0, 0), Vector2(168, 0))
	_flag_menu.visible = false
	var flag_box := _add_window_chrome(_flag_menu, "Flagge", _close_flag_menu)
	_tbutton(flag_box, "Weg bauen", _flag_menu_build_road)
	_tbutton(flag_box, "Flagge entfernen", _flag_menu_remove)
	var geo := _tbutton(flag_box, "Geologe", _noop)
	geo.disabled = true
	geo.tooltip_text = "Noch nicht implementiert"
	var scout := _tbutton(flag_box, "Spaeher", _noop)
	scout.disabled = true
	scout.tooltip_text = "Noch nicht implementiert"

	# Sieg/Niederlage-Anzeige (zentriert)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 52)
	_status_label.anchor_left = 0.5
	_status_label.anchor_top = 0.5
	_status_label.anchor_right = 0.5
	_status_label.anchor_bottom = 0.5
	_status_label.offset_left = -140
	_status_label.offset_top = -30
	_status_label.offset_right = 180
	_status_label.offset_bottom = 40
	_status_label.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_status_label)


func _floating_panel(anchor: Vector2, from: Vector2, to: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.panel_style("panel"))
	panel.anchor_left = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_right = anchor.x
	panel.anchor_bottom = anchor.y
	panel.offset_left = from.x
	panel.offset_top = from.y
	panel.offset_right = to.x
	panel.offset_bottom = to.y
	_ui_root.add_child(panel)
	return panel


## Gibt einem Fenster eine S2-artige Kopfzeile: Titel (Drag), Park- und Schließen-
## Button, Rechtsklick-zum-Schließen. Liefert den Inhalts-Container zurück.
func _add_window_chrome(panel: PanelContainer, title: String, on_close: Callable) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", roundi(6.0 * UISkin.ui_scale()))
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(6.0 * UISkin.ui_scale()))
	# Kopfzeile ist Ziehfläche: Maus-Events hier bewegen das Fenster.
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	var drag := {active = false, start_mouse = Vector2.ZERO, start = Vector2.ZERO}
	head.gui_input.connect(func(ev): _window_header_input(panel, drag, ev))
	outer.add_child(head)

	var title_label := Label.new()
	UISkin.apply_label(title_label, false, 14)
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title_label)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", roundi(6.0 * UISkin.ui_scale()))
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS

	# Park/Einklappen (obere rechte Ecke): klappt das Fenster auf die Titelleiste ein
	# (Rollup) — die Höhe schrumpft wirklich, nicht nur der Inhalt verschwindet.
	var park := _chrome_button("_", func(): _toggle_park(panel, content, head))
	park.tooltip_text = "Einklappen / Ausklappen"
	head.add_child(park)
	# Schließen (obere Ecke) — zusätzlich schließt Rechtsklick im Fenster.
	var close := _chrome_button("X", on_close)
	close.tooltip_text = "Schliessen (oder Rechtsklick im Fenster)"
	head.add_child(close)

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev): _window_panel_input(on_close, ev))

	outer.add_child(content)

	# Größengriff unten rechts: zieht offset_right/offset_bottom (Fenster skalieren).
	var grip_row := HBoxContainer.new()
	grip_row.alignment = BoxContainer.ALIGNMENT_END
	grip_row.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(grip_row)
	var grip := ColorRect.new()
	grip.color = UISkin.color("accent", Color(0.9, 0.74, 0.33)).darkened(0.1)
	grip.custom_minimum_size = Vector2(14, 14) * UISkin.ui_scale()
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.tooltip_text = "Groesse ziehen"
	var rs := {active = false, start_mouse = Vector2.ZERO, w = 0.0, h = 0.0}
	grip.gui_input.connect(func(ev): _window_resize_input(panel, rs, ev))
	grip_row.add_child(grip)

	panel.set_meta("title_label", title_label)
	panel.set_meta("content", content)
	panel.set_meta("head", head)
	# Neu geöffnete Fenster starten IMMER ausgeklappt (Park-Zustand zurücksetzen).
	panel.visibility_changed.connect(func():
		if panel.visible:
			_window_expand(panel))
	return content


## Klappt ein Fenster auf seine Titelleiste ein bzw. wieder aus (echtes Rollup).
func _toggle_park(panel: PanelContainer, content: Control, head: Control) -> void:
	if content.visible:
		# Volle Höhe merken (robust gegen späteres Verschieben), dann auf Titel kürzen.
		panel.set_meta("full_height", panel.offset_bottom - panel.offset_top)
		content.visible = false
		var hh := head.get_combined_minimum_size().y + 14.0
		panel.offset_bottom = panel.offset_top + hh
	else:
		_window_expand(panel)


## Setzt ein Fenster in den ausgeklappten Vollzustand zurück.
func _window_expand(panel: PanelContainer) -> void:
	if panel.has_meta("content"):
		(panel.get_meta("content") as Control).visible = true
	if panel.has_meta("full_height"):
		panel.offset_bottom = panel.offset_top + float(panel.get_meta("full_height"))


func _chrome_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(24, 22) * UISkin.ui_scale()
	b.add_theme_font_size_override("font_size", maxi(8, roundi(12.0 * UISkin.ui_scale())))
	b.add_theme_color_override("font_color", UISkin.color("font", Color.WHITE))
	b.add_theme_stylebox_override("normal", UISkin.button_style("button"))
	b.add_theme_stylebox_override("hover", UISkin.button_style("button_hover"))
	b.add_theme_stylebox_override("pressed", UISkin.button_style("button_pressed"))
	b.pressed.connect(cb)
	return b


## Drag des Fensters an der Titelleiste (Offsets in Pixeln, unabhängig vom Anker).
func _window_header_input(panel: PanelContainer, drag: Dictionary, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			drag.active = true
			drag.start_mouse = panel.get_global_mouse_position()
			drag.start = Vector2(panel.offset_left, panel.offset_top)
		else:
			drag.active = false
	elif ev is InputEventMouseMotion and drag.active:
		var delta: Vector2 = panel.get_global_mouse_position() - (drag.start_mouse as Vector2)
		var start: Vector2 = drag.start
		var w := panel.offset_right - panel.offset_left
		var h := panel.offset_bottom - panel.offset_top
		panel.offset_left = start.x + delta.x
		panel.offset_top = start.y + delta.y
		panel.offset_right = panel.offset_left + w
		panel.offset_bottom = panel.offset_top + h


## Rechtsklick irgendwo im Fenster schließt es (wie im Original).
func _window_panel_input(on_close: Callable, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		on_close.call()


## Skaliert das Fenster über den Griff unten rechts (Breite/Höhe per Maus ziehen).
func _window_resize_input(panel: PanelContainer, rs: Dictionary, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			rs.active = true
			rs.start_mouse = panel.get_global_mouse_position()
			rs.w = panel.offset_right - panel.offset_left
			rs.h = panel.offset_bottom - panel.offset_top
		else:
			rs.active = false
	elif ev is InputEventMouseMotion and rs.active:
		var delta: Vector2 = panel.get_global_mouse_position() - (rs.start_mouse as Vector2)
		var min_size := BUILD_MIN_PANEL_SIZE * UISkin.ui_scale() if panel == _build_panel \
			else Vector2(140, 70) * UISkin.ui_scale()
		var nw: float = maxf(min_size.x, float(rs.w) + delta.x)
		var nh: float = maxf(min_size.y, float(rs.h) + delta.y)
		panel.offset_right = panel.offset_left + nw
		panel.offset_bottom = panel.offset_top + nh
		# Volle Höhe nachführen, damit Ein-/Ausklappen die neue Größe behält.
		if panel.has_meta("full_height"):
			panel.set_meta("full_height", nh)
		if panel == _build_panel:
			_refresh_build_panel_layout()


func _build_stock_cells(parent: GridContainer) -> void:
	_stock_counts.clear()
	for g in Goods.COUNT:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(UISkin.layout_num("good_cell_width", 56),
			UISkin.layout_num("good_cell_height", 24))
		cell.tooltip_text = Goods.name_of(g)
		parent.add_child(cell)
		var icon := TextureRect.new()
		var icon_px := UISkin.layout_num("good_icon_size", 18)
		icon.custom_minimum_size = Vector2(icon_px, icon_px)
		# WICHTIG: ohne EXPAND_IGNORE_SIZE erzwingt die 64x64-Quelltextur ihre
		# eigene Mindestgroesse und macht die Icons riesig — custom_minimum_size
		# wuerde ignoriert.
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = UISkin.good_texture(g)
		cell.add_child(icon)
		var label := Label.new()
		UISkin.apply_label(label, false, 13)
		label.text = "0"
		cell.add_child(label)
		_stock_counts[g] = label


func _open_general_build_menu() -> void:
	build_filter_bq = -1
	build_window_spot = Vector2i(-1, -1)
	if _build_panel != null:
		_hide_management_panels(_build_panel)
		_position_build_panel_default()
		_build_panel.visible = true
	_show_category(ui_category)
	_flash("Baufenster: alle Gebaeude. Space zeigt Bauplaetze; Klick auf Marker filtert passend.")


func _position_build_panel_default() -> void:
	if _build_panel == null:
		return
	var edge := UISkin.layout_num("edge_margin", 8)
	var bottom_h := UISkin.layout_num("bottom_bar_height", 46)
	var build_w := UISkin.layout_num("build_panel_width", 430)
	var build_h := UISkin.layout_num("build_panel_height", 245)
	var view := get_viewport_rect().size
	var size := Vector2(build_w, build_h)
	var pos := Vector2(edge, view.y - bottom_h - size.y - edge * 2.0)
	pos.x = clampf(pos.x, edge, maxf(edge, view.x - size.x - edge))
	pos.y = clampf(pos.y, edge, maxf(edge, view.y - size.y - edge))
	_set_panel_screen_rect(_build_panel, pos, size)
	_refresh_build_panel_layout()


func _position_build_panel_near_node(node: Vector2i) -> void:
	if _build_panel == null:
		return
	var world := map.node_world(node.x, node.y)
	var screen: Vector2 = get_viewport().get_canvas_transform() * world
	var size := _panel_size(_build_panel)
	var edge := UISkin.layout_num("edge_margin", 8)
	var gap := 18.0 * UISkin.ui_scale()
	var view := get_viewport_rect().size
	var pos := screen + Vector2(gap, -size.y * 0.5)
	if pos.x + size.x > view.x - edge:
		pos.x = screen.x - size.x - gap
	pos.x = clampf(pos.x, edge, maxf(edge, view.x - size.x - edge))
	pos.y = clampf(pos.y, edge, maxf(edge, view.y - size.y - edge))
	_set_panel_screen_rect(_build_panel, pos, size)
	_refresh_build_panel_layout()


func _set_panel_screen_rect(panel: PanelContainer, pos: Vector2, size: Vector2) -> void:
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = pos.x
	panel.offset_top = pos.y
	panel.offset_right = pos.x + size.x
	panel.offset_bottom = pos.y + size.y


func _panel_size(panel: PanelContainer) -> Vector2:
	return Vector2(panel.offset_right - panel.offset_left, panel.offset_bottom - panel.offset_top)


func _build_content_scale() -> float:
	if _build_panel == null:
		return 1.0
	var base := Vector2(UISkin.layout_num("build_panel_width", 430),
		UISkin.layout_num("build_panel_height", 245))
	var size := _panel_size(_build_panel)
	if base.x <= 0.0 or base.y <= 0.0:
		return 1.0
	return clampf(minf(size.x / base.x, size.y / base.y), 0.82, 1.55)


func _build_columns_for_width(content_scale: float) -> int:
	if _build_panel == null:
		return 4
	var usable := maxf(_panel_size(_build_panel).x - 32.0 * UISkin.ui_scale(), 120.0)
	var cell := (92.0 * UISkin.ui_scale() * content_scale) + 6.0 * UISkin.ui_scale()
	return clampi(int(floor(usable / maxf(cell, 1.0))), 2, 6)


func _refresh_build_panel_layout() -> void:
	if _build_panel == null or _build_row == null:
		return
	var content_scale := _build_content_scale()
	var sep := maxi(3, roundi(5.0 * UISkin.ui_scale() * content_scale))
	if _build_action_row != null:
		_build_action_row.add_theme_constant_override("separation", sep)
	if _build_group_row != null:
		_build_group_row.add_theme_constant_override("separation", sep)
	if _build_scroll != null:
		_build_scroll.custom_minimum_size = Vector2(0,
			maxf(96.0, 112.0 * UISkin.ui_scale() * content_scale))
	_build_row.columns = _build_columns_for_width(content_scale)
	_build_row.add_theme_constant_override("h_separation", sep)
	_build_row.add_theme_constant_override("v_separation", sep)
	_rescale_build_buttons(_build_panel, content_scale)


func _rescale_build_buttons(root: Node, content_scale: float) -> void:
	for child in root.get_children():
		if child is Button and child.has_meta("base_size"):
			var btn := child as Button
			var base: Vector2 = btn.get_meta("base_size")
			btn.custom_minimum_size = base * UISkin.ui_scale() * content_scale
			btn.add_theme_font_size_override("font_size",
				maxi(8, roundi(12.0 * UISkin.ui_scale() * content_scale)))
		_rescale_build_buttons(child, content_scale)


func _toggle_build_panel() -> void:
	if _build_panel == null:
		return
	var next := not _build_panel.visible
	_hide_management_panels()
	_build_panel.visible = next
	if next:
		build_filter_bq = -1
		build_window_spot = Vector2i(-1, -1)
		_position_build_panel_default()
		_show_category(ui_category)


func _toggle_economy_panel() -> void:
	if _economy_panel == null:
		return
	var next := not _economy_panel.visible
	_hide_management_panels()
	_economy_panel.visible = next
	if next:
		_update_economy_panel()


func _toggle_mainsel() -> void:
	if _mainsel_panel == null:
		return
	var next := not _mainsel_panel.visible
	_hide_management_panels()
	_mainsel_panel.visible = next


func _open_inventory() -> void:
	_hide_management_panels()
	_economy_panel.visible = true
	_update_economy_panel()


func _open_buildings() -> void:
	var next := _buildings_panel == null or not _buildings_panel.visible
	_hide_management_panels()
	if _buildings_panel != null:
		_buildings_panel.visible = next
		if next:
			_update_buildings_panel()


func _open_stats() -> void:
	var next := _stats_panel == null or not _stats_panel.visible
	_hide_management_panels()
	if _stats_panel != null:
		_stats_panel.visible = next
		if next:
			_update_stats_panel()


func _update_buildings_panel() -> void:
	if _buildings_label == null:
		return
	var built := {}        # def_id -> Anzahl fertig
	var building := {}     # def_id -> Anzahl im Bau
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0:
			continue
		if b.under_construction:
			building[b.def_id] = int(building.get(b.def_id, 0)) + 1
		else:
			built[b.def_id] = int(built.get(b.def_id, 0)) + 1
	var keys := {}
	for k in built: keys[k] = true
	for k in building: keys[k] = true
	var names := keys.keys()
	names.sort()
	var lines := PackedStringArray()
	lines.append("Gebaeude (fertig | im Bau):")
	if names.is_empty():
		lines.append("—")
	for k in names:
		var nm := String(BuildingCatalog.get_def(k).get("name", k))
		lines.append("%s: %d | %d" % [nm, int(built.get(k, 0)), int(building.get(k, 0))])
	_buildings_label.text = "\n".join(lines)


func _update_stats_panel() -> void:
	if _stats_label == null:
		return
	var own_b := 0
	var in_build := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0:
			continue
		own_b += 1
		if b.under_construction:
			in_build += 1
	var active_carriers := 0
	for r in economy.carriers:
		var c: Economy.Carrier = economy.carriers[r]
		if c.active:
			active_carriers += 1
	var lines := PackedStringArray()
	lines.append("Statistik")
	lines.append("Gebaeude: %d  (im Bau: %d)" % [own_b, in_build])
	lines.append("Flaggen: %d" % state.flags.size())
	lines.append("Wege: %d" % state.roads.size())
	lines.append("Traeger (aktiv): %d" % active_carriers)
	lines.append("Soldaten-Reserve: %d" % economy.soldiers)
	lines.append("Land (Knoten): %d" % state.territory.size())
	_stats_label.text = "\n".join(lines)


func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	var next := not _settings_panel.visible
	_hide_management_panels()
	_settings_panel.visible = next
	if next:
		_update_settings_text()


func _set_ui_scale(name: String) -> void:
	UISkin.set_ui_scale_name(name)
	call_deferred("_rebuild_ui_after_scale")


func _rebuild_ui_after_scale() -> void:
	var old_layer: Node = _ui_root.get_parent() if _ui_root != null else null
	if old_layer != null:
		old_layer.queue_free()
	_ui_root = null
	_building_windows.clear()
	_build_ui()
	_update_labels()
	_update_stock()
	if _settings_panel != null:
		_settings_panel.visible = true
		_update_settings_text()
	_flash("UI-Groesse: " + UISkin.ui_scale_name())


func _hide_management_panels(except: Control = null) -> void:
	for p in [_build_panel, _economy_panel, _settings_panel, _mainsel_panel,
			_buildings_panel, _stats_panel]:
		if p != null and p != except:
			p.visible = false


func _update_settings_text() -> void:
	if _settings_body == null:
		return
	_settings_body.text = \
		"Hotkeys: Space Bauplaetze, B Baufenster, S Optionen, I Waren, " + \
		"M Minikarte, H HQ, F Nebel, Y UI aus/an.\n\n" + \
		"UI-Groesse: %s\n\n" % UISkin.ui_scale_name() + \
		"Startoptionen: Bauhilfe %s, Nebel %s, KI %s\n\n" % [
			"AN" if UISkin.option_bool("start_build_spots", false) else "AUS",
			"AN" if UISkin.option_bool("start_fog", false) else "AUS",
			"AN" if UISkin.option_bool("start_ai", true) else "AUS",
		] + \
		"Anpassbar:\n" + \
		"- assets/ui.json: UI-Farben, Randabstaende, Panel-/Button-Groessen\n" + \
		"- assets/design.json: Gebaeude-/Flaggen-/Bauplatzgroessen und Eingange\n" + \
		"- assets/tuning.json: Arbeitergeschwindigkeit, Aktions-/Wartezeiten, Baumwachstum\n" + \
		"- assets/ui/build_spots/*.png: Bauplatzmarker\n" + \
		"- assets/ui/flag_*.png und assets/buildings/*_<spieler>.png: Spielerfarben\n\n" + \
		"Naechste Skin-Stufe: 9-Patch-Panels, Icon-Set und ein eigener UI-Editor."


func _toggle_build_spots() -> void:
	renderer.show_build_spots = not renderer.show_build_spots
	UISkin.set_option_bool("start_build_spots", renderer.show_build_spots)
	renderer.queue_redraw()
	_update_labels()


func _toggle_fog() -> void:
	renderer.fog_enabled = not renderer.fog_enabled
	UISkin.set_option_bool("start_fog", renderer.fog_enabled)
	renderer.queue_redraw()
	_flash("Nebel " + ("AN" if renderer.fog_enabled else "AUS"))


func _toggle_ai() -> void:
	economy.ai_enabled = not economy.ai_enabled
	UISkin.set_option_bool("start_ai", economy.ai_enabled)
	_flash("KI " + ("AN" if economy.ai_enabled else "AUS"))
	_update_labels()


func _toggle_pause() -> void:
	paused = not paused
	_update_labels()


func _escape_or_select() -> void:
	if _flag_menu != null and _flag_menu.visible:
		_close_flag_menu()
		return
	for p in [_build_panel, _economy_panel, _settings_panel, _mainsel_panel,
			_buildings_panel, _stats_panel]:
		if p != null and p.visible:
			p.visible = false
			return
	_set_mode(MODE_SELECT)


# --------------------------------------------------------------------------
#  Flaggen-Kontextmenü (S2-artig)
# --------------------------------------------------------------------------

func _open_flag_menu(flagpos: Vector2i) -> void:
	_flag_menu_pos = flagpos
	selected = null
	_hide_management_panels()
	# Welt-Knoten → Bildschirmkoordinate, Menü daneben platzieren (im Bild halten).
	var world := map.node_world(flagpos.x, flagpos.y)
	var screen := get_viewport().get_canvas_transform() * world
	var vp := get_viewport().get_visible_rect().size
	var w := 168.0
	var h := 150.0
	var x: float = clampf(screen.x + 10.0, 4.0, vp.x - w - 4.0)
	var y: float = clampf(screen.y - h * 0.4, 4.0, vp.y - h - 4.0)
	_flag_menu.offset_left = x
	_flag_menu.offset_top = y
	_flag_menu.offset_right = x + w
	_flag_menu.offset_bottom = y + h
	_flag_menu.visible = true


func _close_flag_menu() -> void:
	if _flag_menu != null:
		_flag_menu.visible = false
	_flag_menu_pos = Vector2i(-1, -1)


func _flag_menu_build_road() -> void:
	var fp := _flag_menu_pos
	if fp.x < 0:
		return
	_close_flag_menu()
	_set_mode(MODE_ROAD)
	road_start = fp
	unit_renderer.road_start = fp
	_flash("Weg bauen: Ziel-Flagge anklicken.")


func _flag_menu_remove() -> void:
	var fp := _flag_menu_pos
	_close_flag_menu()
	if fp.x < 0:
		return
	if state.remove_at(fp):
		economy.resync()
		renderer.queue_redraw()
		_flash("Flagge entfernt.")
	else:
		_flash("Flagge laesst sich nicht entfernen.")


func _noop() -> void:
	pass


func _focus_headquarters() -> void:
	var hq := economy.hq_pos_of(0)
	if hq.x >= 0:
		camera.position = map.node_world(hq.x, hq.y)
		_flash("Zum HQ gesprungen.")


func _toggle_selected_production() -> void:
	if selected == null or selected.is_hq or selected.owner != 0:
		_flash("Kein eigenes Produktionsgebaeude gewaehlt.")
		return
	var stopped := economy.toggle_production(selected)
	_flash("Produktion " + ("gestoppt" if stopped else "laeuft"))
	_update_building_windows()


func _delete_selected() -> void:
	if selected == null or selected.is_hq or selected.owner != 0:
		_flash("Abriss: eigenes Nicht-HQ-Gebaeude waehlen.")
		return
	var pos := selected.pos
	selected = null
	if state.remove_at(pos):
		economy.resync()
		renderer.queue_redraw()
		_flash("Gebaeude abgerissen.")
		_update_building_windows()


func _clear_selection() -> void:
	selected = null
	if _selection_panel != null:
		_selection_panel.visible = false


func _selection_goto() -> void:
	if selected == null:
		return
	camera.position = map.node_world(selected.pos.x, selected.pos.y)
	_flash("Zum Gebaeude gesprungen.")


func _open_building_window(b: WorldState.Building) -> void:
	if b == null:
		return
	var idx := map.idx(b.pos.x, b.pos.y)
	selected = b
	if _building_windows.has(idx):
		var existing: Dictionary = _building_windows[idx]
		var panel: PanelContainer = existing["panel"]
		panel.visible = true
		panel.move_to_front()
		_update_one_building_window(idx)
		return
	var world := map.node_world(b.pos.x, b.pos.y)
	var screen := get_viewport().get_canvas_transform() * world
	var vp := get_viewport().get_visible_rect().size
	var w := UISkin.layout_num("selection_panel_width", 260)
	var h := UISkin.layout_num("selection_panel_height", 205)
	var cascade := float(_building_windows.size() % 5) * UISkin.layout_num("window_cascade", 22)
	var x: float = clampf(screen.x + 16.0 + cascade, 4.0, vp.x - w - 4.0)
	var y: float = clampf(screen.y - h * 0.55 + cascade, 4.0, vp.y - h - 4.0)
	var panel := _floating_panel(Vector2.ZERO, Vector2(x, y), Vector2(x + w, y + h))
	var content := _add_window_chrome(panel, _building_window_title(b), _close_building_window.bind(idx))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(head)
	var icon := TextureRect.new()
	var icon_size := UISkin.layout_num("selection_icon_size", 52)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	UISkin.apply_label(title, false, 14)
	head.add_child(title)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	UISkin.apply_label(info, true, 11)
	content.add_child(info)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	content.add_child(actions)
	var stop := _tbutton(actions, "Stop", _toggle_production_window.bind(idx))
	var goto_btn := _tbutton(actions, "Zum Geb.", _goto_building_window.bind(idx))
	var demolish := _tbutton(actions, "Abriss", _delete_building_window.bind(idx))
	var attack := _tbutton(actions, "Angriff", _attack_building_window.bind(idx))

	_building_windows[idx] = {
		panel = panel, title = title, icon = icon, info = info,
		stop = stop, goto_btn = goto_btn, demolish = demolish, attack = attack,
	}
	_update_one_building_window(idx)


func _close_building_window(idx: int) -> void:
	if not _building_windows.has(idx):
		return
	var entry: Dictionary = _building_windows[idx]
	var panel: PanelContainer = entry["panel"]
	panel.queue_free()
	_building_windows.erase(idx)
	if selected != null and map.idx(selected.pos.x, selected.pos.y) == idx:
		selected = null


func _update_building_windows() -> void:
	if _building_windows.is_empty():
		return
	var gone := []
	for idx in _building_windows.keys():
		if not state.buildings.has(idx):
			gone.append(idx)
		else:
			_update_one_building_window(int(idx))
	for idx in gone:
		_close_building_window(int(idx))


func _update_one_building_window(idx: int) -> void:
	if not _building_windows.has(idx) or not state.buildings.has(idx):
		return
	var b: WorldState.Building = state.buildings[idx]
	var entry: Dictionary = _building_windows[idx]
	var title_text := _building_window_title(b)
	var panel: PanelContainer = entry["panel"]
	var title_label: Label = entry["title"]
	var icon: TextureRect = entry["icon"]
	var info: Label = entry["info"]
	var stop: Button = entry["stop"]
	var goto_btn: Button = entry["goto_btn"]
	var demolish: Button = entry["demolish"]
	var attack: Button = entry["attack"]
	if panel.has_meta("title_label"):
		(panel.get_meta("title_label") as Label).text = title_text
	title_label.text = title_text
	icon.texture = GameTheme.building_texture(b.def_id, b.owner)
	var lines := economy.building_status(b)
	if b.influence > 0:
		lines += "\nGarnison: %d/%d  Rangbonus: %d" % [b.garrison, b.capacity, b.promotions]
	info.text = lines
	var own := b.owner == 0
	stop.visible = own and not b.is_hq
	demolish.visible = own and not b.is_hq
	goto_btn.visible = true
	attack.visible = (not own) and b.influence > 0


func _building_window_title(b: WorldState.Building) -> String:
	var d := BuildingCatalog.get_def(b.def_id)
	var title := String(d.get("name", b.def_id))
	if b.owner == 1:
		title += " (Gegner)"
	if b.under_construction:
		title += " (Bau)"
	return title


func _toggle_production_window(idx: int) -> void:
	if not state.buildings.has(idx):
		return
	selected = state.buildings[idx]
	_toggle_selected_production()
	_update_one_building_window(idx)


func _goto_building_window(idx: int) -> void:
	if not state.buildings.has(idx):
		return
	var b: WorldState.Building = state.buildings[idx]
	selected = b
	camera.position = map.node_world(b.pos.x, b.pos.y)
	_flash("Zum Gebaeude gesprungen.")


func _delete_building_window(idx: int) -> void:
	if not state.buildings.has(idx):
		_close_building_window(idx)
		return
	var b: WorldState.Building = state.buildings[idx]
	if b.is_hq or b.owner != 0:
		_flash("Abriss: eigenes Nicht-HQ-Gebaeude waehlen.")
		return
	selected = b
	var pos := b.pos
	if state.remove_at(pos):
		_close_building_window(idx)
		economy.resync()
		renderer.queue_redraw()
		_flash("Gebaeude abgerissen.")


func _attack_building_window(idx: int) -> void:
	if not state.buildings.has(idx):
		return
	var target: WorldState.Building = state.buildings[idx]
	selected = target
	_attack_target(target)
	_update_one_building_window(idx)


## Greift das ausgewählte Gegner-Militärgebäude an — wählt automatisch das eigene
## Militärgebäude mit den meisten Soldaten in Reichweite (siehe Issue #16).
func _attack_selected() -> void:
	if selected == null or selected.owner != 1 or selected.influence <= 0:
		return
	_attack_target(selected)
	_update_building_windows()


func _attack_target(target: WorldState.Building) -> void:
	if target == null or target.owner != 1 or target.influence <= 0:
		return
	var best: WorldState.Building = null
	var best_g := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0 or b.influence <= 0 or b.garrison <= 0:
			continue
		if WorldState.hex_distance(b.pos, target.pos) > b.influence + target.influence + 2:
			continue
		if b.garrison > best_g:
			best_g = b.garrison
			best = b
	if best == null:
		_flash("Kein eigenes Militaergebaeude mit Soldaten in Reichweite.")
		return
	var n := economy.send_attackers(best, target)
	_flash("Angriff mit %d Soldaten!" % n)


func _show_category(cat: String) -> void:
	ui_category = cat
	if _build_row == null:
		return
	var content_scale := _build_content_scale()
	for group in _build_group_buttons:
		var group_btn: Button = _build_group_buttons[group]
		group_btn.button_pressed = String(group) == cat
	for ch in _build_row.get_children():
		ch.queue_free()
	if _build_caption != null:
		if build_window_spot.x >= 0:
			_build_caption.text = "Bauen (%d,%d): bis %s - %s" % [
				build_window_spot.x, build_window_spot.y, _bq_name(build_filter_bq), _group_label(cat)]
		else:
			_build_caption.text = "Bauen - %s" % _group_label(cat)
	for id in BuildingCatalog.menu_order():
		if _building_in_group(id, cat) and _building_allowed_by_filter(id):
			var cb := _build_from_spot.bind(id) if build_window_spot.x >= 0 else _select_building.bind(id)
			var tex := GameTheme.building_texture(id)
			_build_icon_button(_build_row, GameTheme.building_label(id), cb,
				_building_tooltip(id), tex, Vector2(92, 46), content_scale)
	if _build_row.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Keine passenden Gebäude in dieser Kategorie."
		UISkin.apply_label(empty, true, 12)
		_build_row.add_child(empty)
	_refresh_build_panel_layout()


func _group_label(group: String) -> String:
	match group:
		"mine": return "Bergwerke"
		"hut": return "Kleine Häuser"
		"house": return "Mittlere Häuser"
		"castle": return "Große Häuser"
	return group


func _building_in_group(id: String, group: String) -> bool:
	var size: int = BuildingCatalog.get_def(id).get("size", WorldState.BQ_HUT)
	match group:
		"hut": return size == WorldState.BQ_HUT
		"house": return size == WorldState.BQ_HOUSE
		"castle": return size == WorldState.BQ_CASTLE
		"mine": return size == WorldState.BQ_MINE
	return false


func _building_allowed_by_filter(id: String) -> bool:
	if build_filter_bq < 0:
		return true
	var size: int = BuildingCatalog.get_def(id).get("size", WorldState.BQ_HUT)
	if build_filter_bq == WorldState.BQ_MINE:
		return size == WorldState.BQ_MINE
	if size == WorldState.BQ_MINE:
		return false
	return size <= build_filter_bq


func _first_category_for_bq(bq: int) -> String:
	match bq:
		WorldState.BQ_MINE: return "mine"
		WorldState.BQ_CASTLE: return "castle"
		WorldState.BQ_HOUSE: return "house"
		WorldState.BQ_HUT: return "hut"
	return "hut"


## Tooltip-Text eines Gebäudes: Name, Baukosten, Ein-/Ausgänge.
func _building_tooltip(id: String) -> String:
	var d := BuildingCatalog.get_def(id)
	var t := String(d.get("name", id))
	var cost: Dictionary = d.get("cost", {})
	if not cost.is_empty():
		var parts := PackedStringArray()
		for g in cost:
			parts.append("%dx %s" % [int(cost[g]), Goods.name_of(int(g))])
		t += "\nKosten: " + ", ".join(parts)
	var inp: Dictionary = d.get("inputs", {})
	if not inp.is_empty():
		var ip := PackedStringArray()
		for g in inp:
			ip.append("%dx %s" % [int(inp[g]), Goods.name_of(int(g))])
		t += "\nEingang: " + ", ".join(ip)
	var outp: int = int(d.get("output", -1))
	if outp >= 0:
		t += "\nAusgang: " + Goods.name_of(outp)
	return t


func _make_label(layer: Node, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	UISkin.apply_label(l, false, 13)
	layer.add_child(l)
	return l


func _row(layer: Node, pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 4)
	layer.add_child(h)
	return h


func _tbutton(row: Container, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	UISkin.apply_button(btn)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return btn


func _build_icon_button(row: Container, text: String, cb: Callable, tooltip := "",
		icon: Texture2D = null, min_size := Vector2(64, 38), content_scale := 1.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	UISkin.apply_button(btn)
	btn.custom_minimum_size = min_size * UISkin.ui_scale() * content_scale
	btn.add_theme_font_size_override("font_size",
		maxi(8, roundi(12.0 * UISkin.ui_scale() * content_scale)))
	btn.set_meta("base_size", min_size)
	btn.pressed.connect(cb)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
	row.add_child(btn)
	return btn


func _select_building(id: String) -> void:
	mode = MODE_BUILD
	build_def_id = id
	road_start = Vector2i(-1, -1)
	build_filter_bq = -1
	build_window_spot = Vector2i(-1, -1)
	if _build_panel != null:
		_build_panel.visible = false
	_show_category(ui_category)
	_clear_preview()
	if unit_renderer != null:
		unit_renderer.build_preview_id = id
	_update_labels()


func _build_from_spot(id: String) -> void:
	var pos := build_window_spot
	if pos.x < 0:
		_select_building(id)
		return
	build_def_id = id
	if _place_building_at(pos, id):
		economy.resync()
		renderer.queue_redraw()
		_flash("Baustelle gesetzt: " + String(BuildingCatalog.get_def(id).get("name", id)))
		build_window_spot = Vector2i(-1, -1)
		build_filter_bq = -1
		if _build_panel != null:
			_build_panel.visible = false
		_show_category(ui_category)
	else:
		_flash("Passt hier nicht mehr.")


func _update_labels() -> void:
	if _mode_label == null:
		return
	var m := ""
	match mode:
		MODE_SELECT: m = "Auswahl"
		MODE_FLAG:   m = "Flagge setzen"
		MODE_ROAD:   m = "Straße: Flagge anklicken, dann Ziel"
		MODE_BUILD:  m = "Bauen: " + String(BuildingCatalog.get_def(build_def_id).get("name", "?"))
		MODE_DELETE: m = "Abriss"
	var spd := "PAUSE" if paused else (str(sim_speed) + "x")
	var ai_name := String(ai_list[ai_choice].name) if ai_choice < ai_list.size() else "?"
	var ai := ("KI:%s" % ai_name) if economy.ai_enabled else "KI:AUS"
	_mode_label.text = "%s  |  %s  |  %s  |  Space Bauhilfe  B/I/S Fenster" % [m, spd, ai]

	var info := "Knoten: -"
	if map.in_bounds(hover.x, hover.y):
		var t := map.get_tri(hover, Grid.TRI_R)
		var extra := ""
		var b := state.building_at(hover)
		if b != null:
			extra = "  >> " + String(BuildingCatalog.get_def(b.def_id).get("name", "?"))
			if b.under_construction:
				extra += " (Bau...)"
		elif state.has_object(hover.x, hover.y):
			match map.map_object(hover.x, hover.y):
				MapData.MO_TREE:
					var stage := map.tree_stage_at(hover.x, hover.y)
					var sname := "Setzling" if stage == MapData.TREE_SEED else ("kleiner Baum" if stage == MapData.TREE_SMALL else "Baum")
					var tname := map.tree_type_name(map.tree_type_at(hover.x, hover.y))
					extra = "  [%s %s]" % [sname, tname]
				MapData.MO_STONE:
					extra = "  [Stein Stufe %d]" % map.stone_stage_at(hover.x, hover.y)
				MapData.MO_ORE: extra = "  [Erz]"
		info = "(%d,%d) %s  BQ:%s%s" % [hover.x, hover.y, Terrain.name_of(t),
			_bq_name(state.effective_bq(hover.x, hover.y)), extra]
	_info_label.text = info


func _update_stock() -> void:
	for g in Goods.COUNT:
		var n: int = economy.hq_stock.get(g, 0)
		if _stock_counts.has(g):
			var l: Label = _stock_counts[g]
			l.text = str(n)
			l.modulate = Color(1, 1, 1, 1.0 if n > 0 else 0.35)
	if _economy_panel != null and _economy_panel.visible:
		_update_economy_panel()


func _update_economy_panel() -> void:
	if _stock_label == null:
		return
	var lines := PackedStringArray()
	lines.append("HQ-Lager:")
	for g in Goods.COUNT:
		var n: int = economy.hq_stock.get(g, 0)
		if n > 0:
			lines.append("%s: %d" % [Goods.name_of(g), n])
	lines.append("")
	lines.append("Soldaten Reserve: %d" % economy.soldiers)
	lines.append("Tempo: %s" % ("PAUSE" if paused else (str(sim_speed) + "x")))
	_stock_label.text = "\n".join(lines)


func _update_selection_panel() -> void:
	if _selection_panel == null or _sel_label == null:
		return
	if selected == null:
		if _selection_panel != null:
			_selection_panel.visible = false
		return
	if _selection_panel != null:
		_selection_panel.visible = true
	var d := BuildingCatalog.get_def(selected.def_id)
	var bname := String(d.get("name", selected.def_id))
	if selected.owner == 1:
		bname += " (Gegner)"
	# Titelleiste des Fensters zeigt den Gebäudenamen (wie im Original).
	if _selection_panel != null and _selection_panel.has_meta("title_label"):
		(_selection_panel.get_meta("title_label") as Label).text = bname
	if _sel_title_label != null:
		_sel_title_label.text = bname
	if _sel_icon != null:
		_sel_icon.texture = GameTheme.building_texture(selected.def_id, selected.owner)
	var lines := economy.building_status(selected)
	if selected.influence > 0:
		lines += "\nGarnison: %d/%d  Rangbonus: %d" % [
			selected.garrison, selected.capacity, selected.promotions]
	_sel_label.text = lines
	# Aktionen kontextabhängig: eigene Gebäude verwalten, Gegner-Militär angreifen.
	var own := selected.owner == 0
	_sel_btn_stop.visible = own and not selected.is_hq
	_sel_btn_demolish.visible = own and not selected.is_hq
	_sel_btn_goto.visible = true
	_sel_btn_attack.visible = (not own) and selected.influence > 0


# --------------------------------------------------------------------------
#  Eingabe
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_mode(MODE_FLAG)
			KEY_2: _set_mode(MODE_ROAD)
			KEY_9, KEY_DELETE: _set_mode(MODE_DELETE)
			KEY_0, KEY_ESCAPE: _escape_or_select()
			KEY_F2: _save_game()
			KEY_F3: _load_game()
			KEY_F5: _new_game()
			KEY_B: _toggle_build_panel()
			KEY_S: _toggle_settings()
			KEY_I: _toggle_economy_panel()
			KEY_M:
				if _minimap_panel != null:
					_minimap_panel.visible = not _minimap_panel.visible
			KEY_H: _focus_headquarters()
			KEY_Y:
				if _ui_root != null:
					_ui_root.visible = not _ui_root.visible
			KEY_K: _toggle_ai()
			KEY_J: _cycle_ai()
			KEY_P:
				_toggle_selected_production()
			KEY_SPACE:
				_toggle_build_spots()
			KEY_F:
				_toggle_fog()
			KEY_PAUSE: _toggle_pause()
			KEY_EQUAL, KEY_KP_ADD: sim_speed = minf(sim_speed * 2.0, 8.0); _update_labels()
			KEY_MINUS, KEY_KP_SUBTRACT: sim_speed = maxf(sim_speed * 0.5, 0.25); _update_labels()
		return

	if event is InputEventMouseMotion:
		_update_hover()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_hover()
		_handle_click()


func _set_mode(m: int) -> void:
	mode = m
	road_start = Vector2i(-1, -1)
	build_filter_bq = -1
	build_window_spot = Vector2i(-1, -1)
	if _flag_menu != null:
		_flag_menu.visible = false
	if _build_panel != null:
		_build_panel.visible = false
	_show_category(ui_category)
	_clear_preview()
	if unit_renderer != null:
		unit_renderer.build_preview_id = ""   # Geist-Vorschau nur im Bau-Modus
	_update_labels()


func _update_hover() -> void:
	var n := _pick_node(get_global_mouse_position())
	if n != hover:
		hover = n
		unit_renderer.hover = hover
		if mode == MODE_ROAD and map.in_bounds(road_start.x, road_start.y):
			_update_preview()
		_update_labels()
		# Keine Terrain-Neuzeichnung bei Hover — der Overlay genügt.


func _handle_click() -> void:
	if not map.in_bounds(hover.x, hover.y):
		return
	if renderer.show_build_spots and mode == MODE_SELECT and _handle_build_spot_click():
		return
	# Nur echte Struktur-Änderungen lösen ein (teures) resync + Neuzeichnen aus.
	# Reine Auswahl/Angriff NICHT — das war die Ursache für den Klick-Lag.
	var changed := false
	match mode:
		MODE_SELECT:
			var clicked := state.building_at(hover)
			if clicked == null and state.flag_at(hover) != null \
					and not state.enemy_territory.has(map.idx(hover.x, hover.y)):
				_open_flag_menu(hover)   # eigene Flagge angeklickt → Kontextmenü
			else:
				# Gebäude (eigen ODER Gegner) auswählen; Angriff läuft über das
				# kontextabhängige Auswahlfenster (Issue #16).
				selected = clicked
				if clicked != null:
					_open_building_window(clicked)
				_close_flag_menu()
		MODE_FLAG:
			changed = state.place_flag(hover.x, hover.y) != null
		MODE_BUILD:
			changed = _place_building_here()
		MODE_ROAD:
			changed = _handle_road_click()
		MODE_DELETE:
			if selected == state.building_at(hover):
				selected = null
			changed = state.remove_at(hover)
	if changed:
		economy.resync()
		renderer.queue_redraw()


func _handle_build_spot_click() -> bool:
	if state.can_place_road_flag(hover.x, hover.y):
		var f := state.place_flag(hover.x, hover.y)
		if f != null:
			economy.resync()
			renderer.queue_redraw()
			_flash("Strassen-Flagge gesetzt.")
		return true
	var bq := state.actual_build_spot_bq(hover.x, hover.y)
	if bq < WorldState.BQ_FLAG:
		return false
	if bq == WorldState.BQ_FLAG:
		var f := state.place_flag(hover.x, hover.y)
		if f != null:
			economy.resync()
			renderer.queue_redraw()
			_flash("Flagge gesetzt.")
		return true
	build_window_spot = hover
	build_filter_bq = bq
	ui_category = _first_category_for_bq(bq)
	if _build_panel != null:
		_hide_management_panels(_build_panel)
		_build_panel.visible = true
		_position_build_panel_near_node(hover)
	_show_category(ui_category)
	_flash("Bauplatz gewaehlt: %s. Im Baufenster Gebaeude waehlen." % _bq_name(bq))
	return true


func _place_building_here() -> bool:
	return _place_building_at(hover, build_def_id)


func _place_building_at(pos: Vector2i, id: String) -> bool:
	var d := BuildingCatalog.get_def(id)
	if d.is_empty():
		return false
	var size: int = d.get("size", WorldState.BQ_HUT)
	return state.place_building(pos.x, pos.y, size, false, id,
		int(d.get("influence", 0)), true) != null


func _handle_road_click() -> bool:
	if not map.in_bounds(road_start.x, road_start.y):
		if state.flag_at(hover) != null:
			road_start = hover
			unit_renderer.road_start = road_start
		return false  # nur Startflagge gewählt — keine Struktur-Änderung
	var r := state.build_road(road_start, hover)
	if r != null:
		road_start = r.b
		unit_renderer.road_start = road_start
	_clear_preview()
	return r != null


func _update_preview() -> void:
	var path := state.plan_road(road_start, hover)  # gleiches optimales A* wie der Bau
	unit_renderer.preview_path = path
	unit_renderer.preview_ok = not path.is_empty()


func _clear_preview() -> void:
	if unit_renderer != null:
		unit_renderer.preview_path = []
		unit_renderer.road_start = road_start


func _pick_node(world_pos: Vector2) -> Vector2i:
	var approx := Grid.world_to_node_approx(world_pos)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := approx.x + dx
			var y := approx.y + dy
			if not map.in_bounds(x, y):
				continue
			var dd := map.node_world(x, y).distance_to(world_pos)
			if dd < best_d:
				best_d = dd
				best = Vector2i(x, y)
	return best


func _bq_name(bq: int) -> String:
	match bq:
		WorldState.BQ_NOTHING: return "-"
		WorldState.BQ_FLAG:    return "Flagge"
		WorldState.BQ_HUT:     return "Hütte"
		WorldState.BQ_HOUSE:   return "Haus"
		WorldState.BQ_CASTLE:  return "Burg"
		WorldState.BQ_MINE:    return "Mine"
	return "?"


# --------------------------------------------------------------------------
#  Speichern / Laden  (Struktur + HQ-Lager; Produktionsfortschritt setzt neu auf)
# --------------------------------------------------------------------------

func _save_game() -> void:
	var data := {
		w = map.width, h = map.height,
		heights = map.heights, terr_r = map.terr_r, terr_d = map.terr_d,
		objects = map.objects.duplicate(),
		ore_kind = map.ore_kind.duplicate(),
		tree_stage = map.tree_stage.duplicate(),
		tree_type = map.tree_type.duplicate(),
		stone_stage = map.stone_stage.duplicate(),
		stone_hits_left = map.stone_hits_left.duplicate(),
		tree_growth = economy.tree_growth_state(),
		buildings = [], flags = [], roads = [],
		hq_stock = economy.hq_stock.duplicate(),
		soldiers = economy.soldiers,
	}
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		data.buildings.append({
			pos = b.pos, size = b.size, flag = b.flag_pos, hq = b.is_hq,
			def = b.def_id, infl = b.influence, build = b.under_construction,
			gar = b.garrison, cap = b.capacity, owner = b.owner, promo = b.promotions,
		})
	for i in state.flags:
		var f: WorldState.Flag = state.flags[i]
		data.flags.append({ pos = f.pos, owner = f.owner })
	for r in state.roads:
		data.roads.append({
			nodes = r.nodes.duplicate(), a = r.a, b = r.b,
			owner = r.owner, traffic = r.traffic, level = r.level,
		})

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(data, true)
		f.close()
		_flash("Gespeichert.")


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_flash("Kein Spielstand.")
		return
	selected = null
	paused = false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = f.get_var(true)
	f.close()

	map = MapData.new(int(data.w), int(data.h))
	map.heights = data.heights
	map.terr_r = data.terr_r
	map.terr_d = data.terr_d
	map.objects = data.objects
	map.ore_kind = data.get("ore_kind", {})
	var saved_tree_stage = data.get("tree_stage", {})
	if saved_tree_stage is Dictionary:
		map.tree_stage = saved_tree_stage
	var saved_tree_type = data.get("tree_type", {})
	if saved_tree_type is Dictionary:
		map.tree_type = saved_tree_type
	var saved_stone_stage = data.get("stone_stage", {})
	if saved_stone_stage is Dictionary:
		map.stone_stage = saved_stone_stage
	var saved_stone_hits_left = data.get("stone_hits_left", {})
	if saved_stone_hits_left is Dictionary:
		map.stone_hits_left = saved_stone_hits_left
	state = WorldState.new(map)

	for fp in data.flags:
		if fp is Dictionary:
			var pos: Vector2i = fp.pos
			state.ensure_flag(pos.x, pos.y, int(fp.get("owner", 0)))
		else:
			state.place_flag(fp.x, fp.y)
	for bd in data.buildings:
		var bb := WorldState.Building.new()
		bb.pos = bd.pos; bb.size = bd.size; bb.flag_pos = bd.flag
		bb.is_hq = bd.hq; bb.def_id = bd.def; bb.influence = bd.infl
		bb.under_construction = bd.build
		bb.garrison = bd.get("gar", 0); bb.capacity = bd.get("cap", 0)
		bb.owner = bd.get("owner", 0)
		bb.promotions = bd.get("promo", 0)
		var i := map.idx(bb.pos.x, bb.pos.y)
		state.buildings[i] = bb
		state.occupied[i] = WorldState.OBJ_BUILDING
	for rd in data.roads:
		var rr := WorldState.Road.new()
		rr.nodes = rd.nodes; rr.a = rd.a; rr.b = rd.b
		rr.owner = int(rd.get("owner", 0))
		rr.traffic = int(rd.get("traffic", 0))
		rr.level = int(rd.get("level", WorldState.ROAD_DIRT))
		for k in range(1, rr.nodes.size() - 1):
			state.occupied[map.idx(rr.nodes[k].x, rr.nodes[k].y)] = WorldState.OBJ_ROAD
		state.roads.append(rr)

	economy = Economy.new(state)
	economy._hq_inited = true
	economy.hq_stock = data.hq_stock
	economy.soldiers = int(data.get("soldiers", 0))
	var tree_growth = data.get("tree_growth", {})
	if tree_growth is Dictionary:
		economy.restore_tree_growth(tree_growth)
	_wire_world()
	_apply_ai()
	_apply_start_options()
	economy.resync()
	renderer.queue_redraw()
	_flash("Geladen.")


func _flash(text: String) -> void:
	if _info_label != null:
		_info_label.text = text
