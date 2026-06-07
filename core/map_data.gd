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

# Statische Karten-Objekte (Baum/Stein/Erz) — blockieren Bauen & Straßen.
enum { MO_TREE, MO_STONE, MO_ORE }
var objects: Dictionary = {}   # idx -> MO_*

# Erzsorte je Erz-Knoten (nur gesetzt, wo objects == MO_ORE).
enum { ORE_COAL, ORE_IRON, ORE_GOLD, ORE_GRANITE }
var ore_kind: Dictionary = {}  # idx -> ORE_*

# Wachstumsstufe je Baum-Knoten: 0 = Setzling, 1 = kleiner Baum, 2 = großer Baum.
# Nur Stufe 2 darf gefällt werden. Ohne Eintrag gilt ein Baum als ausgewachsen (2),
# damit Karten/Spielstände ohne Stufen-Info wie bisher funktionieren.
enum { TREE_SEED, TREE_SMALL, TREE_BIG }
var tree_stage: Dictionary = {} # idx -> 0/1/2

# Baumtyp je Baum-Knoten. Wird beim Generieren/Pflanzen deterministisch gewählt.
enum { TREE_OAK, TREE_PINE, TREE_BIRCH }
const TREE_TYPE_COUNT := 3
var tree_type: Dictionary = {}  # idx -> TREE_*

# Stein-Stufe je Stein-Knoten: 3/2/1 Abbauten übrig. Ohne Eintrag = alter
# Spielstand mit kleinem Stein (1 Abbau).
enum { STONE_SMALL = 1, STONE_MEDIUM = 2, STONE_BIG = 3 }
var stone_stage: Dictionary = {} # idx -> 1/2/3


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


func clear_map_object(x: int, y: int) -> void:
	objects.erase(idx(x, y))
	ore_kind.erase(idx(x, y))
	tree_stage.erase(idx(x, y))
	tree_type.erase(idx(x, y))
	stone_stage.erase(idx(x, y))


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


func stone_stage_at(x: int, y: int) -> int:
	return stone_stage.get(idx(x, y), STONE_SMALL)


func set_stone_stage(x: int, y: int, stage: int) -> void:
	stone_stage[idx(x, y)] = clampi(stage, STONE_SMALL, STONE_BIG)


func ore_kind_at(x: int, y: int) -> int:
	return ore_kind.get(idx(x, y), -1)


func set_ore_kind(x: int, y: int, kind: int) -> void:
	ore_kind[idx(x, y)] = kind


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
