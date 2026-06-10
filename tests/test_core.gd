extends SceneTree

## Headless-Selbsttests der Kern-Logik. Aufruf:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_core.gd

const Tuning := preload("res://core/tuning.gd")

var _ok := 0
var _fail := 0


func _initialize() -> void:
	print("== Grenzmark — Kern-Tests ==")
	_test_neighbors()
	_test_triangles_around()
	_test_map_generation()
	_test_worldgen_96()
	_test_mapgen_cleanup_and_stone_clusters()
	_test_start_territory_stone_guarantee()
	_test_ore_types()
	_test_ore_deposit_mining()
	_test_catalog_complete()
	_test_asset_files()
	_test_inventory_model()
	_test_visibility()
	_test_bq_and_flags()
	_test_building_spacing()
	_test_road_and_route()
	_test_economy()
	_test_stop_finishes_cycle()
	_test_productivity_and_building_info()
	_test_military()
	_test_combat()
	_test_enemy_road_people()
	_test_ai()
	_test_ai_plugin()
	_test_catapult()
	_test_promotion()
	_test_roadsplit()
	_test_build_help_respects_territory()
	_test_building_needs_territory_margin()
	_test_road_traffic_upgrade()
	_test_swamp()
	_test_tree_types_and_stone_stages()
	_test_construction_stages()
	_test_build_needs_connection()
	_test_material_after_split()
	_test_material_after_road_removed()
	_test_carrier_kept_on_split()
	_test_road_avoids_building()
	_test_road_preview_matches_build()
	_test_territory_closest_wins()
	_test_military_min_distance()
	_test_saveload()
	print("== Ergebnis: %d ok, %d fehlgeschlagen ==" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
		print("  FEHLER: ", msg)


func _test_neighbors() -> void:
	# Nachbar-Reziprozität: Nachbar in dir, zurück in Gegenrichtung -> Ausgang.
	for y in range(0, 6):
		for x in range(0, 6):
			for dir in Grid.DIRS:
				var n := Grid.neighbor(x, y, dir)
				var back := Grid.neighbor(n.x, n.y, Grid.opposite(dir))
				_check(back == Vector2i(x, y),
					"Reziprozität (%d,%d) dir %d -> %s -> %s" % [x, y, dir, n, back])


func _test_triangles_around() -> void:
	var x := 4
	var y := 4
	var tris := Grid.triangles_around(x, y)
	_check(tris.size() == 6, "6 Dreiecke um einen Knoten")
	# Jedes der 6 Dreiecke muss den Knoten selbst als Ecke enthalten.
	for tri in tris:
		var corners := Grid.triangle_corners(tri.pos.x, tri.pos.y, tri.kind)
		_check(corners.has(Vector2i(x, y)),
			"Dreieck %s enthält Knoten (%d,%d)" % [tri, x, y])


func _test_map_generation() -> void:
	var map := MapGenerator.generate(40, 40, 7)
	var meadow := 0
	var water := 0
	for yy in map.height:
		for xx in map.width:
			match map.get_tri(Vector2i(xx, yy), Grid.TRI_R):
				Terrain.MEADOW: meadow += 1
				Terrain.WATER: water += 1
	_check(meadow > 50, "Karte enthält Wiese (%d)" % meadow)
	_check(water > 0, "Karte enthält Wasser am Rand (%d)" % water)


func _test_bq_and_flags() -> void:
	var map := MapGenerator.generate(40, 40, 7)
	var state := WorldState.new(map)
	# Finde einen bebaubaren Knoten und setze dort eine Flagge.
	var placed := false
	for yy in range(2, map.height - 2):
		for xx in range(2, map.width - 2):
			if state.compute_bq(xx, yy) >= WorldState.BQ_HUT:
				var f := state.place_flag(xx, yy)
				_check(f != null, "Flagge auf bebaubarem Knoten setzbar")
				# Direkter Nachbar darf keine zweite Flagge erlauben.
				var n := map.neighbor(xx, yy, Grid.E)
				if n.x >= 0:
					_check(not state.can_place_flag(n.x, n.y),
						"Flaggen-Abstandsregel greift")
				placed = true
				break
		if placed:
			break
	_check(placed, "Es gibt mindestens einen bebaubaren Knoten")


func _test_road_and_route() -> void:
	var map := MapGenerator.generate(40, 40, 7)
	var state := WorldState.new(map)
	# Startflagge auf bebaubarem Knoten.
	var a := _find_buildable(state, map.width / 2, map.height / 2)
	if a.x < 0:
		_check(false, "Bebaubaren Startknoten gefunden")
		return
	state.place_flag(a.x, a.y)
	# Ein in der Nähe erreichbares Ziel suchen (3..8 Knoten entfernt).
	var road: WorldState.Road = null
	for r in range(3, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var b := Vector2i(a.x + dx, a.y + dy)
				if b == a or not map.in_bounds(b.x, b.y):
					continue
				if not state.can_build_road(a, b):
					continue
				road = state.build_road(a, b)
				break
			if road != null: break
		if road != null: break
	_check(road != null, "Straße per Auto-Pfad baubar")
	if road != null:
		_check(road.nodes.size() >= 2, "Straße hat Knoten")
		var route := state.find_route(a, road.b)
		_check(route.size() >= 2, "Route über das Flaggennetz gefunden")


func _test_economy() -> void:
	# Flache Wiesenkarte, damit der Aufbau garantiert verbunden ist.
	var map := _flat_map(28, 28)
	var state := WorldState.new(map)
	var eco := Economy.new(state)

	# HQ (fertig, mit Einflussgebiet).
	var hq := state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	_check(state.in_territory(12, 12), "HQ erzeugt Territorium")
	_check(not state.in_territory(1, 1), "Außerhalb des Gebiets kein Territorium")
	_check(not state.can_place_building(1, 1, WorldState.BQ_HUT),
		"Bauen außerhalb des Gebiets verboten")

	# Sägewerk als Baustelle: Holz -> Bretter, beides läuft über das HQ.
	var saw := state.place_building(12, 7, WorldState.BQ_HOUSE, false, "sawmill", 0, true)
	_check(saw != null, "Sägewerk im Gebiet platzierbar")
	if saw == null:
		return
	var road := state.build_road(hq.flag_pos, saw.flag_pos)
	_check(road != null, "Straße HQ <-> Sägewerk baubar")
	eco.resync()
	_check(eco.carriers.size() == 1, "Ein Träger pro Straße")

	var wood_before: int = eco.hq_stock.get(Goods.WOOD, 0)
	for t in 6000:
		eco.tick()
	_check(not saw.under_construction, "Sägewerk wird fertiggestellt")
	_check(eco.hq_stock.get(Goods.WOOD, 0) < wood_before,
		"Sägewerk verbraucht Holz aus dem HQ (Kette läuft)")

	# Abriss der Straße über einen Zwischenknoten: Träger verschwindet.
	_check(road.nodes.size() >= 3, "Straße hat einen Zwischenknoten zum Abreißen")
	state.remove_at(road.nodes[1])
	eco.resync()
	_check(eco.carriers.is_empty(), "Träger nach Straßen-Abriss entfernt")


## Issue #14: "Stop" blockiert nur den nächsten Arbeitsgang, friert den laufenden
## nicht ein. Der Arbeiter beendet seinen Zyklus und verharrt erst danach im Haus.
func _test_stop_finishes_cycle() -> void:
	var map := _flat_map(24, 24)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Stop-Test: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	# Fertiger Holzfäller im Gebiet (sofort besetzt) + reifer Baum in Reichweite.
	var wc := state.place_building(10, 7, WorldState.BQ_HOUSE, false, "woodcutter", 0, false)
	_check(wc != null, "Stop-Test: Holzfäller platzierbar")
	if wc == null:
		return
	map.set_map_object(10, 6, MapData.MO_TREE)
	map.set_tree_stage(10, 6, MapData.TREE_BIG)
	eco.resync()
	var bs = eco.bstates.get(map.idx(wc.pos.x, wc.pos.y))
	_check(bs != null, "Stop-Test: BState vorhanden")
	if bs == null:
		return

	# In einen laufenden Arbeitsgang kommen (Arbeiter verlässt das Haus).
	var entered_cycle := false
	for t in 600:
		eco.tick()
		if bs.wphase != Economy.WK_IDLE:
			entered_cycle = true
			break
	_check(entered_cycle, "Stop-Test: Arbeiter startet einen Arbeitsgang")

	# Mitten im Zyklus stoppen -> der Gang soll zu Ende laufen (kein Einfrieren).
	bs.stopped = true
	var returned_home := false
	for t in 3000:
		eco.tick()
		if bs.wphase == Economy.WK_IDLE:
			returned_home = true
			break
	_check(returned_home, "Stop-Test: laufender Gang wird trotz Stop beendet")

	# Im Haus angekommen und gestoppt -> es startet KEIN neuer Gang.
	var stayed_home := true
	for t in 600:
		eco.tick()
		if bs.wphase != Economy.WK_IDLE:
			stayed_home = false
			break
	_check(stayed_home, "Stop-Test: gestoppter Arbeiter startet keinen neuen Gang")


## Gebäudefenster-Unterbau (#5): Produktivität % im rollenden Fenster und
## strukturierte building_info()-Daten mit Soll/Ist und Warnzuständen.
func _test_productivity_and_building_info() -> void:
	var map := _flat_map(24, 24)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Prod-Test: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	var wc := state.place_building(10, 7, WorldState.BQ_HOUSE, false, "woodcutter", 0, false)
	_check(wc != null, "Prod-Test: Holzfäller platzierbar")
	if wc == null:
		return
	map.set_map_object(10, 6, MapData.MO_TREE)
	map.set_tree_stage(10, 6, MapData.TREE_BIG)
	eco.resync()
	var bs = eco.bstates.get(map.idx(wc.pos.x, wc.pos.y))
	_check(bs != null, "Prod-Test: BState vorhanden")
	if bs == null:
		return

	# Arbeiten lassen: Produktivität muss > 0 werden und im Fenster auftauchen.
	for t in 2000:
		eco.tick()
	_check(bs.prod_total > 0, "Prod-Test: Bewertungsfenster läuft mit")
	_check(bs.prod_active > 0, "Prod-Test: aktive Arbeitsticks gezählt")
	var info := eco.building_info(wc)
	_check(int(info.productivity) > 0, "Prod-Test: building_info liefert Produktivität > 0")
	_check(int(info.productivity) <= 100, "Prod-Test: Produktivität <= 100")
	_check(not bool(info.construction), "Prod-Test: kein Baustellen-Flag am fertigen Gebäude")

	# Alle Bäume weg -> Leerlaufgrund "kein Rohstoff" mit Warntext.
	for yy in map.height:
		for xx in map.width:
			if map.map_object(xx, yy) == MapData.MO_TREE:
				map.clear_map_object(xx, yy)
	var saw_warning := false
	for t in 4000:
		eco.tick()
		if bs.wphase == Economy.WK_IDLE and bs.idle_reason == Economy.IDLE_NO_RESOURCE:
			saw_warning = true
			break
	_check(saw_warning, "Prod-Test: idle_reason 'kein Rohstoff' gesetzt")
	info = eco.building_info(wc)
	_check(String(info.warning) == "Kein Rohstoff in Reichweite",
		"Prod-Test: Warnung 'Kein Rohstoff in Reichweite' im Fensterinfo")

	# Sägewerk ohne Holzlieferung -> wartet auf Waren; Soll/Ist-Zeile vorhanden.
	var saw := state.place_building(13, 10, WorldState.BQ_HOUSE, false, "sawmill", 0, false)
	_check(saw != null, "Prod-Test: Sägewerk platzierbar")
	if saw == null:
		return
	eco.hq_stock[Goods.WOOD] = 0  # HQ leer: es kann nichts geliefert werden
	eco.resync()
	var sbs = eco.bstates.get(map.idx(saw.pos.x, saw.pos.y))
	var waits := false
	for t in 3000:
		eco.tick()
		if sbs != null and sbs.staffed and sbs.wphase == Economy.WK_IDLE \
				and sbs.idle_reason == Economy.IDLE_NO_INPUTS:
			waits = true
			break
	_check(waits, "Prod-Test: Sägewerk meldet 'wartet auf Waren'")
	var sinfo := eco.building_info(saw)
	_check((sinfo.inputs as Array).size() == 1, "Prod-Test: Sägewerk hat eine Eingangszeile")
	if (sinfo.inputs as Array).size() == 1:
		var row: Dictionary = sinfo.inputs[0]
		_check(int(row.good) == Goods.WOOD, "Prod-Test: Eingangszeile ist Holz")
		_check(int(row.want) > 0 and int(row.have) <= int(row.want),
			"Prod-Test: Soll/Ist-Werte plausibel")
	_check((sinfo.output as Dictionary).get("good", -1) == Goods.BOARDS,
		"Prod-Test: Ausgangszeile ist Bretter")


func _test_military() -> void:
	var map := _flat_map(36, 36)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()

	var gd := BuildingCatalog.get_def("guardhouse")
	var gh := state.place_building(12, 19, gd.size, false, "guardhouse",
		int(gd.influence), true)
	_check(gh != null, "Wachhaus im Gebiet platzierbar")
	if gh == null:
		return
	state.build_road(state.buildings[map.idx(12, 12)].flag_pos, gh.flag_pos)
	eco.resync()
	eco.hq_stock[Goods.SWORD] = 3

	_check(not state.in_territory(12, 24), "Vor Garnison kein Gebiet am Wachhaus-Rand")
	for t in 5000:
		eco.tick()
	_check(not gh.under_construction, "Wachhaus wird gebaut")
	_check(gh.garrison >= 1, "Wachhaus erhält Soldaten (Garnison %d)" % gh.garrison)
	_check(state.in_territory(12, 24), "Wachhaus erweitert das Gebiet nach Besatzung")


func _test_combat() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	# Eigenes Wachhaus mit Garnison (im eigenen Gebiet).
	var pg := state.place_building(13, 13, WorldState.BQ_HUT, false, "guardhouse", 5, false)
	_check(pg != null, "Eigenes Wachhaus platzierbar")
	if pg == null:
		return
	pg.garrison = 3
	# Gegnerisches Wachhaus direkt einsetzen.
	var eb := WorldState.Building.new()
	eb.pos = Vector2i(20, 20)
	eb.size = WorldState.BQ_HUT
	eb.def_id = "guardhouse"
	eb.influence = 5
	eb.owner = 1
	eb.under_construction = false
	eb.garrison = 2
	eb.capacity = 2
	eb.flag_pos = map.neighbor(20, 20, Grid.SE)
	state.buildings[map.idx(20, 20)] = eb
	state.occupied[map.idx(20, 20)] = WorldState.OBJ_BUILDING
	eco.resync()
	_check(state.enemy_territory.size() > 0, "Gegner hat Territorium")

	var n := eco.send_attackers(pg, eb)
	_check(n == 3, "Drei Angreifer losgeschickt")
	for t in 3000:
		eco.tick()
	_check(eb.owner == 0, "Gegnergebäude erobert (Besitzer %d)" % eb.owner)


func _test_ai() -> void:
	var map := _flat_map(50, 50)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(8, 8, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_raw(state, Vector2i(40, 40), "hq", 9, 1, 6, 6, true)
	var eb := _raw(state, Vector2i(40, 35), "guardhouse", 5, 1, 0, 3, false)
	eco.resync()
	var before := _count_enemy_military(state)
	for t in 3000:
		eco.tick()
	_check(eb.garrison > 0, "KI besetzt ihr Wachhaus (Garnison %d)" % eb.garrison)
	_check(_count_enemy_military(state) > before, "KI expandiert (neue Militärgebäude)")
	_check(_count_enemy_roads(state) > 0, "KI baut sichtbare Gegner-Straßen (%d)" % _count_enemy_roads(state))
	_check(_count_active_enemy_carriers(eco) > 0,
		"KI-Gegner hat aktive sichtbare Träger (%d)" % _count_active_enemy_carriers(eco))
	# KI baut auch Wirtschaftsgebäude (Besitzer 1, ohne Einfluss).
	var econ := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner == 1 and not b.is_hq and b.influence == 0:
			econ += 1
	_check(econ > 0, "KI baut Wirtschaftsgebäude (%d)" % econ)


func _test_enemy_road_people() -> void:
	var map := _flat_map(42, 42)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	eco.ai_enabled = false
	var ehq := state.place_building(30, 30, WorldState.BQ_CASTLE, true, "hq", 9, false, 1)
	_check(ehq != null, "Gegner-HQ platzierbar")
	if ehq == null:
		return
	ehq.garrison = 6
	ehq.capacity = 6
	state.recompute_territory()
	var hut := state.place_building(30, 24, WorldState.BQ_HUT, false, "woodcutter", 0, false, 1)
	_check(hut != null, "Gegner-Wirtschaftsgebäude platzierbar")
	if hut == null:
		return
	var road := state.build_road(ehq.flag_pos, hut.flag_pos, 1)
	_check(road != null and road.owner == 1, "Gegnerstraße bekommt Besitzer 1")
	eco.resync()
	for t in 1000:
		eco.tick()
	var c: Economy.Carrier = eco.carriers.get(road, null)
	_check(c != null and c.active and c.road.owner == 1,
		"Gegnerstraße bekommt aktiven Gegner-Träger")
	var bs: Economy.BState = eco.bstates.get(map.idx(hut.pos.x, hut.pos.y), null)
	_check(bs != null and bs.bld.owner == 1, "Gegnergebäude bekommt Visual-State")
	_check(bs != null and bs.staffed, "Gegnerarbeiter kommt sichtbar vom Gegner-HQ")


func _raw(state: WorldState, pos: Vector2i, def: String, infl: int, owner: int,
		gar: int, cap: int, is_hq: bool) -> WorldState.Building:
	var b := WorldState.Building.new()
	b.pos = pos; b.size = (WorldState.BQ_CASTLE if is_hq else WorldState.BQ_HUT)
	b.def_id = def; b.influence = infl; b.owner = owner
	b.under_construction = false; b.garrison = gar; b.capacity = cap; b.is_hq = is_hq
	b.flag_pos = state.map.neighbor(pos.x, pos.y, Grid.SE)
	var i := state.map.idx(pos.x, pos.y)
	state.buildings[i] = b
	state.occupied[i] = WorldState.OBJ_BUILDING
	return b


func _count_enemy_military(state: WorldState) -> int:
	var n := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner == 1 and b.influence > 0 and not b.is_hq:
			n += 1
	return n


func _count_enemy_roads(state: WorldState) -> int:
	var n := 0
	for r in state.roads:
		if r.owner == 1:
			n += 1
	return n


func _count_active_enemy_carriers(eco: Economy) -> int:
	var n := 0
	for r in eco.carriers:
		var c: Economy.Carrier = eco.carriers[r]
		if c.active and c.road.owner == 1:
			n += 1
	return n


func _test_ai_plugin() -> void:
	var l := AIRegistry.list()
	_check(l.size() >= 2, "KI-Registry liefert KIs (%d)" % l.size())
	var has_default := false
	var has_passive := false
	for e in l:
		if e.id == "default": has_default = true
		if e.id == "passive": has_passive = true
	_check(has_default and has_passive, "Eingebaute KIs (Standard/Passiv) vorhanden")
	_check(AIRegistry.create({ path = "builtin:default" }) is DefaultAI, "create() → DefaultAI")
	_check(AIRegistry.create({ path = "builtin:passive" }) is PassiveAI, "create() → PassiveAI")
	# Passiv-KI tut nichts: Garnison bleibt 0.
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	eco.ai = PassiveAI.new()
	state.place_building(8, 8, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_raw(state, Vector2i(22, 22), "hq", 9, 1, 6, 6, true)
	var eb := _raw(state, Vector2i(22, 18), "guardhouse", 5, 1, 0, 3, false)
	eco.resync()
	for t in 1500:
		eco.tick()
	_check(eb.garrison == 0, "Passiv-KI besetzt nichts")


func _test_worldgen_96() -> void:
	# Die echte Spielkarte (Seed 1337, 96x96): Berge, Erz und Burgplatz müssen da sein.
	var map := MapGenerator.generate(96, 96, 1337)
	var mountain := 0
	var ore := 0
	for yy in map.height:
		for xx in map.width:
			if map.get_tri(Vector2i(xx, yy), Grid.TRI_R) == Terrain.MOUNTAIN:
				mountain += 1
	for k in map.ore_deposit_amount:
		if int(map.ore_deposit_amount[k]) > 0:
			ore += 1
	_check(mountain > 50, "Karte hat Gebirge (%d Dreiecke)" % mountain)
	_check(ore > 0, "Gebirge enthält unterirdische Erz-Vorkommen (%d)" % ore)
	# Erz ist unterirdisch — es darf kein sichtbares MO_ORE-Objekt auf der Karte sein.
	var visible_ore := 0
	for k in map.objects:
		if map.objects[k] == MapData.MO_ORE:
			visible_ore += 1
	_check(visible_ore == 0, "Kein sichtbares Erz-Objekt auf der Karte (%d)" % visible_ore)
	# Es gibt einen Burgplatz (für Spieler- und Gegner-HQ).
	var state := WorldState.new(map)
	var castle := 0
	for yy in range(2, map.height - 2):
		for xx in range(2, map.width - 2):
			if state.compute_bq(xx, yy) >= WorldState.BQ_CASTLE:
				castle += 1
	_check(castle >= 2, "Mindestens zwei Burgplätze (Spieler + Gegner): %d" % castle)


func _test_mapgen_cleanup_and_stone_clusters() -> void:
	var map := MapGenerator.generate(96, 96, 1337)
	var again := MapGenerator.generate(96, 96, 1337)
	_check(map.heights == again.heights and map.terr_r == again.terr_r \
			and map.terr_d == again.terr_d and map.objects == again.objects,
		"#19: Kartengenerator bleibt deterministisch")
	var spikes := _terrain_spike_count(map)
	_check(spikes <= 8, "#19: wenige isolierte Terrain-Dreiecke (%d)" % spikes)
	var stone_sizes := _stone_component_sizes(map)
	var stones := 0
	var clustered := 0
	for s in stone_sizes:
		stones += int(s)
		if int(s) >= 2:
			clustered += int(s)
	_check(stones > 0, "#19: Steincluster erzeugen Steine (%d)" % stones)
	_check(clustered * 100 >= stones * 60,
		"#19: Mehrheit der Steine liegt in Clustern (%d/%d)" % [clustered, stones])


func _test_start_territory_stone_guarantee() -> void:
	var map := _flat_map(40, 40)
	var world := World.new()
	world.map = map
	world.state = WorldState.new(map)
	world.state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false, 0)
	world.state.place_building(28, 28, WorldState.BQ_CASTLE, true, "hq", 9, false, 1)
	world.state.recompute_territory()
	world._ensure_stone_cluster_in_territory(0)
	world._ensure_stone_cluster_in_territory(1)
	_check(_owner_territory_stones(world.state, 0) >= 3,
		"#19: Spieler startet mit Steincluster im Gebiet")
	_check(_owner_territory_stones(world.state, 1) >= 3,
		"#19: KI startet mit Steincluster im Gebiet")
	world.free()


func _test_catalog_complete() -> void:
	for id in ["hunter", "pigfarm", "slaughterhouse", "toolmaker", "granitemine"]:
		_check(not BuildingCatalog.get_def(id).is_empty(), "Gebäude im Katalog: %s" % id)


func _test_asset_files() -> void:
	for g in Goods.COUNT:
		_check(FileAccess.file_exists("res://assets/goods/%d.png" % g),
			"Waren-Icon vorhanden: %d %s" % [g, Goods.name_of(g)])
	for id in BuildingCatalog.defs().keys():
		_check(FileAccess.file_exists("res://assets/buildings/%s.png" % id),
			"Gebäude-Sprite vorhanden: %s" % id)


## S2-Lagermodell: Waren (inkl. 12 Originalwerkzeuge) + Personen (Berufe) + die
## Werkzeug->Beruf-Zuordnung, sowie das HQ-Startinventar aus dem Tuning.
func _test_inventory_model() -> void:
	# --- Waren: die 12 Einzelwerkzeuge sind vorhanden und konsistent ---
	_check(Goods.COUNT == 31, "Goods.COUNT == 31 (19 Basis + 12 Werkzeuge)")
	for g in Goods.COUNT:
		_check(Goods.name_of(g) != "?", "Ware hat Namen: %d" % g)
		_check(Goods.id_of(Goods.key_of(g)) == g, "Goods-KEY Roundtrip: %d" % g)
	_check(Goods.is_tool_good(Goods.AXE) and Goods.is_tool_good(Goods.BOW), "Axt/Bogen sind Werkzeuge")
	_check(not Goods.is_tool_good(Goods.WOOD) and not Goods.is_tool_good(Goods.TOOLS),
		"Holz/altes TOOLS sind keine Einzelwerkzeuge")

	# --- Berufe: Liste, Namen, KEY-Roundtrip, Soldaten ---
	_check(Jobs.COUNT == 27, "Jobs.COUNT == 27")
	for j in Jobs.COUNT:
		_check(Jobs.name_of(j) != "?", "Beruf hat Namen: %d" % j)
		_check(Jobs.id_of(Jobs.key_of(j)) == j, "Jobs-KEY Roundtrip: %d" % j)
	_check(Jobs.is_soldier(Jobs.GENERAL) and not Jobs.is_soldier(Jobs.HELPER),
		"Soldatenerkennung (General ja, Träger nein)")

	# --- Werkzeug -> Beruf (RTTR JobConsts): Stichproben ---
	_check(Jobs.tool_for(Jobs.WOODCUTTER) == Goods.AXE, "Holzfäller braucht Axt")
	_check(Jobs.tool_for(Jobs.STONEMASON) == Goods.PICKAXE, "Steinmetz braucht Spitzhacke")
	_check(Jobs.tool_for(Jobs.MINER) == Goods.PICKAXE, "Bergarbeiter braucht Spitzhacke")
	_check(Jobs.tool_for(Jobs.BAKER) == Goods.ROLLING_PIN, "Bäcker braucht Nudelholz")
	_check(Jobs.tool_for(Jobs.METALWORKER) == Goods.TONGS, "Werkzeugmacher braucht Zange")
	_check(Jobs.tool_for(Jobs.HELPER) == -1, "Träger braucht kein Werkzeug")
	_check(Jobs.tool_for(Jobs.MILLER) == -1, "Müller braucht kein Werkzeug")

	# --- Gebäude -> Beruf ---
	_check(BuildingCatalog.job_of("woodcutter") == Jobs.WOODCUTTER, "Holzfäller-Hütte -> Holzfäller")
	_check(BuildingCatalog.job_of("smithy") == Jobs.ARMORER, "Schmiede -> Waffenschmied")
	_check(BuildingCatalog.job_of("ironmine") == Jobs.MINER, "Eisenmine -> Bergarbeiter")
	_check(BuildingCatalog.job_of("hq") == -1, "HQ hat keinen Produktionsberuf")
	_check(BuildingCatalog.job_of("fortress") == -1, "Festung hat keinen Produktionsberuf")

	# --- HQ-Startinventar hält Waren UND Personen ---
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	_check(eco.hq_stock.get(Goods.BOARDS, 0) > 0, "HQ startet mit Brettern")
	_check(eco.hq_stock.get(Goods.HAMMER, 0) > 0, "HQ startet mit Werkzeug (Hammer) zur Rekrutierung")
	_check(eco.hq_people_count(Jobs.HELPER) > 0, "HQ-Lager hält Träger (Personen)")
	_check(eco.soldiers > 0, "HQ hat Soldaten-Reserve")

	# --- Tuning liefert das Startinventar (Defaults bzw. JSON) ---
	_check(Tuning.hq_start_goods().get(Goods.BOARDS, 0) > 0, "Tuning: Startwaren")
	_check(Tuning.hq_start_people().get(Jobs.HELPER, 0) > 0, "Tuning: Startpersonen")


func _test_visibility() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	_check(state.explored.has(map.idx(10, 10)), "HQ-Umgebung aufgedeckt")
	_check(not state.explored.has(map.idx(34, 34)), "Ferne Karte bleibt im Nebel")


func _test_ore_types() -> void:
	var map := _flat_map(20, 20)
	map.set_ore_deposit(10, 8, MapData.ORE_COAL, 5)
	map.set_ore_deposit(12, 12, MapData.ORE_IRON, 5)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	_check(eco._find_deposit(Vector2i(10, 10), MapData.ORE_IRON, 6) == Vector2i(12, 12),
		"Eisenmine findet Eisen-Vorkommen, nicht Kohle")
	_check(eco._find_deposit(Vector2i(10, 10), MapData.ORE_COAL, 6) == Vector2i(10, 8),
		"Kohlemine findet Kohle-Vorkommen")
	_check(eco._find_deposit(Vector2i(10, 10), MapData.ORE_GOLD, 6).x < 0,
		"Keine Gold-Ader in der Nähe → kein Fund")


## #19: Erz liegt unterirdisch. Die Mine findet ein Vorkommen im Radius (nicht
## nur am eigenen Knoten) und baut es Schlag für Schlag ab, bis es erschöpft ist.
func _test_ore_deposit_mining() -> void:
	var map := _flat_map(20, 20)
	map.set_ore_deposit(10, 8, MapData.ORE_IRON, 3)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var target := eco._find_deposit(Vector2i(10, 10), MapData.ORE_IRON, Economy.ORE_RADIUS)
	_check(target == Vector2i(10, 8), "Mine findet Erz-Vorkommen im Radius (nicht nur am Knoten)")
	var bs := Economy.BState.new()
	bs.def = { resource = "ore" }
	bs.worker_target = Vector2i(10, 8)
	eco._do_resource_action(bs)
	_check(map.ore_deposit_amount_at(10, 8) == 2, "1. Abbau: Menge 3 → 2")
	eco._do_resource_action(bs)
	eco._do_resource_action(bs)
	_check(map.ore_deposit_amount_at(10, 8) == 0, "Vorkommen nach 3 Schlägen erschöpft")
	_check(eco._find_deposit(Vector2i(10, 10), MapData.ORE_IRON, Economy.ORE_RADIUS).x < 0,
		"Erschöpftes Vorkommen wird nicht mehr gefunden")


## S2-Footprint: Hütte/Haus dürfen direkt neben ein Gebäude; nur Burgen brauchen
## Luft (kein Gebäude im Radius 2). Große Gebäude (Burg/HQ) belegen zusätzlich
## ihre 3 Extension-Knoten oben-links (W/NW/NE).
func _test_building_spacing() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	var b := state.place_building(13, 16, WorldState.BQ_HUT, false, "woodcutter", 0, false)
	_check(b != null, "Gebäude im Gebiet platzierbar")
	if b == null:
		return
	var n := map.neighbor(13, 16, Grid.E)
	# S2: Footprint neben einem Gebäude erlaubt Hütte/Haus (kein Flaggen-Ring mehr).
	# (Ob dort tatsächlich gebaut werden kann, hängt zusätzlich am Flaggenabstand.)
	_check(state.effective_bq(n.x, n.y) >= WorldState.BQ_HUT,
		"S2: Footprint direkt neben Gebäude erlaubt Hütte/Haus (eff. BQ %d)" % state.effective_bq(n.x, n.y))
	# S2: aber KEINE Burg im Umkreis von 2 Knoten eines Gebäudes.
	_check(state.effective_bq(n.x, n.y) <= WorldState.BQ_HOUSE,
		"S2: keine Burg direkt neben Gebäude (nur bis Haus)")
	# Freier, flacher Platz weit weg erlaubt eine Burg.
	_check(state.effective_bq(25, 4) >= WorldState.BQ_CASTLE,
		"Freier, flacher Platz erlaubt Burg")
	# Eine platzierte Burg belegt ihre 3 Extension-Knoten (W/NW/NE).
	var castle := state.place_building(25, 4, WorldState.BQ_CASTLE, false, "fortress", 10, false)
	_check(castle != null, "Burg auf freiem Platz baubar")
	if castle != null:
		_check(castle.ext_nodes.size() == 3, "Burg reserviert 3 Extension-Knoten (%d)" % castle.ext_nodes.size())
		for dir in [Grid.W, Grid.NW, Grid.NE]:
			var e := map.neighbor(25, 4, dir)
			_check(state.effective_bq(e.x, e.y) == WorldState.BQ_NOTHING,
				"Extension-Knoten der Burg ist gesperrt (dir %d)" % dir)
		# Nach Abriss sind die Extension-Knoten wieder frei.
		state.remove_at(Vector2i(25, 4))
		var w := map.neighbor(25, 4, Grid.W)
		_check(state.effective_bq(w.x, w.y) != WorldState.BQ_NOTHING,
			"Extension-Knoten nach Abriss wieder baubar")


func _test_catapult() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var cat := state.place_building(13, 13, WorldState.BQ_HOUSE, false, "catapult", 4, false)
	_check(cat != null, "Katapult baubar")
	if cat == null:
		return
	cat.garrison = 1
	var eb := _raw(state, Vector2i(17, 15), "guardhouse", 5, 1, 3, 3, false)
	eco.resync()
	for t in 2500:
		eco.tick()
	_check(eb.garrison < 3, "Katapult dezimiert Gegner-Garnison (%d)" % eb.garrison)


func _test_promotion() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var gh := state.place_building(13, 13, WorldState.BQ_HUT, false, "guardhouse", 5, false)
	_check(gh != null, "Wachhaus baubar")
	if gh == null:
		return
	gh.garrison = 3
	state.build_road(state.buildings[map.idx(10, 10)].flag_pos, gh.flag_pos)
	eco.resync()
	eco.hq_stock[Goods.COINS] = 5
	for t in 2500:
		eco.tick()
	_check(gh.promotions > 0, "Münzen befördern die Garnison (Rang +%d)" % gh.promotions)


func _test_roadsplit() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var hqflag: Vector2i = state.buildings[map.idx(12, 12)].flag_pos
	var road := state.build_road(hqflag, Vector2i(12, 18))
	_check(road != null, "Teststraße baubar")
	if road == null:
		return
	_check(road.nodes.size() >= 4, "Straße hat innere Knoten")
	var before := state.roads.size()
	var midn: Vector2i = road.nodes[2]
	var f := state.place_flag(midn.x, midn.y)
	_check(f != null, "Flagge auf Straße setzbar (teilt)")
	_check(state.roads.size() == before + 1, "Straße in zwei geteilt")
	_check(state.flag_at(midn) != null, "Neue Flagge liegt auf dem Knoten")


func _test_build_help_respects_territory() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	_check(hq != null, "HQ für Bauhilfe-Test platzierbar")
	_check(state.actual_build_spot_bq(10, 16) >= WorldState.BQ_FLAG,
		"Bauhilfe zeigt Plätze im eigenen Gebiet")
	_check(state.actual_build_spot_bq(35, 35) == WorldState.BQ_NOTHING,
		"Bauhilfe zeigt keine fremden Kartenplätze außerhalb des Gebiets")


func _test_building_needs_territory_margin() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	_check(hq != null, "HQ für Grenzbau-Test platzierbar")
	var saw_border := false
	var saw_inner_buildable := false
	for k in state.territory:
		var x := int(k) % map.width
		var y := int(k) / map.width
		if state.is_territory_border_node(x, y):
			saw_border = true
			_check(not state.can_place_building(x, y, WorldState.BQ_HUT),
				"Bauen direkt auf der Grenze verboten")
		elif state.can_place_building(x, y, WorldState.BQ_HUT):
			saw_inner_buildable = true
	_check(saw_border, "Grenzknoten im Territorium gefunden")
	_check(saw_inner_buildable, "Innen im Gebiet bleiben Bauplätze erlaubt")


func _test_road_traffic_upgrade() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var hqflag: Vector2i = state.buildings[map.idx(12, 12)].flag_pos
	var road := state.build_road(hqflag, Vector2i(12, 18))
	_check(road != null, "Straße für Last-Ausbau baubar")
	if road == null:
		return
	for i in Tuning.road_upgrade_deliveries():
		eco._mark_road_delivery(road)
	_check(road.level == WorldState.ROAD_COBBLE, "Straße wird nach Warenlast gepflastert")


func _test_saveload() -> void:
	# Serialisierungs-Primitive (PackedByteArray, Vector2i, verschachtelte Dicts).
	var map := _flat_map(16, 16)
	map.set_height(3, 4, 7)
	map.set_map_object(5, 5, MapData.MO_TREE)
	var state := WorldState.new(map)
	state.place_building(8, 8, WorldState.BQ_CASTLE, true, "hq", 9, false)

	var data := {
		w = map.width, h = map.height,
		heights = map.heights, terr_r = map.terr_r, terr_d = map.terr_d,
		objects = map.objects.duplicate(),
		buildings = [],
		# Personen-Inventar (int-keyed) muss den Roundtrip überstehen.
		hq_people = { Jobs.HELPER: 7, Jobs.MINER: 2 },
	}
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		data.buildings.append({ pos = b.pos, def = b.def_id, hq = b.is_hq })

	var path := "user://test_roundtrip.dat"
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_var(data, true)
	fw.close()
	var fr := FileAccess.open(path, FileAccess.READ)
	var back: Dictionary = fr.get_var(true)
	fr.close()

	_check(int(back.w) == 16 and int(back.h) == 16, "Save/Load: Kartengröße")
	var map2 := MapData.new(int(back.w), int(back.h))
	map2.heights = back.heights
	map2.objects = back.objects
	_check(map2.get_height(3, 4) == 7, "Save/Load: Höhe erhalten")
	_check(map2.map_object(5, 5) == MapData.MO_TREE, "Save/Load: Objekt erhalten")
	_check(back.buildings.size() == 1, "Save/Load: Gebäude erhalten")
	_check(Vector2i(back.buildings[0].pos) == Vector2i(8, 8), "Save/Load: Vector2i erhalten")
	var people: Dictionary = back.get("hq_people", {})
	_check(int(people.get(Jobs.HELPER, 0)) == 7 and int(people.get(Jobs.MINER, 0)) == 2,
		"Save/Load: Personen-Inventar (Träger+Bergarbeiter) erhalten")


## Sumpf wird erzeugt und ist begehbar, aber NICHT bebaubar (wie in S2).
func _test_swamp() -> void:
	# Eigenschaften des Terrains.
	_check(Terrain.is_walkable(Terrain.SWAMP), "Sumpf ist begehbar (Straßen/Träger)")
	_check(not Terrain.is_buildable(Terrain.SWAMP), "Sumpf ist NICHT bebaubar")
	# Der Generator erzeugt tatsächlich Sumpf auf der echten Karte.
	var map := MapGenerator.generate(96, 96, 1337)
	var swamp := 0
	for yy in map.height:
		for xx in map.width:
			if map.get_tri(Vector2i(xx, yy), Grid.TRI_R) == Terrain.SWAMP:
				swamp += 1
			if map.get_tri(Vector2i(xx, yy), Grid.TRI_D) == Terrain.SWAMP:
				swamp += 1
	_check(swamp > 0, "Karte enthält Sumpf (%d Dreiecke)" % swamp)
	# Ein Knoten, der nur von Sumpf umgeben ist, darf kein Gebäude zulassen.
	var sm := _flat_map(20, 20)
	for yy in 20:
		for xx in 20:
			sm.set_tri(Vector2i(xx, yy), Grid.TRI_R, Terrain.SWAMP)
			sm.set_tri(Vector2i(xx, yy), Grid.TRI_D, Terrain.SWAMP)
	var ss := WorldState.new(sm)
	_check(ss.compute_bq(10, 10) < WorldState.BQ_HUT, "Auf reinem Sumpf kein Gebäude")


func _test_tree_types_and_stone_stages() -> void:
	var map := _flat_map(20, 20)
	map.set_map_object(5, 5, MapData.MO_TREE)
	map.set_tree_stage(5, 5, MapData.TREE_SEED)
	map.set_tree_type(5, 5, MapData.TREE_BIRCH)
	_check(map.tree_stage_at(5, 5) == MapData.TREE_SEED, "Baumstufe gespeichert")
	_check(map.tree_type_at(5, 5) == MapData.TREE_BIRCH, "Baumtyp gespeichert")

	map.set_map_object(10, 10, MapData.MO_STONE)
	map.set_stone_stage(10, 10, MapData.STONE_BIG)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var bs := Economy.BState.new()
	bs.def = { resource = "stone" }
	bs.worker_target = Vector2i(10, 10)
	# BIG braucht 3 Schläge → MEDIUM
	eco._do_resource_action(bs)
	_check(map.stone_stage_at(10, 10) == MapData.STONE_BIG, "BIG nach 1. Schlag noch BIG")
	eco._do_resource_action(bs)
	_check(map.stone_stage_at(10, 10) == MapData.STONE_BIG, "BIG nach 2. Schlag noch BIG")
	eco._do_resource_action(bs)
	_check(map.stone_stage_at(10, 10) == MapData.STONE_MEDIUM, "BIG → MEDIUM nach 3 Schlägen")
	# MEDIUM braucht 2 Schläge → SMALL
	eco._do_resource_action(bs)
	_check(map.stone_stage_at(10, 10) == MapData.STONE_MEDIUM, "MEDIUM nach 1. Schlag noch MEDIUM")
	eco._do_resource_action(bs)
	_check(map.stone_stage_at(10, 10) == MapData.STONE_SMALL, "MEDIUM → SMALL nach 2 Schlägen")
	# SMALL verschwindet nach 1 Schlag
	eco._do_resource_action(bs)
	_check(map.map_object(10, 10) == -1, "SMALL nach 1 Schlag weg")


## 2-stufiger Baufortschritt: mit Stein erst Holzstufe, dann Steinstufe;
## ohne Stein gleichmäßig auf beide Stufen aufgeteilt.
func _test_construction_stages() -> void:
	var map := _flat_map(28, 28)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	# Sägewerk: Bretter (Holz, Wert 3) + Stein (Wert 4) → Stufe 1 endet bei Holz=3.
	var saw := state.place_building(12, 7, WorldState.BQ_HOUSE, false, "sawmill", 0, true)
	var wc := state.place_building(8, 12, WorldState.BQ_HUT, false, "woodcutter", 0, true)
	eco.resync()
	if saw != null:
		var bs: Economy.BState = eco.bstates[map.idx(12, 7)]
		bs.built = 1.0
		_check(int(eco.construct_stage_info(bs).stage) == 1,
			"Bau mit Stein: kleiner Fortschritt ist Stufe 1 (Holz)")
		bs.built = 5.0
		_check(int(eco.construct_stage_info(bs).stage) == 2,
			"Bau mit Stein: nach dem Holzanteil Stufe 2 (Stein)")
	# Holzfäller: nur 2 Bretter, kein Stein → Stufe 1 endet bei der Hälfte (Wert 1).
	if wc != null:
		var bs2: Economy.BState = eco.bstates[map.idx(8, 12)]
		bs2.built = 0.5
		_check(int(eco.construct_stage_info(bs2).stage) == 1,
			"Bau ohne Stein: erste Hälfte ist Stufe 1")
		bs2.built = 1.5
		_check(int(eco.construct_stage_info(bs2).stage) == 2,
			"Bau ohne Stein: zweite Hälfte ist Stufe 2")


## Ein Gebäude ohne Straße zum HQ bleibt Baustelle (kein „unsichtbarer" Arbeiter);
## erst mit Verbindung kommt der Bauarbeiter und der Bau läuft.
func _test_build_needs_connection() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var saw := state.place_building(20, 14, WorldState.BQ_HOUSE, false, "sawmill", 0, true)
	eco.resync()
	for t in 50:
		eco.tick()
	var bs: Economy.BState = eco.bstates[map.idx(20, 14)]
	_check(not bs.staffed, "Ohne Straße kein Bauarbeiter (nicht sofort besetzt)")
	_check(saw.under_construction, "Ohne Straße bleibt es Baustelle")
	state.build_road(hq.flag_pos, saw.flag_pos)
	eco.resync()
	for t in 8000:
		eco.tick()
	_check(not saw.under_construction, "Mit Straße wird gebaut (Arbeiter kam vom HQ)")


## Eine Flagge auf den Lieferweg setzen (Straße teilen) darf Material NICHT
## verschwinden lassen — der Bau wird trotzdem fertig.
func _test_material_after_split() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var saw := state.place_building(20, 14, WorldState.BQ_HOUSE, false, "sawmill", 0, true)
	var road := state.build_road(hq.flag_pos, saw.flag_pos)
	eco.resync()
	for t in 80:
		eco.tick()  # Material ist jetzt unterwegs
	if road != null and road.nodes.size() >= 3:
		var mid: Vector2i = road.nodes[road.nodes.size() / 2]
		state.place_flag(mid.x, mid.y)  # Straße teilen (Träger trägt evtl. gerade)
		eco.resync()
	for t in 8000:
		eco.tick()
	_check(not saw.under_construction,
		"Bau wird trotz Flagge auf dem Lieferweg fertig (Material nicht verloren)")


## Wird die Lieferstraße abgerissen, während Material unterwegs ist, darf das
## `incoming`-Konto nicht hängen bleiben: nach erneutem Anschluss muss das Gebäude
## fehlendes Material NACHFORDERN und fertig werden (kein dauerhafter Stillstand).
func _test_material_after_road_removed() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	var saw := state.place_building(20, 14, WorldState.BQ_HOUSE, false, "sawmill", 0, true)
	var road := state.build_road(hq.flag_pos, saw.flag_pos)
	eco.resync()
	for t in 80:
		eco.tick()  # Material ist jetzt unterwegs (incoming > 0)
	if road != null:
		state.remove_at(road.nodes[road.nodes.size() / 2])  # Straße mittendrin abreißen
		eco.resync()
	for t in 200:
		eco.tick()  # verirrte Träger / Flaggen-Waren räumen sich auf
	# Neu verbinden — jetzt muss erneut angefordert und fertiggebaut werden.
	state.build_road(hq.flag_pos, saw.flag_pos)
	eco.resync()
	for t in 8000:
		eco.tick()
	_check(not saw.under_construction,
		"Bau wird nach Straßenabriss + Neuanschluss fertig (Material nachgefordert)")


## Beim Teilen einer Straße soll der bestehende Träger auf seinem Teilstück aktiv
## WEITERarbeiten (nicht beide Teilstücke komplett neu vom HQ besetzt werden).
func _test_carrier_kept_on_split() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()
	state.place_flag(20, 14)
	var road := state.build_road(hq.flag_pos, Vector2i(20, 14))
	eco.resync()
	for t in 1500:
		eco.tick()  # Träger marschiert vom HQ an und wird aktiv
	var active_before := 0
	for r in eco.carriers:
		if eco.carriers[r].active:
			active_before += 1
	_check(active_before >= 1, "Träger ist vor der Teilung aktiv")
	if road != null and road.nodes.size() >= 3:
		var mid: Vector2i = road.nodes[road.nodes.size() / 2]
		state.place_flag(mid.x, mid.y)
		eco.resync()
	# Direkt nach dem resync (vor gestaffeltem Nachbesetzen) muss schon ein Träger
	# aktiv sein — der erhaltene auf seinem Teilstück.
	var active_after := 0
	for r in eco.carriers:
		if eco.carriers[r].active:
			active_after += 1
	_check(eco.carriers.size() == 2, "Nach Teilung zwei Straßen-Träger")
	_check(active_after >= 1, "Bestehender Träger bleibt nach Teilung sofort aktiv")


## Straßen-Zwischenknoten dürfen nicht direkt an einem Gebäude liegen
## (Fußabdruck wie in S2 — sonst kreuzt die Straße das Gebäude-Sprite).
func _test_road_avoids_building() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	var hut := state.place_building(15, 15, WorldState.BQ_HUT, false, "woodcutter", 0, false)
	_check(hut != null, "Kleines Gebäude für Straßenabstand-Test platzierbar")
	if hut != null:
		var hn := map.neighbor(hut.pos.x, hut.pos.y, Grid.E)
		_check(not state.road_margin_blocked(hn.x, hn.y),
			"Kleines Gebäude blockt umliegende Straßenknoten nicht")
	state.place_flag(24, 26)
	var path := state.plan_road(hq.flag_pos, Vector2i(24, 26))
	_check(not path.is_empty(), "Straße trotz Gebäude-Umweg planbar")
	for k in range(1, path.size() - 1):
		_check(not state._adjacent_to_building(path[k].x, path[k].y),
			"Kein Straßen-Zwischenknoten direkt am Gebäude")


## #23: Die Vorschau (plan_road) muss exakt den Pfad liefern, den der Bau
## (build_road) verlegt — sonst „springt" die Straße beim Loslassen. Seit beide
## dasselbe optimale A* (Heap) nutzen, müssen die Knotenfolgen identisch sein.
func _test_road_preview_matches_build() -> void:
	var targets := [Vector2i(20, 26), Vector2i(24, 24), Vector2i(16, 25), Vector2i(25, 17)]
	var checked := 0
	for t in targets:
		var map := _flat_map(40, 40)
		var state := WorldState.new(map)
		state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
		state.recompute_territory()
		var hqflag: Vector2i = state.buildings[map.idx(20, 20)].flag_pos
		var preview := state.plan_road(hqflag, t)
		if preview.is_empty():
			continue
		var road := state.build_road(hqflag, t)
		_check(road != null, "#23: Straße nach %s baubar" % t)
		if road == null:
			continue
		_check(road.nodes == preview,
			"#23: Vorschau == Bau nach %s (Vorschau %s, Bau %s)" % [t, preview, road.nodes])
		checked += 1
	_check(checked >= 2, "#23: mehrere Vorschau/Bau-Paare geprüft (%d)" % checked)


## #15: Landeinnahme nach S2 „closest building wins". Baut ein Gegner nahe der
## Grenze, verliert man NUR den wirklich näheren Streifen — nicht den vollen
## Gegner-Radius und nicht das eigene Kerngebiet.
func _test_territory_closest_wins() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	state.recompute_territory()
	# Anfangs liegen beide Knoten im HQ-Radius und gehören dem Spieler.
	_check(state.in_territory(16, 16), "#15: Grenzknoten zunächst beim Spieler")
	_check(state.in_territory(14, 14), "#15: innerer Knoten zunächst beim Spieler")
	# Gegner baut ein deckendes Militärgebäude nahe der Grenze (mit Garnison).
	_raw(state, Vector2i(18, 18), "watchtower", 7, 1, 1, 6, false)
	state.recompute_territory()
	# Der dem Gegnerbau NÄHERE Knoten wechselt — ein bisschen Grenze verloren.
	_check(state.enemy_territory.has(map.idx(16, 16)),
		"#15: der dem Gegner nähere Grenzknoten geht über")
	_check(not state.in_territory(16, 16),
		"#15: dieser Knoten ist nicht mehr Spielergebiet")
	# Der dem HQ nähere Knoten bleibt beim Spieler — NICHT der volle Gegnerradius.
	_check(state.in_territory(14, 14),
		"#15: HQ-näherer Knoten bleibt Spieler (nur der Streifen geht verloren)")
	# Das Kerngebiet am HQ wird nie geschluckt.
	_check(state.in_territory(12, 13), "#15: HQ-Kerngebiet bleibt unangetastet")


## #15: S2-Mindestabstand — ein Militärgebäude darf nicht zu dicht an einem
## anderen Militärgebäude/HQ stehen (eigen ODER fremd); Wirtschaftsgebäude schon.
func _test_military_min_distance() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	state.recompute_territory()
	# Dicht am HQ: Militärbau verboten, Wirtschaftsbau erlaubt (Regel ist militärspezifisch).
	var near := Vector2i(12, 15)
	_check(WorldState.hex_distance(Vector2i(12, 12), near) < WorldState.MILITARY_MIN_DIST,
		"#15: Testknoten liegt innerhalb des Mindestabstands")
	_check(not state.can_place_building(near.x, near.y, WorldState.BQ_HUT, 0, 5),
		"#15: Militärgebäude zu nah am HQ wird verhindert")
	_check(state.can_place_building(near.x, near.y, WorldState.BQ_HUT, 0, 0),
		"#15: Wirtschaftsgebäude an gleicher Stelle bleibt erlaubt")
	# Genug Abstand im eigenen Gebiet: Militärbau erlaubt.
	var far := Vector2i(12, 18)
	_check(state.can_place_building(far.x, far.y, WorldState.BQ_HUT, 0, 5),
		"#15: Militärgebäude mit >= 5 Knoten Abstand ist erlaubt")
	# Der Mindestabstand zählt auch gegenüber fremden Militärgebäuden.
	_raw(state, Vector2i(20, 12), "guardhouse", 5, 1, 1, 3, false)
	_check(not state.military_placement_clear(18, 12),
		"#15: nahes Gegner-Militärgebäude blockiert den Militärbau (Abstand < 5)")
	_check(state.military_placement_clear(30, 12),
		"#15: weit weg vom nächsten Militärgebäude bleibt der Militärbau frei")


func _terrain_spike_count(map: MapData) -> int:
	var spikes := 0
	for y in map.height:
		for x in map.width:
			for kind in [Grid.TRI_R, Grid.TRI_D]:
				var current := map.get_tri(Vector2i(x, y), kind)
				var same := 0
				var total := 0
				for nb in Grid.tri_edge_neighbors(x, y, kind):
					var nt := map.get_tri(nb.pos, int(nb.kind))
					if nt == current:
						same += 1
					total += 1
				if total >= 3 and same == 0:
					spikes += 1
	return spikes


func _stone_component_sizes(map: MapData) -> Array[int]:
	var sizes: Array[int] = []
	var seen := {}
	for key in map.objects:
		var i := int(key)
		if seen.has(i) or map.objects[i] != MapData.MO_STONE:
			continue
		var size := 0
		var stack: Array[int] = [i]
		seen[i] = true
		while not stack.is_empty():
			var cur := int(stack.pop_back())
			size += 1
			var x := cur % map.width
			var y := int(cur / map.width)
			for dir in Grid.DIRS:
				var n := map.neighbor(x, y, dir)
				if n.x < 0:
					continue
				var ni := map.idx(n.x, n.y)
				if seen.has(ni) or map.objects.get(ni, -1) != MapData.MO_STONE:
					continue
				seen[ni] = true
				stack.append(ni)
		sizes.append(size)
	return sizes


func _owner_territory_stones(state: WorldState, owner: int) -> int:
	var n := 0
	var area := state.owner_territory(owner)
	for k in area:
		if state.map.objects.get(k, -1) == MapData.MO_STONE:
			n += 1
	return n


func _flat_map(w: int, h: int) -> MapData:
	var map := MapData.new(w, h)
	for y in h:
		for x in w:
			map.set_height(x, y, 10)
			map.set_tri(Vector2i(x, y), Grid.TRI_R, Terrain.MEADOW)
			map.set_tri(Vector2i(x, y), Grid.TRI_D, Terrain.MEADOW)
	return map


func _find_buildable(state: WorldState, sx: int, sy: int) -> Vector2i:
	var map := state.map
	for r in range(0, 8):
		for yy in range(maxi(2, sy - r), mini(map.height - 2, sy + r + 1)):
			for xx in range(maxi(2, sx - r), mini(map.width - 2, sx + r + 1)):
				if state.compute_bq(xx, yy) >= WorldState.BQ_HUT and state._occ(xx, yy) == WorldState.OBJ_NONE:
					return Vector2i(xx, yy)
	return Vector2i(-1, -1)
