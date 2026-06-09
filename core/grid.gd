class_name Grid
extends RefCounted

## Reine Geometrie des Siedler-Gitters.
##
## Die Karte ist ein versetztes Dreiecksgitter: ungerade Zeilen sind um eine
## halbe Kachel nach rechts verschoben. Jeder Knoten hat 6 Nachbarn und
## "besitzt" 2 Terrain-Dreiecke (ein rechtes R und ein unteres D).
##
## Alle Funktionen sind statisch und kennen keine konkrete Karte — sie rechnen
## nur mit Koordinaten. Das Klemmen an den Kartenrand macht MapData.

# Bildschirm-Maße eines Knotens (dimetrische, flach gedrückte Darstellung).
const TILE_W := 64.0          # waagerechter Abstand zweier Knoten einer Zeile
const TILE_H := 32.0          # senkrechter Abstand zweier Zeilen
const HEIGHT_PER_LEVEL := 4.0 # Pixel, um die ein Höhenpunkt nach oben rückt

# Die 6 Richtungen. Reihenfolge im Uhrzeigersinn ab Osten.
enum { E, NE, NW, W, SW, SE }
const DIR_COUNT := 6
const DIRS := [E, NE, NW, W, SW, SE]

# Die zwei Dreiecke, die ein Knoten besitzt.
enum { TRI_R, TRI_D }


## Nachbarknoten in Richtung [param dir]. Berücksichtigt den Zeilenversatz.
static func neighbor(x: int, y: int, dir: int) -> Vector2i:
	var odd := (y & 1) == 1
	match dir:
		E:  return Vector2i(x + 1, y)
		W:  return Vector2i(x - 1, y)
		NE: return Vector2i(x + (1 if odd else 0), y - 1)
		NW: return Vector2i(x + (0 if odd else -1), y - 1)
		SE: return Vector2i(x + (1 if odd else 0), y + 1)
		SW: return Vector2i(x + (0 if odd else -1), y + 1)
	return Vector2i(x, y)


## Gegenrichtung (für Hin- und Rückweg auf Straßen).
static func opposite(dir: int) -> int:
	match dir:
		E:  return W
		W:  return E
		NE: return SW
		SW: return NE
		NW: return SE
		SE: return NW
	return dir


## Bildschirmposition eines Knotens (Höhe rückt ihn nach oben).
static func node_to_world(x: int, y: int, h: int) -> Vector2:
	var sx := x * TILE_W + (TILE_W * 0.5 if (y & 1) == 1 else 0.0)
	var sy := y * TILE_H - h * HEIGHT_PER_LEVEL
	return Vector2(sx, sy)


## Grobe Umkehrung ohne Höhe — liefert den ungefähren Knoten unter einem Punkt.
## Das genaue Picking (mit Höhe) macht WorldState.pick_node().
static func world_to_node_approx(world: Vector2) -> Vector2i:
	var y := int(round(world.y / TILE_H))
	var off := TILE_W * 0.5 if (y & 1) == 1 else 0.0
	var x := int(round((world.x - off) / TILE_W))
	return Vector2i(x, y)


## Die 3 Eck-Knoten eines Dreiecks.
## TRI_R von N: N, E(N), SE(N).  TRI_D von N: N, SE(N), SW(N).
static func triangle_corners(x: int, y: int, kind: int) -> Array:
	if kind == TRI_R:
		return [Vector2i(x, y), neighbor(x, y, E), neighbor(x, y, SE)]
	return [Vector2i(x, y), neighbor(x, y, SE), neighbor(x, y, SW)]


## Die bis zu 3 Dreiecke, die mit diesem Dreieck eine Kante teilen.
## Randdreiecke koennen Nachbarn ausserhalb der Karte liefern; MapData filtert
## oder behandelt diese Stellen als Wasser.
static func tri_edge_neighbors(x: int, y: int, kind: int) -> Array:
	var self_pos := Vector2i(x, y)
	var corners := triangle_corners(x, y, kind)
	var edges := [
		[corners[0], corners[1]],
		[corners[1], corners[2]],
		[corners[2], corners[0]],
	]
	var out := []
	var seen := {}
	for edge in edges:
		var found := false
		for c in edge:
			for tri in triangles_around(c.x, c.y):
				var pos: Vector2i = tri.pos
				var tk: int = tri.kind
				if pos == self_pos and tk == kind:
					continue
				if not _tri_has_edge(pos.x, pos.y, tk, edge[0], edge[1]):
					continue
				var key := "%d,%d,%d" % [pos.x, pos.y, tk]
				if not seen.has(key):
					out.append({ pos = pos, kind = tk })
					seen[key] = true
				found = true
				break
			if found:
				break
	return out


static func _tri_has_edge(x: int, y: int, kind: int, a: Vector2i, b: Vector2i) -> bool:
	var corners := triangle_corners(x, y, kind)
	return corners.has(a) and corners.has(b)


## Die 6 Dreiecke, die einen Knoten umgeben (für BauQualität & Schattierung).
## Jeder Eintrag ist { pos = Vector2i, kind = TRI_R|TRI_D }.
static func triangles_around(x: int, y: int) -> Array:
	var nw := neighbor(x, y, NW)
	var w := neighbor(x, y, W)
	var ne := neighbor(x, y, NE)
	return [
		{ pos = Vector2i(x, y), kind = TRI_R },
		{ pos = Vector2i(x, y), kind = TRI_D },
		{ pos = w,  kind = TRI_R },
		{ pos = nw, kind = TRI_R },
		{ pos = nw, kind = TRI_D },
		{ pos = ne, kind = TRI_D },
	]
