class_name GameTheme
extends RefCounted

## ZENTRALE, AUSTAUSCHBARE DESIGN-SCHICHT.
##
## Alle Farben, Kürzel und (später) Texturen kommen von hier. Wer eigene Grafik
## einbauen will, ersetzt nur diese Datei bzw. legt Texturen in `assets/` ab und
## ordnet sie hier zu — der restliche Code bleibt unangetastet.
##
## TODO (Grafik-Stufe): pro Gebäude/Ware/Terrain ein Texture2D laden und in den
## Renderern statt der Platzhalter-Formen zeichnen. Vorbild-Stil: Die Siedler 2 /
## Return to the Roots (eigene, neu gezeichnete Assets — keine Originaldateien).

# --- Terrain -------------------------------------------------------------
static func terrain_color(t: int) -> Color:
	return Terrain.color(t)


## assets/terrain/<name>.png (water/meadow/mountain/sand/swamp/snow)
static func terrain_texture(t: int) -> Texture2D:
	match t:
		Terrain.WATER: return _tex("res://assets/terrain/water.png")
		Terrain.MEADOW: return _tex("res://assets/terrain/meadow.png")
		Terrain.MOUNTAIN: return _tex("res://assets/terrain/mountain.png")
		Terrain.MOUNTAIN_MEADOW: return _tex("res://assets/terrain/mountain_meadow.png")
		Terrain.SAND: return _tex("res://assets/terrain/sand.png")
		Terrain.SWAMP: return _tex("res://assets/terrain/swamp.png")
		Terrain.SNOW: return _tex("res://assets/terrain/snow.png")
	return null


# --- Waren ---------------------------------------------------------------
static func good_color(g: int) -> Color:
	match g:
		Goods.WOOD: return Color(0.55, 0.36, 0.18)
		Goods.BOARDS: return Color(0.80, 0.62, 0.36)
		Goods.STONE: return Color(0.62, 0.62, 0.64)
		Goods.GRAIN: return Color(0.88, 0.78, 0.30)
		Goods.FLOUR: return Color(0.92, 0.88, 0.78)
		Goods.WATER: return Color(0.30, 0.55, 0.85)
		Goods.BREAD: return Color(0.78, 0.55, 0.28)
		Goods.FISH: return Color(0.55, 0.70, 0.80)
		Goods.MEAT: return Color(0.80, 0.40, 0.40)
		Goods.COAL: return Color(0.18, 0.18, 0.20)
		Goods.IRON_ORE: return Color(0.55, 0.40, 0.32)
		Goods.IRON: return Color(0.70, 0.72, 0.78)
		Goods.GOLD_ORE: return Color(0.72, 0.58, 0.25)
		Goods.COINS: return Color(0.95, 0.82, 0.30)
		Goods.BEER: return Color(0.85, 0.62, 0.20)
		Goods.TOOLS: return Color(0.50, 0.50, 0.55)
		Goods.SWORD: return Color(0.80, 0.80, 0.88)
		Goods.SHIELD: return Color(0.65, 0.55, 0.40)
		Goods.PIG: return Color(0.92, 0.70, 0.70)
	return Color.WHITE


# --- Gebäude -------------------------------------------------------------
static func building_color(def_id: String) -> Color:
	var cat := String(BuildingCatalog.get_def(def_id).get("category", ""))
	match cat:
		"lager": return Color(0.85, 0.78, 0.30)
		"holz": return Color(0.45, 0.55, 0.30)
		"bau": return Color(0.60, 0.60, 0.62)
		"nahrung": return Color(0.80, 0.70, 0.35)
		"bergbau": return Color(0.40, 0.36, 0.45)
		"metall": return Color(0.55, 0.45, 0.45)
		"militaer": return Color(0.55, 0.30, 0.30)
	return Color(0.7, 0.5, 0.35)


## Kurzes Kürzel über dem Gebäude (Platzhalter, bis Sprites da sind).
static func building_label(def_id: String) -> String:
	match def_id:
		"hq": return "HQ"
		"storehouse": return "La"
		"woodcutter": return "Hf"
		"forester": return "Fö"
		"sawmill": return "Sä"
		"quarry": return "St"
		"well": return "Br"
		"farm": return "Ba"
		"mill": return "Mü"
		"bakery": return "Bä"
		"fishery": return "Fi"
		"hunter": return "Jä"
		"pigfarm": return "Sw"
		"slaughterhouse": return "Sl"
		"toolmaker": return "Wz"
		"coalmine": return "Ko"
		"ironmine": return "Ei"
		"goldmine": return "Go"
		"granitemine": return "Gr"
		"smelter": return "Sm"
		"mint": return "Mz"
		"brewery": return "Bi"
		"smithy": return "Sc"
		"guardhouse": return "Wa"
		"watchtower": return "Wt"
		"fortress": return "Fe"
		"catapult": return "Ka"
	return "?"


static func territory_color() -> Color:
	return Color(0.30, 0.70, 1.0, 0.12)


static func border_color() -> Color:
	return Color(0.30, 0.70, 1.0, 0.85)


static func enemy_territory_color() -> Color:
	return Color(1.0, 0.35, 0.30, 0.12)


static func enemy_border_color() -> Color:
	return Color(1.0, 0.35, 0.30, 0.85)


# --- Optionale Texturen ---------------------------------------------------
# Liegt eine passende PNG in assets/, wird sie automatisch verwendet, sonst
# die Platzhalter-Form. So lässt sich eigene Grafik einbauen, ohne Code zu ändern.
# PNGs werden zuerst als Godot-Resource geladen. Wenn Godot sie noch nicht
# importiert hat, laden wir sie direkt als ImageTexture aus res://.

static var _tex_cache := {}


static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if FileAccess.file_exists(path) and path.to_lower().ends_with(".png"):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			t = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


## assets/buildings/<def_id>.png   (z. B. assets/buildings/sawmill.png)
## Pro Spieler eigenes PNG möglich: <def_id>_<owner>.png (z. B. sawmill_1.png für
## den Gegner). Fehlt es, gilt das gemeinsame <def_id>.png für alle Spieler.
static func building_texture(def_id: String, owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/buildings/%s_%d.png" % [def_id, owner])
		if t != null:
			return t
	return _tex("res://assets/buildings/%s.png" % def_id)


## assets/objects/<name>.png       (tree.png / stone.png / ore.png)
static func object_texture(name: String) -> Texture2D:
	return _tex("res://assets/objects/%s.png" % name)


## Terrain-Kurzname für Datei-Pfade (water/meadow/mountain/sand/swamp/snow).
static func terrain_name(t: int) -> String:
	match t:
		Terrain.WATER: return "water"
		Terrain.MEADOW: return "meadow"
		Terrain.MOUNTAIN: return "mountain"
		Terrain.MOUNTAIN_MEADOW: return "mountain_meadow"
		Terrain.SAND: return "sand"
		Terrain.SWAMP: return "swamp"
		Terrain.SNOW: return "snow"
	return "meadow"


## Straßen-Textur. Pro Untergrund eigene PNG möglich:
##   assets/roads/<terrain>.png  (z. B. roads/mountain.png), sonst roads/road.png.
## Wird getilt entlang der Straße gezeichnet (sonst zeichnet der Renderer eine Linie).
static func road_texture(terrain := -1, level := WorldState.ROAD_DIRT) -> Texture2D:
	if level >= WorldState.ROAD_COBBLE:
		if terrain >= 0:
			var ct := _tex("res://assets/roads/%s_cobble.png" % terrain_name(terrain))
			if ct != null:
				return ct
		var cobble := _tex("res://assets/roads/road_cobble.png")
		if cobble != null:
			return cobble
	if terrain >= 0:
		var t := _tex("res://assets/roads/%s.png" % terrain_name(terrain))
		if t != null:
			return t
	return _tex("res://assets/roads/road.png")


## assets/ui/build_spots/<kind>.png (castle/house/hut/mine/flag/road_flag/blocked).
static func build_spot_texture(kind: String) -> Texture2D:
	return _tex("res://assets/ui/build_spots/%s.png" % kind)


## Bauplatz-Grafik (statt gelbem Platzhalter), gezeigt solange noch nichts steht.
##   assets/construction/<def_id>_site.png  (pro Gebäude) sonst construction/site.png
static func construction_site_texture(def_id := "") -> Texture2D:
	if def_id != "":
		var t := _tex("res://assets/construction/%s_site.png" % def_id)
		if t != null:
			return t
	return _tex("res://assets/construction/site.png")


## Planierkreuz/-Schild vor der normalen Bauplatzgrafik (#65).
static func construction_planing_texture() -> Texture2D:
	return _tex("res://assets/construction/planing_site.png")


## Baustufe-1-Grafik (Holzkonstruktion). Pro Gebäude oder generisch:
##   assets/construction/<def_id>_stage1.png  sonst  construction/stage1.png
## Fehlt sie, fällt der Renderer auf die fertige Gebäude-Textur zurück (1 Stufe).
static func construction_stage1_texture(def_id := "") -> Texture2D:
	if def_id != "":
		var t := _tex("res://assets/construction/%s_stage1.png" % def_id)
		if t != null:
			return t
	return _tex("res://assets/construction/stage1.png")


## Baum-Sprite (Textur + Zeichengröße) für Typ-Name (oak/pine/birch) und Stufe
## (0=Setzling, 1=klein, 2=groß). Liefert {tex, size}; tex == null → Platzhalter.
## Wird von Map- UND Unit-Renderer genutzt (Occlusion), damit die Maße identisch sind.
static func tree_sprite(type_name: String, stage: int) -> Dictionary:
	var base := "tree_%s" % type_name
	var name := base
	if stage == 0:
		name = "%s_seed" % base
	elif stage == 1:
		name = "%s_small" % base
	var tex := object_texture(name)
	var draw_name := name
	if tex == null:
		var legacy := "tree"
		if stage == 0:
			legacy = "tree_seed"
		elif stage == 1:
			legacy = "tree_small"
		tex = object_texture(legacy)
		draw_name = legacy
	if tex == null:
		return { tex = null, size = Vector2.ZERO }
	var sz := object_draw_size(draw_name)
	if tex == object_texture("tree"):
		if stage == 0:
			sz *= 0.35
		elif stage == 1:
			sz *= 0.62
	return { tex = tex, size = sz }


static func object_draw_size(name: String) -> Vector2:
	# Design-Override (design.json -> "object_sizes": { name: [w, h] }) gewinnt immer.
	# Damit lassen sich Karten-Objekte (v. a. Felder) im Design-Editor frei skalieren,
	# ohne Code zu ändern.
	var override: Dictionary = _design().get("object_sizes", {})
	if override.has(name):
		var v = override[name]
		if v is Array and v.size() >= 2:
			return Vector2(float(v[0]), float(v[1]))
	var tree_h := _tree_draw_height(name)
	if tree_h > 0.0:
		return _texture_draw_size(name, tree_h, _tree_fallback_size(name))
	match name:
		"tree_seed": return Vector2(16, 20)
		"tree_small": return Vector2(28, 38)
		"tree": return Vector2(40, 54)
		"stone": return Vector2(32, 27)
		"stone_stage2": return Vector2(44, 34)
		"stone_stage3": return Vector2(58, 44)
		"ore": return Vector2(32, 27)
		# Felder decken ~eine Kachel ab (TILE 64×32) — vorher 30×18 war deutlich zu klein.
		"field_seed", "field_young", "field_growing", "field_ripe", "field_cut", "field_withered": return Vector2(48, 30)
	return Vector2(28, 28)


static func _tree_draw_height(name: String) -> float:
	if not (name == "tree" or name.begins_with("tree_")):
		return 0.0
	var stage_key := "tree_big"
	if name.ends_with("_seed"):
		stage_key = "tree_seed"
	elif name.ends_with("_small"):
		stage_key = "tree_small"
	var heights: Dictionary = _design().get("object_heights", {})
	if heights.has(name):
		return float(heights[name])
	if heights.has(stage_key):
		return float(heights[stage_key])
	match stage_key:
		"tree_seed": return 22.0
		"tree_small": return 44.0
	return 78.0


static func _tree_fallback_size(name: String) -> Vector2:
	if name.ends_with("_seed"):
		return Vector2(16, 20)
	if name.ends_with("_small"):
		return Vector2(30, 42)
	if name == "tree":
		return Vector2(40, 54)
	return Vector2(42, 58)


static func _texture_draw_size(name: String, target_height: float, fallback: Vector2) -> Vector2:
	var tex := object_texture(name)
	if tex != null and tex.get_height() > 0:
		var w := target_height * float(tex.get_width()) / float(tex.get_height())
		return Vector2(maxf(1.0, w), target_height)
	return fallback


static func build_spot_size(kind: String) -> Vector2:
	var per: Dictionary = _design().get("build_spot_sizes", {})
	if per.has(kind):
		return _to_vec(per[kind])
	match kind:
		"castle": return Vector2(34, 34)
		"house": return Vector2(30, 30)
		"hut": return Vector2(26, 26)
		"mine": return Vector2(30, 30)
		"flag", "road_flag", "blocked": return Vector2(24, 24)
	return Vector2(26, 26)


## design.json "build_spot_offsets": { "flag": [dx,dy], "road_flag": [dx,dy], ... }
## Versatz zum Zentrierungspunkt (Standard: mittig auf dem Knoten).
static func build_spot_offset(kind: String) -> Vector2:
	var per: Dictionary = _design().get("build_spot_offsets", {})
	if per.has(kind):
		return _to_vec(per[kind])
	return Vector2.ZERO


## Spielerfarbe — NUR für Platzhalter (wenn KEIN eigenes PNG vorhanden ist).
## Die echte Optik kommt aus den pro Spieler eigenen PNGs (siehe *_texture(owner)).
static func player_color(owner: int) -> Color:
	match owner:
		0: return Color(0.35, 0.55, 0.95)  # blau
		1: return Color(0.90, 0.25, 0.20)  # rot
		2: return Color(0.25, 0.80, 0.30)  # grün
		3: return Color(0.90, 0.80, 0.15)  # gelb
		4: return Color(0.75, 0.20, 0.75)  # lila
		5: return Color(0.90, 0.50, 0.15)  # orange
	return Color(0.70, 0.70, 0.70)


## Flaggen-Textur je Spieler — EIGENES PNG pro Spieler (keine Färbung):
##   assets/ui/flag_<owner>.png  (flag_0.png = Spieler, flag_1.png = Gegner, …)
## Fällt zurück auf assets/ui/flag.png (für alle gleich), sonst Platzhalter.
static func flag_texture(owner := 0) -> Texture2D:
	var t := _tex("res://assets/ui/flag_%d.png" % owner)
	if t != null:
		return t
	return _tex("res://assets/ui/flag.png")


## Platzhalter-Farbe einer Flagge (nur wenn kein PNG da ist).
static func flag_color(owner := 0) -> Color:
	return player_color(owner)


## Zeichengröße einer Flagge (PNG-Modus). design.json "flag_size": [w,h].
## Basis des Pfahls liegt auf dem Knoten; Textur wird nach oben gezeichnet.
static func flag_draw_size() -> Vector2:
	var s = _design().get("flag_size", null)
	if s != null:
		return _to_vec(s)
	return Vector2(16.0, 24.0)


## assets/goods/<good_id>.png      (good_id = Goods-Enumwert, z. B. 0.png = Holz)
static func good_texture(good_id: int) -> Texture2D:
	return _tex("res://assets/goods/%d.png" % good_id)


# --- Wasserfahrzeuge ------------------------------------------------------
## assets/ships/boat.png: kleines Boot/Faehre fuer Wasserstrassen.
## Pro Spieler eigenes PNG moeglich: boat_<owner>.png (z. B. boat_1.png).
static func boat_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/ships/boat_%d.png" % owner)
		if t != null:
			return t
	return _tex("res://assets/ships/boat.png")


## Wassertraeger/Faehrmann: Einheit im Boot, 4 Frames x 6 Richtungen.
## Primaerer Pfad: assets/units/water_carrier.png, rote Variante water_carrier_1.png.
static func water_carrier_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/units/water_carrier_%d.png" % owner)
		if t != null:
			return t
	var base := _tex("res://assets/units/water_carrier.png")
	if base != null:
		return base
	# Fallback fuer alte Assetstaende vor der Umbenennung.
	if owner != 0:
		var old_owner := _tex("res://assets/ships/boat_sheet_%d.png" % owner)
		if old_owner != null:
			return old_owner
	return _tex("res://assets/ships/boat_sheet.png")


## Altname fuer Kompatibilitaet: heute ist das der Wassertraeger-Sprite.
static func boat_sheet_texture(owner := 0) -> Texture2D:
	return water_carrier_texture(owner)


static func boat_draw_size() -> Vector2:
	var s = _design().get("boat_size", null)
	if s != null:
		return _to_vec(s)
	return Vector2(24.0, 24.0)


static func boat_carrier_size() -> float:
	return float(_design().get("boat_carrier_size", 28.0))


## assets/ships/ship.png: grosses See-Schiff; ship_stage1.png = Baugerippe.
## Pro Spieler eigenes PNG moeglich: ship_<owner>.png (z. B. ship_1.png).
static func ship_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/ships/ship_%d.png" % owner)
		if t != null:
			return t
	return _tex("res://assets/ships/ship.png")


## Richtungs-Sheet fuer grosse Schiffe: 4 Frames x 6 Richtungen.
static func ship_sheet_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/ships/ship_sheet_%d.png" % owner)
		if t != null:
			return t
	return _tex("res://assets/ships/ship_sheet.png")


static func ship_construction_stage1_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/ships/ship_stage1_%d.png" % owner)
		if t != null:
			return t
	return _tex("res://assets/ships/ship_stage1.png")


static func ship_construction_stage1_sheet_texture(owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/ships/ship_stage1_sheet_%d.png" % owner)
		if t != null:
			return t
	return _tex("res://assets/ships/ship_stage1_sheet.png")


static func ship_draw_size() -> Vector2:
	var s = _design().get("ship_size", null)
	if s != null:
		return _to_vec(s)
	return Vector2(46.0, 46.0)


static func ship_build_offset() -> Vector2:
	var s = _design().get("ship_build_offset", null)
	if s != null:
		return _to_vec(s)
	return Vector2.ZERO


# --- Einheiten-Animation --------------------------------------------------
# Optionales Sprite-Sheet je Einheitstyp: assets/units/<kind>.png
# Raster: ANIM_FRAMES Spalten (Lauf-Phasen) x 6 Zeilen (Weg-Richtungen:
# NE, E, SE, SW, W, NW). Zellgroesse wird aus der
# Bildgröße abgeleitet. kind = "carrier" | "worker" | "soldier" | "builder".
# Fehlt das Sheet, zeichnet der UnitRenderer die Platzhalter-Figur.
const ANIM_FRAMES := 4
const ANIM_DIRS := 6


## Pro Spieler eigenes Lauf-Sheet möglich: <kind>_<owner>.png (z. B. soldier_1.png).
## Fehlt es, gilt das gemeinsame <kind>.png für alle Spieler.
static func unit_texture(kind: String, owner := 0) -> Texture2D:
	if owner != 0:
		var t := _tex("res://assets/units/%s_%d.png" % [kind, owner])
		if t != null:
			return t
	return _tex("res://assets/units/%s.png" % kind)


## assets/border/player.png bzw. enemy.png — Grenzstein-Design (sonst Punkt).
static func border_texture(owner: int) -> Texture2D:
	return _tex("res://assets/border/%s.png" % ("player" if owner == 0 else "enemy"))


# --- Design-Konfiguration (assets/design.json, ohne Code änderbar) ---------
# Erlaubt das Anpassen von Gebäudegrößen, Texturskalierung und Eingangspunkt.
# Fehlt die Datei, gelten die eingebauten Standardwerte.

static var _cfg_loaded := false
static var _cfg := {}


static func _design() -> Dictionary:
	if _cfg_loaded:
		return _cfg
	_cfg_loaded = true
	_cfg = {}
	var path := "res://assets/design.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_cfg = parsed
	return _cfg


static func _size_key(size: int) -> String:
	match size:
		WorldState.BQ_CASTLE: return "castle"
		WorldState.BQ_HOUSE: return "house"
		WorldState.BQ_MINE: return "mine"
	return "hut"


## Zeichengröße eines Gebäudes. Das Sprite wird IMMER quadratisch (Breite=Höhe)
## und seitenverhältniserhaltend gezeichnet — es zählt nur EIN Größenwert.
## Pro Gebäude überschreibbar via "building_sizes": { "<def_id>": <größe> }.
## Altformat [w,h] wird weiter gelesen (es zählt der erste Wert).
static func building_dims(size: int, def_id := "") -> Vector2:
	var cfg := _design()
	var per: Dictionary = cfg.get("building_sizes", {})
	if def_id != "" and per.has(def_id):
		var b = per[def_id]
		var w := float(b[0]) if (b is Array and not (b as Array).is_empty()) else float(b)
		return Vector2(w, w)
	var sizes: Dictionary = cfg.get("sizes", {})
	var key := _size_key(size)
	if sizes.has(key):
		var a = sizes[key]
		return Vector2(float(a[0]), float(a[1]))
	match size:
		WorldState.BQ_CASTLE: return Vector2(46, 44)
		WorldState.BQ_HOUSE: return Vector2(32, 30)
		WorldState.BQ_MINE: return Vector2(26, 22)
	return Vector2(30, 28)


## Faktor, mit dem Gebäude-Texturen ggü. den Platzhalter-Maßen skaliert werden.
static func texture_scale() -> float:
	return float(_design().get("texture_scale", 2.0))


## Zusätzlicher Skalierungsfaktor für das Hauptquartier.
static func hq_scale() -> float:
	return float(_design().get("hq_scale", 1.35))


## Ziel-Höhe einer Einheiten-Figur in Pixeln (skaliert große Sprite-Sheets herunter).
static func unit_size() -> float:
	return float(_design().get("unit_size", 18.0))


## Weltpixel pro Terrain-Texturkachel. Kleinerer Wert = feinere Bodentextur.
static func terrain_uv_world_size() -> float:
	return float(_design().get("terrain_uv_world_size", 96.0))


## Bild-Versatz eines Gebäudes gegenüber seinem Knoten (Position zur Flagge).
## design.json "building_offset": { "<def_id>": [x,y] }. Standard (0,0).
static func building_offset(def_id := "") -> Vector2:
	var per: Dictionary = _design().get("building_offset", {})
	if def_id != "" and per.has(def_id):
		return _to_vec(per[def_id])
	return Vector2.ZERO


## Eingangspunkt (Tür) relativ zum Gebäudeknoten — PRO Gebäude konfigurierbar.
## design.json "entrance": { "default":[x,y], "<def_id>":[x,y], ... }
## Dorthin führt der kurze Weg von der Flagge; so passt der Eingang zu jedem
## eigenen Sprite (Position/Richtung). Fällt auf "default" bzw. [0,-6] zurück.
static func entrance_offset(def_id := "") -> Vector2:
	var cfg := _design()
	var ent = cfg.get("entrance", {})
	if ent is Dictionary:
		if def_id != "" and ent.has(def_id):
			return _to_vec(ent[def_id])
		if ent.has("default"):
			return _to_vec(ent["default"])
	if cfg.has("entrance_offset"):  # rückwärtskompatibel (alter globaler Schlüssel)
		return _to_vec(cfg["entrance_offset"])
	return Vector2(0, -6)


static func _to_vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
