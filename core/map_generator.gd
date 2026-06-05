class_name MapGenerator
extends RefCounted

## Prozeduraler Karten-Generator. Deterministisch über den Seed, damit später
## alle Multiplayer-Clients dieselbe Karte erzeugen.

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

	# --- Terrain aus Höhe ableiten (pro Dreieck der Mittelwert der Ecken) ---
	for y in height:
		for x in width:
			_assign_tri(map, x, y, Grid.TRI_R)
			_assign_tri(map, x, y, Grid.TRI_D)

	_scatter_objects(map, seed)
	return map


## Bäume auf Wiesen, Steine vereinzelt, Erz in den Bergen — deterministisch.
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
				if rng.randf() < 0.18:
					map.set_map_object(x, y, MapData.MO_ORE)
					map.set_ore_kind(x, y, _ore_kind_for(vein.get_noise_2d(x, y) * 0.5 + 0.5))
			elif all_meadow:
				var f := forest.get_noise_2d(x, y) * 0.5 + 0.5
				if f > 0.62:
					map.set_map_object(x, y, MapData.MO_TREE)
				elif rng.randf() < 0.03:
					map.set_map_object(x, y, MapData.MO_STONE)


## Erzsorte aus dem Adern-Rauschwert (0..1): Kohle häufig, Gold selten.
static func _ore_kind_for(v: float) -> int:
	if v < 0.42:
		return MapData.ORE_COAL
	elif v < 0.72:
		return MapData.ORE_IRON
	elif v < 0.90:
		return MapData.ORE_GRANITE
	return MapData.ORE_GOLD


static func _assign_tri(map: MapData, x: int, y: int, kind: int) -> void:
	var corners := Grid.triangle_corners(x, y, kind)
	var sum := 0.0
	var valid := true
	for c in corners:
		if not map.in_bounds(c.x, c.y):
			valid = false
			break
		sum += map.get_height(c.x, c.y)
	if not valid:
		map.set_tri(Vector2i(x, y), kind, Terrain.WATER)
		return
	var avg := sum / 3.0
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
	map.set_tri(Vector2i(x, y), kind, t)
