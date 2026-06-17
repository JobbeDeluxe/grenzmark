class_name MapGenerator
extends RefCounted

## Prozeduraler Karten-Generator. Deterministisch über den Seed, damit später
## alle Multiplayer-Clients dieselbe Karte erzeugen.

const TERRAIN_CLEANUP_PASSES := 2
const STONE_CLUSTER_AREA := 1400
const MAP_GENERATOR_VERSION := "grenzmark-map-v4"
const MOUNTAIN_MEADOW_PATCH_AREA := 1800
const MOUNTAIN_MEADOW_RADIUS := 2
const MOUNTAIN_MEADOW_MIN_SEPARATION := 10

# Höhenrelief (#50): Die Höhen waren mit Amplitude ~24 zu flach gestaucht — Land lag
# fast nur bei Nachbar-Höhendiff <=1, kaum Hütte/Haus-Plätze, Planierer (#49) ohne
# sichtbare Arbeit. HEIGHT_SCALE dehnt das Relief (näher an RTTRs Höhenskala, sodass
# die absoluten BQ-Schwellen 1/2/3 wieder passen) und skaliert die Terrain-Bänder
# proportional mit, damit die Terrain-Anteile (Wiese/Berg/…) gleich bleiben.
const HEIGHT_SCALE := 1.8
const LAND_AMP := 24.0 * HEIGHT_SCALE        # Grundland-Amplitude (vorher 24)
const H_WATER_MAX := 3.0 * HEIGHT_SCALE      # darunter Wasser
const H_SAND_MAX := 5.0 * HEIGHT_SCALE       # darunter Sand
const H_MEADOW_MAX := 17.0 * HEIGHT_SCALE    # darunter Wiese
const H_MOUNTAIN_MAX := 24.0 * HEIGHT_SCALE  # Referenz für Bergwiesen-Plateauhöhe
const H_SNOW_MIN := 33.0 * HEIGHT_SCALE      # darüber Schnee/Fels — nur echte Gipfel
const H_SWAMP_MAX := 11.0 * HEIGHT_SCALE     # niedrige feuchte Wiese → Sumpf
const STEEP_MEADOW_MOUNTAIN_MIN_HEIGHT := 12.0 * HEIGHT_SCALE
const STEEP_MEADOW_MOUNTAIN_SLOPE := 4

# Bodenschätze auf Bergen (#54): RTTR-nahe Verteilung Kohle 40 / Eisen 36 / Granit 15
# / Gold 9. Granit & Gold bekommen eigene Noise-Masken (eigener Seed), weil das
# Value-Noise praktisch nur ~0.25..0.76 erreicht und schwellenbasierte Bänder auf EINER
# Maske die seltenen Erze sonst verhungern lassen (vorher Gold 0 %, Granit ~1 %).
const ORE_DEPOSIT_MIN := 0.32       # darüber Vorkommen — deckt den Großteil der Berge ab
const ORE_AMOUNT_MIN := 3
const ORE_AMOUNT_SPAN := 9          # Menge 3..12, skaliert mit Aderstärke
const ORE_GOLD_THRESHOLD := 0.628   # eigene Maske > Schwelle → Gold-Cluster (~9 %)
const ORE_GRANITE_THRESHOLD := 0.607  # eigene Maske > Schwelle → Granit-Cluster (~15 %)
const ORE_COAL_IRON_SPLIT := 0.478  # Basis-Adern: darunter Kohle, darüber Eisen

# Gebirgs-Aufbau (#50/#51): additive Gipfel statt Plateau-Klemme.
const MOUNTAIN_MASK_MIN := 0.50   # ab diesem Maskenwert beginnt Bergland
const MOUNTAIN_PEAK_EXP := 1.3    # Potenzkurve: konzentriert Höhe Richtung Gipfel
const MOUNTAIN_PEAK_AMP := 65.0   # max. Gipfelanhebung über dem Grundland
const MOUNTAIN_ROUGHNESS := 9.0   # Zerklüftung der Gipfel (feines Detail)

## Erzeugt eine MapData mit Höhen und Terrain.
static func generate(width: int, height: int, seed: int = 12345, options: Dictionary = {}) -> MapData:
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

	# Mittlere Oktave (#50): füllt die Lücke zwischen sehr glattem Basis-Noise (0.06)
	# und feinem Detail (0.18). Ohne sie ist das Land fast flach (Nachbar-Höhendiff
	# meist <=1) — mit ihr entstehen sanft rollende Hügel mit mittleren Hängen (2-3),
	# sodass sich Hütte/Haus/Burg über die Karte real abstufen und der Planierer (#49)
	# sichtbar wird. Gleiches Höhenbudget (Gewichte summieren zu 1) → Terrain-Bänder bleiben.
	var hills := FastNoiseLite.new()
	hills.noise_type = FastNoiseLite.TYPE_VALUE
	hills.seed = seed + 7
	hills.frequency = 0.12

	# Niederfrequente Berg-Maske: erzeugt verlässlich Gebirge (mit Erz). Ridged-Fractal
	# bildet S2-typische Bergketten/Grate mit scharfen Gipfeln statt runder Kuppeln und
	# liefert eine Maske, die bis ~1.0 reicht (Value-Noise blieb zu flach gestaucht).
	var mountain := FastNoiseLite.new()
	mountain.noise_type = FastNoiseLite.TYPE_VALUE
	mountain.seed = seed + 5
	mountain.frequency = 0.045
	mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain.fractal_octaves = 4
	mountain.fractal_gain = 0.5

	# Randabfall zum Wasser hin (Inselform) — sanft, damit viel Land bleibt.
	var cx := width * 0.5
	var cy := height * 0.5
	var max_r := minf(cx, cy)

	for y in height:
		for x in width:
			# Drei Oktaven mischen (Summe der Gewichte = 1 → unverändertes Höhenbudget):
			# großräumige Form (0.06) + rollende Hügel (0.12) + feines Detail (0.18).
			var base_n := noise.get_noise_2d(x, y) * 0.5 + 0.5    # 0..1
			var hill_n := hills.get_noise_2d(x, y) * 0.5 + 0.5
			var det_n := detail.get_noise_2d(x, y) * 0.5 + 0.5
			var n := base_n * 0.55 + hill_n * 0.35 + det_n * 0.10
			var dx := (x - cx) / max_r
			var dy := (y - cy) / max_r
			var dist: float = sqrt(dx * dx + dy * dy)
			var falloff: float = clampf(1.18 - dist, 0.0, 1.0)
			var h: float = n * falloff * LAND_AMP   # Grundland 0..~LAND_AMP
			# Gebirge (#50/#51): NICHT mehr auf ein flaches Plateau klemmen (das erzeugte
			# Berge wie Tafelberge mit Steilkante rundum und flacher Schneefläche). Wie in
			# RTTRs Generator wird die Höhe stattdessen additiv zu echten Gipfeln angehoben:
			# eine Potenzkurve konzentriert die Höhe auf den Maskenkern, sodass die Flanken
			# stetig abfallen (keine Ringklippe) und nur die Spitzen die Schnee-Höhe erreichen.
			if falloff > 0.3:
				var mn: float = mountain.get_noise_2d(x, y) * 0.5 + 0.5
				if mn > MOUNTAIN_MASK_MIN:
					var b: float = (mn - MOUNTAIN_MASK_MIN) / (1.0 - MOUNTAIN_MASK_MIN)  # 0..1
					var peak: float = pow(b, MOUNTAIN_PEAK_EXP) * MOUNTAIN_PEAK_AMP
					# Zerklüftung: feines Detail nur auf Bergen, damit Gipfel keine glatten
					# Kuppeln sind. Mit b skaliert → am Fuß sanft, oben schroff.
					peak += (det_n - 0.5) * MOUNTAIN_ROUGHNESS * b
					h += peak * falloff
			map.set_height(x, y, maxi(0, int(round(h))))

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
	_seed_mountain_meadows(map, node_terrain, seed)
	_paint_node_terrain(map, node_terrain)
	_cleanup_terrain(map)

	_scatter_objects(map, seed, options)
	seed_coastal_fish(map)
	return map


## Stabile String->Seed-Abbildung fuer Spieler-Seeds. Nicht Godots hash() nutzen:
## der Wert muss fuer Savegames/Multiplayer ueber Versionen hinweg nachvollziehbar bleiben.
static func stable_seed_from_string(text: String) -> int:
	var bytes := text.strip_edges().to_utf8_buffer()
	var h := 2166136261  # FNV-1a 32-bit offset basis
	for b in bytes:
		h = int((h ^ int(b)) * 16777619) & 0xffffffff
	return int(h & 0x7fffffff)


# --- Welt-Code (Issue #27) -------------------------------------------------
# Ein teilbarer String buendelt Kartengroesse, Gegnerzahl und den eigentlichen
# Karten-Token: "BxH-G-TOKEN", z. B. "96x96-2-K7P3QZ". Wer den Code eintippt,
# bekommt exakt dieselbe Welt. Groesse/Gegner sind feste Werte VOR dem Token;
# der Token allein steuert das Terrain (Gegnerzahl veraendert die Landschaft nicht).
const DEVMAP_CODE := "DEVMAP"
const WORLD_TOKEN_LEN := 6
# Alphabet ohne verwechselbare Zeichen (kein 0/O/1/I) — leichter abzulesen/zu teilen.
const WORLD_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAP_MIN_DIM := 32
const MAP_MAX_DIM := 512
const MAP_MAX_ENEMIES := 8

## Wuerfelt einen neuen zufaelligen Karten-Token (nur den TOKEN-Teil des Welt-Codes).
static func random_world_token(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var out := ""
	for _i in WORLD_TOKEN_LEN:
		out += WORLD_CODE_ALPHABET[rng.randi() % WORLD_CODE_ALPHABET.length()]
	return out


## Baut den kanonischen Welt-Code aus seinen Teilen.
static func format_world_code(width: int, height: int, enemies: int, token: String) -> String:
	var w := clampi(width, MAP_MIN_DIM, MAP_MAX_DIM)
	var h := clampi(height, MAP_MIN_DIM, MAP_MAX_DIM)
	var e := clampi(enemies, 0, MAP_MAX_ENEMIES)
	var t := token.strip_edges().to_upper()
	if t == "":
		t = random_world_token()
	return "%dx%d-%d-%s" % [w, h, e, t]


## Zerlegt einen eingetippten Welt-Code in seine Teile. Toleranter Parser:
## - "DEVMAP"                -> { devmap = true }
## - "BxH-G-TOKEN"           -> volle Angabe (has_size = true)
## - alles andere ("SIEDLER")-> nur Token, Groesse/Gegner offen (has_size = false)
## Rueckgabe: { devmap, has_size, width, height, enemies, token }
static func parse_world_code(code: String) -> Dictionary:
	var raw := code.strip_edges()
	var result := {
		"devmap": false, "has_size": false,
		"width": 0, "height": 0, "enemies": 0, "token": "",
	}
	if raw.to_upper() == DEVMAP_CODE:
		result.devmap = true
		return result
	var parts := raw.split("-", false)
	if parts.size() >= 3:
		var size_part := String(parts[0]).to_lower()
		var xy := size_part.split("x", false)
		if xy.size() == 2 and String(xy[0]).is_valid_int() and String(xy[1]).is_valid_int() \
				and String(parts[1]).is_valid_int():
			# Token = Rest ab dem dritten Feld (darf weitere "-" enthalten).
			var token := raw.substr(size_part.length() + String(parts[1]).length() + 2)
			result.has_size = true
			result.width = clampi(int(xy[0]), MAP_MIN_DIM, MAP_MAX_DIM)
			result.height = clampi(int(xy[1]), MAP_MIN_DIM, MAP_MAX_DIM)
			result.enemies = clampi(int(parts[1]), 0, MAP_MAX_ENEMIES)
			result.token = token.strip_edges().to_upper()
			return result
	# Kein voller Code -> ganzer String ist der Token.
	result.token = raw.to_upper()
	return result


## Zerlegt eine freie Groessen-Eingabe wie "200x100" oder "96" in WxH (geclamped).
static func parse_size_text(text: String, fallback: Vector2i = Vector2i(96, 96)) -> Vector2i:
	var t := text.strip_edges().to_lower()
	var xy := t.split("x", false)
	if xy.size() == 2 and String(xy[0]).is_valid_int() and String(xy[1]).is_valid_int():
		return Vector2i(clampi(int(xy[0]), MAP_MIN_DIM, MAP_MAX_DIM),
			clampi(int(xy[1]), MAP_MIN_DIM, MAP_MAX_DIM))
	if xy.size() == 1 and String(xy[0]).is_valid_int():
		var d := clampi(int(xy[0]), MAP_MIN_DIM, MAP_MAX_DIM)
		return Vector2i(d, d)
	return fallback


## Endlicher Fischbestand (Issue #6) auf allen Küstenknoten (Knoten mit Wasser UND
## Land im Dreiecksring). Reine Tiefwasserknoten bleiben leer — dort fischt niemand.
## Überschreibt vorhandene Werte nicht (idempotent, auch für nachträglich gegrabene
## Gewässer wie den Test-Teich aufrufbar).
static func seed_coastal_fish(map: MapData) -> void:
	for y in map.height:
		for x in map.width:
			if map.fish_at(x, y) > 0:
				continue
			var has_water := false
			var has_land := false
			for t in map.terrains_around(x, y):
				if Terrain.is_water(t): has_water = true
				else: has_land = true
			if has_water and has_land:
				map.set_fish(x, y, Tuning.fish_per_node())


## Bäume auf Wiesen, Stein-Haufen, Erz in den Bergen — deterministisch.
static func _scatter_objects(map: MapData, seed: int, options: Dictionary = {}) -> void:
	var replace_gold := bool(options.get("replace_gold", false))
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

	# Eigene Masken für die seltenen Erze (#54): so lassen sich Gold/Granit als echte
	# Cluster verteilen, ohne dass sie im gemeinsamen Adern-Noise verhungern.
	var gold_mask := FastNoiseLite.new()
	gold_mask.noise_type = FastNoiseLite.TYPE_VALUE
	gold_mask.seed = seed + 17
	gold_mask.frequency = 0.10
	var granite_mask := FastNoiseLite.new()
	granite_mask.noise_type = FastNoiseLite.TYPE_VALUE
	granite_mask.seed = seed + 19
	granite_mask.frequency = 0.09

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
				# verstecktes Vorkommen. Der Großteil der Berge trägt Erz (S2-nah),
				# die Menge skaliert mit der Aderstärke (endlicher Abbau).
				var dv := deposit.get_noise_2d(x, y) * 0.5 + 0.5
				if dv > ORE_DEPOSIT_MIN:
					var kind := _pick_ore_kind(
						gold_mask.get_noise_2d(x, y) * 0.5 + 0.5,
						granite_mask.get_noise_2d(x, y) * 0.5 + 0.5,
						vein.get_noise_2d(x, y) * 0.5 + 0.5,
						replace_gold)
					var amount := ORE_AMOUNT_MIN + int(
						(dv - ORE_DEPOSIT_MIN) / (1.0 - ORE_DEPOSIT_MIN) * float(ORE_AMOUNT_SPAN))
					map.set_ore_deposit(x, y, kind, amount)
			elif all_meadow:
				var f := forest.get_noise_2d(x, y) * 0.5 + 0.5
				if f > 0.62:
					map.set_map_object(x, y, MapData.MO_TREE)
					map.set_tree_type(x, y, rng.randi_range(0, MapData.TREE_TYPE_COUNT - 1))
				else:
					stone_candidates.append(Vector2i(x, y))
	_place_stone_clusters(map, rng, stone_candidates)


## Erzsorte für einen Bergknoten (#54). Seltene Erze (Gold/Granit) haben eigene Masken
## und bekommen Vorrang als Cluster; sonst Basis-Adern Kohle/Eisen. Zielverteilung
## RTTR-nah: Kohle ~40 / Eisen ~36 / Granit ~15 / Gold ~9 %. `replace_gold` macht das
## Spiel schwerer: Gold-Cluster werden zu Kohle (kein Gold auf der Karte).
static func _pick_ore_kind(gold_v: float, granite_v: float, vein_v: float,
		replace_gold: bool) -> int:
	if gold_v > ORE_GOLD_THRESHOLD:
		return MapData.ORE_COAL if replace_gold else MapData.ORE_GOLD
	if granite_v > ORE_GRANITE_THRESHOLD:
		return MapData.ORE_GRANITE
	return MapData.ORE_COAL if vein_v < ORE_COAL_IRON_SPLIT else MapData.ORE_IRON


static func _classify_node_terrain(map: MapData, wet: FastNoiseLite) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var h := _smoothed_node_height(map, x, y)
			var t: int
			if h < H_WATER_MAX:
				t = Terrain.WATER
			elif h < H_SAND_MAX:
				t = Terrain.SAND
			elif h < H_MEADOW_MAX:
				t = Terrain.MEADOW
			elif h < H_SNOW_MIN:
				t = Terrain.MOUNTAIN
			else:
				t = Terrain.SNOW
			# Hohe, sehr steile Wiesenflanken sind spielerisch Bergkanten:
			# RTTR/S2 stuft direkte Höhendifferenzen > 3 für Gebäude auf
			# Flaggenqualität zurück. Damit die Grafik nicht "Wiese" auf einer
			# Felswand verspricht, malen wir solche Knoten als Berg.
			if t == Terrain.MEADOW and h >= STEEP_MEADOW_MOUNTAIN_MIN_HEIGHT \
					and map.max_slope(x, y) >= STEEP_MEADOW_MOUNTAIN_SLOPE:
				t = Terrain.MOUNTAIN
			if t == Terrain.MEADOW and h < H_SWAMP_MAX and wet != null:
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


static func _seed_mountain_meadows(map: MapData, terrain: PackedByteArray, seed: int) -> void:
	var plateau_noise := FastNoiseLite.new()
	plateau_noise.noise_type = FastNoiseLite.TYPE_VALUE
	plateau_noise.seed = seed + 23
	plateau_noise.frequency = 0.08

	var candidates := []
	var margin := MOUNTAIN_MEADOW_RADIUS + 2
	for y in range(margin, map.height - margin):
		for x in range(margin, map.width - margin):
			var p := Vector2i(x, y)
			if not _mountain_meadow_candidate(map, terrain, p):
				continue
			var score := plateau_noise.get_noise_2d(x, y) * 0.5 + 0.5
			candidates.append({ p = p, score = score })
	candidates.sort_custom(func(a, b): return float(a.score) > float(b.score))

	var target := clampi(int((map.width * map.height) / MOUNTAIN_MEADOW_PATCH_AREA), 1, 12)
	var placed: Array[Vector2i] = []
	for entry in candidates:
		if placed.size() >= target:
			return
		var p: Vector2i = entry.p
		var too_close := false
		for prev in placed:
			if _hex_distance(prev, p) < MOUNTAIN_MEADOW_MIN_SEPARATION:
				too_close = true
				break
		if too_close:
			continue
		_carve_mountain_meadow(map, terrain, p)
		placed.append(p)


static func _mountain_meadow_candidate(map: MapData, terrain: PackedByteArray,
		center: Vector2i) -> bool:
	if int(terrain[map.idx(center.x, center.y)]) != Terrain.MOUNTAIN:
		return false
	var mountain := 0
	var total := 0
	for dy in range(-MOUNTAIN_MEADOW_RADIUS, MOUNTAIN_MEADOW_RADIUS + 1):
		for dx in range(-MOUNTAIN_MEADOW_RADIUS, MOUNTAIN_MEADOW_RADIUS + 1):
			var p := center + Vector2i(dx, dy)
			if _hex_distance(center, p) > MOUNTAIN_MEADOW_RADIUS:
				continue
			if not map.in_bounds(p.x, p.y):
				return false
			var t := int(terrain[map.idx(p.x, p.y)])
			if t == Terrain.WATER or t == Terrain.SAND or t == Terrain.SWAMP:
				return false
			if t == Terrain.MOUNTAIN:
				mountain += 1
			total += 1
	return mountain >= total - 2


static func _carve_mountain_meadow(map: MapData, terrain: PackedByteArray,
		center: Vector2i) -> void:
	var base_height := _mountain_meadow_height(map, center, MOUNTAIN_MEADOW_RADIUS)
	for dy in range(-MOUNTAIN_MEADOW_RADIUS - 1, MOUNTAIN_MEADOW_RADIUS + 2):
		for dx in range(-MOUNTAIN_MEADOW_RADIUS - 1, MOUNTAIN_MEADOW_RADIUS + 2):
			var p := center + Vector2i(dx, dy)
			if not map.in_bounds(p.x, p.y):
				continue
			var d := _hex_distance(center, p)
			if d <= MOUNTAIN_MEADOW_RADIUS:
				var i := map.idx(p.x, p.y)
				var t := int(terrain[i])
				if t == Terrain.MOUNTAIN or t == Terrain.SNOW:
					terrain[i] = Terrain.MOUNTAIN_MEADOW
					map.clear_map_object(p.x, p.y)
					map.set_height(p.x, p.y, base_height)
			elif d == MOUNTAIN_MEADOW_RADIUS + 1:
				var h := map.get_height(p.x, p.y)
				var delta := base_height - h
				if absi(delta) > 2:
					map.set_height(p.x, p.y, h + clampi(delta, -2, 2))


static func _mountain_meadow_height(map: MapData, center: Vector2i, radius: int) -> int:
	var sum := 0
	var count := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := center + Vector2i(dx, dy)
			if map.in_bounds(p.x, p.y) and _hex_distance(center, p) <= radius:
				sum += map.get_height(p.x, p.y)
				count += 1
	var avg := int(round(float(sum) / float(maxi(count, 1))))
	return clampi(avg, int(H_MEADOW_MAX) + 2, int(H_MOUNTAIN_MAX) - 2)


static func _paint_node_terrain(map: MapData, terrain: PackedByteArray) -> void:
	for y in map.height:
		for x in map.width:
			var t := int(terrain[map.idx(x, y)])
			map.set_tri(Vector2i(x, y), Grid.TRI_R, t)
			map.set_tri(Vector2i(x, y), Grid.TRI_D, t)
	for t in [Terrain.MEADOW, Terrain.SWAMP, Terrain.MOUNTAIN, Terrain.MOUNTAIN_MEADOW,
			Terrain.SNOW, Terrain.SAND, Terrain.WATER]:
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
	if avg < H_WATER_MAX:
		t = Terrain.WATER
	elif avg < H_SAND_MAX:
		t = Terrain.SAND
	elif avg < H_MEADOW_MAX:
		t = Terrain.MEADOW
	elif avg < H_SNOW_MIN:
		t = Terrain.MOUNTAIN
	else:
		t = Terrain.SNOW
	# Niedrige, feuchte Wiesen nahe dem Wasser werden zu Sumpf (begehbar, nicht bebaubar).
	if t == Terrain.MEADOW and avg < H_SWAMP_MAX and wet != null:
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
