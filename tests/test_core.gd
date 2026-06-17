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
	_test_seed_hash()
	_test_world_code()
	_test_worldgen_96()
	_test_mountain_meadow_plateaus()
	_test_mapgen_cleanup_and_stone_clusters()
	_test_start_territory_stone_guarantee()
	_test_ore_types()
	_test_ore_distribution()
	_test_ore_deposit_mining()
	_test_mine_food()
	_test_fishery_fish()
	_test_farm_fields()
	_test_catalog_complete()
	_test_asset_files()
	_test_inventory_model()
	_test_visibility()
	_test_bq_and_flags()
	_test_mine_bq_on_mountains()
	_test_building_spacing()
	_test_road_and_route()
	_test_route_cache_invalidation()
	_test_build_spots_within_territory()
	_test_build_spot_bq_equivalence()
	_test_economy()
	_test_population_limit()
	_test_population_growth()
	_test_storage_list()
	_test_storehouse_routing()
	_test_stop_finishes_cycle()
	_test_productivity_and_building_info()
	_test_distribution()
	_test_transport_priority()
	_test_military()
	_test_tools_and_recruitment()
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
	_test_road_runs_adjacent_to_building()
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

	# Hohe, steile Wiesenflanken sollen als Bergkante erscheinen, nicht als
	# fruchtbare Wiese. Sonst wirken Felder/Gebäude auf Bergwänden erlaubt.
	# Höhen oberhalb der Steilwiesen-Schwelle (#50: skaliert mit HEIGHT_SCALE), aber
	# unter dem Schnee-Band, mit einer steilen Kante (Diff >= STEEP_SLOPE) am Knoten.
	var steep := _flat_map(8, 8)
	var steep_base := int(MapGenerator.STEEP_MEADOW_MOUNTAIN_MIN_HEIGHT) + 3
	for yy in steep.height:
		for xx in steep.width:
			steep.set_height(xx, yy, steep_base)
	steep.set_height(5, 4, steep_base + MapGenerator.STEEP_MEADOW_MOUNTAIN_SLOPE + 1)
	var terrain := MapGenerator._classify_node_terrain(steep, null)
	_check(int(terrain[steep.idx(4, 4)]) == Terrain.MOUNTAIN,
		"Kartengenerator: hohe Steilwiese wird Bergkante")


func _test_seed_hash() -> void:
	var a := MapGenerator.stable_seed_from_string("SIEDLER")
	var b := MapGenerator.stable_seed_from_string("SIEDLER")
	var c := MapGenerator.stable_seed_from_string("siedler")
	_check(a == b, "Seed-Hash: gleicher Text ergibt gleichen Seed")
	_check(a != c, "Seed-Hash: Gross/Klein bleibt unterscheidbar")
	var map_a := MapGenerator.generate(32, 32, a)
	var map_b := MapGenerator.generate(32, 32, b)
	_check(map_a.heights == map_b.heights and map_a.terr_r == map_b.terr_r \
			and map_a.terr_d == map_b.terr_d and map_a.objects == map_b.objects,
		"Seed-Hash: gleiche Kartenoptionen erzeugen gleiche Startkarte")


## Welt-Code (Issue #27): teilbarer String aus Groesse, Gegnerzahl und Karten-Token.
func _test_world_code() -> void:
	# Kanonisches Format zusammenbauen und wieder zerlegen (Roundtrip).
	var code := MapGenerator.format_world_code(200, 100, 3, "K7P3QZ")
	_check(code == "200x100-3-K7P3QZ", "Welt-Code: kanonisches Format BxH-G-TOKEN (%s)" % code)
	var p := MapGenerator.parse_world_code(code)
	_check(bool(p.has_size) and not bool(p.devmap), "Welt-Code: voller Code wird als Groessen-Code erkannt")
	_check(int(p.width) == 200 and int(p.height) == 100 and int(p.enemies) == 3 \
			and String(p.token) == "K7P3QZ", "Welt-Code: Roundtrip erhaelt alle Teile")

	# Geteilter Code reproduziert dieselbe Welt: gleicher Token -> gleicher Terrain-Seed.
	var p2 := MapGenerator.parse_world_code("200x100-3-K7P3QZ")
	_check(MapGenerator.stable_seed_from_string(String(p.token))
			== MapGenerator.stable_seed_from_string(String(p2.token)),
		"Welt-Code: gleicher Code ergibt gleichen Terrain-Seed")

	# Gegnerzahl steckt im teilbaren Code (anderer String), veraendert aber das Terrain nicht.
	var enemies_diff := MapGenerator.format_world_code(200, 100, 5, "K7P3QZ")
	_check(enemies_diff != code, "Welt-Code: andere Gegnerzahl ergibt anderen Code")
	_check(MapGenerator.stable_seed_from_string("K7P3QZ")
			== MapGenerator.stable_seed_from_string(String(MapGenerator.parse_world_code(enemies_diff).token)),
		"Welt-Code: Gegnerzahl veraendert den Terrain-Token nicht")

	# DEVMAP wird als Sonderquelle erkannt.
	_check(bool(MapGenerator.parse_world_code("devmap").devmap), "Welt-Code: DEVMAP erkannt (klein)")
	_check(bool(MapGenerator.parse_world_code(" DEVMAP ").devmap), "Welt-Code: DEVMAP mit Leerzeichen")

	# Blanker Token ohne Groesse: has_size = false, ganzer String ist der Token.
	var bare := MapGenerator.parse_world_code("SIEDLER")
	_check(not bool(bare.has_size) and not bool(bare.devmap) and String(bare.token) == "SIEDLER",
		"Welt-Code: blanker Token ohne Groesse")

	# Freie Groessen-Eingabe parsen.
	_check(MapGenerator.parse_size_text("200x100") == Vector2i(200, 100), "Groesse: freie Eingabe 200x100")
	_check(MapGenerator.parse_size_text("128") == Vector2i(128, 128), "Groesse: einzelne Zahl = quadratisch")
	_check(MapGenerator.parse_size_text("quatsch", Vector2i(96, 96)) == Vector2i(96, 96),
		"Groesse: Unsinn faellt auf Fallback zurueck")
	# Clamping in sinnvolle Grenzen.
	var clamped := MapGenerator.parse_size_text("9999x1")
	_check(clamped.x == MapGenerator.MAP_MAX_DIM and clamped.y == MapGenerator.MAP_MIN_DIM,
		"Groesse: extreme Werte werden geclamped")

	# Token ist case-insensitiv normalisiert (Gross), damit Teilen robust bleibt.
	_check(String(MapGenerator.parse_world_code("96x96-1-abc").token) == "ABC",
		"Welt-Code: Token wird auf Grossbuchstaben normalisiert")


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


## #42: Bauqualität auf Bergen nach RTTR — Minen hängen NICHT an max_slope über alle
## 6 Nachbarn, sondern an der SE-Eingangsflagge. Ein zerklüfteter Berg (ein Nachbar
## viel höher) bietet weiter Minenplätze; nur eine zu hoch liegende SE-Flagge sperrt.
func _test_mine_bq_on_mountains() -> void:
	var mm := _flat_map(12, 12)
	for yy in mm.height:
		for xx in mm.width:
			mm.set_tri(Vector2i(xx, yy), Grid.TRI_R, Terrain.MOUNTAIN)
			mm.set_tri(Vector2i(xx, yy), Grid.TRI_D, Terrain.MOUNTAIN)
			mm.set_height(xx, yy, 10)
	var st := WorldState.new(mm)
	var p := Vector2i(6, 6)
	_check(st.compute_bq(p.x, p.y) == WorldState.BQ_MINE, "BQ-Berg: flaches Massiv → Mine")

	# Zerklüftet: ein NICHT-SE-Nachbar liegt viel höher (max_slope > 4). Früher wurde
	# der Knoten dadurch zur Flagge; jetzt bleibt er Mine.
	var nw := mm.neighbor(p.x, p.y, Grid.NW)
	mm.set_height(nw.x, nw.y, 18)
	_check(mm.max_slope(p.x, p.y) > 4, "BQ-Berg: Testaufbau erzeugt steile Kante (max_slope > 4)")
	_check(st.compute_bq(p.x, p.y) == WorldState.BQ_MINE,
		"BQ-Berg: zerklüfteter Berg bietet weiter eine Mine (keine Flaggenwüste)")
	mm.set_height(nw.x, nw.y, 10)

	# Zu hohe SE-Eingangsflagge (> +3) → nur Flagge.
	var se := mm.neighbor(p.x, p.y, Grid.SE)
	mm.set_height(se.x, se.y, 15)
	_check(st.compute_bq(p.x, p.y) == WorldState.BQ_FLAG,
		"BQ-Berg: zu hohe SE-Eingangsflagge → nur Flagge")
	mm.set_height(se.x, se.y, 12)  # +2 ≤ 3
	_check(st.compute_bq(p.x, p.y) == WorldState.BQ_MINE,
		"BQ-Berg: leicht erhöhter SE-Eingang (+2) erlaubt weiter die Mine")


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


## #30: find_route cacht Graph + gelöste Routen. Hier wird sichergestellt, dass jede
## Straßenänderung (Bau wie Abriss) den Cache verwirft und nicht eine veraltete bzw.
## negative Route zurückgegeben wird.
func _test_route_cache_invalidation() -> void:
	var map := _flat_map(24, 24)
	var state := WorldState.new(map)
	var a := Vector2i(6, 6)
	var b := Vector2i(14, 6)
	_check(state.place_flag(a.x, a.y) != null, "Cache: Flagge A gesetzt")
	_check(state.place_flag(b.x, b.y) != null, "Cache: Flagge B gesetzt")

	# Negativ-Ergebnis wird gecacht: vor dem Straßenbau gibt es keine Verbindung.
	_check(state.find_route(a, b).size() == 0, "Cache: vor Straßenbau keine Route")

	# build_road muss den (Negativ-)Cache verwerfen.
	var road := state.build_road(a, b)
	_check(road != null and road.nodes.size() >= 3, "Cache: Straße A→B mit Zwischenknoten")
	if road == null or road.nodes.size() < 3:
		return
	_check(state.find_route(a, b).size() >= 2, "Cache: nach Straßenbau Route vorhanden")

	# Route ist jetzt gecacht. Straße über einen Zwischenknoten abreißen — beide
	# Flaggen bleiben bestehen (der flag_at-Frühausstieg greift also NICHT), sodass nur
	# eine korrekte Cache-Invalidierung in _remove_road das richtige Ergebnis liefert.
	var mid := road.nodes[road.nodes.size() / 2]
	_check(mid != a and mid != b, "Cache: Zwischenknoten ist kein Endpunkt")
	_check(state.remove_at(mid), "Cache: Straße über Zwischenknoten abgerissen")
	_check(state.find_route(a, b).size() == 0,
		"Cache: nach Straßenabriss keine veraltete Route mehr")


## #31: Das HQ ist Lager #0 der storages-Liste; die hq_*-Aliase delegieren 1:1 auf
## storages[0] (Lese-, In-Place- und Setter-Zugriff). Sichert das Fundament des
## Mehr-Lager-Systems gegen Regressionen ab.
func _test_storage_list() -> void:
	var map := _flat_map(20, 20)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	# Schon vor dem HQ existiert genau ein Lager, damit die Aliase nie ins Leere greifen.
	_check(eco.storages.size() == 1, "Lager: genau ein Lager nach _init")
	var hq := state.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Lager: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	_check(eco.hq_flag == eco.storages[0].flag_idx and eco.hq_flag >= 0,
		"Lager: hq_flag == storages[0].flag_idx")
	_check(eco.hq_idx == eco.storages[0].idx, "Lager: hq_idx == storages[0].idx")
	# In-Place-Mutation über den Alias (hq_stock[x]=…) erreicht das Lagerobjekt.
	eco.hq_stock[Goods.WOOD] = 42
	_check(int(eco.storages[0].stock.get(Goods.WOOD, 0)) == 42,
		"Lager: hq_stock[]= schreibt in storages[0].stock")
	# Volle Zuweisung über den Alias-Setter.
	eco.hq_people = { Jobs.HELPER: 7 }
	_check(int(eco.storages[0].people.get(Jobs.HELPER, 0)) == 7,
		"Lager: hq_people= setzt storages[0].people")
	# Und umgekehrt: direkt aufs Lagerobjekt geschrieben ist über den Alias sichtbar.
	eco.storages[0].stock[Goods.BOARDS] = 5
	_check(int(eco.hq_stock.get(Goods.BOARDS, 0)) == 5,
		"Lager: storages[0].stock über hq_stock sichtbar")


## #31: Ein fertiges Lagerhaus wird als zweites Lager geführt; das Waren-Routing
## bedient stets das NÄCHSTE Lager. Abriss räumt das Lager ab (Restbestand → HQ).
func _test_storehouse_routing() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(15, 22, WorldState.BQ_CASTLE, true, "hq", 9, false)
	# Lagerhaus fertig (nicht im Bau) zwischen HQ und Produzent.
	var store := state.place_building(15, 14, WorldState.BQ_HOUSE, false, "storehouse", 0, false)
	# Produzent (Sägewerk) nahe am Lagerhaus.
	var saw := state.place_building(15, 8, WorldState.BQ_HOUSE, false, "sawmill", 0, false)
	_check(hq != null and store != null and saw != null, "Lagerhaus: Gebäude platzierbar")
	if hq == null or store == null or saw == null:
		return
	# Kette HQ — Lagerhaus — Sägewerk: das Sägewerk ist näher am Lagerhaus als am HQ.
	var r1 := state.build_road(hq.flag_pos, store.flag_pos)
	var r2 := state.build_road(store.flag_pos, saw.flag_pos)
	_check(r1 != null and r2 != null, "Lagerhaus: Straßenkette baubar")
	if r1 == null or r2 == null:
		return
	eco.resync()
	# Das fertige Lagerhaus ist als zweites Lager registriert (eigener Tür-Träger).
	_check(eco.storages.size() == 2, "Lagerhaus: als zweites Lager registriert")
	var sf := state.map.idx(store.flag_pos.x, store.flag_pos.y)
	var s2 = null
	for st in eco.storages:
		if st.flag_idx == sf:
			s2 = st
	_check(s2 != null and s2.house != null, "Lagerhaus: eigener Tür-Träger")
	if s2 == null:
		return

	# Ausgangswaren des Sägewerks gehen ins NÄCHSTE Lager (= Lagerhaus, nicht HQ).
	var sidx := state.map.idx(saw.pos.x, saw.pos.y)
	var bs = eco.bstates.get(sidx)
	_check(bs != null, "Lagerhaus: Sägewerk hat bstate")
	if bs == null:
		return
	bs.out_stock = {Goods.BOARDS: 1}
	eco._ship_outputs(bs)
	var q: Array = eco.flag_goods.get(bs.flag_idx, [])
	_check(q.size() == 1 and q[0].dest == sf,
		"Lagerhaus: Ausgang geht zum nächsten Lager (Lagerhaus)")

	# Eingang anfordern: kommt aus dem nächsten Lager mit Vorrat (= Lagerhaus, nicht HQ).
	eco.hq_stock[Goods.WOOD] = 5
	s2.stock[Goods.WOOD] = 5
	eco._request_from_hq(bs, Goods.WOOD, 1)
	_check(int(s2.stock.get(Goods.WOOD, 0)) == 4 and int(eco.hq_stock.get(Goods.WOOD, 0)) == 5,
		"Lagerhaus: Eingang kommt aus dem nächsten Lager")
	_check(s2.outbox.size() == 1 and s2.outbox[0].dest == bs.flag_idx,
		"Lagerhaus: angeforderte Ware liegt in dessen outbox")

	# Abriss: Lager raus aus der Liste, Restbestand (Bestand 4 + outbox 1) wandert ins HQ.
	state.remove_at(store.pos)
	eco.resync()
	_check(eco.storages.size() == 1, "Lagerhaus: nach Abriss wieder nur ein Lager")
	_check(int(eco.hq_stock.get(Goods.WOOD, 0)) == 10,
		"Lagerhaus: Restbestand ins HQ übernommen (5 + 4 + 1)")


## #30 (Renderer): Das Bauplatz-Overlay scannt nur noch das eigene Territorium statt
## der ganzen Karte. Dieser Test belegt, dass dabei KEIN Bauplatz verloren geht — alle
## per Ganzkarten-Scan gefundenen Spots liegen auch im Territoriums-Scan (can_place_*
## verlangt ohnehin eigenes Gebiet).
func _test_build_spots_within_territory() -> void:
	var map := MapGenerator.generate(48, 48, 4242)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var c := _find_buildable(state, 24, 24)
	if c.x < 0:
		_check(false, "Bauspots: HQ-Knoten gefunden")
		return
	var hq := state.place_building(c.x, c.y, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Bauspots: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	# Referenz: voller Ganzkarten-Scan (das alte Verhalten).
	var full := {}
	for y in map.height:
		for x in map.width:
			if state.can_place_road_flag(x, y) or state.actual_build_spot_bq(x, y) >= WorldState.BQ_FLAG:
				full[map.idx(x, y)] = true
	# Neu: nur Territorium scannen.
	var terr := {}
	for ti in state.territory:
		var x := int(ti) % map.width
		var y := int(ti) / map.width
		if state.can_place_road_flag(x, y) or state.actual_build_spot_bq(x, y) >= WorldState.BQ_FLAG:
			terr[map.idx(x, y)] = true
	_check(full.size() > 0, "Bauspots: Referenz-Scan findet überhaupt Bauplätze")
	var missing := 0
	for k in full:
		if not terr.has(k):
			missing += 1
	_check(missing == 0,
		"Bauspots: Territoriums-Scan verschluckt keinen Bauplatz (fehlend=%d von %d)" % [missing, full.size()])


## #30: Der Einpass-actual_build_spot_bq muss EXAKT dasselbe liefern wie die alte
## CASTLE/HOUSE/HUT/MINE/FLAG-Kaskade (über die unveränderten can_place_*). Sichert,
## dass die Performance-Optimierung das sichtbare Overlay nicht verändert.
func _test_build_spot_bq_equivalence() -> void:
	var map := MapGenerator.generate(48, 48, 909)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var c := _find_buildable(state, 24, 24)
	if c.x >= 0:
		state.place_building(c.x, c.y, WorldState.BQ_CASTLE, true, "hq", 9, false)
		eco.resync()
	var mism := 0
	var cells := 0
	for y in map.height:
		for x in map.width:
			cells += 1
			if state.actual_build_spot_bq(x, y) != _cascade_spot_bq(state, x, y):
				mism += 1
	_check(mism == 0, "BQ-Einpass: identisch zur Kaskade (Abweichungen=%d von %d)" % [mism, cells])


## Referenz: die frühere Kaskade aus can_place_building/can_place_flag (unverändert).
func _cascade_spot_bq(state: WorldState, x: int, y: int) -> int:
	if state.can_place_building(x, y, WorldState.BQ_CASTLE): return WorldState.BQ_CASTLE
	if state.can_place_building(x, y, WorldState.BQ_HOUSE): return WorldState.BQ_HOUSE
	if state.can_place_building(x, y, WorldState.BQ_HUT): return WorldState.BQ_HUT
	if state.can_place_building(x, y, WorldState.BQ_MINE): return WorldState.BQ_MINE
	if state.can_place_flag(x, y): return WorldState.BQ_FLAG
	return WorldState.BQ_NOTHING


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


## Issue #9: Träger und Arbeiter kommen aus dem begrenzten Personen-Lager des HQ.
## Ohne verfügbares Personal bleibt eine Straße/ein Gebäude unbesetzt; Abriss gibt
## die Person zurück; Spezialisten werden aus Träger + Werkzeug rekrutiert und kehren
## als Beruf zurück. Save zählt die Gesamtbevölkerung (Reserve + Eingesetzte).
func _test_population_limit() -> void:
	# --- Träger-Begrenzung: künstlich genau 1 HELPER im Lager ---
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Pop: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	eco.hq_people = { Jobs.HELPER: 1 }
	# Träger-Nachschub (#33) für diesen Test einfrieren — hier geht es gezielt um das
	# Verhalten bei leerem Pool, nicht um das Wiederauffüllen.
	eco._helper_timer = 1_000_000_000

	# Zwei Straßen direkt vom HQ in verschiedene Richtungen (bleiben beide verbunden).
	state.place_flag(20, 14)
	state.place_flag(14, 20)
	var r1 := state.build_road(hq.flag_pos, Vector2i(20, 14))
	var r2 := state.build_road(hq.flag_pos, Vector2i(14, 20))
	_check(r1 != null and r2 != null, "Pop: zwei Straßen ab HQ baubar")
	if r1 == null or r2 == null:
		return
	eco.resync()
	for t in 500:
		eco.tick()
	var active := 0
	for r in eco.carriers:
		if eco.carriers[r].active:
			active += 1
	_check(active == 1, "Pop: nur 1 von 2 Straßen besetzt (1 HELPER im Lager)")
	_check(eco.hq_people_count(Jobs.HELPER) == 0, "Pop: HELPER-Pool aufgebraucht")
	# Save-Sicht: der eingesetzte Träger zählt zur Gesamtbevölkerung.
	_check(int(eco.total_people().get(Jobs.HELPER, 0)) == 1,
		"Pop: total_people() zählt den eingesetzten Träger mit")

	# Die besetzte Straße abreißen → HELPER kehrt zurück → die andere wird besetzt.
	var busy: WorldState.Road = r1 if (eco.carriers.has(r1) and eco.carriers[r1].active) else r2
	var idle: WorldState.Road = r2 if busy == r1 else r1
	_check(busy.nodes.size() >= 3, "Pop: besetzte Straße hat Zwischenknoten")
	state.remove_at(busy.nodes[1])
	eco.resync()
	_check(eco.hq_people_count(Jobs.HELPER) == 1, "Pop: HELPER nach Straßen-Abriss zurück im Lager")
	for t in 500:
		eco.tick()
	_check(eco.carriers.has(idle) and eco.carriers[idle].active,
		"Pop: bisher unbesetzte Straße wird nach Abriss besetzt")
	_check(eco.hq_people_count(Jobs.HELPER) == 0, "Pop: HELPER wieder im Einsatz")

	# --- Spezialist-Rekrutierung: Holzfäller = HELPER + AXT, Rückgabe als Beruf ---
	var map2 := _flat_map(40, 40)
	var st2 := WorldState.new(map2)
	var eco2 := Economy.new(st2)
	var hq2 := st2.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq2 != null, "Pop: HQ #2 platzierbar")
	if hq2 == null:
		return
	eco2.resync()
	eco2.hq_people = { Jobs.HELPER: 1 }
	eco2.hq_stock = { Goods.AXE: 1 }
	var wc := st2.place_building(20, 16, WorldState.BQ_HUT, false, "woodcutter", 0, false)
	_check(wc != null, "Pop: Holzfäller-Hütte platzierbar")
	if wc == null:
		return
	st2.build_road(hq2.flag_pos, wc.flag_pos)
	eco2.resync()
	var wbi := st2.map.idx(wc.pos.x, wc.pos.y)
	_check(eco2.bstates.has(wbi) and eco2.bstates[wbi].staffed, "Pop: Holzfäller besetzt")
	_check(eco2.hq_people_count(Jobs.HELPER) == 0, "Pop: HELPER für Spezialist verbraucht")
	_check(int(eco2.hq_stock.get(Goods.AXE, 0)) == 0, "Pop: Werkzeug (Axt) für Spezialist verbraucht")

	# Abriss gibt den Spezialisten als BERUF zurück (Werkzeug bleibt verbraucht).
	st2.remove_at(wc.pos)
	eco2.resync()
	_check(eco2.hq_people_count(Jobs.WOODCUTTER) == 1, "Pop: Holzfäller kehrt als Beruf ins Lager zurück")
	_check(eco2.hq_people_count(Jobs.HELPER) == 0 and int(eco2.hq_stock.get(Goods.AXE, 0)) == 0,
		"Pop: weder HELPER noch Werkzeug kehren zurück (Werkzeug bleibt verbraucht)")


## Issue #33: Das HQ-Lager schiebt Träger nach (RTTR ProduceHelperEvent): füllt den
## Reservebestand bis zur Obergrenze auf, stoppt dort und baut Überbevölkerung ab.
func _test_population_growth() -> void:
	var map := _flat_map(24, 24)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	eco.ai_enabled = false
	var hq := state.place_building(12, 12, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Wachstum: HQ platzierbar")
	if hq == null:
		return
	eco.resync()
	var cap := Tuning.helper_cap()

	# Reserve künstlich leeren → ein Takt später muss das Lager nachschieben.
	eco.hq_people = { Jobs.HELPER: 0 }
	eco._helper_timer = 0
	eco.tick()
	_check(eco.hq_people_count(Jobs.HELPER) == 1, "Wachstum: Lager schiebt einen Träger nach")

	# Über genug Takte wächst der Bestand bis zur Obergrenze und stoppt dort.
	for t in (cap + 5) * Tuning.helper_produce_ticks():
		eco.tick()
	_check(eco.hq_people_count(Jobs.HELPER) == cap,
		"Wachstum: Bestand erreicht Obergrenze (%d) und stoppt" % cap)

	# Über der Obergrenze wird abgebaut (Überbevölkerung).
	eco.hq_people[Jobs.HELPER] = cap + 5
	eco._helper_timer = 0
	eco.tick()
	_check(eco.hq_people_count(Jobs.HELPER) == cap + 4, "Wachstum: Überbevölkerung wird abgebaut")


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


## #43 Phase 1: gewichtete Warenverteilung. Knappe Mehrfach-Waren (Fisch, Getreide,
## Wasser, Kohle, Eisen) werden gemäß einstellbarer Gewichte (RTTR distributionMap)
## auf die konkurrierenden Abnehmer verteilt — deterministisch (seeded).
func _test_distribution() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)

	# Defaults vorhanden und für die existierenden Gebäude gesetzt.
	_check(eco._is_distributed(Goods.FISH), "Verteilung: Fisch ist verteilt (mehrere Minen)")
	_check(eco._is_distributed(Goods.COAL), "Verteilung: Kohle ist verteilt")
	_check(not eco._is_distributed(Goods.WOOD), "Verteilung: Holz NICHT verteilt (ein Abnehmer)")
	_check(eco._dist_weight(Goods.FISH, "goldmine") == 10, "Verteilung: Goldmine-Fischgewicht 10 (RTTR)")
	_check(eco._dist_weight(Goods.FISH, "coalmine") == 5, "Verteilung: Kohlemine-Fischgewicht 5 (RTTR)")

	# Setter clampt und ignoriert unbekannte Abnehmer/Waren.
	eco.set_distribution(Goods.FISH, "goldmine", 99)
	_check(eco._dist_weight(Goods.FISH, "goldmine") == 10, "Verteilung: Setter clampt auf 10")
	eco.set_distribution(Goods.FISH, "sawmill", 7)  # Sägewerk isst keinen Fisch
	_check(eco._dist_weight(Goods.FISH, "sawmill") == 0, "Verteilung: unbekannter Abnehmer wird nicht gesetzt")
	eco.set_distribution(Goods.WOOD, "sawmill", 7)  # Holz ist gar nicht verteilt
	_check(not eco._is_distributed(Goods.WOOD), "Verteilung: nicht verteilte Ware bleibt unverändert")
	eco.set_distribution(Goods.FISH, "goldmine", 10)  # zurücksetzen

	# Szenario: HQ + Gold- und Kohlemine ans Netz. Bei Fischknappheit (1 Stück/Runde)
	# muss die höher gewichtete Goldmine (10) deutlich öfter bedient werden als Kohle (5).
	var hq := state.place_building(15, 22, WorldState.BQ_CASTLE, true, "hq", 0, false)
	var gold := state.place_building(15, 14, WorldState.BQ_HOUSE, false, "goldmine", 0, false)
	var coal := state.place_building(15, 8, WorldState.BQ_HOUSE, false, "coalmine", 0, false)
	_check(hq != null and gold != null and coal != null, "Verteilung: HQ und zwei Minen platzierbar")
	if hq == null or gold == null or coal == null:
		return
	var r1 := state.build_road(hq.flag_pos, gold.flag_pos)
	var r2 := state.build_road(gold.flag_pos, coal.flag_pos)
	_check(r1 != null and r2 != null, "Verteilung: Straßenkette HQ—Gold—Kohle baubar")
	eco.resync()
	var gbs: Economy.BState = eco.bstates.get(state.map.idx(gold.pos.x, gold.pos.y))
	var cbs: Economy.BState = eco.bstates.get(state.map.idx(coal.pos.x, coal.pos.y))
	_check(gbs != null and cbs != null, "Verteilung: beide Minen haben bstate")
	if gbs == null or cbs == null:
		return
	# Arbeiter als anwesend annehmen (isoliert die Verteil-Logik vom Personalweg).
	gbs.staffed = true; gbs.has_person = true
	cbs.staffed = true; cbs.has_person = true

	var gold_total := 0
	var coal_total := 0
	for _t in 300:
		gbs.delivered.clear(); gbs.incoming.clear()
		cbs.delivered.clear(); cbs.incoming.clear()
		eco.storages[0].outbox.clear()
		eco.hq_stock[Goods.FISH] = 1  # nur EIN Fisch pro Runde → echte Knappheit
		eco._distribute_good(Goods.FISH)
		gold_total += int(gbs.incoming.get(Goods.FISH, 0))
		coal_total += int(cbs.incoming.get(Goods.FISH, 0))
	_check(gold_total + coal_total == 300, "Verteilung: jede knappe Einheit wurde genau einmal zugeteilt")
	_check(gold_total > coal_total, "Verteilung: höher gewichtete Goldmine (10) bekommt mehr als Kohle (5)")
	_check(gold_total > int(coal_total * 1.4), "Verteilung: Anteil grob nach Gewicht (~10:5)")

	# Genügend Fisch: beide Minen füllen ihren Sollbestand (kein Verlust durch Verteilung).
	gbs.delivered.clear(); gbs.incoming.clear()
	cbs.delivered.clear(); cbs.incoming.clear()
	eco.storages[0].outbox.clear()
	eco.hq_stock[Goods.FISH] = 99
	eco._distribute_good(Goods.FISH)
	_check(int(gbs.incoming.get(Goods.FISH, 0)) == Economy.FOOD_BUFFER \
		and int(cbs.incoming.get(Goods.FISH, 0)) == Economy.FOOD_BUFFER,
		"Verteilung: bei Überfluss füllen beide Minen den Nahrungs-Sollbestand")


## #43 Phase 2: Transport-Prioritäten. Bei mehreren wartenden Waren Richtung selber
## Flagge fährt die höher priorisierte zuerst (RTTR STD_TRANSPORT_PRIO); Reihenfolge
## ist umsortierbar und vollständig.
func _test_transport_priority() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)

	# Standardreihenfolge vollständig und sinnvoll sortiert.
	_check(eco.transport_order.size() == Goods.COUNT, "Transport: alle Waren in der Reihenfolge")
	_check(eco._transport_rank(Goods.COINS) < eco._transport_rank(Goods.STONE),
		"Transport: Münzen haben höhere Priorität als Steine")
	_check(eco._transport_rank(Goods.SWORD) < eco._transport_rank(Goods.WOOD),
		"Transport: Waffen vor Baustoffen")

	# Umsortieren: ▲ (−1) eins höher, ▼ (+1) zurück; Ränder clampen.
	var before := eco._transport_rank(Goods.STONE)
	eco.move_transport(Goods.STONE, -1)
	_check(eco._transport_rank(Goods.STONE) == before - 1, "Transport: ▲ verschiebt um eins nach oben")
	eco.move_transport(Goods.STONE, 1)
	_check(eco._transport_rank(Goods.STONE) == before, "Transport: ▼ verschiebt zurück")
	var top := int(eco.transport_order[0])
	eco.move_transport(top, -1)
	_check(int(eco.transport_order[0]) == top, "Transport: oberste Ware bleibt bei ▲ oben (Rand)")

	# „Ganz nach oben": eine niedrig priorisierte Ware an die Spitze setzen.
	var low_good := int(eco.transport_order[eco.transport_order.size() - 1])
	eco.move_transport_top(low_good)
	_check(int(eco.transport_order[0]) == low_good and eco._transport_rank(low_good) == 0,
		"Transport: ⤒ setzt die Ware ganz nach oben")
	_check(eco.transport_order.size() == Goods.COUNT, "Transport: ⤒ verliert keine Ware")

	# „Zurücksetzen": Standardreihenfolge wiederherstellen.
	eco.reset_transport_default()
	_check(eco._transport_rank(Goods.COINS) < eco._transport_rank(Goods.STONE) \
		and eco.transport_order.size() == Goods.COUNT,
		"Transport: Zurücksetzen stellt die Standardreihenfolge wieder her")

	# Aufnahme nach Priorität: HQ + Holzfäller per Straße verbunden.
	var hq := state.place_building(15, 20, WorldState.BQ_CASTLE, true, "hq", 0, false)
	var wc := state.place_building(15, 14, WorldState.BQ_HOUSE, false, "woodcutter", 0, false)
	_check(hq != null and wc != null, "Transport: HQ und Holzfäller platzierbar")
	if hq == null or wc == null:
		return
	var road := state.build_road(hq.flag_pos, wc.flag_pos)
	_check(road != null, "Transport: Straße HQ—Holzfäller baubar")
	eco.resync()
	var wf := state.map.idx(wc.flag_pos.x, wc.flag_pos.y)
	var hf := state.map.idx(hq.flag_pos.x, hq.flag_pos.y)
	# Stein (niedrige Prio) wartet ZUERST, Münze (hohe Prio) kommt später dazu — beide zum HQ.
	var low := Economy.Good.new(); low.type = Goods.STONE; low.dest = hf
	var high := Economy.Good.new(); high.type = Goods.COINS; high.dest = hf
	eco.flag_goods[wf] = [low, high]
	var first = eco._take_good_for(wf, hf)
	_check(first != null and first.type == Goods.COINS,
		"Transport: höher priorisierte Münze fährt zuerst (trotz späterer Ankunft)")
	var second = eco._take_good_for(wf, hf)
	_check(second != null and second.type == Goods.STONE,
		"Transport: danach die niedriger priorisierte Ware")


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


## Werkzeugmacher-Produktion (Prioritäten/Bestellungen), Schmiede Schwert/Schild
## und Soldaten-Rekrutierung aus Schwert+Schild+Bier+Träger (#41).
func _test_tools_and_recruitment() -> void:
	var map := _flat_map(30, 30)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(15, 15, WorldState.BQ_CASTLE, true, "hq", 9, false)
	_check(hq != null, "Werkzeug/Rekrut: HQ platzierbar")
	if hq == null:
		return
	eco.resync()

	# --- Katalog: Werkzeugmacher/Schmiede sind Mehrfach-Produzenten ---
	var tm := BuildingCatalog.get_def("toolmaker")
	_check(bool(tm.get("produces_tools", false)) and int(tm.get("output", 0)) == -1,
		"Werkzeugmacher: produces_tools, kein festes Einzel-output")
	var sm := BuildingCatalog.get_def("smithy")
	var sm_out: Array = sm.get("outputs", [])
	_check(sm_out.has(Goods.SWORD) and sm_out.has(Goods.SHIELD),
		"Schmiede: outputs = Schwert + Schild")

	# --- Werkzeugmacher: Auswahl nach Prioritäten (nur Axt > 0 → immer Axt) ---
	for g in Goods.tools():
		eco.tool_priority[g] = 0
		eco.tool_orders[g] = 0
	eco.tool_priority[Goods.AXE] = 5
	var only_axe := true
	for _i in 30:
		if eco._pick_tool() != Goods.AXE:
			only_axe = false
			break
	_check(only_axe, "Werkzeugmacher: nur Axt-Priorität → produziert nur Axt")

	# Alle Prioritäten 0 und keine Bestellung → nichts wählbar (-1).
	eco.tool_priority[Goods.AXE] = 0
	_check(eco._pick_tool() == -1, "Werkzeugmacher: alle Prioritäten 0 → kein Werkzeug")

	# --- Bestellungen haben Vorrang: 2 Sägen bestellt, alle Prioritäten 5 ---
	for g in Goods.tools():
		eco.tool_priority[g] = 5
	eco.tool_orders[Goods.SAW] = 2
	var first := eco._pick_tool()
	var second := eco._pick_tool()
	_check(first == Goods.SAW and second == Goods.SAW,
		"Werkzeugmacher: Bestellungen (Säge) zuerst")
	_check(int(eco.tool_orders.get(Goods.SAW, 0)) == 0,
		"Werkzeugmacher: Bestellmenge nach 2 Stück aufgebraucht")

	# --- Schmiede wechselt Schwert/Schild ab ---
	var bs := Economy.BState.new()
	bs.def = sm
	bs.out_cycle = 0
	var a := eco._pick_output(bs)
	var b := eco._pick_output(bs)
	var c := eco._pick_output(bs)
	_check(a == Goods.SWORD and b == Goods.SHIELD and c == Goods.SWORD,
		"Schmiede: produziert abwechselnd Schwert/Schild")

	# --- Rekrutierung #41: braucht alle vier Zutaten ---
	eco.soldiers = 0
	eco._recruit_accum = 0
	eco.recruiting_ratio = 10
	eco.hq_stock = { Goods.SWORD: 0, Goods.SHIELD: 0, Goods.BEER: 0 }
	eco.hq_people = { Jobs.HELPER: 0 }
	eco._try_recruit()
	_check(eco.soldiers == 0, "Rekrut: ohne Zutaten kein Soldat")

	eco.hq_stock[Goods.SWORD] = 1  # nur Schwert reicht NICHT mehr (vorher: ja)
	eco._try_recruit()
	_check(eco.soldiers == 0, "Rekrut: 1 Schwert allein erzeugt keinen Soldaten")

	eco.hq_stock = { Goods.SWORD: 1, Goods.SHIELD: 1, Goods.BEER: 1 }
	eco.hq_people = { Jobs.HELPER: 1 }
	eco._try_recruit()
	_check(eco.soldiers == 1, "Rekrut: Schwert+Schild+Bier+Träger → 1 Soldat")
	_check(int(eco.hq_stock.get(Goods.SWORD, 0)) == 0
		and int(eco.hq_stock.get(Goods.SHIELD, 0)) == 0
		and int(eco.hq_stock.get(Goods.BEER, 0)) == 0
		and int(eco.hq_people.get(Jobs.HELPER, 0)) == 0,
		"Rekrut: je 1 Schwert/Schild/Bier/Träger verbraucht")

	# --- Rekrutierungsrate drosselt: Rate 5 → erst jeder zweite Takt ---
	eco.soldiers = 0
	eco._recruit_accum = 0
	eco.recruiting_ratio = 5
	eco.hq_stock = { Goods.SWORD: 5, Goods.SHIELD: 5, Goods.BEER: 5 }
	eco.hq_people = { Jobs.HELPER: 5 }
	eco._try_recruit()
	_check(eco.soldiers == 0, "Rekrut: Rate 5 → erster Takt rekrutiert noch nicht")
	eco._try_recruit()
	_check(eco.soldiers == 1, "Rekrut: Rate 5 → zweiter Takt rekrutiert")

	# Rate 0 → nie rekrutieren.
	eco.soldiers = 0
	eco._recruit_accum = 0
	eco.recruiting_ratio = 0
	eco._try_recruit()
	_check(eco.soldiers == 0, "Rekrut: Rate 0 → keine Rekrutierung")


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


## #54: Bodenschätze auf Bergen — alle vier Sorten vorhanden, RTTR-nahe Anteile,
## hohe Abdeckung und die "Gold durch Kohle"-Schwierigkeitsoption.
func _test_ore_distribution() -> void:
	var map := MapGenerator.generate(128, 128, 4242)
	var counts := { MapData.ORE_COAL: 0, MapData.ORE_IRON: 0,
		MapData.ORE_GOLD: 0, MapData.ORE_GRANITE: 0 }
	var mountain_nodes := 0
	var with_dep := 0
	for y in map.height:
		for x in map.width:
			var terr := map.terrains_around(x, y)
			var all_m := true
			for t in terr:
				if t != Terrain.MOUNTAIN:
					all_m = false
					break
			if not all_m:
				continue
			mountain_nodes += 1
			var k := map.ore_deposit_kind_at(x, y)
			if k >= 0:
				with_dep += 1
				counts[k] = int(counts[k]) + 1
	_check(counts[MapData.ORE_COAL] > 0 and counts[MapData.ORE_IRON] > 0 \
			and counts[MapData.ORE_GOLD] > 0 and counts[MapData.ORE_GRANITE] > 0,
		"Erz: alle vier Sorten vorhanden (C=%d I=%d Go=%d Gr=%d)" % [
			counts[MapData.ORE_COAL], counts[MapData.ORE_IRON],
			counts[MapData.ORE_GOLD], counts[MapData.ORE_GRANITE]])
	# Granit und Gold sind keine Rundungsreste mehr (vorher Gold 0 %, Granit ~1 %).
	var granite_pct := 100.0 * float(counts[MapData.ORE_GRANITE]) / float(maxi(with_dep, 1))
	var gold_pct := 100.0 * float(counts[MapData.ORE_GOLD]) / float(maxi(with_dep, 1))
	_check(granite_pct >= 8.0 and granite_pct <= 22.0, "Erz: Granit-Anteil ~15 %% (%.0f%%)" % granite_pct)
	_check(gold_pct >= 4.0 and gold_pct <= 14.0, "Erz: Gold-Anteil ~9 %% (%.0f%%)" % gold_pct)
	# Der Großteil der Berge trägt Erz (S2-nah), nicht nur ~30 %.
	var coverage := 100.0 * float(with_dep) / float(maxi(mountain_nodes, 1))
	_check(coverage >= 70.0, "Erz: hohe Bergabdeckung (%.0f%%)" % coverage)

	# Schwierigkeitsoption: Gold durch Kohle ersetzen -> kein Gold mehr auf der Karte.
	var hard := MapGenerator.generate(128, 128, 4242, { "replace_gold": true })
	var hard_gold := 0
	for y in hard.height:
		for x in hard.width:
			if hard.ore_deposit_kind_at(x, y) == MapData.ORE_GOLD:
				hard_gold += 1
	_check(hard_gold == 0, "Erz: 'Gold durch Kohle' entfernt alles Gold (%d übrig)" % hard_gold)


func _test_mountain_meadow_plateaus() -> void:
	var map := MapGenerator.generate(96, 96, 1337)
	var state := WorldState.new(map)
	var tri_count := 0
	var hut_spots := 0
	var oversized := 0
	for yy in range(2, map.height - 2):
		for xx in range(2, map.width - 2):
			if map.get_tri(Vector2i(xx, yy), Grid.TRI_R) == Terrain.MOUNTAIN_MEADOW:
				tri_count += 1
			if map.get_tri(Vector2i(xx, yy), Grid.TRI_D) == Terrain.MOUNTAIN_MEADOW:
				tri_count += 1
			var has_highland := false
			for t in map.terrains_around(xx, yy):
				if t == Terrain.MOUNTAIN_MEADOW:
					has_highland = true
					break
			if has_highland:
				var bq := state.compute_bq(xx, yy)
				if bq >= WorldState.BQ_HUT:
					hut_spots += 1
				if bq > WorldState.BQ_HUT:
					oversized += 1
	_check(tri_count > 20, "Bergwiese: Generator erzeugt Plateau-Terrain (%d Dreiecke)" % tri_count)
	_check(hut_spots > 0, "Bergwiese: mindestens ein Huetten-/Wachhuettenplatz im Gebirge")
	_check(oversized == 0, "Bergwiese: nur kleine Gebaeude, keine Haus/Burg-Plaetze (%d)" % oversized)


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
	for id in ["water", "meadow", "mountain", "mountain_meadow", "sand", "swamp", "snow"]:
		_check(FileAccess.file_exists("res://assets/terrain/%s.png" % id),
			"Terrain-Textur vorhanden: %s" % id)
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

	# Inkrementelles Aufdecken (Issue #30): eine neu gesetzte Flagge deckt ihre
	# Umgebung SOFORT auf — ohne dass resync() die ganze Karte neu scannen muss.
	# Knoten suchen, der im Gebiet & baubar, aber noch NICHT aufgedeckt ist.
	var spot := Vector2i(-1, -1)
	for yy in range(2, map.height - 2):
		for xx in range(2, map.width - 2):
			var idx := map.idx(xx, yy)
			if not state.explored.has(idx) and state.can_place_flag(xx, yy):
				spot = Vector2i(xx, yy)
				break
		if spot.x >= 0:
			break
	_check(spot.x >= 0, "Visibility: unaufgedeckter Bauplatz im Gebiet gefunden")
	if spot.x >= 0:
		_check(state.place_flag(spot.x, spot.y) != null, "Visibility: Testflagge setzbar")
		_check(state.explored.has(map.idx(spot.x, spot.y)),
			"Neue Flagge deckt ihren Knoten inkrementell auf (ohne resync)")


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


## Minen verbrauchen eine ODER-Nahrung wie im Original: Fisch, Fleisch oder Brot.
## Der reine Erzabbau-Test oben nutzt _do_resource_action direkt und bleibt bewusst
## frei von Nahrungslogik; hier wird nur Eingang/Verbrauch/Nachforderung geprüft.
func _test_mine_food() -> void:
	var map := _flat_map(20, 20)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var group := [Goods.FISH, Goods.MEAT, Goods.BREAD]
	var bs := Economy.BState.new()
	bs.def = { food_inputs = group, resource = "ore", output = Goods.COAL }

	_check(not eco._has_inputs(bs), "Mine: ohne Nahrung startet kein Zyklus")
	bs.delivered[Goods.BREAD] = 1
	_check(eco._has_inputs(bs), "Mine: Brot reicht als ODER-Nahrung")
	eco._consume_inputs(bs)
	_check(int(bs.delivered.get(Goods.BREAD, 0)) == 0,
		"Mine: ein Zyklus verbraucht genau eine Nahrungseinheit")

	bs.delivered.clear()
	bs.delivered[Goods.FISH] = 1
	_check(eco._has_inputs(bs), "Mine: Fisch reicht als ODER-Nahrung")
	bs.delivered.clear()
	bs.delivered[Goods.MEAT] = 1
	_check(eco._has_inputs(bs), "Mine: Fleisch reicht als ODER-Nahrung")

	bs.delivered.clear()
	bs.delivered[Goods.BEER] = 1
	_check(not eco._has_inputs(bs),
		"Mine: Bier zählt standardmäßig nicht als Original-Nahrung")
	eco.set_mines_accept_beer(true)
	_check(eco._has_inputs(bs), "Mine: Hausregel erlaubt Bier als Minennahrung")
	eco._consume_inputs(bs)
	_check(int(bs.delivered.get(Goods.BEER, 0)) == 0,
		"Mine: Hausregel-Bier wird als eine Nahrungseinheit verbraucht")

	var hq_flag := state.place_flag(4, 10)
	var mine_flag := state.place_flag(10, 10)
	_check(hq_flag != null and mine_flag != null, "Mine: Testflaggen platzierbar")
	if hq_flag == null or mine_flag == null:
		return
	_check(state.build_road(hq_flag.pos, mine_flag.pos) != null,
		"Mine: Teststraße für Nahrungsanforderung baubar")
	eco.hq_flag = map.idx(hq_flag.pos.x, hq_flag.pos.y)
	eco.hq_stock = { Goods.MEAT: 1, Goods.BREAD: 1 }
	eco.hq_outbox.clear()
	var req := Economy.BState.new()
	req.def = { food_inputs = group, resource = "ore", output = Goods.COAL }
	req.flag_idx = map.idx(mine_flag.pos.x, mine_flag.pos.y)
	eco._request_inputs(req)
	_check(int(req.incoming.get(Goods.MEAT, 0)) == 1
			and int(req.incoming.get(Goods.BREAD, 0)) == 1,
		"Mine: fordert bis zum Nahrungspuffer verschiedene verfügbare Sorten an")
	_check(eco.hq_outbox.size() == 2 and int(eco.hq_stock.get(Goods.MEAT, 0)) == 0
			and int(eco.hq_stock.get(Goods.BREAD, 0)) == 0,
		"Mine: angeforderte Nahrung wird aus dem Lager ausgelagert")


## Endliche Fischbestände (Issue #6), original-getreu an RTTR nofFisher: Fisch ist
## eine begrenzte Ressource je Küstenknoten; der Fischer baut sie ab, bei 0 ist der
## Grund leer und die Hütte wartet. seed_coastal_fish belegt nur echte Küstenknoten.
func _test_fishery_fish() -> void:
	var map := _flat_map(20, 20)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	map.set_fish(10, 8, 2)
	# Fischer findet den Fischgrund im Radius.
	_check(eco._find_water_edge(Vector2i(10, 10)) == Vector2i(10, 8), "Fischer findet Fischgrund im Radius")
	# Fangen reduziert den Bestand.
	var bs := Economy.BState.new()
	bs.def = { resource = "water", output = Goods.FISH }
	bs.worker_target = Vector2i(10, 8)
	eco._do_resource_action(bs)
	_check(map.fish_at(10, 8) == 1, "1. Fang: Bestand 2 → 1")
	eco._do_resource_action(bs)
	_check(map.fish_at(10, 8) == 0, "Fischgrund nach 2 Fängen erschöpft")
	# Erschöpfter Grund wird nicht mehr gefunden → Hütte hat keine Fische in Reichweite.
	_check(eco._find_water_edge(Vector2i(10, 10)).x < 0, "Erschöpfter Fischgrund wird nicht mehr gefunden")

	# seed_coastal_fish: nur Küstenknoten (Wasser UND Land im Dreiecksring) bekommen Fisch.
	var cmap := _flat_map(12, 12)
	cmap.set_tri(Vector2i(6, 6), Grid.TRI_R, Terrain.WATER)
	cmap.set_tri(Vector2i(6, 6), Grid.TRI_D, Terrain.WATER)
	MapGenerator.seed_coastal_fish(cmap)
	_check(cmap.fish_at(6, 6) > 0, "seed_coastal_fish: Küstenknoten bekommt Fisch")
	_check(cmap.fish_at(2, 2) == 0, "seed_coastal_fish: reines Land bleibt fischlos")


## Bauernhof-Felder (Issue #26), original-getreu an RTTR nofFarmer/noGrainfield:
## säen → wachsen → ernten (Säen liefert kein Getreide), Ernte hinterlässt eine
## nicht-blockierende Stoppel-Deko, ungeerntete reife Felder verdorren, neben
## wachsenden Feldern ist nur eine Flagge möglich, Saatregel verbietet Felder/
## Gebäude direkt daneben, Suchradius 2; Save/Load erhält den Feldzustand.
func _test_farm_fields() -> void:
	var map := _flat_map(24, 24)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var farm_pos := Vector2i(12, 12)
	var bs := Economy.BState.new()
	bs.def = { resource = "field", output = Goods.GRAIN }

	# Leeres Wiesen-Umfeld → der Bauer wählt einen Saatplatz im Radius 2.
	var sow := eco._find_farm_target(farm_pos)
	_check(sow.x >= 0, "Farm: findet freien Ackerplatz im leeren Wiesen-Umfeld")
	_check(WorldState.hex_distance(farm_pos, sow) <= Economy.FARM_RADIUS,
		"Farm: Saatplatz liegt im Arbeitsradius (FARM_RADIUS)")

	# #7/#26: Auf offener Wiese müssen rund um den Hof viele Felder gleichzeitig
	# möglich sein (nicht nur die 3 aus dem zu kleinen Radius). Gierig nicht-benachbarte
	# Saatplätze im Radius zählen — Burg-Fußabdruck kostet den inneren Bereich.
	var sim_map := _flat_map(40, 40)
	var sim_state := WorldState.new(sim_map)
	var sim_eco := Economy.new(sim_state)
	var sim_farm := sim_state.place_building(20, 20, WorldState.BQ_CASTLE, false, "farm", 0, false)
	sim_eco.resync()
	var placed: Array[Vector2i] = []
	for r in range(1, Economy.FARM_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var fx: int = sim_farm.pos.x + dx
				var fy: int = sim_farm.pos.y + dy
				if not sim_map.in_bounds(fx, fy):
					continue
				if WorldState.hex_distance(sim_farm.pos, Vector2i(fx, fy)) != r:
					continue
				if not sim_eco._is_field_spot(fx, fy):
					continue
				var ok := true
				for q in placed:
					if WorldState.hex_distance(Vector2i(fx, fy), q) <= 1:
						ok = false
				if ok:
					placed.append(Vector2i(fx, fy))
	_check(placed.size() >= 6,
		"Farm: viele gleichzeitige Felder auf offener Wiese (>=6, ist %d)" % placed.size())

	# Säen: Feld entsteht, aber KEIN Getreide-Ertrag.
	bs.worker_target = sow
	bs.out_yield = true
	eco._do_resource_action(bs)
	_check(map.map_object(sow.x, sow.y) == MapData.MO_FIELD, "Farm: Saat erzeugt ein Feld")
	_check(map.field_stage_at(sow.x, sow.y) == MapData.FIELD_SEED, "Farm: frisches Feld ist Stufe SEED")
	_check(bs.out_yield == false, "Farm: Säen liefert kein Getreide (out_yield=false)")

	# S2: direkt neben einem wachsenden Feld ist nur eine Flagge möglich (kein Gebäude).
	var nb := map.neighbor(sow.x, sow.y, Grid.E)
	_check(state.compute_bq(nb.x, nb.y) == WorldState.BQ_FLAG,
		"Farm: neben wachsendem Feld nur Flagge (RTTR FlagsAround)")
	# Die Saatregel verbietet ein zweites Feld direkt daneben.
	_check(not eco._is_field_spot(nb.x, nb.y), "Farm: kein zweites Feld direkt neben einem Feld")

	# Steile Wiesenhänge sind kein Ackerplatz. Das entspricht der RTTR/S2-BQ-
	# Schwelle: direkte Höhendifferenz > 3 ist nur noch Flaggenqualität.
	var steep_field_map := _flat_map(16, 16)
	steep_field_map.set_height(8, 8, 10)
	steep_field_map.set_height(9, 8, 14)
	var steep_field_state := WorldState.new(steep_field_map)
	var steep_field_eco := Economy.new(steep_field_state)
	_check(not steep_field_eco._is_field_spot(8, 8),
		"Farm: kein Ackerplatz auf steilem Wiesenhang")

	# Wachstum: seed → ripe.
	var total := Tuning.field_growth_ticks(0) + Tuning.field_growth_ticks(1) + Tuning.field_growth_ticks(2)
	for t in total:
		eco._tick_field_growth()
	_check(map.field_stage_at(sow.x, sow.y) == MapData.FIELD_RIPE, "Farm: Feld reift nach %d Ticks" % total)

	# Reifes Feld wird zum Ernten priorisiert (Class1 vor Class2).
	_check(eco._find_farm_target(farm_pos) == sow, "Farm: reifes Feld wird zum Ernten gewählt")

	# Ernten: Feld verschwindet, out_yield bleibt true → Getreide; Stoppel-Deko bleibt.
	bs.worker_target = sow
	bs.out_yield = true
	eco._do_resource_action(bs)
	_check(map.map_object(sow.x, sow.y) != MapData.MO_FIELD, "Farm: Ernte entfernt das Feld")
	_check(bs.out_yield == true, "Farm: Ernte liefert Getreide (out_yield=true)")
	_check(map.field_decay_at(sow.x, sow.y) == MapData.FIELD_DECAY_CUT,
		"Farm: Ernte hinterlässt ein Stoppelfeld (CUT)")
	_check(not state.has_object(sow.x, sow.y), "Farm: Stoppelfeld ist kein blockierendes Objekt")
	_check(state.effective_bq(sow.x, sow.y) >= WorldState.BQ_HUT,
		"Farm: auf/an der Stoppel-Deko ist wieder ein Gebäude möglich (blockiert nicht)")
	for t in Tuning.field_decay_ticks():
		eco._tick_decay_fields()
	_check(not map.has_field_decay(sow.x, sow.y), "Farm: Stoppelfeld verschwindet nach field_decay_ticks")

	# Verdorren: ein reifes, ungeerntetes Feld wird nach field_wither_ticks zu
	# verdorrter Deko (RTTR State::Withering) und verschwindet dann.
	var wmap := _flat_map(20, 20)
	var wstate := WorldState.new(wmap)
	var weco := Economy.new(wstate)
	wmap.set_map_object(10, 10, MapData.MO_FIELD)
	wmap.set_field_stage(10, 10, MapData.FIELD_RIPE)
	weco._init_field_growth_from_map()  # reifes Feld bekommt Verdorr-Timer
	_check(int(weco._growing_fields.get(wmap.idx(10, 10), -1)) == Tuning.field_wither_ticks(),
		"Farm: reifes Feld bekommt Verdorr-Timer")
	for t in Tuning.field_wither_ticks():
		weco._tick_field_growth()
	_check(wmap.map_object(10, 10) != MapData.MO_FIELD, "Farm: ungeerntetes reifes Feld verdorrt")
	_check(wmap.field_decay_at(10, 10) == MapData.FIELD_DECAY_WITHERED, "Farm: verdorrtes Feld als WITHERED-Deko")

	# Ungeeignete Fläche (Sand statt Wiese): kein Ackerplatz → Hof wartet.
	var smap := _flat_map(24, 24)
	for yy in smap.height:
		for xx in smap.width:
			smap.set_tri(Vector2i(xx, yy), Grid.TRI_R, Terrain.SAND)
			smap.set_tri(Vector2i(xx, yy), Grid.TRI_D, Terrain.SAND)
	var sstate := WorldState.new(smap)
	var seco := Economy.new(sstate)
	_check(seco._find_farm_target(Vector2i(12, 12)).x < 0, "Farm: auf Sand kein Ackerplatz → wartet")

	# Save/Load: Wachstums- und Deko-Timer werden rekonstruiert.
	var fidx := map.idx(4, 4)
	map.set_map_object(4, 4, MapData.MO_FIELD)
	map.set_field_stage(4, 4, MapData.FIELD_YOUNG)
	eco.restore_field_growth({ fidx: 42.0 })
	_check(int(eco._growing_fields.get(fidx, -1)) == 42, "Farm: Save/Load stellt Feld-Wachstumsticks wieder her")
	map.set_field_decay(18, 18, MapData.FIELD_DECAY_WITHERED)
	eco.restore_decay_fields({ map.idx(18, 18): 99.0 })
	_check(int(eco._decay_fields.get(map.idx(18, 18), -1)) == 99,
		"Farm: Save/Load stellt den Feld-Deko-Timer wieder her")

	# Voller Pipeline-Durchlauf: ein realer Hof produziert Getreide ERST nach
	# Säen + Reifen + Ernten (nicht aus dem Nichts).
	var imap := _flat_map(28, 28)
	var istate := WorldState.new(imap)
	var ieco := Economy.new(istate)
	istate.place_building(10, 10, WorldState.BQ_CASTLE, true, "hq", 9, false)
	ieco.resync()
	var farm := istate.place_building(15, 13, WorldState.BQ_HOUSE, false, "farm", 0, false)
	_check(farm != null, "Farm baubar")
	if farm != null:
		ieco.resync()
		var fbs: Economy.BState = ieco.bstates[imap.idx(15, 13)]
		fbs.staffed = true
		var grain_seen := false
		var field_seen := false
		for t in 16000:
			ieco._tick_work(fbs)
			ieco._tick_field_growth()
			if not field_seen:
				for k in imap.objects:
					if int(imap.objects[k]) == MapData.MO_FIELD:
						field_seen = true
						break
			if ieco._out_total(fbs) > 0:
				grain_seen = true
				break
		_check(field_seen, "Farm: legt sichtbar ein Feld auf der Karte an")
		_check(grain_seen, "Farm: produziert Getreide erst nach Säen+Reifen+Ernten")


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

	# Münzanforderung abschalten (S2: Goldmünzen aus) -> keine weitere Beförderung,
	# obwohl Münzen im HQ liegen.
	gh.wants_coins = false
	var promo_before := gh.promotions
	eco.hq_stock[Goods.COINS] = 5
	for t in 2500:
		eco.tick()
	_check(gh.promotions == promo_before,
		"Münzen AUS: keine weitere Beförderung trotz Gold im HQ")
	_check(eco.hq_stock.get(Goods.COINS, 0) == 5,
		"Münzen AUS: HQ-Gold bleibt unangetastet")


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
		map_source = "random",
		map_seed_text = "SIEDLER",
		map_seed_value = MapGenerator.stable_seed_from_string("SIEDLER"),
		map_generator_version = MapGenerator.MAP_GENERATOR_VERSION,
		map_enemy_count = 3,
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


	_check(String(back.get("map_seed_text", "")) == "SIEDLER" \
			and int(back.get("map_enemy_count", -1)) == 3,
		"Save/Load: Kartenmetadaten (Seed + Gegner) erhalten")
	_check(String(back.get("map_generator_version", "")) == MapGenerator.MAP_GENERATOR_VERSION,
		"Save/Load: Generator-Version erhalten")


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


## Originaltreu (RTTR/S2, #37): Straßen dürfen DICHT an Gebäuden entlanglaufen.
## Tabu sind nur die belegten Gebäude-/Extension-Knoten selbst — KEIN kosmetischer
## Sperrkranz um Häuser/Burgen mehr (der hat die Bebauung künstlich auseinandergezogen).
func _test_road_runs_adjacent_to_building() -> void:
	var map := _flat_map(40, 40)
	var state := WorldState.new(map)
	var hq := state.place_building(20, 20, WorldState.BQ_CASTLE, true, "hq", 9, false)
	var house := state.place_building(15, 15, WorldState.BQ_HOUSE, false, "sawmill", 0, false)
	_check(house != null, "Haus für Straßen-Dichte-Test platzierbar")
	if house == null:
		return
	# Ein freier Knoten DIREKT neben dem Haus ist jetzt für Straßen nutzbar
	# (früher durch den Margin-Ring gesperrt).
	var adj := map.neighbor(house.pos.x, house.pos.y, Grid.NE)
	_check(state._occ(adj.x, adj.y) == WorldState.OBJ_NONE and state.node_walkable(adj.x, adj.y),
		"Knoten direkt neben Haus ist für Straßen frei/begehbar (kein Sperrkranz)")
	# Straße bleibt planbar — und KEIN Zwischenknoten liegt auf einem belegten
	# Gebäude-/Extension-Knoten (Burg-Extensions bleiben tabu).
	state.place_flag(24, 26)
	var path := state.plan_road(hq.flag_pos, Vector2i(24, 26))
	_check(not path.is_empty(), "Straße planbar")
	for k in range(1, path.size() - 1):
		_check(state._occ(path[k].x, path[k].y) == WorldState.OBJ_NONE,
			"Straße läuft nicht über belegte Gebäude-/Extension-Knoten")


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


func _find_buildable(state: WorldState, sx: int, sy: int, min_bq: int = WorldState.BQ_CASTLE) -> Vector2i:
	# Sucht spiralförmig einen Platz, der mindestens min_bq trägt. Default BURG, weil die
	# meisten Aufrufer hier ein HQ setzen — auf relief­reicherem Terrain (Generator v3)
	# darf der Treffer kein knapper Hüttenplatz an einer Bergflanke sein.
	var map := state.map
	for r in range(0, 20):
		for yy in range(maxi(2, sy - r), mini(map.height - 2, sy + r + 1)):
			for xx in range(maxi(2, sx - r), mini(map.width - 2, sx + r + 1)):
				if state.compute_bq(xx, yy) >= min_bq and state._occ(xx, yy) == WorldState.OBJ_NONE:
					return Vector2i(xx, yy)
	return Vector2i(-1, -1)
