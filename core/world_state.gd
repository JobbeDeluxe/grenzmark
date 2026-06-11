class_name WorldState
extends RefCounted

## Der gesamte veränderliche Spielzustand: Karte + Flaggen + Straßen + Gebäude.
## Enthält die Bau-Regeln (BauQualität) und die Pfadfindung. Reine Logik,
## kennt Godot nicht.

# BauQualität eines Knotens (aufsteigend). MINE ist ein Sonderfall daneben.
enum { BQ_NOTHING, BQ_FLAG, BQ_HUT, BQ_HOUSE, BQ_CASTLE, BQ_MINE }
enum { ROAD_DIRT, ROAD_COBBLE }

# Was auf einem Knoten liegt.
enum { OBJ_NONE, OBJ_FLAG, OBJ_BUILDING, OBJ_ROAD }

# S2-Regel: Militärgebäude (inkl. HQ) müssen mindestens so viele Knoten von
# jedem anderen Militärgebäude/HQ entfernt sein — egal welchem Spieler. So kann
# ein Gegner nicht direkt an ein etabliertes Militärgebäude bauen und dessen
# Kerngebiet schlucken; Expansion Richtung Grenze bleibt aber erlaubt.
const MILITARY_MIN_DIST := 5


class Flag:
	extends RefCounted
	var pos: Vector2i
	var id: int
	var owner := 0


class Building:
	extends RefCounted
	var pos: Vector2i
	var size: int        # BQ_HUT / BQ_HOUSE / BQ_CASTLE / BQ_MINE
	var flag_pos: Vector2i
	var is_hq := false   # Hauptquartier = Lager/Senke
	var def_id := ""     # Katalog-ID des Gebäudetyps
	var influence := 0   # Einflussradius (militärisch / HQ), 0 = keiner
	var under_construction := true  # Baustelle, bis Material geliefert ist
	var garrison := 0    # stationierte Soldaten
	var capacity := 0    # max. Soldaten (Militärgebäude)
	var promotions := 0  # Beförderungen durch Münzen (Verteidigungs-Rüstung)
	var wants_coins := true  # fordert dieses Militärgebäude Gold zur Beförderung an? (S2)
	var owner := 0       # 0 = Spieler, 1 = Gegner
	var ext_nodes: Array[Vector2i] = []  # zusätzlich belegte Extension-Knoten (Burg/HQ)


class Road:
	extends RefCounted
	var nodes: Array[Vector2i] = []   # Knotenfolge inkl. beider Flaggen
	var a: Vector2i
	var b: Vector2i
	var owner := 0
	var traffic := 0
	var level := ROAD_DIRT
	func length() -> int:
		return nodes.size() - 1


var map: MapData
var flags: Dictionary = {}      # idx -> Flag
var buildings: Dictionary = {}  # idx -> Building
var roads: Array[Road] = []
var occupied: Dictionary = {}   # idx -> OBJ_*
var territory: Dictionary = {}        # idx -> true (Spieler-Gebiet, Besitzer 0)
var enemy_territory: Dictionary = {}  # idx -> true (Gegner-Gebiet, Besitzer 1)
var territory_owner: Dictionary = {}  # idx -> Besitzer-ID (für Grenz-Gleichstand)
var explored: Dictionary = {}         # idx -> true (vom Spieler aufgedeckt)
# Straßenteilungen seit dem letzten resync: { old, r1, r2, k } — damit die Economy
# den vorhandenen Träger auf seinem Teilstück WEITERführen kann (statt ihn zu
# verwerfen und beide Teilstücke neu vom HQ zu besetzen). k = Teilungs-Knotenindex.
var splits: Array = []

# Routing-Cache (#30): Flaggengraph und gelöste Routen ändern sich NUR, wenn Straßen
# entstehen/wegfallen. Statt bei jedem find_route() den Graphen aus allen Straßen neu
# zu bauen, halten wir ihn vor und merken uns gelöste Routen je (Start, Ziel) — der
# Warenfluss fragt pro Ware pro Tick dieselben Routen ab. Jede strukturelle Straßen-
# änderung (build_road / _remove_road / _split_road_with_flag / Laden) muss
# invalidate_routes() rufen und verwirft beides. Routing-Kosten hängen nur an
# Road.length() (= nodes.size()-1), das sich nach dem Anlegen nicht mehr ändert.
var _flag_graph_cache: Dictionary = {}
var _flag_graph_dirty := true
var _route_cache: Dictionary = {}   # Vector2i(start_idx, goal_idx) -> Array[Vector2i]

var _next_flag_id := 1


func _init(map_data: MapData) -> void:
	map = map_data


# --------------------------------------------------------------------------
#  Hilfen
# --------------------------------------------------------------------------

func _occ(x: int, y: int) -> int:
	return occupied.get(map.idx(x, y), OBJ_NONE)


## Begehbar = mindestens ein angrenzendes Dreieck ist begehbares Terrain.
func node_walkable(x: int, y: int) -> bool:
	if not map.in_bounds(x, y):
		return false
	for t in map.terrains_around(x, y):
		if Terrain.is_walkable(t):
			return true
	return false


## Liegt ein Karten-Objekt (Baum/Stein/Erz) auf dem Knoten?
func has_object(x: int, y: int) -> bool:
	return map.map_object(x, y) >= 0


# --------------------------------------------------------------------------
#  Territorium (Einflussgebiet)
# --------------------------------------------------------------------------

func in_territory(x: int, y: int) -> bool:
	return territory.has(map.idx(x, y))


func owner_territory(owner: int) -> Dictionary:
	return territory if owner == 0 else enemy_territory


func in_owner_territory(owner: int, x: int, y: int) -> bool:
	return owner_territory(owner).has(map.idx(x, y))


func is_territory_border_node_for(owner: int, x: int, y: int) -> bool:
	var area := owner_territory(owner)
	if area.is_empty() or not map.in_bounds(x, y) or not in_owner_territory(owner, x, y):
		return false
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x < 0 or not in_owner_territory(owner, n.x, n.y):
			return true
	return false


func is_territory_border_node(x: int, y: int) -> bool:
	return is_territory_border_node_for(0, x, y)


func has_building_territory_margin_for(owner: int, x: int, y: int) -> bool:
	var area := owner_territory(owner)
	if area.is_empty():
		return true
	return in_owner_territory(owner, x, y) and not is_territory_border_node_for(owner, x, y)


func has_building_territory_margin(x: int, y: int) -> bool:
	return has_building_territory_margin_for(0, x, y)


const REVEAL_BUILDING := 7   # Aufdeck-Radius eigener Gebäude
const REVEAL_FLAG := 5       # Aufdeck-Radius einer Flagge
const REVEAL_ROAD := 3       # Aufdeck-Radius je Straßenknoten


## Sichtbarkeit: deckt Knoten rund um eigene Gebäude/Flaggen/Straßen auf.
## Aufgedecktes bleibt aufgedeckt (wie in S2 die erkundete Karte).
## WICHTIG: Das ist die VOLL-Neuberechnung über alle Strukturen — teuer und nur
## beim Laden/Reset nötig. Im laufenden Spiel decken `place_building`, `_add_flag`
## und `build_road` inkrementell auf (siehe dort), damit das Platzieren nicht bei
## jedem Klick die ganze Karte neu scannt (Performance, Issue #30).
func recompute_visibility() -> void:
	for i in buildings:
		var b: Building = buildings[i]
		if b.owner == 0:
			_reveal(b.pos, REVEAL_BUILDING)
	for i in flags:
		_reveal(flags[i].pos, REVEAL_FLAG)
	for r in roads:
		for n in r.nodes:
			_reveal(n, REVEAL_ROAD)


func _reveal(center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			if map.in_bounds(x, y) and hex_distance(center, Vector2i(x, y)) <= radius:
				explored[map.idx(x, y)] = true


## Hex-Distanz zweier Knoten (für kreisförmiges Einflussgebiet).
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	# odd-r Offset -> Cube-Koordinaten
	var aq := a.x - (a.y - (a.y & 1)) / 2
	var bq := b.x - (b.y - (b.y & 1)) / 2
	var az := a.y
	var bz := b.y
	var ay := -aq - az
	var by := -bq - bz
	return int((absi(aq - bq) + absi(ay - by) + absi(az - bz)) / 2)


## Neu berechnen: Gebiet wird durch HQ + besetzte Militärgebäude beansprucht.
## S2-Modell „closest building wins": Jeder Knoten gehört dem NÄCHSTGELEGENEN
## deckenden Militärgebäude/HQ (per Hex-Distanz). Bei exakt gleicher Distanz
## behält der bisherige Halter den Knoten (stabile Grenze, kein Flackern), sonst
## gewinnt die kleinere Besitzer-ID. Damit verliert man beim Bau eines Gegners
## an der Grenze nur den wirklich näheren Streifen — nicht den vollen Radius und
## nicht das eigene Kerngebiet. Getrennt für Spieler (0) / Gegner (>0).
func recompute_territory() -> void:
	var prev_owner := territory_owner   # Halter vor dieser Neuberechnung (Gleichstand)
	territory.clear()
	enemy_territory.clear()
	territory_owner = {}
	var best_dist := {}  # idx -> kleinste Distanz eines deckenden Gebäudes
	for i in buildings:
		var b: Building = buildings[i]
		if b.influence <= 0 or b.under_construction:
			continue
		# Militärgebäude halten ihr Gebiet nur mit mindestens einem Soldaten.
		if not b.is_hq and b.garrison <= 0:
			continue
		var r := b.influence
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := b.pos.x + dx
				var y := b.pos.y + dy
				if not map.in_bounds(x, y):
					continue
				var d := hex_distance(b.pos, Vector2i(x, y))
				if d > r:
					continue
				var k := map.idx(x, y)
				var cur = best_dist.get(k)
				if cur == null or d < cur:
					best_dist[k] = d
					territory_owner[k] = b.owner
				elif d == cur:
					# Gleichstand: bisheriger Halter behält, sonst kleinere ID.
					var assigned: int = territory_owner[k]
					if assigned != b.owner:
						var prev = prev_owner.get(k)
						if prev == b.owner:
							territory_owner[k] = b.owner
						elif prev != assigned and b.owner < assigned:
							territory_owner[k] = b.owner
	for k in territory_owner:
		if territory_owner[k] == 0:
			territory[k] = true
		else:
			enemy_territory[k] = true


# --------------------------------------------------------------------------
#  BauQualität
# --------------------------------------------------------------------------

## Reines Terrain-/Hang-Potenzial eines Knotens, ohne bereits gesetzte Objekte.
func compute_bq(x: int, y: int) -> int:
	if not map.in_bounds(x, y):
		return BQ_NOTHING
	# Bäume/Steine/Erz blockieren den Knoten vollständig.
	if has_object(x, y):
		return BQ_NOTHING

	var terr := map.terrains_around(x, y)
	var all_build := true
	var all_mountain := true
	var any_walk := false
	for t in terr:
		if not Terrain.is_buildable(t):
			all_build = false
		if not Terrain.is_mountain(t):
			all_mountain = false
		if Terrain.is_walkable(t):
			any_walk = true

	if not any_walk:
		return BQ_NOTHING

	var slope := map.max_slope(x, y)

	if all_mountain:
		return BQ_MINE if slope <= 4 else BQ_FLAG

	if all_build:
		var base := BQ_FLAG
		if slope <= 1:
			base = BQ_CASTLE
		elif slope <= 2:
			base = BQ_HOUSE
		elif slope <= 3:
			base = BQ_HUT
		# Ein Gebäude braucht rechts unten (SE) einen gültigen Flaggenplatz.
		if base >= BQ_HUT:
			var se := map.neighbor(x, y, Grid.SE)
			if se.x < 0 or not node_walkable(se.x, se.y):
				base = BQ_FLAG
		return base

	# Gemischtes, aber begehbares Terrain: nur Flagge.
	return BQ_FLAG


## Effektive BauQualität: Terrain-Potenzial, reduziert durch belegte Knoten und
## benachbarte Gebäude — größenabhängig wie in S2 (RTTR BQCalculator):
## Hütten/Häuser dürfen direkt neben ein Gebäude. Nur eine BURG braucht Luft:
## ihre 3 Extension-Knoten oben-links (W/NW/NE) müssen frei sein UND es darf kein
## Gebäude im Umkreis von 2 Knoten stehen, sonst sinkt sie auf ein Haus. Belegte
## Knoten (inkl. der Extensions großer Gebäude) bleiben gesperrt.
func effective_bq(x: int, y: int) -> int:
	var bq := compute_bq(x, y)
	if bq == BQ_NOTHING:
		return BQ_NOTHING
	if _occ(x, y) != OBJ_NONE:
		return BQ_NOTHING
	if bq == BQ_FLAG or bq == BQ_MINE:
		return bq
	var cap := bq
	# Nur Burg-Kandidaten sind durch Nachbar-Gebäude eingeschränkt.
	if cap == BQ_CASTLE:
		# a) Die 3 Extension-Knoten (W/NW/NE) müssen frei sein.
		for dir in [Grid.W, Grid.NW, Grid.NE]:
			var e := map.neighbor(x, y, dir)
			if e.x < 0 or _occ(e.x, e.y) != OBJ_NONE:
				cap = BQ_HOUSE
				break
	if cap == BQ_CASTLE:
		# b) Kein Gebäude im Umkreis von 2 Knoten.
		for i in buildings:
			if hex_distance(Vector2i(x, y), buildings[i].pos) <= 2:
				cap = BQ_HOUSE
				break
	return cap


# --------------------------------------------------------------------------
#  Flaggen
# --------------------------------------------------------------------------

func can_place_flag(x: int, y: int, owner := 0) -> bool:
	if compute_bq(x, y) < BQ_FLAG:
		return false
	var area := owner_territory(owner)
	if not area.is_empty() and not in_owner_territory(owner, x, y):
		return false
	if _occ(x, y) != OBJ_NONE:
		return false
	# Abstandsregel: kein direkter Nachbar darf eine Flagge sein.
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x >= 0 and _occ(n.x, n.y) == OBJ_FLAG:
			return false
	return true


func place_flag(x: int, y: int, owner := 0) -> Flag:
	# Flagge auf eine bestehende Straße setzen → Straße an dieser Stelle teilen.
	if _occ(x, y) == OBJ_ROAD:
		return _split_road_with_flag(x, y, owner)
	if not can_place_flag(x, y, owner):
		return null
	return _add_flag(x, y, owner)


func ensure_flag(x: int, y: int, owner := 0) -> Flag:
	var i := map.idx(x, y)
	if flags.has(i):
		flags[i].owner = owner
		return flags[i]
	if not map.in_bounds(x, y) or _occ(x, y) != OBJ_NONE:
		return null
	return _add_flag(x, y, owner)


func _add_flag(x: int, y: int, owner := 0) -> Flag:
	var f := Flag.new()
	f.pos = Vector2i(x, y)
	f.id = _next_flag_id
	f.owner = owner
	_next_flag_id += 1
	var i := map.idx(x, y)
	flags[i] = f
	occupied[i] = OBJ_FLAG
	_reveal(Vector2i(x, y), REVEAL_FLAG)  # inkrementell aufdecken (Issue #30)
	return f


## Teilt die Straße, die durch (x,y) läuft, in zwei Straßen mit neuer Flagge.
func _split_road_with_flag(x: int, y: int, owner := 0) -> Flag:
	var pos := Vector2i(x, y)
	# Abstandsregel: nicht direkt neben eine andere Flagge.
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x >= 0 and _occ(n.x, n.y) == OBJ_FLAG:
			return null
	var road: Road = null
	var k := -1
	for r in roads:
		var idxp := r.nodes.find(pos)
		if idxp > 0 and idxp < r.nodes.size() - 1:
			road = r
			k = idxp
			break
	if road == null:
		return null
	var f := _add_flag(x, y, owner)  # setzt occupied[pos] = OBJ_FLAG

	var r1 := Road.new()
	r1.nodes = road.nodes.slice(0, k + 1)
	r1.a = road.a
	r1.b = pos
	r1.owner = road.owner
	r1.traffic = road.traffic / 2
	r1.level = road.level
	var r2 := Road.new()
	r2.nodes = road.nodes.slice(k)
	r2.a = pos
	r2.b = road.b
	r2.owner = road.owner
	r2.traffic = road.traffic / 2
	r2.level = road.level

	roads.erase(road)
	roads.append(r1)
	roads.append(r2)
	invalidate_routes()  # Graph/Routen-Cache verwerfen (#30)
	# Teilung vormerken, damit die Economy den bestehenden Träger erhalten kann.
	splits.append({ old = road, r1 = r1, r2 = r2, k = k })
	return f


func flag_at(pos: Vector2i) -> Flag:
	return flags.get(map.idx(pos.x, pos.y), null)


# --------------------------------------------------------------------------
#  Gebäude
# --------------------------------------------------------------------------

## S2-Regel: ein Militärgebäude darf nicht zu dicht an einem anderen
## Militärgebäude/HQ stehen — egal welchem Spieler es gehört. Das verhindert,
## dass ein Gegner direkt an ein etabliertes Militärgebäude baut und dessen
## Kerngebiet schluckt; Bauten in Richtung Grenze bleiben erlaubt.
func military_placement_clear(x: int, y: int) -> bool:
	var here := Vector2i(x, y)
	for i in buildings:
		var b: Building = buildings[i]
		if not (b.is_hq or b.influence > 0):
			continue
		if hex_distance(here, b.pos) < MILITARY_MIN_DIST:
			return false
	return true


func can_place_building(x: int, y: int, size: int, owner := 0, influence := 0) -> bool:
	if not has_building_territory_margin_for(owner, x, y):
		return false
	if _occ(x, y) != OBJ_NONE:
		return false
	# Militärgebäude (influence > 0) brauchen S2-Mindestabstand zu jedem
	# Militärgebäude/HQ; Wirtschaftsgebäude (influence 0) sind davon frei.
	if influence > 0 and not military_placement_clear(x, y):
		return false
	# Eingangsflagge unten rechts muss frei oder schon eine Flagge sein.
	var se := map.neighbor(x, y, Grid.SE)
	if se.x < 0:
		return false
	if not has_building_territory_margin_for(owner, se.x, se.y):
		return false
	if _occ(se.x, se.y) != OBJ_FLAG and not can_place_flag(se.x, se.y, owner):
		return false
	if size == BQ_MINE:
		if compute_bq(x, y) != BQ_MINE:
			return false
		# Minen nicht direkt neben anderen Gebäuden.
		for dir in Grid.DIRS:
			var n := map.neighbor(x, y, dir)
			if n.x >= 0 and _occ(n.x, n.y) == OBJ_BUILDING:
				return false
		return true
	# Normale Gebäude: effektive BQ (mit Nachbar-Abstand) muss reichen.
	var ebq := effective_bq(x, y)
	if ebq == BQ_MINE or ebq < size:
		return false
	return true


## Bauhilfe: was ist an diesem Knoten wirklich baubar, inkl. Gebiet/Flaggenregel?
func actual_build_spot_bq(x: int, y: int) -> int:
	if can_place_building(x, y, BQ_CASTLE):
		return BQ_CASTLE
	if can_place_building(x, y, BQ_HOUSE):
		return BQ_HOUSE
	if can_place_building(x, y, BQ_HUT):
		return BQ_HUT
	if can_place_building(x, y, BQ_MINE):
		return BQ_MINE
	if can_place_flag(x, y):
		return BQ_FLAG
	return BQ_NOTHING


func place_building(x: int, y: int, size: int, is_hq := false,
		def_id := "", influence := 0, under_construction := true, owner := 0) -> Building:
	if not can_place_building(x, y, size, owner, influence):
		return null
	var se := map.neighbor(x, y, Grid.SE)
	if _occ(se.x, se.y) != OBJ_FLAG:
		# Beim HQ darf die Eingangsflagge auch ohne Territorium gesetzt werden.
		ensure_flag(se.x, se.y, owner)
	else:
		var f := flag_at(se)
		if f != null:
			f.owner = owner
	var b := Building.new()
	b.pos = Vector2i(x, y)
	b.size = size
	b.flag_pos = se
	b.is_hq = is_hq
	b.def_id = def_id
	b.influence = influence
	b.under_construction = under_construction
	b.owner = owner
	var i := map.idx(x, y)
	buildings[i] = b
	occupied[i] = OBJ_BUILDING
	reserve_building_extensions(b)
	if owner == 0:
		_reveal(b.pos, REVEAL_BUILDING)  # inkrementell aufdecken (Issue #30)
	return b


## S2: große Gebäude (Burg/HQ) belegen zusätzlich ihre 3 Extension-Knoten oben-
## links (W/NW/NE). Reserviert die freien davon als belegt und merkt sie am
## Gebäude (für den Abriss). Idempotent — kann nach Laden erneut aufgerufen werden.
func reserve_building_extensions(b: Building) -> void:
	b.ext_nodes.clear()
	if b.size != BQ_CASTLE:
		return
	for dir in [Grid.W, Grid.NW, Grid.NE]:
		var e := map.neighbor(b.pos.x, b.pos.y, dir)
		if e.x < 0:
			continue
		var ei := map.idx(e.x, e.y)
		if occupied.get(ei, OBJ_NONE) == OBJ_NONE:
			occupied[ei] = OBJ_BUILDING
			b.ext_nodes.append(e)


func building_at(pos: Vector2i) -> Building:
	return buildings.get(map.idx(pos.x, pos.y), null)


# --------------------------------------------------------------------------
#  Abriss
# --------------------------------------------------------------------------

## Entfernt, was an [param pos] liegt (Gebäude, Flagge inkl. angeschlossener
## Straßen, oder eine Straße über ihren Zwischenknoten). Liefert true bei Erfolg.
func remove_at(pos: Vector2i) -> bool:
	var i := map.idx(pos.x, pos.y)
	if buildings.has(i):
		for e in buildings[i].ext_nodes:
			occupied.erase(map.idx(e.x, e.y))
		buildings.erase(i)
		occupied.erase(i)
		return true
	if flags.has(i):
		# HQ-Flagge oder Gebäude-Eingangsflagge nicht einzeln entfernbar.
		for bi in buildings:
			if buildings[bi].flag_pos == pos:
				return false
		_remove_roads_touching(pos)
		flags.erase(i)
		occupied.erase(i)
		return true
	# Straße über einen Zwischenknoten treffen?
	for r in roads:
		if pos != r.a and pos != r.b and r.nodes.has(pos):
			_remove_road(r)
			return true
	return false


func _remove_roads_touching(flag_pos: Vector2i) -> void:
	var to_remove: Array[Road] = []
	for r in roads:
		if r.a == flag_pos or r.b == flag_pos:
			to_remove.append(r)
	for r in to_remove:
		_remove_road(r)


func _remove_road(r: Road) -> void:
	for k in range(1, r.nodes.size() - 1):
		occupied.erase(map.idx(r.nodes[k].x, r.nodes[k].y))
	roads.erase(r)
	invalidate_routes()  # Graph/Routen-Cache verwerfen (#30)


# --------------------------------------------------------------------------
#  Straßen — Auto-Pfad (A*) zwischen einer Flagge und einem Zielknoten
# --------------------------------------------------------------------------

const ROAD_SEARCH_CAP := 6000   # max. A*-Knoten beim Straßenplanen (Freeze-Schutz)


## Mittlere/große Gebäude bekommen einen Straßen-Sperrkranz, damit Wege nicht
## sichtbar durch den Sprite-Fuß laufen. Kleine Hütten blocken nur ihren Knoten.
func _building_blocks_road_margin(b: Building) -> bool:
	return b.size >= BQ_HOUSE or b.is_hq


## Ist dieser freie Knoten für Straßen durch einen nahen Gebäude-Fuß blockiert?
## Die Eingangsflagge selbst ist OBJ_FLAG (kein Gebäude) und bleibt nutzbar.
func road_margin_blocked(x: int, y: int) -> bool:
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x < 0:
			continue
		var b: Building = buildings.get(map.idx(n.x, n.y), null)
		if b != null and _building_blocks_road_margin(b):
			return true
	return false


func _adjacent_to_building(x: int, y: int) -> bool:
	return road_margin_blocked(x, y)


func can_place_road_flag(x: int, y: int, owner := 0) -> bool:
	if not map.in_bounds(x, y) or _occ(x, y) != OBJ_ROAD:
		return false
	var area := owner_territory(owner)
	if not area.is_empty() and not in_owner_territory(owner, x, y):
		return false
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x >= 0 and _occ(n.x, n.y) == OBJ_FLAG:
			return false
	var pos := Vector2i(x, y)
	for r in roads:
		var k := r.nodes.find(pos)
		if k > 0 and k < r.nodes.size() - 1:
			return true
	return false


## Plant eine Straße von [param from] (muss eine Flagge sein) nach [param to].
## Liefert die Knotenfolge inkl. Endpunkten, oder leeres Array wenn unmöglich.
## Optimales A* mit Binär-Heap (siehe [method _heap_pop]) — schnell genug, dass
## Vorschau und Bau denselben Pfad liefern (kein gewichtetes „fast"-A* mehr nötig).
func plan_road(from: Vector2i, to: Vector2i, owner := -1) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var start_flag := flag_at(from)
	if start_flag == null:
		return empty
	var road_owner := start_flag.owner if owner < 0 else owner
	if from == to:
		return empty
	if not map.in_bounds(to.x, to.y) or not node_walkable(to.x, to.y):
		return empty

	# A* über begehbare, freie Knoten. Endpunkt darf eine Flagge sein.
	var start_i := map.idx(from.x, from.y)
	var goal_i := map.idx(to.x, to.y)
	var cap := ROAD_SEARCH_CAP

	var came_from := {}
	var g := { start_i: 0.0 }
	# Open-Set als Binär-Min-Heap mit Lazy-Deletion: Einträge sind [f, idx];
	# veraltete (mit größerem g neu eingereihte) Einträge werden beim Pop
	# übersprungen. O(n log n) statt O(n²) — dadurch ist optimales A* schnell genug.
	var heap: Array = []
	_heap_push(heap, _heuristic(from, to), start_i)
	var closed := {}
	var iter := 0

	while not heap.is_empty():
		var cur_i: int = _heap_pop(heap)[1]
		if closed.has(cur_i):
			continue
		closed[cur_i] = true
		# Sicherung gegen Endlos-/Komplettsuche (z. B. unerreichbares Ziel über
		# Wasser): sonst durchsucht A* die GANZE Karte → ~1 s Freeze beim Ziehen.
		iter += 1
		if iter > cap:
			return empty
		var cur := Vector2i(cur_i % map.width, cur_i / map.width)
		if cur_i == goal_i:
			return _reconstruct(came_from, cur_i)

		for dir in Grid.DIRS:
			var n := map.neighbor(cur.x, cur.y, dir)
			if n.x < 0:
				continue
			var ni := map.idx(n.x, n.y)
			if has_object(n.x, n.y):
				continue
			if ni != goal_i:
				# Zwischenknoten müssen begehbar UND frei sein.
				if not node_walkable(n.x, n.y) or _occ(n.x, n.y) != OBJ_NONE:
					continue
				var area := owner_territory(road_owner)
				if not area.is_empty() and not in_owner_territory(road_owner, n.x, n.y):
					continue
				# Straßen laufen nicht direkt an mittleren/großen Gebäuden entlang,
				# sonst kreuzen sie sichtbar den Sprite-Fußabdruck.
				if road_margin_blocked(n.x, n.y):
					continue
			else:
				# Ziel: begehbar; entweder frei (neue Flagge) oder bestehende Flagge.
				if not node_walkable(n.x, n.y):
					continue
				var occ := _occ(n.x, n.y)
				if occ != OBJ_NONE and occ != OBJ_FLAG:
					continue
				var area := owner_territory(road_owner)
				if occ == OBJ_NONE and not area.is_empty() \
						and not in_owner_territory(road_owner, n.x, n.y):
					continue
			var tentative: float = g[cur_i] + 1.0
			if tentative < float(g.get(ni, INF)):
				came_from[ni] = cur_i
				g[ni] = tentative
				_heap_push(heap, tentative + _heuristic(n, to), ni)

	return empty


func can_build_road(from: Vector2i, to: Vector2i, owner := -1) -> bool:
	return not plan_road(from, to, owner).is_empty()


## Baut die geplante Straße. Erzeugt am Ziel bei Bedarf eine Flagge.
func build_road(from: Vector2i, to: Vector2i, owner := -1) -> Road:
	var start_flag := flag_at(from)
	if start_flag == null:
		return null
	var road_owner := start_flag.owner if owner < 0 else owner
	var path := plan_road(from, to, road_owner)
	if path.is_empty():
		return null
	var end := path[path.size() - 1]
	if flag_at(end) == null:
		if place_flag(end.x, end.y, road_owner) == null:
			return null
	else:
		flag_at(end).owner = road_owner
	var r := Road.new()
	r.nodes = path
	r.a = from
	r.b = end
	r.owner = road_owner
	# Zwischenknoten als Straße markieren (Endpunkte bleiben Flaggen).
	for k in range(1, path.size() - 1):
		occupied[map.idx(path[k].x, path[k].y)] = OBJ_ROAD
	for n in path:
		_reveal(n, REVEAL_ROAD)  # inkrementell aufdecken (Issue #30)
	roads.append(r)
	invalidate_routes()  # Graph/Routen-Cache verwerfen (#30)
	return r


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Weltabstand / Kachelbreite ist zulässig (unterschätzt nie).
	var wa := Grid.node_to_world(a.x, a.y, 0)
	var wb := Grid.node_to_world(b.x, b.y, 0)
	return wa.distance_to(wb) / Grid.TILE_W


# --- Binär-Min-Heap für A* (Einträge: [f: float, idx: int]) ---------------

func _heap_push(heap: Array, f: float, idx: int) -> void:
	heap.append([f, idx])
	var c := heap.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if heap[p][0] <= heap[c][0]:
			break
		var tmp = heap[p]; heap[p] = heap[c]; heap[c] = tmp
		c = p


func _heap_pop(heap: Array) -> Array:
	var top = heap[0]
	var last = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var n := heap.size()
		var c := 0
		while true:
			var l := 2 * c + 1
			var r := 2 * c + 2
			var smallest := c
			if l < n and heap[l][0] < heap[smallest][0]:
				smallest = l
			if r < n and heap[r][0] < heap[smallest][0]:
				smallest = r
			if smallest == c:
				break
			var tmp = heap[smallest]; heap[smallest] = heap[c]; heap[c] = tmp
			c = smallest
	return top


## Linearer Pop für den kleinen Flaggen-Graph in [method find_route] (wenige
## Knoten — hier lohnt der Heap nicht). [param open] = idx -> Distanz.
func _pop_lowest(open: Dictionary) -> int:
	var best_i := -1
	var best_f := INF
	for i in open:
		if open[i] < best_f:
			best_f = open[i]
			best_i = i
	open.erase(best_i)
	return best_i


func _reconstruct(came_from: Dictionary, cur_i: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	while true:
		out.push_front(Vector2i(cur_i % map.width, cur_i / map.width))
		if not came_from.has(cur_i):
			break
		cur_i = came_from[cur_i]
	return out


# --------------------------------------------------------------------------
#  Pfadfindung über das Flaggen-/Straßennetz (Dijkstra)
# --------------------------------------------------------------------------

## Verwirft den gecachten Flaggengraphen und alle gemerkten Routen. MUSS nach jeder
## strukturellen Straßenänderung aufgerufen werden (siehe Cache-Felder oben). Billig:
## der Graph wird beim nächsten find_route() faul neu gebaut.
func invalidate_routes() -> void:
	_flag_graph_dirty = true
	_route_cache.clear()


## Liefert den (gecachten) Flaggen-/Straßengraphen; baut ihn nur neu, wenn seit der
## letzten Straßenänderung als veraltet markiert.
func _get_flag_graph() -> Dictionary:
	if _flag_graph_dirty:
		_flag_graph_cache = _build_flag_graph()
		_flag_graph_dirty = false
	return _flag_graph_cache


## Kürzeste Route über das Straßennetz. Liefert die Folge der Flaggen-Knoten,
## oder leeres Array wenn nicht verbunden. Ergebnis ist gecacht (#30) — der Aufrufer
## darf das zurückgegebene Array behandeln, als wäre es nur lesbar (es ist eine Kopie).
func find_route(from_flag: Vector2i, to_flag: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if flag_at(from_flag) == null or flag_at(to_flag) == null:
		return empty

	var start := map.idx(from_flag.x, from_flag.y)
	var goal := map.idx(to_flag.x, to_flag.y)
	var key := Vector2i(start, goal)
	if _route_cache.has(key):
		var hit: Array[Vector2i] = _route_cache[key]
		return hit.duplicate()

	var adj := _get_flag_graph()
	var dist := { start: 0.0 }
	var prev := {}
	var open := { start: 0.0 }

	while not open.is_empty():
		var cur := _pop_lowest(open)
		if cur == goal:
			break
		for edge in adj.get(cur, []):
			var nd: float = dist[cur] + edge.cost
			if nd < float(dist.get(edge.to, INF)):
				dist[edge.to] = nd
				prev[edge.to] = cur
				open[edge.to] = nd

	# Auch das "nicht verbunden"-Ergebnis cachen, damit wiederholte Fehlanfragen
	# (z. B. noch nicht ans Netz angeschlossene Baustellen pro Tick) nicht jedes Mal
	# eine volle Dijkstra-Suche auslösen.
	var out: Array[Vector2i] = []
	if dist.has(goal):
		var c: int = goal
		while true:
			out.push_front(Vector2i(c % map.width, c / map.width))
			if c == start:
				break
			c = prev[c]
	_route_cache[key] = out
	return out.duplicate()


func _build_flag_graph() -> Dictionary:
	var adj := {}
	for r in roads:
		var ai := map.idx(r.a.x, r.a.y)
		var bi := map.idx(r.b.x, r.b.y)
		var cost := float(r.length())
		adj.get_or_add(ai, []).append({ to = bi, cost = cost })
		adj.get_or_add(bi, []).append({ to = ai, cost = cost })
	return adj
