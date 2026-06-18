class_name MapGenerator
extends RefCounted

## Prozeduraler Karten-Generator. Deterministisch über den Seed, damit später
## alle Multiplayer-Clients dieselbe Karte erzeugen.

const TERRAIN_CLEANUP_PASSES := 2
const STONE_CLUSTER_AREA := 1400
const MAP_GENERATOR_VERSION := "grenzmark-map-v6"
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
const SWAMP_WET_MIN := 0.66                   # höhere Feuchte-Schwelle → kleinere Flächen
const SWAMP_WATER_RADIUS := 3                 # Sumpf nur in Ufernähe (Hex-Reichweite)
const STEEP_MEADOW_MOUNTAIN_MIN_HEIGHT := 12.0 * HEIGHT_SCALE
const STEEP_MEADOW_MOUNTAIN_SLOPE := 4

# Bodenschätze auf Bergen (#54): RTTR-nahe Verteilung Kohle 40 / Eisen 36 / Granit 15
# / Gold 9. Granit & Gold bekommen eigene Noise-Masken (eigener Seed), weil das
# Value-Noise praktisch nur ~0.25..0.76 erreicht und schwellenbasierte Bänder auf EINER
# Maske die seltenen Erze sonst verhungern lassen (vorher Gold 0 %, Granit ~1 %).
const ORE_DEPOSIT_MIN := 0.32       # darüber Vorkommen — deckt den Großteil der Berge ab
const ORE_AMOUNT_MIN := 3
const ORE_AMOUNT_SPAN := 9          # Menge 3..12, skaliert mit Aderstärke
# Schwellen für Vollland (v6) nachkalibriert: ohne Inselabfall tragen mehr/andere Berge
# Erz, was Gold/Granit sonst auf ~16/18 % hob → Schwellen angehoben, Ziel weiter 9/15 %.
const ORE_GOLD_THRESHOLD := 0.664   # eigene Maske > Schwelle → Gold-Cluster (~9 %)
const ORE_GRANITE_THRESHOLD := 0.619  # eigene Maske > Schwelle → Granit-Cluster (~15 %)
const ORE_COAL_IRON_SPLIT := 0.478  # Basis-Adern: darunter Kohle, darüber Eisen

# Kartentyp-Modifikatoren (#27).
const ISLAND_LAND_MIN := 0.37     # Kontinentmaske darunter → versinkt Richtung Meer
const ISLAND_LAND_SPAN := 0.05    # Breite des Küsten-Übergangs (schmal = klare Küsten)
const ISLAND_SEA_DEPTH := 12.0    # wie tief Nicht-Insel-Flächen abgesenkt werden
const RIVER_BRANCH_CHANCE := 0.010
# Flussufer (#58): abgestufter Hang statt Klippe. Banken steigen je Knoten um
# RIVER_BANK_RISE Höheneinheiten über RIVER_BANK_WIDTH Knoten hinweg an.
const RIVER_BANK_WIDTH := 3        # Knoten breiter Uferhang beidseits des Betts
const RIVER_BANK_RISE := 1.6       # Höhenanstieg pro Uferknoten (kleiner = sanfter)
# Gewässer-Größe (#58): schmale Gewässer (Flüsse, kleine Teiche) sind kleiner als
# SEA_MIN_SIZE Knoten und bekommen Wiesenufer statt Strand; größere = Meer/See.
const SEA_MIN_SIZE := 48
# Sand fleckenweise (#58, wie Sumpf): Strand nur gebrochen am Meer, plus seltene
# Wüsten-Flecken im Trockenen. Rauschmaske statt durchgehendem Höhenband.
const SAND_PATCH_FREQ := 0.05
const BEACH_PATCH_MIN := 0.50    # Anteil der Meeresküste, der Sand wird (Rest Wiese)
const DESERT_PATCH_MIN := 0.82   # darüber seltener Wüstenfleck (höher = seltener)
const DESERT_WATER_CLEARANCE := 3  # Wüste nur fern von Wasser (Hex-Reichweite)
# Fisch-Teich (#59): hat eine Karte weniger als diesen Wasseranteil, wird mindestens
# ein kleiner Teich eingebrannt, damit es Fischgründe gibt.
const MIN_WATER_FRACTION := 0.012
const POND_RADIUS := 3              # Knoten-Radius der Not-Teiche

# Gebirgs-Aufbau (#50/#51): additive Gipfel statt Plateau-Klemme.
const MOUNTAIN_MASK_MIN := 0.50   # Insel: ab diesem Maskenwert beginnt Bergland
# Vollland (#58): ohne Inselabfall würde fast die halbe Karte zu Gebirge. Höhere Schwelle
# → diskrete Bergketten statt Berg-überall; das rollende Relief (#50) bleibt (kommt aus
# Basis+Hügeln, nicht aus dieser Maske).
const MOUNTAIN_MASK_MIN_INLAND := 0.76
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

	# Kartenform (#58): NUR "insel" bekommt den radialen Randabfall (Archipel). "flach"/
	# "fluss" füllen die Karte mit Land (Wasser nur aus Flüssen/Not-Teich) — der alte
	# globale Abfall ertränkte v. a. breite Karten (256x128 → ~83% Wasser → sah aus wie
	# Inseln statt Flüsse). Pro Achse normiert (dx/cx, dy/cy), damit der Inselabfall vom
	# Seitenverhältnis unabhängig ist; quadratische Inselkarten bleiben wie zuvor (cx==cy).
	var map_type := String(options.get("map_type", DEFAULT_MAP_TYPE)).to_lower()
	var island_shape := map_type == "insel"
	var cx := width * 0.5
	var cy := height * 0.5

	for y in height:
		for x in width:
			# Drei Oktaven mischen (Summe der Gewichte = 1 → unverändertes Höhenbudget):
			# großräumige Form (0.06) + rollende Hügel (0.12) + feines Detail (0.18).
			var base_n := noise.get_noise_2d(x, y) * 0.5 + 0.5    # 0..1
			var hill_n := hills.get_noise_2d(x, y) * 0.5 + 0.5
			var det_n := detail.get_noise_2d(x, y) * 0.5 + 0.5
			var n := base_n * 0.55 + hill_n * 0.35 + det_n * 0.10
			var falloff: float = 1.0
			if island_shape:
				var dx := (x - cx) / cx
				var dy := (y - cy) / cy
				var dist: float = sqrt(dx * dx + dy * dy)
				falloff = clampf(1.18 - dist, 0.0, 1.0)
			var h: float = n * falloff * LAND_AMP   # Grundland 0..~LAND_AMP
			# Gebirge (#50/#51): NICHT mehr auf ein flaches Plateau klemmen (das erzeugte
			# Berge wie Tafelberge mit Steilkante rundum und flacher Schneefläche). Wie in
			# RTTRs Generator wird die Höhe stattdessen additiv zu echten Gipfeln angehoben:
			# eine Potenzkurve konzentriert die Höhe auf den Maskenkern, sodass die Flanken
			# stetig abfallen (keine Ringklippe) und nur die Spitzen die Schnee-Höhe erreichen.
			var mtn_min: float = MOUNTAIN_MASK_MIN if island_shape else MOUNTAIN_MASK_MIN_INLAND
			if falloff > 0.3:
				var mn: float = mountain.get_noise_2d(x, y) * 0.5 + 0.5
				if mn > mtn_min:
					var b: float = (mn - mtn_min) / (1.0 - mtn_min)  # 0..1
					var peak: float = pow(b, MOUNTAIN_PEAK_EXP) * MOUNTAIN_PEAK_AMP
					# Zerklüftung: feines Detail nur auf Bergen, damit Gipfel keine glatten
					# Kuppeln sind. Mit b skaliert → am Fuß sanft, oben schroff.
					peak += (det_n - 0.5) * MOUNTAIN_ROUGHNESS * b
					h += peak * falloff
			map.set_height(x, y, maxi(0, int(round(h))))

	# Kartentyp (#27): Höhen vor der Klassifizierung anpassen. "flach" lässt sie wie sie
	# sind; "insel" senkt Bereiche mit niedriger Kontinentmaske unter den Meeresspiegel
	# (Archipel); "fluss" gräbt gewundene Wasserläufe ein.
	if map_type == "insel":
		_apply_island_mask(map, seed)
	elif map_type == "fluss":
		_carve_rivers(map, seed)

	# Fisch-Teich (#59): garantiert Fischgründe, falls die Karte zu trocken geriet.
	_ensure_fishing_water(map, seed)

	# Feuchtigkeits-Maske: niedrige, feuchte Flächen werden Sumpf (nicht bebaubar).
	var wet := FastNoiseLite.new()
	wet.noise_type = FastNoiseLite.TYPE_VALUE
	wet.seed = seed + 11
	wet.frequency = 0.05

	# --- Terrain als S2-naehere Knoten-/Regionenmaske ableiten und dann mit
	# Hex-Brushes auf Dreiecke malen. So entstehen Flaechen statt Zackenketten.
	var node_terrain := _classify_node_terrain(map)
	_smooth_node_terrain(map, node_terrain, 2)
	var water_region_size := _water_region_sizes(map, node_terrain)
	_apply_sand_patches(map, node_terrain, water_region_size, seed)
	_apply_swamp(map, node_terrain, wet)
	_seed_mountain_meadows(map, node_terrain, seed)
	_paint_node_terrain(map, node_terrain)
	_cleanup_terrain(map)

	_scatter_objects(map, seed, options)
	seed_coastal_fish(map)
	return map


## Inselkarte (#27): senkt Flächen mit niedriger Kontinentmaske unter den Meeresspiegel,
## sodass mehrere getrennte Landmassen (Archipel) übrig bleiben. Berge auf den Inseln
## bleiben erhalten (nur abgesenkt, wenn die Maske niedrig ist).
static func _apply_island_mask(map: MapData, seed: int) -> void:
	var continent := FastNoiseLite.new()
	continent.noise_type = FastNoiseLite.TYPE_VALUE
	continent.seed = seed + 31
	continent.frequency = 0.028
	continent.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent.fractal_octaves = 3
	for y in map.height:
		for x in map.width:
			var c: float = continent.get_noise_2d(x, y) * 0.5 + 0.5
			var landness: float = clampf((c - ISLAND_LAND_MIN) / ISLAND_LAND_SPAN, 0.0, 1.0)
			var h: float = float(map.get_height(x, y))
			# landness 1 → unverändert, 0 → tief unter Wasser; dazwischen Küste.
			var nh: float = lerp(-ISLAND_SEA_DEPTH, h, landness)
			map.set_height(x, y, maxi(0, int(round(nh))))


## Flusskarte (#27): gräbt einige gewundene Wasserläufe in die Höhenkarte (Höhe unter
## den Wasserspiegel). Anzahl skaliert mit der Kartengröße; sanftes Wandern + seltene
## Verzweigung (wie RTTRs CreateStream/splitRate, vereinfacht).
static func _carve_rivers(map: MapData, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 41
	var count := clampi(int((map.width + map.height) / 90), 1, 4)
	var level := maxi(0, int(H_WATER_MAX) - 1)   # garantiert < H_WATER_MAX → Wasser
	for _i in count:
		var start := Vector2(
			rng.randf_range(map.width * 0.2, map.width * 0.8),
			rng.randf_range(map.height * 0.2, map.height * 0.8))
		var ang := rng.randf() * TAU
		_carve_stream(map, rng, start, ang, level, int((map.width + map.height) * 0.8), true)


static func _carve_stream(map: MapData, rng: RandomNumberGenerator, start: Vector2,
		ang: float, level: int, length: int, may_branch: bool) -> void:
	var pos := start
	var width := rng.randf_range(0.9, 1.8)   # Knoten-Radius des Flussbetts
	for _step in length:
		var px := int(round(pos.x))
		var py := int(round(pos.y))
		# Abgestufte Ufer (#58): Flussbett auf Wasserniveau, danach steigt der Boden
		# je Knoten nur um RIVER_BANK_RISE an (sanfter Hang statt Klippe). mini() senkt
		# nur ab — höher liegendes Land bleibt, sodass das Bett sich ins Gelände schmiegt.
		var r := int(ceil(width)) + RIVER_BANK_WIDTH
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nx := px + dx
				var ny := py + dy
				if not map.in_bounds(nx, ny):
					continue
				var d := Vector2(dx, dy).length()
				if d <= width:
					map.set_height(nx, ny, mini(map.get_height(nx, ny), level))
				elif d <= width + RIVER_BANK_WIDTH:
					var bank := level + int(ceil((d - width) * RIVER_BANK_RISE))
					map.set_height(nx, ny, mini(map.get_height(nx, ny), bank))
		ang += rng.randf_range(-0.4, 0.4)
		pos += Vector2(cos(ang), sin(ang))
		if pos.x < 1 or pos.x > map.width - 2 or pos.y < 1 or pos.y > map.height - 2:
			return
		if may_branch and rng.randf() < RIVER_BRANCH_CHANCE:
			_carve_stream(map, rng, pos, ang + rng.randf_range(-1.2, 1.2),
				level, int(length * 0.5), false)


## Fisch-Teich (#59): Manche Karten (v. a. "flach", hoher Seed) geraten fast wasserlos —
## ohne Wasser keine Fischgründe. Liegt der Wasseranteil unter MIN_WATER_FRACTION,
## brennen wir 1–2 kleine Teiche an geeigneten Landstellen (Wiesenhöhe, flach, fern vom
## Rand) ein. Deterministisch über den Seed; Ufer werden später zu Wiese (kein Strand).
static func _ensure_fishing_water(map: MapData, seed: int) -> void:
	var water := 0
	for y in map.height:
		for x in map.width:
			if map.get_height(x, y) < H_WATER_MAX:
				water += 1
	var total := map.width * map.height
	if total > 0 and float(water) / float(total) >= MIN_WATER_FRACTION:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 73
	var level := maxi(0, int(H_WATER_MAX) - 1)
	var placed := 0
	for _try in 200:
		if placed >= 2:
			break
		var px := rng.randi_range(POND_RADIUS + 2, map.width - POND_RADIUS - 3)
		var py := rng.randi_range(POND_RADIUS + 2, map.height - POND_RADIUS - 3)
		var h := map.get_height(px, py)
		# Nur auf bebaubarer Wiesenhöhe und nicht dort, wo schon Wasser/Berg ist.
		if h < int(H_SAND_MAX) or h >= int(H_MEADOW_MAX):
			continue
		_carve_pond(map, px, py, level)
		placed += 1


static func _carve_pond(map: MapData, px: int, py: int, level: int) -> void:
	for dy in range(-POND_RADIUS, POND_RADIUS + 1):
		for dx in range(-POND_RADIUS, POND_RADIUS + 1):
			var nx := px + dx
			var ny := py + dy
			if not map.in_bounds(nx, ny):
				continue
			var d := Vector2(dx, dy).length()
			if d <= POND_RADIUS - 1:
				map.set_height(nx, ny, mini(map.get_height(nx, ny), level))
			elif d <= POND_RADIUS:
				# abgestuftes Ufer (analog Flüsse): kein Steilrand
				map.set_height(nx, ny, mini(map.get_height(nx, ny), level + 1))


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
# Kartentypen (#27): Teil des Welt-Codes. "zufall" löst deterministisch in einen der
# konkreten Typen auf (aus dem Token), damit ein geteilter Code dieselbe Welt ergibt.
const CONCRETE_MAP_TYPES := ["flach", "fluss", "insel"]
const MAP_TYPES := ["flach", "fluss", "insel", "zufall"]
const DEFAULT_MAP_TYPE := "flach"

## Wuerfelt einen neuen zufaelligen Karten-Token (nur den TOKEN-Teil des Welt-Codes).
static func random_world_token(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var out := ""
	for _i in WORLD_TOKEN_LEN:
		out += WORLD_CODE_ALPHABET[rng.randi() % WORLD_CODE_ALPHABET.length()]
	return out


## Baut den kanonischen Welt-Code aus seinen Teilen: BxH-G-TYP-TOKEN.
static func format_world_code(width: int, height: int, enemies: int, token: String,
		map_type: String = DEFAULT_MAP_TYPE) -> String:
	var w := clampi(width, MAP_MIN_DIM, MAP_MAX_DIM)
	var h := clampi(height, MAP_MIN_DIM, MAP_MAX_DIM)
	var e := clampi(enemies, 0, MAP_MAX_ENEMIES)
	var mt := map_type.strip_edges().to_lower()
	if not MAP_TYPES.has(mt):
		mt = DEFAULT_MAP_TYPE
	var t := token.strip_edges().to_upper()
	if t == "":
		t = random_world_token()
	return "%dx%d-%d-%s-%s" % [w, h, e, mt, t]


## Zerlegt einen eingetippten Welt-Code in seine Teile. Toleranter Parser:
## - "DEVMAP"                  -> { devmap = true }
## - "BxH-G-TYP-TOKEN"         -> volle Angabe inkl. Typ (has_size = true)
## - "BxH-G-TOKEN"             -> alt, ohne Typ -> map_type = flach (has_size = true)
## - alles andere ("SIEDLER")  -> nur Token, Groesse/Gegner offen (has_size = false)
## Rueckgabe: { devmap, has_size, width, height, enemies, map_type, token }
static func parse_world_code(code: String) -> Dictionary:
	var raw := code.strip_edges()
	var result := {
		"devmap": false, "has_size": false,
		"width": 0, "height": 0, "enemies": 0,
		"map_type": DEFAULT_MAP_TYPE, "token": "",
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
			result.has_size = true
			result.width = clampi(int(xy[0]), MAP_MIN_DIM, MAP_MAX_DIM)
			result.height = clampi(int(xy[1]), MAP_MIN_DIM, MAP_MAX_DIM)
			result.enemies = clampi(int(parts[1]), 0, MAP_MAX_ENEMIES)
			# Rest nach "WxH-G-": optional ein Typ-Feld, dann der Token.
			var rest := raw.substr(size_part.length() + String(parts[1]).length() + 2)
			var rest_parts := rest.split("-", false)
			if rest_parts.size() >= 2 and MAP_TYPES.has(String(rest_parts[0]).to_lower()):
				result.map_type = String(rest_parts[0]).to_lower()
				rest = rest.substr(String(rest_parts[0]).length() + 1)
			result.token = rest.strip_edges().to_upper()
			return result
	# Kein voller Code -> ganzer String ist der Token.
	result.token = raw.to_upper()
	return result


## Löst den (evtl. "zufall") Kartentyp deterministisch in einen konkreten Typ auf.
static func resolve_map_type(map_type: String, token: String) -> String:
	var mt := map_type.strip_edges().to_lower()
	if CONCRETE_MAP_TYPES.has(mt):
		return mt
	var pick := stable_seed_from_string("type:" + token.to_upper()) % CONCRETE_MAP_TYPES.size()
	return String(CONCRETE_MAP_TYPES[pick])


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


static func _classify_node_terrain(map: MapData) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var h := _smoothed_node_height(map, x, y)
			var t: int
			# Kein Sand-Höhenband mehr (#58): niedriges Land ist Wiese; Sand entsteht
			# nur noch fleckenweise (_apply_sand_patches: Strandflecken + Wüste).
			if h < H_WATER_MAX:
				t = Terrain.WATER
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
			out[map.idx(x, y)] = t
	return out


## Sumpf (#50-Folge): kleine feuchte Senken NAHE dem Wasser, nicht großflächig im
## Inland. Läuft NACH dem Ufer-Ring — direkt am Wasser liegt Sand, der Sumpf bildet
## das Band knapp dahinter. Bedingungen: niedrige, feuchte Wiese mit Wasser/Sand in
## kurzer Reichweite. Höhere Feuchte-Schwelle als zuvor → deutlich kleinere Flächen.
static func _apply_swamp(map: MapData, terrain: PackedByteArray, wet: FastNoiseLite) -> void:
	if wet == null:
		return
	var next := terrain.duplicate()
	for y in map.height:
		for x in map.width:
			var i := map.idx(x, y)
			if int(terrain[i]) != Terrain.MEADOW:
				continue
			if _smoothed_node_height(map, x, y) >= H_SWAMP_MAX:
				continue
			if (wet.get_noise_2d(x, y) * 0.5 + 0.5) <= SWAMP_WET_MIN:
				continue
			if _water_within_radius(map, terrain, x, y, SWAMP_WATER_RADIUS):
				next[i] = Terrain.SWAMP
	for i in terrain.size():
		terrain[i] = next[i]


## Wasser oder Sand (= Küste) in Hex-Reichweite r? Bindet Sumpf ans Ufer.
static func _water_within_radius(map: MapData, terrain: PackedByteArray,
		cx: int, cy: int, r: int) -> bool:
	var center := Vector2i(cx, cy)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := center + Vector2i(dx, dy)
			if not map.in_bounds(p.x, p.y) or _hex_distance(center, p) > r:
				continue
			var nt := int(terrain[map.idx(p.x, p.y)])
			if nt == Terrain.WATER or nt == Terrain.SAND:
				return true
	return false


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


## Sand fleckenweise statt flächig (#58, wie vom Spieler gewünscht): KEIN durchgehender
## Strandsaum mehr. Stattdessen zwei rauschgesteuerte Quellen, analog zum Sumpf:
##  (a) gebrochene Strandflecken nur an GROSSEN Gewässern (Meer/große Seen),
##  (b) seltene Wüsten-Flecken im Trockenen, fern von Wasser (S2 hat Wüste/Savanne).
## Flüsse/Teiche behalten dadurch Wiesenufer.
static func _apply_sand_patches(map: MapData, terrain: PackedByteArray,
		region_size: PackedInt32Array, seed: int) -> void:
	var sand := FastNoiseLite.new()
	sand.noise_type = FastNoiseLite.TYPE_VALUE
	sand.seed = seed + 23
	sand.frequency = SAND_PATCH_FREQ
	sand.fractal_type = FastNoiseLite.FRACTAL_FBM
	sand.fractal_octaves = 3
	var next := terrain.duplicate()
	for y in map.height:
		for x in map.width:
			var i := map.idx(x, y)
			if int(terrain[i]) != Terrain.MEADOW:
				continue
			var s: float = sand.get_noise_2d(x, y) * 0.5 + 0.5
			if _node_neighbor_has_large_water(map, terrain, region_size, x, y):
				if s > BEACH_PATCH_MIN:          # gebrochener Strand am Meer
					next[i] = Terrain.SAND
			elif s > DESERT_PATCH_MIN \
					and not _water_within_radius(map, terrain, x, y, DESERT_WATER_CLEARANCE):
				next[i] = Terrain.SAND           # seltener Wüstenfleck im Trockenen
	for i in terrain.size():
		terrain[i] = next[i]


## Flood-Fill der Wasserknoten: liefert je Knoten die Größe seiner Wasserkomponente
## (0 für Land). So lassen sich Meer/See (groß) von Fluss/Teich (klein) trennen.
static func _water_region_sizes(map: MapData, terrain: PackedByteArray) -> PackedInt32Array:
	var size := PackedInt32Array()
	size.resize(map.width * map.height)
	var visited := PackedByteArray()
	visited.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var start := map.idx(x, y)
			if int(terrain[start]) != Terrain.WATER or visited[start] != 0:
				continue
			var stack: Array[int] = [start]
			var component: Array[int] = []
			visited[start] = 1
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				component.append(cur)
				var cx := cur % map.width
				@warning_ignore("integer_division")
				var cy := cur / map.width
				for dir in Grid.DIRS:
					var n := map.neighbor(cx, cy, dir)
					if n.x < 0:
						continue
					var ni := map.idx(n.x, n.y)
					if visited[ni] == 0 and int(terrain[ni]) == Terrain.WATER:
						visited[ni] = 1
						stack.append(ni)
			for ci in component:
				size[ci] = component.size()
	return size


static func _node_neighbor_has_large_water(map: MapData, terrain: PackedByteArray,
		region_size: PackedInt32Array, x: int, y: int) -> bool:
	for dir in Grid.DIRS:
		var n := map.neighbor(x, y, dir)
		if n.x < 0:
			continue
		var ni := map.idx(n.x, n.y)
		if int(terrain[ni]) == Terrain.WATER and region_size[ni] >= SEA_MIN_SIZE:
			return true
	return false


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
