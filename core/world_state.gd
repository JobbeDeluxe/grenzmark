class_name WorldState
extends RefCounted

## Der gesamte veränderliche Spielzustand: Karte + Flaggen + Straßen + Gebäude.
## Enthält die Bau-Regeln (BauQualität) und die Pfadfindung. Reine Logik,
## kennt Godot nicht.

# BauQualität eines Knotens (aufsteigend). MINE ist ein Sonderfall daneben.
enum { BQ_NOTHING, BQ_FLAG, BQ_HUT, BQ_HOUSE, BQ_CASTLE, BQ_MINE }

# Was auf einem Knoten liegt.
enum { OBJ_NONE, OBJ_FLAG, OBJ_BUILDING, OBJ_ROAD }


class Flag:
	extends RefCounted
	var pos: Vector2i
	var id: int


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
	var owner := 0       # 0 = Spieler, 1 = Gegner


class Road:
	extends RefCounted
	var nodes: Array[Vector2i] = []   # Knotenfolge inkl. beider Flaggen
	var a: Vector2i
	var b: Vector2i
	func length() -> int:
		return nodes.size() - 1


var map: MapData
var flags: Dictionary = {}      # idx -> Flag
var buildings: Dictionary = {}  # idx -> Building
var roads: Array[Road] = []
var occupied: Dictionary = {}   # idx -> OBJ_*
var territory: Dictionary = {}        # idx -> true (Spieler-Gebiet, Besitzer 0)
var enemy_territory: Dictionary = {}  # idx -> true (Gegner-Gebiet, Besitzer 1)
var explored: Dictionary = {}         # idx -> true (vom Spieler aufgedeckt)

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


## Sichtbarkeit: deckt Knoten rund um eigene Gebäude/Flaggen/Straßen auf.
## Aufgedecktes bleibt aufgedeckt (wie in S2 die erkundete Karte).
func recompute_visibility() -> void:
	for i in buildings:
		var b: Building = buildings[i]
		if b.owner == 0:
			_reveal(b.pos, 7)
	for i in flags:
		_reveal(flags[i].pos, 5)
	for r in roads:
		for n in r.nodes:
			_reveal(n, 3)


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


## Neu berechnen: jeder Knoten gehört dem Besitzer des NÄCHSTEN einflussreichen
## Gebäudes (HQ oder besetztes Militärgebäude). Getrennt für Spieler/Gegner.
func recompute_territory() -> void:
	territory.clear()
	enemy_territory.clear()
	var claim := {}  # idx -> { dist, owner }
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
				var cur = claim.get(k)
				if cur == null or d < cur.dist:
					claim[k] = { dist = d, owner = b.owner }
	for k in claim:
		if claim[k].owner == 0:
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


## Effektive BauQualität: Terrain-Potenzial, durch belegte Knoten und benachbarte
## Gebäude reduziert. Wie in S2 brauchen große Gebäude mehr freien Platz —
## direkt neben einem Gebäude geht nur eine Flagge, zwei Felder daneben höchstens
## ein mittleres Haus. So „verkleinern" sich die Bauplätze neben großen Gebäuden.
func effective_bq(x: int, y: int) -> int:
	var bq := compute_bq(x, y)
	if bq == BQ_NOTHING:
		return BQ_NOTHING
	if _occ(x, y) != OBJ_NONE:
		return BQ_NOTHING
	if bq == BQ_FLAG:
		return BQ_FLAG
	var cap := bq
	for i in buildings:
		var b: Building = buildings[i]
		var d := hex_distance(Vector2i(x, y), b.pos)
		if d == 0:
			return BQ_NOTHING
		elif d == 1:
			cap = mini(cap, BQ_FLAG)        # direkt daneben: nur Flagge
		elif d == 2:
			cap = mini(cap, BQ_HOUSE)       # nah dran: höchstens mittleres Haus
	return cap


# --------------------------------------------------------------------------
#  Flaggen
# --------------------------------------------------------------------------

func can_place_flag(x: int, y: int) -> bool:
	if compute_bq(x, y) < BQ_FLAG:
		return false
	if not territory.is_empty() and not in_territory(x, y):
		return false
	if _occ(x, y) != OBJ_NONE:
		return false
	# Abstandsregel: kein direkter Nachbar darf eine Flagge sein.
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x >= 0 and _occ(n.x, n.y) == OBJ_FLAG:
			return false
	return true


func place_flag(x: int, y: int) -> Flag:
	# Flagge auf eine bestehende Straße setzen → Straße an dieser Stelle teilen.
	if _occ(x, y) == OBJ_ROAD:
		return _split_road_with_flag(x, y)
	if not can_place_flag(x, y):
		return null
	return _add_flag(x, y)


func _add_flag(x: int, y: int) -> Flag:
	var f := Flag.new()
	f.pos = Vector2i(x, y)
	f.id = _next_flag_id
	_next_flag_id += 1
	var i := map.idx(x, y)
	flags[i] = f
	occupied[i] = OBJ_FLAG
	return f


## Teilt die Straße, die durch (x,y) läuft, in zwei Straßen mit neuer Flagge.
func _split_road_with_flag(x: int, y: int) -> Flag:
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
	var f := _add_flag(x, y)  # setzt occupied[pos] = OBJ_FLAG

	var r1 := Road.new()
	r1.nodes = road.nodes.slice(0, k + 1)
	r1.a = road.a
	r1.b = pos
	var r2 := Road.new()
	r2.nodes = road.nodes.slice(k)
	r2.a = pos
	r2.b = road.b

	roads.erase(road)
	roads.append(r1)
	roads.append(r2)
	return f


func flag_at(pos: Vector2i) -> Flag:
	return flags.get(map.idx(pos.x, pos.y), null)


# --------------------------------------------------------------------------
#  Gebäude
# --------------------------------------------------------------------------

func can_place_building(x: int, y: int, size: int) -> bool:
	if not territory.is_empty() and not in_territory(x, y):
		return false
	if _occ(x, y) != OBJ_NONE:
		return false
	# Eingangsflagge unten rechts muss frei oder schon eine Flagge sein.
	var se := map.neighbor(x, y, Grid.SE)
	if se.x < 0:
		return false
	if _occ(se.x, se.y) != OBJ_FLAG and not can_place_flag(se.x, se.y):
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


func place_building(x: int, y: int, size: int, is_hq := false,
		def_id := "", influence := 0, under_construction := true, owner := 0) -> Building:
	if not can_place_building(x, y, size):
		return null
	var se := map.neighbor(x, y, Grid.SE)
	if _occ(se.x, se.y) != OBJ_FLAG:
		# Beim HQ darf die Eingangsflagge auch ohne Territorium gesetzt werden.
		place_flag(se.x, se.y)
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
	return b


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


# --------------------------------------------------------------------------
#  Straßen — Auto-Pfad (A*) zwischen einer Flagge und einem Zielknoten
# --------------------------------------------------------------------------

## Plant eine Straße von [param from] (muss eine Flagge sein) nach [param to].
## Liefert die Knotenfolge inkl. Endpunkten, oder leeres Array wenn unmöglich.
func plan_road(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if flag_at(from) == null:
		return empty
	if from == to:
		return empty
	if not map.in_bounds(to.x, to.y) or not node_walkable(to.x, to.y):
		return empty

	# A* über begehbare, freie Knoten. Endpunkt darf eine Flagge sein.
	var start_i := map.idx(from.x, from.y)
	var goal_i := map.idx(to.x, to.y)

	var came_from := {}
	var g := { start_i: 0.0 }
	var open := { start_i: _heuristic(from, to) }  # idx -> f-Wert

	while not open.is_empty():
		var cur_i := _pop_lowest(open)
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
			else:
				# Ziel: begehbar; entweder frei (neue Flagge) oder bestehende Flagge.
				if not node_walkable(n.x, n.y):
					continue
				var occ := _occ(n.x, n.y)
				if occ != OBJ_NONE and occ != OBJ_FLAG:
					continue
			var tentative: float = g[cur_i] + 1.0
			if tentative < float(g.get(ni, INF)):
				came_from[ni] = cur_i
				g[ni] = tentative
				open[ni] = tentative + _heuristic(n, to)

	return empty


func can_build_road(from: Vector2i, to: Vector2i) -> bool:
	return not plan_road(from, to).is_empty()


## Baut die geplante Straße. Erzeugt am Ziel bei Bedarf eine Flagge.
func build_road(from: Vector2i, to: Vector2i) -> Road:
	var path := plan_road(from, to)
	if path.is_empty():
		return null
	var end := path[path.size() - 1]
	if flag_at(end) == null:
		if place_flag(end.x, end.y) == null:
			return null
	var r := Road.new()
	r.nodes = path
	r.a = from
	r.b = end
	# Zwischenknoten als Straße markieren (Endpunkte bleiben Flaggen).
	for k in range(1, path.size() - 1):
		occupied[map.idx(path[k].x, path[k].y)] = OBJ_ROAD
	roads.append(r)
	return r


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Weltabstand / Kachelbreite ist zulässig (unterschätzt nie).
	var wa := Grid.node_to_world(a.x, a.y, 0)
	var wb := Grid.node_to_world(b.x, b.y, 0)
	return wa.distance_to(wb) / Grid.TILE_W


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

## Kürzeste Route über das Straßennetz. Liefert die Folge der Flaggen-Knoten,
## oder leeres Array wenn nicht verbunden.
func find_route(from_flag: Vector2i, to_flag: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if flag_at(from_flag) == null or flag_at(to_flag) == null:
		return empty

	var adj := _build_flag_graph()
	var start := map.idx(from_flag.x, from_flag.y)
	var goal := map.idx(to_flag.x, to_flag.y)

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

	if not dist.has(goal):
		return empty

	var out: Array[Vector2i] = []
	var c: int = goal
	while true:
		out.push_front(Vector2i(c % map.width, c / map.width))
		if c == start:
			break
		c = prev[c]
	return out


func _build_flag_graph() -> Dictionary:
	var adj := {}
	for r in roads:
		var ai := map.idx(r.a.x, r.a.y)
		var bi := map.idx(r.b.x, r.b.y)
		var cost := float(r.length())
		adj.get_or_add(ai, []).append({ to = bi, cost = cost })
		adj.get_or_add(bi, []).append({ to = ai, cost = cost })
	return adj
