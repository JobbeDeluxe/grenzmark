class_name MapData
extends RefCounted

## Die reine Karte: Höhe pro Knoten und Terrain für die zwei Dreiecke jedes
## Knotens. Kein Spielzustand (Flaggen/Gebäude liegen im WorldState).
##
## Begrenzte (nicht-toroidale) Karte: Nachbarn außerhalb des Randes gelten als
## ungültig. Ein Wasserrand sorgt für natürliche Grenzen.

var width: int
var height: int

var heights: PackedByteArray   # ein Höhenwert pro Knoten
var terr_r: PackedByteArray    # Terrain des rechten Dreiecks pro Knoten
var terr_d: PackedByteArray    # Terrain des unteren Dreiecks pro Knoten

# Statische Karten-Objekte (Baum/Stein/Erz/Feld) — blockieren Bauen & Straßen.
# Reihenfolge = Serialisierungswert; NEUE Typen nur ANHÄNGEN.
enum { MO_TREE, MO_STONE, MO_ORE, MO_FIELD }
var objects: Dictionary = {}   # idx -> MO_*

# Erzsorten. ore_kind/MO_ORE bleiben nur für optionale dekorative Erzbrocken;
# die SPIELRELEVANTE Ressource liegt unterirdisch in den Lagerstätten unten.
enum { ORE_COAL, ORE_IRON, ORE_GOLD, ORE_GRANITE }
var ore_kind: Dictionary = {}  # idx -> ORE_* (nur Deko-Objekte)

# Fischbestand je Wasser-/Küstenknoten (Issue #6). In S2 unsichtbar unter Wasser:
# ein begrenzter Vorrat, den der Fischer am Ufer abbaut; bei 0 ist dort Schluss.
# Analog zu den Erz-Lagerstätten eine versteckte Mengen-Schicht (kein Rendering).
var fish_stock: Dictionary = {}  # idx -> verbleibende Fische (>0)

# Feste Hafenpunkte (#46, S2-treu): vom Generator deterministisch markierte Küsten-
# knoten, an denen (und nur dort) ein Hafen gebaut werden darf. Zugleich die Ziele für
# Expeditionen. Knoten an einer großen Meeres-Komponente, mit Mindestabstand zueinander.
var harbor_points: Dictionary = {}  # idx -> true

# Unterirdische Erz-Lagerstätten (in S2 unsichtbar bis ein Geologe sie aufdeckt).
# Eine Mine baut im Umkreis ab; jedes Vorkommen liefert `amount` Einheiten, dann
# ist es erschöpft. `found` wird später vom Geologen/Debug gesetzt (#21).
var ore_deposit_kind: Dictionary = {}    # idx -> ORE_*
var ore_deposit_amount: Dictionary = {}  # idx -> verbleibende Menge (>0)
var ore_deposit_found: Dictionary = {}   # idx -> true (aufgedeckt)

# Sichtbarer, NICHT blockierender Erz-Hinweis (#54): rein optische Markierung (das
# alte Erz-PNG) über einer großen unterirdischen Ader derselben Sorte. Überbaubar —
# blockiert weder Mine noch Flagge/Straße; deterministisch aus dem Map-Seed erzeugt.
var ore_hint_kind: Dictionary = {}       # idx -> ORE_*

# Wachstumsstufe je Baum-Knoten: 0 = Setzling, 1 = kleiner Baum, 2 = großer Baum.
# Nur Stufe 2 darf gefällt werden. Ohne Eintrag gilt ein Baum als ausgewachsen (2),
# damit Karten/Spielstände ohne Stufen-Info wie bisher funktionieren.
enum { TREE_SEED, TREE_SMALL, TREE_BIG }
var tree_stage: Dictionary = {} # idx -> 0/1/2

# Baumtyp je Baum-Knoten. Wird beim Generieren/Pflanzen deterministisch gewählt.
enum { TREE_OAK, TREE_PINE, TREE_BIRCH }
const TREE_TYPE_COUNT := 3
var tree_type: Dictionary = {}  # idx -> TREE_*

# Feld-Wachstumsstufe je Acker-Knoten (Bauernhof, Issue #26):
# 0 = frisch gesät, 1 = junges Korn, 2 = wachsend, 3 = reif/erntebereit.
# Nur Stufe 3 darf geerntet werden. Ein MO_FIELD-Knoten hat immer einen Eintrag;
# ohne Eintrag wird ein Feld als frisch gesät (0) behandelt.
enum { FIELD_SEED, FIELD_YOUNG, FIELD_GROWING, FIELD_RIPE }
var field_stage: Dictionary = {}  # idx -> 0/1/2/3

# Feld-Deko nach Ernte/Verdorren (RTTR: das Feld wird durch ein noEnvObject
# ersetzt — reine Deko, die NICHTS blockiert und nach kurzer Zeit verschwindet).
# CUT = abgeerntetes Stoppelfeld, WITHERED = ungeerntet verdorrtes Feld. Bewusst
# NICHT in `objects`, damit has_object/Bau/Straßen den Knoten frei sehen.
# Existenz/Art hier, Restzeit in Economy._decay_fields.
enum { FIELD_DECAY_CUT, FIELD_DECAY_WITHERED }
var field_decay: Dictionary = {}  # idx -> FIELD_DECAY_*

# Stein-Stufe (visuelle Größe): STONE_BIG → STONE_MEDIUM → STONE_SMALL → weg.
enum { STONE_SMALL = 1, STONE_MEDIUM = 2, STONE_BIG = 3 }
var stone_stage: Dictionary = {}      # idx -> 1/2/3
# Abbau-Schläge die noch auf der aktuellen Stufe übrig sind.
# Ohne Eintrag → Default = Stufenwert (BIG=3, MEDIUM=2, SMALL=1).
var stone_hits_left: Dictionary = {}  # idx -> 1..3


func _init(w: int, h: int) -> void:
	width = w
	height = h
	var n := w * h
	heights = PackedByteArray()
	heights.resize(n)
	terr_r = PackedByteArray()
	terr_r.resize(n)
	terr_d = PackedByteArray()
	terr_d.resize(n)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func idx(x: int, y: int) -> int:
	return y * width + x


func get_height(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return heights[idx(x, y)]


func set_height(x: int, y: int, h: int) -> void:
	heights[idx(x, y)] = clampi(h, 0, 255)


func get_tri(pos: Vector2i, kind: int) -> int:
	if not in_bounds(pos.x, pos.y):
		return Terrain.WATER
	if kind == Grid.TRI_R:
		return terr_r[idx(pos.x, pos.y)]
	return terr_d[idx(pos.x, pos.y)]


func set_tri(pos: Vector2i, kind: int, t: int) -> void:
	if kind == Grid.TRI_R:
		terr_r[idx(pos.x, pos.y)] = t
	else:
		terr_d[idx(pos.x, pos.y)] = t


func map_object(x: int, y: int) -> int:
	return objects.get(idx(x, y), -1)


func set_map_object(x: int, y: int, obj: int) -> void:
	var i := idx(x, y)
	objects[i] = obj
	if obj != MO_ORE:
		ore_kind.erase(i)
	if obj != MO_TREE:
		tree_stage.erase(i)
		tree_type.erase(i)
	if obj != MO_STONE:
		stone_stage.erase(i)
		stone_hits_left.erase(i)
	if obj != MO_FIELD:
		field_stage.erase(i)


func clear_map_object(x: int, y: int) -> void:
	objects.erase(idx(x, y))
	ore_kind.erase(idx(x, y))
	tree_stage.erase(idx(x, y))
	tree_type.erase(idx(x, y))
	stone_stage.erase(idx(x, y))
	stone_hits_left.erase(idx(x, y))
	field_stage.erase(idx(x, y))


## Baum-Wachstumsstufe (0/1/2). Ohne Eintrag = ausgewachsen (2, fällbar).
func tree_stage_at(x: int, y: int) -> int:
	return tree_stage.get(idx(x, y), TREE_BIG)


func set_tree_stage(x: int, y: int, stage: int) -> void:
	tree_stage[idx(x, y)] = clampi(stage, TREE_SEED, TREE_BIG)


func tree_type_at(x: int, y: int) -> int:
	return tree_type.get(idx(x, y), TREE_OAK)


func set_tree_type(x: int, y: int, typ: int) -> void:
	tree_type[idx(x, y)] = clampi(typ, 0, TREE_TYPE_COUNT - 1)


func tree_type_name(typ: int) -> String:
	match typ:
		TREE_PINE: return "pine"
		TREE_BIRCH: return "birch"
	return "oak"


func deterministic_tree_type(x: int, y: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (width * 83492791) ^ (height * 2654435761)
	return absi(h) % TREE_TYPE_COUNT


## Feld-Wachstumsstufe (0..3). Ohne Eintrag = frisch gesät (0).
func field_stage_at(x: int, y: int) -> int:
	return field_stage.get(idx(x, y), FIELD_SEED)


func set_field_stage(x: int, y: int, stage: int) -> void:
	field_stage[idx(x, y)] = clampi(stage, FIELD_SEED, FIELD_RIPE)


## Liegt eine Feld-Deko (Stoppel/verdorrt) auf dem Knoten? (rein dekorativ)
func has_field_decay(x: int, y: int) -> bool:
	return field_decay.has(idx(x, y))


## Art der Feld-Deko (FIELD_DECAY_*) oder -1, wenn keine.
func field_decay_at(x: int, y: int) -> int:
	return field_decay.get(idx(x, y), -1)


func set_field_decay(x: int, y: int, kind: int) -> void:
	field_decay[idx(x, y)] = kind


func clear_field_decay(x: int, y: int) -> void:
	field_decay.erase(idx(x, y))


func stone_stage_at(x: int, y: int) -> int:
	return stone_stage.get(idx(x, y), STONE_SMALL)


func set_stone_stage(x: int, y: int, stage: int) -> void:
	stone_stage[idx(x, y)] = clampi(stage, STONE_SMALL, STONE_BIG)


func stone_hits_left_at(x: int, y: int) -> int:
	return stone_hits_left.get(idx(x, y), stone_stage_at(x, y))


func set_stone_hits_left(x: int, y: int, hits: int) -> void:
	stone_hits_left[idx(x, y)] = maxi(hits, 1)


func ore_kind_at(x: int, y: int) -> int:
	return ore_kind.get(idx(x, y), -1)


func set_ore_kind(x: int, y: int, kind: int) -> void:
	ore_kind[idx(x, y)] = kind


# --- Sichtbarer Erz-Hinweis (Deko, #54) -----------------------------------

func ore_hint_kind_at(x: int, y: int) -> int:
	return ore_hint_kind.get(idx(x, y), -1)


func set_ore_hint(x: int, y: int, kind: int) -> void:
	ore_hint_kind[idx(x, y)] = kind


# --- Unterirdische Erz-Lagerstätten ---------------------------------------

func ore_deposit_kind_at(x: int, y: int) -> int:
	return ore_deposit_kind.get(idx(x, y), -1)


func ore_deposit_amount_at(x: int, y: int) -> int:
	return ore_deposit_amount.get(idx(x, y), 0)


func ore_deposit_found_at(x: int, y: int) -> bool:
	return ore_deposit_found.get(idx(x, y), false)


func set_ore_deposit(x: int, y: int, kind: int, amount: int) -> void:
	var i := idx(x, y)
	if amount <= 0:
		ore_deposit_kind.erase(i)
		ore_deposit_amount.erase(i)
		ore_deposit_found.erase(i)
		return
	ore_deposit_kind[i] = kind
	ore_deposit_amount[i] = amount


func set_ore_deposit_found(x: int, y: int, found: bool) -> void:
	var i := idx(x, y)
	if found:
		ore_deposit_found[i] = true
	else:
		ore_deposit_found.erase(i)


## Baut eine Einheit aus dem Vorkommen ab. Gibt true zurück, wenn etwas abgebaut
## wurde; leert das Vorkommen bei Erschöpfung.
func take_ore_deposit(x: int, y: int) -> bool:
	var i := idx(x, y)
	var amount: int = ore_deposit_amount.get(i, 0)
	if amount <= 0:
		return false
	amount -= 1
	if amount <= 0:
		ore_deposit_kind.erase(i)
		ore_deposit_amount.erase(i)
		ore_deposit_found.erase(i)
	else:
		ore_deposit_amount[i] = amount
	return true


# --- Fischbestand (Issue #6) ----------------------------------------------

func fish_at(x: int, y: int) -> int:
	return fish_stock.get(idx(x, y), 0)


func set_fish(x: int, y: int, amount: int) -> void:
	var i := idx(x, y)
	if amount <= 0:
		fish_stock.erase(i)
	else:
		fish_stock[i] = amount


## Fängt einen Fisch am Knoten. Gibt true zurück, wenn etwas da war; leert den
## Knoten bei Erschöpfung.
func take_fish(x: int, y: int) -> bool:
	var i := idx(x, y)
	var amount: int = fish_stock.get(i, 0)
	if amount <= 0:
		return false
	amount -= 1
	if amount <= 0:
		fish_stock.erase(i)
	else:
		fish_stock[i] = amount
	return true


# --- Hafenpunkte (#46) ----------------------------------------------------

func is_harbor_point(x: int, y: int) -> bool:
	return harbor_points.has(idx(x, y))


func set_harbor_point(x: int, y: int, on: bool) -> void:
	if on:
		harbor_points[idx(x, y)] = true
	else:
		harbor_points.erase(idx(x, y))


## Alle Hafenpunkte als Knoten-Koordinaten (für Expeditions-Zielwahl/Rendering).
func harbor_point_list() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in harbor_points:
		@warning_ignore("integer_division")
		out.append(Vector2i(int(i) % width, int(i) / width))
	return out


## Bildschirmposition eines Knotens inklusive seiner Höhe.
func node_world(x: int, y: int) -> Vector2:
	return Grid.node_to_world(x, y, get_height(x, y))


## Gültiger Nachbar oder Vector2i(-1,-1).
func neighbor(x: int, y: int, dir: int) -> Vector2i:
	var n := Grid.neighbor(x, y, dir)
	if in_bounds(n.x, n.y):
		return n
	return Vector2i(-1, -1)


## Die Terrains der 6 Dreiecke um einen Knoten (Rand → Wasser).
func terrains_around(x: int, y: int) -> Array[int]:
	var out: Array[int] = []
	for tri in Grid.triangles_around(x, y):
		out.append(get_tri(tri.pos, tri.kind))
	return out


## Maximaler Höhenunterschied zu den 6 Nachbarn (für Hangneigung/BQ).
func max_slope(x: int, y: int) -> int:
	var h0 := get_height(x, y)
	var m := 0
	for dir in Grid.DIRS:
		var n := neighbor(x, y, dir)
		if n.x >= 0:
			m = maxi(m, absi(get_height(n.x, n.y) - h0))
	return m


## Zieht die 6 Nachbarknoten von (x,y) auf dessen Höhe (Planierer #49, RTTR
## nofPlaner: ChangeAltitude der umliegenden Knoten auf die Bauknoten-Höhe). Der
## Bauknoten selbst bleibt unverändert. Gibt true zurück, wenn dabei mindestens ein
## Knoten verändert wurde.
func flatten_around(x: int, y: int) -> bool:
	var h0 := get_height(x, y)
	var changed := false
	for dir in Grid.DIRS:
		var n := neighbor(x, y, dir)
		if n.x >= 0 and get_height(n.x, n.y) != h0:
			set_height(n.x, n.y, h0)
			changed = true
	return changed
