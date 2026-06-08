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
var _status_label: Label
var _build_panel: PanelContainer
var _build_group_row: HBoxContainer
var _build_row: GridContainer
var _build_caption: Label
var _economy_panel: PanelContainer
var _settings_panel: PanelContainer
var _settings_body: Label
var _minimap_panel: PanelContainer
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
	var b := WorldState.Building.new()
	b.pos = pos
	b.size = size
	b.def_id = def_id
	b.influence = infl
	b.owner = owner
	b.under_construction = false
	b.garrison = gar
	b.capacity = cap
	b.is_hq = is_hq
	b.flag_pos = map.neighbor(pos.x, pos.y, Grid.SE)
	var i := map.idx(pos.x, pos.y)
	state.buildings[i] = b
	state.occupied[i] = WorldState.OBJ_BUILDING


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
	if _sel_label != null:
		_update_selection_panel()
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
	["Wege", "roads"],
	["Klein", "hut"],
	["Mittel", "house"],
	["Gross", "castle"],
	["Mine", "mine"],
]


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

	# Rechts: Auswahlfenster nur anzeigen, wenn wirklich etwas ausgewaehlt ist.
	var side := _floating_panel(Vector2(1, 0), Vector2(-right_w - edge, edge + top_h + 8),
		Vector2(-edge, edge + top_h + 236))
	_selection_panel = side
	_selection_panel.visible = false
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	side.add_child(side_box)
	var sel_head := HBoxContainer.new()
	sel_head.add_theme_constant_override("separation", 8)
	side_box.add_child(sel_head)
	_sel_icon = TextureRect.new()
	_sel_icon.custom_minimum_size = Vector2(52, 52)
	_sel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sel_head.add_child(_sel_icon)
	_sel_title_label = Label.new()
	_sel_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UISkin.apply_label(_sel_title_label, false, 15)
	sel_head.add_child(_sel_title_label)
	_sel_label = Label.new()
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UISkin.apply_label(_sel_label, true, 12)
	side_box.add_child(_sel_label)
	var sel_actions := HBoxContainer.new()
	sel_actions.add_theme_constant_override("separation", 4)
	side_box.add_child(sel_actions)
	_tbutton(sel_actions, "Stop", _toggle_selected_production)
	_tbutton(sel_actions, "Abriss", _delete_selected)

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
	_tbutton(main_buttons, "Wirtschaft", _toggle_economy_panel)
	_tbutton(main_buttons, "System", _toggle_settings)

	_build_panel = _floating_panel(Vector2(0, 1), Vector2(edge, -bottom_h - build_h - edge * 2.0),
		Vector2(edge + build_w, -bottom_h - edge * 2.0))
	_build_panel.visible = false
	var build_box := VBoxContainer.new()
	build_box.add_theme_constant_override("separation", 5)
	_build_panel.add_child(build_box)
	_build_caption = Label.new()
	UISkin.apply_label(_build_caption, true, 12)
	build_box.add_child(_build_caption)
	_build_group_row = HBoxContainer.new()
	_build_group_row.add_theme_constant_override("separation", 4)
	build_box.add_child(_build_group_row)
	for c in BUILD_GROUPS:
		_tbutton(_build_group_row, c[0], _show_category.bind(c[1]))
	_build_row = GridContainer.new()
	_build_row.columns = 5
	_build_row.add_theme_constant_override("separation", 4)
	build_box.add_child(_build_row)
	_show_category(ui_category)

	_economy_panel = _floating_panel(Vector2(0, 1), Vector2(edge + 304, -bottom_h - 250 - edge * 2.0),
		Vector2(edge + 604, -bottom_h - edge * 2.0))
	_economy_panel.visible = false
	var economy_box := VBoxContainer.new()
	economy_box.add_theme_constant_override("separation", 6)
	_economy_panel.add_child(economy_box)
	var economy_title := Label.new()
	economy_title.text = "Wirtschaft"
	UISkin.apply_label(economy_title, false, 15)
	economy_box.add_child(economy_title)
	_stock_label = Label.new()
	_stock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_stock_label, true, 11)
	economy_box.add_child(_stock_label)

	_settings_panel = _floating_panel(Vector2(0.5, 0.5), Vector2(-260, -180), Vector2(260, 180))
	_settings_panel.visible = false
	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(settings_box)
	var settings_title := Label.new()
	settings_title.text = "Einstellungen & anpassbares Design"
	UISkin.apply_label(settings_title, false, 16)
	settings_box.add_child(settings_title)
	_settings_body = Label.new()
	_settings_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UISkin.apply_label(_settings_body, true, 12)
	settings_box.add_child(_settings_body)
	var settings_actions := HBoxContainer.new()
	settings_actions.add_theme_constant_override("separation", 4)
	settings_box.add_child(settings_actions)
	_tbutton(settings_actions, "Bauplaetze", _toggle_build_spots)
	_tbutton(settings_actions, "Nebel", _toggle_fog)
	_tbutton(settings_actions, "KI", _toggle_ai)
	_tbutton(settings_actions, "Pause", _toggle_pause)
	_tbutton(settings_actions, "Schliessen", _toggle_settings)
	_update_settings_text()

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


func _build_stock_cells(parent: GridContainer) -> void:
	_stock_counts.clear()
	for g in Goods.COUNT:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(UISkin.layout_num("good_cell_width", 56),
			UISkin.layout_num("good_cell_height", 24))
		cell.tooltip_text = Goods.name_of(g)
		parent.add_child(cell)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(UISkin.layout_num("good_icon_size", 18),
			UISkin.layout_num("good_icon_size", 18))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = UISkin.good_texture(g)
		cell.add_child(icon)
		var label := Label.new()
		UISkin.apply_label(label, false, 9)
		label.text = "0"
		cell.add_child(label)
		_stock_counts[g] = label


func _open_general_build_menu() -> void:
	build_filter_bq = -1
	build_window_spot = Vector2i(-1, -1)
	if _build_panel != null:
		_hide_management_panels(_build_panel)
		_build_panel.visible = true
	_show_category(ui_category)
	_flash("Baufenster: alle Gebaeude. Space zeigt Bauplaetze; Klick auf Marker filtert passend.")


func _toggle_build_panel() -> void:
	if _build_panel == null:
		return
	var next := not _build_panel.visible
	_hide_management_panels()
	_build_panel.visible = next
	if next:
		build_filter_bq = -1
		build_window_spot = Vector2i(-1, -1)
		_show_category(ui_category)


func _toggle_economy_panel() -> void:
	if _economy_panel == null:
		return
	var next := not _economy_panel.visible
	_hide_management_panels()
	_economy_panel.visible = next
	if next:
		_update_economy_panel()


func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	var next := not _settings_panel.visible
	_hide_management_panels()
	_settings_panel.visible = next
	if next:
		_update_settings_text()


func _hide_management_panels(except: Control = null) -> void:
	for p in [_build_panel, _economy_panel, _settings_panel]:
		if p != null and p != except:
			p.visible = false


func _update_settings_text() -> void:
	if _settings_body == null:
		return
	_settings_body.text = \
		"Hotkeys: Space Bauplaetze, B Baufenster, S Optionen, I Waren, " + \
		"M Minikarte, H HQ, F Nebel, Y UI aus/an.\n\n" + \
		"Anpassbar:\n" + \
		"- assets/ui.json: UI-Farben, Randabstaende, Panel-/Button-Groessen\n" + \
		"- assets/design.json: Gebaeude-/Flaggen-/Bauplatzgroessen und Eingange\n" + \
		"- assets/tuning.json: Arbeitergeschwindigkeit, Aktions-/Wartezeiten, Baumwachstum\n" + \
		"- assets/ui/build_spots/*.png: Bauplatzmarker\n" + \
		"- assets/ui/flag_*.png und assets/buildings/*_<spieler>.png: Spielerfarben\n\n" + \
		"Naechste Skin-Stufe: 9-Patch-Panels, Icon-Set und ein eigener UI-Editor."


func _toggle_build_spots() -> void:
	renderer.show_build_spots = not renderer.show_build_spots
	renderer.queue_redraw()
	_update_labels()


func _toggle_fog() -> void:
	renderer.fog_enabled = not renderer.fog_enabled
	renderer.queue_redraw()
	_flash("Nebel " + ("AN" if renderer.fog_enabled else "AUS"))


func _toggle_ai() -> void:
	economy.ai_enabled = not economy.ai_enabled
	_flash("KI " + ("AN" if economy.ai_enabled else "AUS"))
	_update_labels()


func _toggle_pause() -> void:
	paused = not paused
	_update_labels()


func _escape_or_select() -> void:
	for p in [_build_panel, _economy_panel, _settings_panel]:
		if p != null and p.visible:
			p.visible = false
			return
	_set_mode(MODE_SELECT)


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
	_update_selection_panel()


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
		_update_selection_panel()


func _show_category(cat: String) -> void:
	ui_category = cat
	if _build_row == null:
		return
	for ch in _build_row.get_children():
		ch.queue_free()
	if _build_caption != null:
		if build_window_spot.x >= 0:
			_build_caption.text = "Bauplatz (%d,%d): bis %s - %s" % [
				build_window_spot.x, build_window_spot.y, _bq_name(build_filter_bq), _group_label(cat)]
		else:
			_build_caption.text = "Baufenster - %s" % _group_label(cat)
	if cat == "roads":
		_tbutton(_build_row, "Flagge", _set_mode.bind(MODE_FLAG))
		_tbutton(_build_row, "Strasse", _set_mode.bind(MODE_ROAD))
		_tbutton(_build_row, "Abriss", _set_mode.bind(MODE_DELETE))
		_tbutton(_build_row, "Bauhilfe", _toggle_build_spots)
		return
	for id in BuildingCatalog.menu_order():
		var def := BuildingCatalog.get_def(id)
		if _building_in_group(id, cat) and _building_allowed_by_filter(id):
			var cb := _build_from_spot.bind(id) if build_window_spot.x >= 0 else _select_building.bind(id)
			var btn := _tbutton(_build_row, String(def.get("name", id)), cb)
			btn.tooltip_text = _building_tooltip(id)
			var tex := GameTheme.building_texture(id)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true
	if _build_row.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Keine passenden Gebaeude in dieser Kategorie."
		UISkin.apply_label(empty, true, 12)
		_build_row.add_child(empty)


func _group_label(group: String) -> String:
	match group:
		"roads": return "Wege"
		"hut": return "Kleine Haeuser"
		"house": return "Mittlere Haeuser"
		"castle": return "Grosse Haeuser"
		"mine": return "Bergwerke"
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
	return "roads"


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
	if selected == null:
		if _selection_panel != null:
			_selection_panel.visible = false
		return
	if _selection_panel != null:
		_selection_panel.visible = true
	var d := BuildingCatalog.get_def(selected.def_id)
	if _sel_title_label != null:
		_sel_title_label.text = String(d.get("name", selected.def_id))
		if selected.owner == 1:
			_sel_title_label.text += " (Gegner)"
	if _sel_icon != null:
		_sel_icon.texture = GameTheme.building_texture(selected.def_id, selected.owner)
	var lines := economy.building_status(selected)
	if selected.influence > 0:
		lines += "\nGarnison: %d/%d  Rangbonus: %d" % [
			selected.garrison, selected.capacity, selected.promotions]
	_sel_label.text = lines


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
			if clicked != null and clicked.owner == 1 and selected != null \
					and selected.owner == 0 and selected.influence > 0 and selected.garrison > 0:
				_try_attack(selected, clicked)
			else:
				selected = clicked
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
	_show_category(ui_category)
	_flash("Bauplatz gewaehlt: %s. Im Baufenster Gebaeude waehlen." % _bq_name(bq))
	return true


func _try_attack(src: WorldState.Building, tgt: WorldState.Building) -> void:
	var d := WorldState.hex_distance(src.pos, tgt.pos)
	if d > src.influence + tgt.influence + 2:
		_flash("Ziel zu weit weg — näheres Militärgebäude nötig.")
		return
	var n := economy.send_attackers(src, tgt)
	_flash("Angriff mit %d Soldaten!" % n)


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
	var path := state.plan_road(road_start, hover, true)  # fast mode für Vorschau
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
		data.flags.append(state.flags[i].pos)
	for r in state.roads:
		data.roads.append({
			nodes = r.nodes.duplicate(), a = r.a, b = r.b,
			traffic = r.traffic, level = r.level,
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
	economy.resync()
	renderer.queue_redraw()
	_flash("Geladen.")


func _flash(text: String) -> void:
	if _info_label != null:
		_info_label.text = text
