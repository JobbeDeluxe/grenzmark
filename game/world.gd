class_name World
extends Node2D

## Aufbau der Welt, Bau-Modi, Eingabe, HUD/Menü/Minikarte und Speichern/Laden.
## Verbindet die reine Logik (WorldState/Economy) mit Darstellung und Kamera.

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
var _sel_label: Label
var _status_label: Label
var _build_row: HBoxContainer
var ui_category := "holz"
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
	if _stock_label != null:
		_update_stock()
	if _sel_label != null:
		_sel_label.text = economy.building_status(selected) if selected != null \
			else "Auswahl: ein Gebäude anklicken (Modus Auswahl)"
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

const CATEGORIES := [
	["Holz", "holz"], ["Bau", "bau"], ["Nahrung", "nahrung"],
	["Bergbau", "bergbau"], ["Metall", "metall"], ["Militär", "militaer"],
]


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var vp := get_viewport_rect().size

	# Statusleiste oben
	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.6)
	top.position = Vector2(8, 8)
	top.size = Vector2(vp.x - 210, 30)
	layer.add_child(top)
	_mode_label = _make_label(layer, Vector2(16, 12))

	# Info-/Hover-Zeile darunter
	var info_bg := ColorRect.new()
	info_bg.color = Color(0, 0, 0, 0.55)
	info_bg.position = Vector2(8, 42)
	info_bg.size = Vector2(vp.x - 210, 26)
	layer.add_child(info_bg)
	_info_label = _make_label(layer, Vector2(16, 45))
	_sel_label = _make_label(layer, Vector2(360, 45))

	# Vorrats-Anzeige rechts
	var stock_bg := ColorRect.new()
	stock_bg.color = Color(0, 0, 0, 0.55)
	stock_bg.position = Vector2(vp.x - 190, 8)
	stock_bg.size = Vector2(182, 360)
	layer.add_child(stock_bg)
	_stock_label = _make_label(layer, Vector2(vp.x - 182, 14))

	# --- Untere Werkzeugleiste (wie im Original) ---
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.62)
	bar.position = Vector2(0, vp.y - 110)
	bar.size = Vector2(vp.x - 200, 110)
	layer.add_child(bar)

	# Zeile 1: Modi
	var modes := _row(layer, Vector2(8, vp.y - 104))
	_tbutton(modes, "Auswahl", _set_mode.bind(MODE_SELECT))
	_tbutton(modes, "Flagge", _set_mode.bind(MODE_FLAG))
	_tbutton(modes, "Straße", _set_mode.bind(MODE_ROAD))
	_tbutton(modes, "Abriss", _set_mode.bind(MODE_DELETE))

	# Zeile 2: Kategorien
	var cats := _row(layer, Vector2(8, vp.y - 76))
	for c in CATEGORIES:
		_tbutton(cats, c[0], _show_category.bind(c[1]))

	# Zeile 3: Gebäude der gewählten Kategorie
	_build_row = _row(layer, Vector2(8, vp.y - 44))
	_show_category(ui_category)

	# Sieg/Niederlage-Anzeige (zentriert)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 52)
	_status_label.position = Vector2(vp.x * 0.5 - 140, vp.y * 0.5 - 30)
	_status_label.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	layer.add_child(_status_label)

	# Minikarte unten rechts
	minimap = MiniMap.new()
	minimap.position = Vector2(vp.x - 196, vp.y - 196)
	minimap.size = Vector2(188, 188)
	minimap.setup(state, economy, camera)
	layer.add_child(minimap)


func _show_category(cat: String) -> void:
	ui_category = cat
	if _build_row == null:
		return
	for ch in _build_row.get_children():
		ch.queue_free()
	for id in BuildingCatalog.menu_order():
		if String(BuildingCatalog.get_def(id).get("category", "")) == cat:
			var btn := _tbutton(_build_row, String(BuildingCatalog.get_def(id).get("name", id)),
				_select_building.bind(id))
			btn.tooltip_text = _building_tooltip(id)
			var tex := GameTheme.building_texture(id)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true


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


func _make_label(layer: CanvasLayer, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 13)
	layer.add_child(l)
	return l


func _row(layer: CanvasLayer, pos: Vector2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = pos
	h.add_theme_constant_override("separation", 4)
	layer.add_child(h)
	return h


func _tbutton(row: HBoxContainer, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(96, 26)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return btn


func _select_building(id: String) -> void:
	mode = MODE_BUILD
	build_def_id = id
	road_start = Vector2i(-1, -1)
	_clear_preview()
	if unit_renderer != null:
		unit_renderer.build_preview_id = id
	_update_labels()


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
	_mode_label.text = "Modus: %s  [%s · %s]  (Leertaste Bauplätze · F Nebel · +/- Tempo · K/J KI · P Stop · F2/F3 · F5 Neu)" % [m, spd, ai]

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
	var lines := "HQ-Lager:\n"
	for g in Goods.COUNT:
		var n: int = economy.hq_stock.get(g, 0)
		if n > 0:
			lines += "%s: %d\n" % [Goods.name_of(g), n]
	lines += "\nSoldaten (Reserve): %d" % economy.soldiers
	_stock_label.text = lines


# --------------------------------------------------------------------------
#  Eingabe
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_mode(MODE_FLAG)
			KEY_2: _set_mode(MODE_ROAD)
			KEY_9, KEY_DELETE: _set_mode(MODE_DELETE)
			KEY_0, KEY_ESCAPE: _set_mode(MODE_SELECT)
			KEY_F2: _save_game()
			KEY_F3: _load_game()
			KEY_F5: _new_game()
			KEY_K: economy.ai_enabled = not economy.ai_enabled; _flash("KI " + ("AN" if economy.ai_enabled else "AUS")); _update_labels()
			KEY_J: _cycle_ai()
			KEY_P:
				if selected != null and not selected.is_hq and selected.owner == 0:
					var st := economy.toggle_production(selected)
					_flash("Produktion " + ("gestoppt" if st else "läuft"))
			KEY_SPACE:
				renderer.show_build_spots = not renderer.show_build_spots
				renderer.queue_redraw()
			KEY_F:
				renderer.fog_enabled = not renderer.fog_enabled
				renderer.queue_redraw()
				_flash("Nebel " + ("AN" if renderer.fog_enabled else "AUS"))
			KEY_PAUSE: paused = not paused; _update_labels()
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


func _try_attack(src: WorldState.Building, tgt: WorldState.Building) -> void:
	var d := WorldState.hex_distance(src.pos, tgt.pos)
	if d > src.influence + tgt.influence + 2:
		_flash("Ziel zu weit weg — näheres Militärgebäude nötig.")
		return
	var n := economy.send_attackers(src, tgt)
	_flash("Angriff mit %d Soldaten!" % n)


func _place_building_here() -> bool:
	var d := BuildingCatalog.get_def(build_def_id)
	if d.is_empty():
		return false
	var size: int = d.get("size", WorldState.BQ_HUT)
	return state.place_building(hover.x, hover.y, size, false, build_def_id,
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
	var path := state.plan_road(road_start, hover)
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
