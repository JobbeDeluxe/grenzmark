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
static func building_texture(def_id: String) -> Texture2D:
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


## Baustufe-1-Grafik (Holzkonstruktion). Pro Gebäude oder generisch:
##   assets/construction/<def_id>_stage1.png  sonst  construction/stage1.png
## Fehlt sie, fällt der Renderer auf die fertige Gebäude-Textur zurück (1 Stufe).
static func construction_stage1_texture(def_id := "") -> Texture2D:
	if def_id != "":
		var t := _tex("res://assets/construction/%s_stage1.png" % def_id)
		if t != null:
			return t
	return _tex("res://assets/construction/stage1.png")


static func object_draw_size(name: String) -> Vector2:
	if name.begins_with("tree_") and name.ends_with("_seed"):
		return Vector2(16, 20)
	if name.begins_with("tree_") and name.ends_with("_small"):
		return Vector2(30, 42)
	if name in ["tree_oak", "tree_pine", "tree_birch"]:
		return Vector2(42, 58)
	match name:
		"tree_seed": return Vector2(16, 20)
		"tree_small": return Vector2(28, 38)
		"tree": return Vector2(40, 54)
		"stone": return Vector2(32, 27)
		"stone_stage2": return Vector2(44, 34)
		"stone_stage3": return Vector2(58, 44)
		"ore": return Vector2(32, 27)
	return Vector2(28, 28)


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


## assets/goods/<good_id>.png      (good_id = Goods-Enumwert, z. B. 0.png = Holz)
static func good_texture(good_id: int) -> Texture2D:
	return _tex("res://assets/goods/%d.png" % good_id)


# --- Einheiten-Animation --------------------------------------------------
# Optionales Sprite-Sheet je Einheitstyp: assets/units/<kind>.png
# Raster: ANIM_FRAMES Spalten (Lauf-Phasen) x 6 Zeilen (Weg-Richtungen:
# NE, E, SE, SW, W, NW). Zellgroesse wird aus der
# Bildgröße abgeleitet. kind = "carrier" | "worker" | "soldier" | "builder".
# Fehlt das Sheet, zeichnet der UnitRenderer die Platzhalter-Figur.
const ANIM_FRAMES := 4
const ANIM_DIRS := 6


static func unit_texture(kind: String) -> Texture2D:
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


## Zeichengröße eines Gebäudes (Platzhalter-Maße). Aus design.json oder Standard.
## Pro Gebäude überschreibbar via "building_sizes": { "<def_id>": [w,h] }.
static func building_dims(size: int, def_id := "") -> Vector2:
	var cfg := _design()
	var per: Dictionary = cfg.get("building_sizes", {})
	if def_id != "" and per.has(def_id):
		var b = per[def_id]
		return Vector2(float(b[0]), float(b[1]))
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
