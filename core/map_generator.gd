class_name MapGenerator
extends RefCounted

## Prozeduraler Karten-Generator. Deterministisch über den Seed, damit später
## alle Multiplayer-Clients dieselbe Karte erzeugen.

const TERRAIN_CLEANUP_PASSES := 2
const STONE_CLUSTER_AREA := 1400

## Erzeugt eine MapData mit Höhen und Terrain.
static func generate(width: int, height: int, seed: int = 12345) -> MapData:
	var map := MapData.new(width, height)

	# --- Höhen: zwei Lagen Value-Noise, deterministisch ---
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.seed = seed
	noise.frequency = 0.06

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_VALUE
	detail.seed = seed + 1
	detail.frequency = 0.18

	# Niederfrequente Berg-Maske: erzeugt verlässlich Gebirge (mit Erz).
	var mountain := FastNoiseLite.new()
	mountain.noise_type = FastNoiseLite.TYPE_VALUE
	mountain.seed = seed + 5
	mountain.frequency = 0.045

	# Randabfall zum Wasser hin (Inselform) — sanft, damit viel Land bleibt.
	var cx := width * 0.5
	var cy := height * 0.5
	var max_r := minf(cx, cy)

	for y in height:
		for x in width:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5         # 0..1
			n += (detail.get_noise_2d(x, y) * 0.5 + 0.5) * 0.25
			n /= 1.25
			var dx := (x - cx) / max_r
			var dy := (y - cy) / max_r
			var dist: float = sqrt(dx * dx + dy * dy)
			var falloff: float = clampf(1.18 - dist, 0.0, 1.0)
			var h := int(n * falloff * 24.0)   # Grundland 0..~24
			# Gebirge: Maske hebt Landflächen in den Berg-/Schnee-Bereich.
			if falloff > 0.3:
				var mn: float = mountain.get_noise_2d(x, y) * 0.5 + 0.5
				if mn > 0.60:
					var boost: float = (mn - 0.60) / 0.40   # 0..1
					h = maxi(h, 18 + int(boost * 12.0))      # 18..30 → Berg/Schnee
			map.set_height(x, y, h)

	# Feuchtigkeits-Maske: niedrige, feuchte Flächen werden Sumpf (nicht bebaubar).
	var wet := FastNoiseLite.new()
	wet.noise_type = FastNoiseLite.TYPE_VALUE
	wet.seed = seed + 11
	wet.frequency = 0.05

	# --- Terrain als S2-naehere Knoten-/Regionenmaske ableiten und dann mit
	# Hex-Brushes auf Dreiecke malen. So entstehen Flaechen statt Zackenketten.
	var node_terrain := _classify_node_terrain(map, wet)
	_smooth_node_terrain(map, node_terrain, 2)
	_apply_shore_ring(map, node_terrain)
	_paint_node_terrain(map, node_terrain)
	_cleanup_terrain(map)

	_scatter_objects(map, seed)
	return map


## Bäume auf Wiesen, Stein-Haufen, Erz in den Bergen — deterministisch.
static func _scatter_objects(map: MapData, seed: int) -> void:
	var forest := FastNoiseLite.new()
	forest.noise_type = FastNoiseLite.TYPE_VALUE
	forest.seed = seed + 2
	forest.frequency = 0.12

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 99

	# Niederfrequente Maske für zusammenhängende Erz-Adern je Sorte.
	var vein := FastNoiseLite.new()
	vein.noise_type = FastNoiseLite.TYPE_VALUE
	vein.seed = seed + 7
	vein.frequency = 0.07

	# Füll-/Adern-Maske für unterirdische Lagerstätten (zusammenhängende Adern).
	var deposit := FastNoiseLite.new()
	deposit.noise_type = FastNoiseLite.TYPE_VALUE
	deposit.seed = seed + 13
	deposit.frequency = 0.09

	var stone_candidates: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			# Knoten gilt als Wiese/Berg, wenn alle umgebenden Dreiecke passen.
			var terr := map.terrains_around(x, y)
			var all_meadow := true
			var all_mountain := true
			for t in terr:
				if t != Terrain.MEADOW: all_meadow = false
				if t != Terrain.MOUNTAIN: all_mountain = false
			if all_mountain:
				# Erz ist UNTERIRDISCH: kein sichtbares Objekt, sondern ein
				# verstecktes Vorkommen. Adern entstehen aus der glatten Maske,
				# die Menge skaliert mit der Aderstärke (endlicher Abbau).
				var dv := deposit.get_noise_2d(x, y) * 0.5 + 0.5
				if dv > 0.55:
					var kind := _ore_kind_for(vein.get_noise_2d(x, y) * 0.5 + 0.5)
					var amount := 3 + int((dv - 0.55) / 0.45 * 7.0)   # 3..10
					map.set_ore_deposit(x, y, kind, amount)
			elif all_meadow:
				var f := forest.get_noise_2d(x, y) * 0.5 + 0.5
				if f > 0.62:
					map.set_map_object(x, y, MapData.MO_TREE)
					map.set_tree_type(x, y, rng.randi_range(0, MapData.TREE_TYPE_COUNT - 1))
				else:
					stone_candidates.append(Vector2i(x, y))
	_place_stone_clusters(map, rng, stone_candidates)


## Erzsorte aus dem Adern-Rauschwert (0..1): Kohle häufig, Gold selten.
static func _ore_kind_for(v: float) -> int:
	if v < 0.42:
		return MapData.ORE_COAL
	elif v < 0.72:
		return MapData.ORE_IRON
	elif v < 0.90:
		return MapData.ORE_GRANITE
	return MapData.ORE_GOLD


static func _classify_node_terrain(map: MapData, wet: FastNoiseLite) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var h := _smoothed_node_height(map, x, y)
			var t: int
			if h < 3.0:
				t = Terrain.WATER
			elif h < 5.0:
				t = Terrain.SAND
			elif h < 17.0:
				t = Terrain.MEADOW
			elif h < 24.0:
				t = Terrain.MOUNTAIN
			else:
				t = Terrain.SNOW
			if t == Terrain.MEADOW and h < 11.0 and wet != null:
				var w: float = wet.get_noise_2d(x, y) * 0.5 + 0.5
				if w > 0.64:
					t = Terrain.SWAMP
			out[map.idx(x, y)] = t
	return out


static func _smooth_node_terrain(map: MapData, terrain: PackedByteArray, passes: int) -> void:
	for pass_i in passes:
		var next := terrain.duplicate()
		for y in map.height:
			for x in map.width:
				var current := int(terrain[map.idx(x, y)])
				if current == Terrain.WATER or current == Terrain.SNOW:
					continue
				var counts := {}
				counts[current] = 2
				for dir in Grid.DIRS:
					var n := map.neighbor(x, y, dir)
					if n.x < 0:
						continue
					var nt := int(terrain[map.idx(n.x, n.y)])
					counts[nt] = int(counts.get(nt, 0)) + 1
				var best := current
				var best_count := int(counts[current])
				for t in counts:
					var c := int(counts[t])
					if c > best_count:
						best = int(t)
						best_count = c
				if best != current and best_count >= 4:
					next[map.idx(x, y)] = best
		for i in terrain.size():
			terrain[i] = next[i]


static func _apply_shore_ring(map: MapData, terrain: PackedByteArray) -> void:
	var next := terrain.duplicate()
	for y in map.height:
		for x in map.width:
			var i := map.idx(x, y)
			var t := int(terrain[i])
			if t == Terrain.WATER or t == Terrain.MOUNTAIN or t == Terrain.SNOW:
				continue
			if _node_neighbor_has_terrain(map, terrain, x, y, Terrain.WATER):
				next[i] = Terrain.SAND
			elif t == Terrain.SAND and not _node_neighbor_has_terrain(map, terrain, x, y, Terrain.WATER):
				next[i] = Terrain.MEADOW
	for i in terrain.size():
		terrain[i] = next[i]


static func _node_neighbor_has_terrain(map: MapData, terrain: PackedByteArray,
		x: int, y: int, wanted: int) -> bool:
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x >= 0 and int(terrain[map.idx(n.x, n.y)]) == wanted:
			return true
	return false


static func _paint_node_terrain(map: MapData, terrain: PackedByteArray) -> void:
	for y in map.height:
		for x in map.width:
			var t := int(terrain[map.idx(x, y)])
			map.set_tri(Vector2i(x, y), Grid.TRI_R, t)
			map.set_tri(Vector2i(x, y), Grid.TRI_D, t)
	for t in [Terrain.MEADOW, Terrain.SWAMP, Terrain.MOUNTAIN, Terrain.SNOW, Terrain.SAND, Terrain.WATER]:
		for y in map.height:
			for x in map.width:
				if int(terrain[map.idx(x, y)]) == t:
					_paint_hex_terrain(map, Vector2i(x, y), t)


static func paint_hex_terrain(map: MapData, center: Vector2i, terrain: int,
		height := -1, clear_objects := true) -> void:
	if not map.in_bounds(center.x, center.y):
		return
	if height >= 0:
		map.set_height(center.x, center.y, height)
	if clear_objects:
		map.clear_map_object(center.x, center.y)
	_paint_hex_terrain(map, center, terrain)


static func _paint_hex_terrain(map: MapData, center: Vector2i, terrain: int) -> void:
	for tri in Grid.triangles_around(center.x, center.y):
		var pos: Vector2i = tri.pos
		if map.in_bounds(pos.x, pos.y):
			map.set_tri(pos, int(tri.kind), terrain)


static func _assign_tri(map: MapData, x: int, y: int, kind: int, wet: FastNoiseLite = null) -> void:
	var corners := Grid.triangle_corners(x, y, kind)
	var valid := true
	for c in corners:
		if not map.in_bounds(c.x, c.y):
			valid = false
			break
	if not valid:
		map.set_tri(Vector2i(x, y), kind, Terrain.WATER)
		return
	var avg := _smoothed_tri_height(map, corners)
	var t: int
	if avg < 3.0:
		t = Terrain.WATER
	elif avg < 5.0:
		t = Terrain.SAND
	elif avg < 17.0:
		t = Terrain.MEADOW
	elif avg < 24.0:
		t = Terrain.MOUNTAIN
	else:
		t = Terrain.SNOW
	# Niedrige, feuchte Wiesen nahe dem Wasser werden zu Sumpf (begehbar, nicht bebaubar).
	if t == Terrain.MEADOW and avg < 11.0 and wet != null:
		var w: float = wet.get_noise_2d(x, y) * 0.5 + 0.5
		if w > 0.64:
			t = Terrain.SWAMP
	map.set_tri(Vector2i(x, y), kind, t)


## Nur die Terrain-Klassifikation wird geglaettet; die echte Hoehenkarte bleibt
## unveraendert, damit Bauplaetze und sichtbare Bergformen stabil bleiben.
static func _smoothed_tri_height(map: MapData, corners: Array) -> float:
	var sum := 0.0
	for c in corners:
		sum += _smoothed_node_height(map, c.x, c.y)
	return sum / float(corners.size())


static func _smoothed_node_height(map: MapData, x: int, y: int) -> float:
	var sum := float(map.get_height(x, y)) * 2.0
	var weight := 2.0
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x < 0:
			continue
		sum += float(map.get_height(n.x, n.y))
		weight += 1.0
	return sum / weight


## Entfernt isolierte Einzel-Dreiecke und kurze Zacken an Terrain-Grenzen.
static func _cleanup_terrain(map: MapData) -> void:
	for pass_i in TERRAIN_CLEANUP_PASSES:
		var next_r := map.terr_r.duplicate()
		var next_d := map.terr_d.duplicate()
		for y in map.height:
			for x in map.width:
				_cleanup_one_tri(map, x, y, Grid.TRI_R, next_r, next_d)
				_cleanup_one_tri(map, x, y, Grid.TRI_D, next_r, next_d)
		map.terr_r = next_r
		map.terr_d = next_d


static func _cleanup_one_tri(map: MapData, x: int, y: int, kind: int,
		next_r: PackedByteArray, next_d: PackedByteArray) -> void:
	var current := map.get_tri(Vector2i(x, y), kind)
	if current == Terrain.SWAMP:
		return
	var counts := {}
	var same := 0
	var total := 0
	for nb in Grid.tri_edge_neighbors(x, y, kind):
		var nt := map.get_tri(nb.pos, int(nb.kind))
		counts[nt] = int(counts.get(nt, 0)) + 1
		if nt == current:
			same += 1
		total += 1
	if total < 3:
		return
	var majority := current
	var majority_count := 0
	for t in counts:
		var c := int(counts[t])
		if c > majority_count:
			majority = int(t)
			majority_count = c
	if majority == current or majority_count < 2:
		return
	if same == 0 or (same == 1 and majority_count == 2):
		var i := map.idx(x, y)
		if kind == Grid.TRI_R:
			next_r[i] = majority
		else:
			next_d[i] = majority


static func _place_stone_clusters(map: MapData, rng: RandomNumberGenerator,
		candidates: Array[Vector2i]) -> void:
	if candidates.is_empty():
		return
	var target := maxi(1, int((map.width * map.height) / STONE_CLUSTER_AREA))
	var placed := 0
	var attempts := target * 12
	for a in attempts:
		if placed >= target:
			return
		var center: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		if map.map_object(center.x, center.y) != -1:
			continue
		if _near_object(map, center, MapData.MO_STONE, 5):
			continue
		var n := _place_one_stone_cluster(map, rng, center)
		if n >= 2:
			placed += 1


static func _place_one_stone_cluster(map: MapData, rng: RandomNumberGenerator,
		center: Vector2i) -> int:
	var radius := rng.randi_range(1, 2)
	var placed := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := Vector2i(center.x + dx, center.y + dy)
			if not map.in_bounds(p.x, p.y):
				continue
			var dist := _hex_distance(center, p)
			if dist > radius:
				continue
			var chance := 1.0 if dist == 0 else (0.78 if dist == 1 else 0.42)
			if rng.randf() > chance:
				continue
			if map.map_object(p.x, p.y) != -1 or not _all_terrain(map, p, Terrain.MEADOW):
				continue
			map.set_map_object(p.x, p.y, MapData.MO_STONE)
			var r := rng.randf()
			var stage := MapData.STONE_BIG
			if r > 0.86:
				stage = MapData.STONE_SMALL
			elif r > 0.58:
				stage = MapData.STONE_MEDIUM
			map.set_stone_stage(p.x, p.y, stage)
			placed += 1
	return placed


static func _near_object(map: MapData, center: Vector2i, obj: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := Vector2i(center.x + dx, center.y + dy)
			if not map.in_bounds(p.x, p.y):
				continue
			if _hex_distance(center, p) <= radius and map.map_object(p.x, p.y) == obj:
				return true
	return false


static func _all_terrain(map: MapData, pos: Vector2i, terrain: int) -> bool:
	for t in map.terrains_around(pos.x, pos.y):
		if t != terrain:
			return false
	return true


static func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x - int((a.y - (a.y & 1)) / 2)
	var bq := b.x - int((b.y - (b.y & 1)) / 2)
	var az := -aq - a.y
	var bz := -bq - b.y
	return int((absi(aq - bq) + absi(a.y - b.y) + absi(az - bz)) / 2)
