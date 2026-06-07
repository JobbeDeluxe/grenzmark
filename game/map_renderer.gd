class_name MapRenderer
extends Node2D

## STATISCHE Ebene: Terrain, Gebiet, Objekte, Straßen, Gebäude, Flaggen.
## Wird NUR bei echten Änderungen neu gezeichnet (nicht bei Mausbewegung).
## Scharfe Darstellung: flache Dreiecksfarben + nearest-Filter für Texturen.

const C_WALL := Color(0.86, 0.79, 0.62)
const C_DOOR := Color(0.28, 0.18, 0.10)
const C_STONE := Color(0.62, 0.62, 0.66)
const C_OUTLINE := Color(0.12, 0.10, 0.08)
const ROAD_W := 8.0        # Straßenbreite (Pixel)
const ENTRANCE_ROAD_W := 7.0
const ROAD_TILE := 48.0    # Kachellänge der Straßentextur entlang des Wegs

var state: WorldState
var _font: Font = ThemeDB.fallback_font

var fog_enabled := false        # Nebel des Krieges an/aus (zum Testen)
var show_build_spots := false   # Bauplätze einblenden (Leertaste)


func setup(world_state: WorldState) -> void:
	state = world_state
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # eigene Texturen scharf
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	_draw_terrain()
	# Keine Flächen-Einfärbung des Gebiets — nur Grenzsteine (siehe _draw_border).
	_draw_objects()
	_draw_roads()
	_draw_entrance_paths()
	_draw_buildings()
	_draw_enemy_markers()
	_draw_flags()
	_draw_border()
	if show_build_spots:
		_draw_build_spots()
	if fog_enabled:
		_draw_fog()


## Bauplatz-Anzeige (Leertaste): Symbole je effektiver Bauqualität.
func _draw_build_spots() -> void:
	var map := state.map
	for y in map.height:
		for x in map.width:
			var p := map.node_world(x, y)
			if state.can_place_road_flag(x, y):
				_draw_build_spot_road_flag(p)
				continue
			if state._occ(x, y) == WorldState.OBJ_NONE and not state.has_object(x, y) \
					and _node_in_player_area(x, y) and state.node_walkable(x, y) \
					and state.road_margin_blocked(x, y):
				_draw_build_spot_blocked(p)
			var bq := state.actual_build_spot_bq(x, y)
			if bq < WorldState.BQ_FLAG:
				continue
			_draw_build_spot_symbol(p, bq)


func _node_in_player_area(x: int, y: int) -> bool:
	return state.territory.is_empty() or state.in_territory(x, y)


func _draw_build_spot_symbol(p: Vector2, bq: int) -> void:
	var col := _spot_color(bq)
	var key := _build_spot_key(bq)
	if _draw_build_spot_texture(p, key):
		return
	match bq:
		WorldState.BQ_CASTLE:
			_draw_build_spot_box(p, Vector2(24, 18), col, 2.0)
			_draw_build_spot_box(p, Vector2(14, 10), col.lightened(0.15), 1.2)
		WorldState.BQ_HOUSE:
			_draw_build_spot_box(p, Vector2(18, 14), col, 1.8)
			draw_line(p + Vector2(-7, -7), p + Vector2(0, -13), col, 1.4, true)
			draw_line(p + Vector2(7, -7), p + Vector2(0, -13), col, 1.4, true)
		WorldState.BQ_HUT:
			_draw_build_spot_box(p, Vector2(13, 10), col, 1.7)
		WorldState.BQ_MINE:
			var pts := PackedVector2Array([
				p + Vector2(-10, 4), p + Vector2(10, 4), p + Vector2(0, -12), p + Vector2(-10, 4)
			])
			draw_polyline(pts, col, 2.0, true)
			draw_line(p + Vector2(-4, -2), p + Vector2(4, -7), col.lightened(0.2), 1.3, true)
		WorldState.BQ_FLAG:
			_draw_spot_flag(p, col)


func _build_spot_key(bq: int) -> String:
	match bq:
		WorldState.BQ_CASTLE: return "castle"
		WorldState.BQ_HOUSE: return "house"
		WorldState.BQ_HUT: return "hut"
		WorldState.BQ_MINE: return "mine"
		WorldState.BQ_FLAG: return "flag"
	return "blocked"


func _draw_build_spot_texture(p: Vector2, key: String) -> bool:
	var tex := GameTheme.build_spot_texture(key)
	if tex == null:
		return false
	var sz := GameTheme.build_spot_size(key)
	draw_texture_rect(tex, Rect2(p.x - sz.x * 0.5, p.y - sz.y * 0.5, sz.x, sz.y), false)
	return true


func _draw_build_spot_box(p: Vector2, size: Vector2, col: Color, width: float) -> void:
	var r := Rect2(p - size * 0.5, size)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y), r.position])
	draw_polyline(pts, col, width, true)
	draw_line(r.position, r.end, col.darkened(0.12), 1.0, true)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y),
		col.darkened(0.12), 1.0, true)


func _draw_spot_flag(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(0, -10), p + Vector2(0, 3), Color(0.18, 0.12, 0.08, 0.85), 1.4, true)
	draw_rect(Rect2(p.x, p.y - 10, 8, 5), col)
	draw_circle(p, 2.0, col.lightened(0.15))


func _draw_build_spot_road_flag(p: Vector2) -> void:
	if _draw_build_spot_texture(p, "road_flag"):
		return
	var col := Color(0.95, 0.15, 0.18, 0.95)
	draw_circle(p, 5.0, Color(1.0, 1.0, 1.0, 0.55))
	_draw_spot_flag(p + Vector2(0, -2), col)


func _draw_build_spot_blocked(p: Vector2) -> void:
	if _draw_build_spot_texture(p, "blocked"):
		return
	var col := Color(1.0, 0.18, 0.12, 0.82)
	draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), col, 2.0, true)
	draw_line(p + Vector2(6, -6), p + Vector2(-6, 6), col, 2.0, true)


func _spot_color(bq: int) -> Color:
	match bq:
		WorldState.BQ_CASTLE: return Color(0.2, 0.9, 0.2)
		WorldState.BQ_HOUSE:  return Color(0.7, 0.9, 0.2)
		WorldState.BQ_HUT:    return Color(0.95, 0.85, 0.2)
		WorldState.BQ_MINE:   return Color(0.6, 0.4, 0.9)
		WorldState.BQ_FLAG:   return Color(0.95, 0.55, 0.2)
	return Color(0.6, 0.6, 0.6, 0.6)


## Nebel des Krieges: unerkundete Dreiecke abdunkeln.
func _draw_fog() -> void:
	var fog := Color(0.03, 0.03, 0.05, 0.92)
	var map := state.map
	for y in map.height:
		for x in map.width:
			_fog_tri(x, y, Grid.TRI_R, fog)
			_fog_tri(x, y, Grid.TRI_D, fog)


func _fog_tri(x: int, y: int, kind: int, col: Color) -> void:
	var corners := Grid.triangle_corners(x, y, kind)
	var pts := PackedVector2Array()
	for c in corners:
		if not state.map.in_bounds(c.x, c.y):
			return
		if state.explored.has(state.map.idx(c.x, c.y)):
			return  # mindestens eine Ecke erkundet → nicht abdunkeln
		pts.append(state.map.node_world(c.x, c.y))
	draw_colored_polygon(pts, col)


# --- Terrain (scharf, flach pro Dreieck) ---------------------------------

func _draw_terrain() -> void:
	var map := state.map
	for y in map.height:
		for x in map.width:
			_draw_tri(x, y, Grid.TRI_R)
			_draw_tri(x, y, Grid.TRI_D)


func _draw_tri(x: int, y: int, kind: int) -> void:
	var map := state.map
	var corners := Grid.triangle_corners(x, y, kind)
	var pts := PackedVector2Array()
	var hsum := 0
	for c in corners:
		if not map.in_bounds(c.x, c.y):
			return
		pts.append(map.node_world(c.x, c.y))
		hsum += map.get_height(c.x, c.y)
	var t := map.get_tri(Vector2i(x, y), kind)
	var shade: float = clampf(0.80 + (hsum / 3.0) * 0.012, 0.62, 1.18)
	var col := GameTheme.terrain_color(t) * shade
	col.a = 1.0
	var tex := GameTheme.terrain_texture(t)
	if tex != null:
		var tint := Color(shade, shade, shade, 1.0)
		var uvs := PackedVector2Array()
		for c in corners:
			var flat := Grid.node_to_world(c.x, c.y, 0)
			uvs.append(flat / GameTheme.terrain_uv_world_size())
		draw_polygon(pts, PackedColorArray([tint, tint, tint]), uvs, tex)
		return
	draw_colored_polygon(pts, col)


## Territorium: ein Dreieck wird eingefärbt, wenn ALLE DREI Eck-Nodes zum
## Gebiet gehören. So läuft die Farbgrenze durch die Nodes (Node zu Node) und
## die Fläche ist einfarbig — passend zum Hexagon-Besitz von Die Siedler.
func _draw_territory() -> void:
	var map := state.map
	for y in map.height:
		for x in map.width:
			_fill_owned_tri(x, y, Grid.TRI_R, state.territory, GameTheme.territory_color())
			_fill_owned_tri(x, y, Grid.TRI_D, state.territory, GameTheme.territory_color())
			_fill_owned_tri(x, y, Grid.TRI_R, state.enemy_territory, GameTheme.enemy_territory_color())
			_fill_owned_tri(x, y, Grid.TRI_D, state.enemy_territory, GameTheme.enemy_territory_color())


func _fill_owned_tri(x: int, y: int, kind: int, owned: Dictionary, col: Color) -> void:
	var corners := Grid.triangle_corners(x, y, kind)
	var pts := PackedVector2Array()
	for c in corners:
		if not state.map.in_bounds(c.x, c.y):
			return
		if not owned.has(state.map.idx(c.x, c.y)):
			return
		pts.append(state.map.node_world(c.x, c.y))
	draw_colored_polygon(pts, col)


func _draw_border() -> void:
	_border_stones(state.territory, GameTheme.border_color(), 0)
	_border_stones(state.enemy_territory, GameTheme.enemy_border_color(), 1)


func _border_stones(owned: Dictionary, col: Color, owner: int) -> void:
	var tex := GameTheme.border_texture(owner)
	for i in owned:
		var x := int(i) % state.map.width
		var y := int(i) / state.map.width
		for dir in Grid.DIRS:
			var nb := Grid.neighbor(x, y, dir)
			if not state.map.in_bounds(nb.x, nb.y) or not owned.has(state.map.idx(nb.x, nb.y)):
				var p := state.map.node_world(x, y)
				if tex != null:
					draw_texture_rect(tex, Rect2(p.x - 6, p.y - 12, 12, 12), false)
				else:
					draw_circle(p + Vector2(0, -3), 2.5, col)
				break


# --- Karten-Objekte ------------------------------------------------------

func _draw_objects() -> void:
	var map := state.map
	for i in map.objects:
		var x := int(i) % map.width
		var y := int(i) / map.width
		var p := map.node_world(x, y)
		if int(map.objects[i]) == MapData.MO_TREE:
			_draw_tree_object(p, map.tree_stage_at(x, y), map.tree_type_at(x, y))
			continue
		if int(map.objects[i]) == MapData.MO_STONE:
			_draw_stone_object(p, map.stone_stage_at(x, y))
			continue
		var oname: String = ["tree", "stone", "ore"][int(map.objects[i])]
		var tex := GameTheme.object_texture(oname)
		if tex != null:
			var sz := GameTheme.object_draw_size(oname)
			draw_texture_rect(tex, Rect2(p.x - sz.x * 0.5, p.y - sz.y, sz.x, sz.y), false)
			continue
		match map.objects[i]:
			MapData.MO_TREE: _paint_tree(p, MapData.TREE_BIG)
			MapData.MO_STONE: _paint_stone(p)
			MapData.MO_ORE: _paint_ore(p, map.ore_kind_at(x, y))


func _draw_tree_object(p: Vector2, stage: int, typ := MapData.TREE_OAK) -> void:
	var base := "tree_%s" % state.map.tree_type_name(typ)
	var name := base
	if stage == MapData.TREE_SEED:
		name = "%s_seed" % base
	elif stage == MapData.TREE_SMALL:
		name = "%s_small" % base
	var tex := GameTheme.object_texture(name)
	if tex == null:
		var legacy := "tree"
		if stage == MapData.TREE_SEED:
			legacy = "tree_seed"
		elif stage == MapData.TREE_SMALL:
			legacy = "tree_small"
		tex = GameTheme.object_texture(legacy)
	if tex != null:
		var sz := GameTheme.object_draw_size(name)
		if tex == GameTheme.object_texture("tree"):
			match stage:
				MapData.TREE_SEED: sz *= 0.35
				MapData.TREE_SMALL: sz *= 0.62
		draw_texture_rect(tex, Rect2(p.x - sz.x * 0.5, p.y - sz.y, sz.x, sz.y), false)
	else:
		_paint_tree(p, stage)


func _draw_stone_object(p: Vector2, stage: int) -> void:
	var name := "stone"
	if stage == MapData.STONE_MEDIUM:
		name = "stone_stage2"
	elif stage == MapData.STONE_BIG:
		name = "stone_stage3"
	var tex := GameTheme.object_texture(name)
	if tex == null and name != "stone":
		tex = GameTheme.object_texture("stone")
	if tex != null:
		var sz := GameTheme.object_draw_size(name)
		draw_texture_rect(tex, Rect2(p.x - sz.x * 0.5, p.y - sz.y, sz.x, sz.y), false)
	else:
		_paint_stone(p, stage)


func _paint_tree(p: Vector2, stage := MapData.TREE_BIG) -> void:
	var s := 1.0
	match stage:
		MapData.TREE_SEED: s = 0.35
		MapData.TREE_SMALL: s = 0.62
	draw_rect(Rect2(p.x - 1.5 * s, p.y - 6 * s, 3 * s, 6 * s), Color(0.40, 0.27, 0.15))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-7, -5) * s, p + Vector2(7, -5) * s, p + Vector2(0, -16) * s]),
		Color(0.16, 0.40, 0.16))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-5, -11) * s, p + Vector2(5, -11) * s, p + Vector2(0, -20) * s]),
		Color(0.20, 0.48, 0.20))


func _paint_stone(p: Vector2, stage := MapData.STONE_SMALL) -> void:
	var s := 1.0
	match stage:
		MapData.STONE_MEDIUM: s = 1.35
		MapData.STONE_BIG: s = 1.7
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-7, 0) * s, p + Vector2(-3, -8) * s, p + Vector2(4, -6) * s,
		p + Vector2(7, 0) * s]), C_STONE)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(2, 0) * s, p + Vector2(6, -5) * s, p + Vector2(9, 0) * s]),
		C_STONE.darkened(0.15))


func _paint_ore(p: Vector2, kind: int) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-6, 0), p + Vector2(-2, -7), p + Vector2(5, -5),
		p + Vector2(7, 0)]), Color(0.42, 0.40, 0.44))
	var c := _ore_color(kind)
	draw_circle(p + Vector2(-1, -3), 1.8, c)
	draw_circle(p + Vector2(3, -2), 1.5, c)


func _ore_color(kind: int) -> Color:
	match kind:
		MapData.ORE_COAL: return Color(0.12, 0.12, 0.14)
		MapData.ORE_IRON: return Color(0.70, 0.45, 0.30)
		MapData.ORE_GOLD: return Color(0.95, 0.80, 0.25)
		MapData.ORE_GRANITE: return Color(0.75, 0.75, 0.78)
	return Color(0.80, 0.55, 0.30)


# --- Straßen -------------------------------------------------------------

func _draw_roads() -> void:
	for r in state.roads:
		var nodes := r.nodes
		if nodes.size() < 2:
			continue
		# Segmentweise: jedes Teilstück nach dem Untergrund seines Knotens texturieren.
		for k in range(nodes.size() - 1):
			var a := state.map.node_world(nodes[k].x, nodes[k].y)
			var b := state.map.node_world(nodes[k + 1].x, nodes[k + 1].y)
			var terr := state.map.get_tri(nodes[k], Grid.TRI_R)
			var tex := GameTheme.road_texture(terr, r.level)
			if tex != null:
				_road_quad(a, b, tex, ROAD_W)
			else:
				draw_line(a, b, Color(0.78, 0.64, 0.40), ROAD_W, true)


## Ein Straßen-Segment als getiltes Textur-Quad (entlang der Wegrichtung).
func _road_quad(a: Vector2, b: Vector2, tex: Texture2D, width := ROAD_W) -> void:
	var dir := b - a
	var ln := dir.length()
	if ln < 0.01:
		return
	var n := dir / ln
	var perp := Vector2(-n.y, n.x) * (width * 0.5)
	var pts := PackedVector2Array([a - perp, b - perp, b + perp, a + perp])
	var uw := ln / ROAD_TILE
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(uw, 0), Vector2(uw, 1), Vector2(0, 1)])
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	draw_polygon(pts, white, uvs, tex)


## Kurzer Weg von der Eingangsflagge zur Tür des Gebäudes (wie in S2).
func _draw_entrance_paths() -> void:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		var flag := state.map.node_world(b.flag_pos.x, b.flag_pos.y)
		var door := state.map.node_world(b.pos.x, b.pos.y) + GameTheme.entrance_offset(b.def_id)
		var terr := state.map.get_tri(b.flag_pos, Grid.TRI_R)
		var tex := GameTheme.road_texture(terr, WorldState.ROAD_DIRT)
		if tex != null:
			_road_quad(flag, door, tex, ENTRANCE_ROAD_W)
		else:
			draw_line(flag, door, Color(0.74, 0.60, 0.36), ENTRANCE_ROAD_W, true)


# --- Gebäude (scharfe Platzhalter-Grafik oder Textur) --------------------

func _draw_buildings() -> void:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		var p := state.map.node_world(b.pos.x, b.pos.y) + GameTheme.building_offset(b.def_id)
		# Baustelle: nur das Gerüst (das wachsende Gebäude zeichnet der UnitRenderer).
		if b.under_construction:
			_paint_site(p, b)
			continue
		var tex := GameTheme.building_texture(b.def_id)
		if tex != null:
			var sz := _dims(b.size, b.def_id).x * GameTheme.texture_scale()
			if b.is_hq:
				sz *= GameTheme.hq_scale()  # Hauptquartier sticht heraus
			draw_texture_rect(tex, Rect2(p.x - sz * 0.5, p.y - sz, sz, sz), false)
			continue
		if b.is_hq:
			_paint_hq(p)
		elif b.size == WorldState.BQ_MINE:
			_paint_mine(p)
		elif String(BuildingCatalog.get_def(b.def_id).get("category", "")) == "militaer":
			_paint_tower(p, b)
		else:
			_paint_house(p, b)


## Roter Umriss + Fähnchen über allen Gegner-Gebäuden.
func _draw_enemy_markers() -> void:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 1:
			continue
		var p := state.map.node_world(b.pos.x, b.pos.y) + GameTheme.building_offset(b.def_id)
		var d := _dims(b.size, b.def_id)
		# Kein roter Rahmen mehr — nur ein kleines Besitzer-Fähnchen.
		_paint_flag(p + Vector2(0, -d.y - 6), Color(0.95, 0.15, 0.15))


func _dims(size: int, def_id := "") -> Vector2:
	return GameTheme.building_dims(size, def_id)


func _paint_house(p: Vector2, b: WorldState.Building) -> void:
	var d := _dims(b.size, b.def_id)
	var w := d.x
	var h := d.y
	var wall_h := h * 0.6
	var wall_top := p.y - wall_h
	var roof := GameTheme.building_color(b.def_id)
	draw_rect(Rect2(p.x - w * 0.5, wall_top, w, wall_h), C_WALL)
	draw_rect(Rect2(p.x - w * 0.5, wall_top, w, wall_h), C_OUTLINE, false, 1.0)
	var rpts := PackedVector2Array([
		Vector2(p.x - w * 0.5 - 2, wall_top), Vector2(p.x + w * 0.5 + 2, wall_top),
		Vector2(p.x, p.y - h)])
	draw_colored_polygon(rpts, roof)
	draw_polyline(rpts + PackedVector2Array([rpts[0]]), C_OUTLINE, 1.0)
	draw_rect(Rect2(p.x - 3, p.y - 9, 6, 9), C_DOOR)


func _paint_tower(p: Vector2, b: WorldState.Building) -> void:
	var d := _dims(b.size, b.def_id)
	var w := d.x * 0.8
	var h := d.y * 1.15
	var body := Rect2(p.x - w * 0.5, p.y - h, w, h)
	draw_rect(body, C_STONE)
	draw_rect(body, C_OUTLINE, false, 1.0)
	# Zinnen
	var n := 3
	var bw := w / float(n)
	for k in n:
		draw_rect(Rect2(p.x - w * 0.5 + k * bw, p.y - h - 4, bw - 1.5, 4), C_STONE.darkened(0.1))
	draw_rect(Rect2(p.x - 3, p.y - 10, 6, 10), C_DOOR)
	_paint_flag(p + Vector2(w * 0.5 - 2, -h - 4), Color(0.75, 0.20, 0.20))
	# Garnison: gefüllte Punkte = Soldaten, leere = freie Plätze
	for k in b.capacity:
		var c := Color(0.30, 0.45, 0.85) if k < b.garrison else Color(0.3, 0.3, 0.3)
		draw_circle(p + Vector2(-w * 0.5 + 3 + k * 5.0, 4), 2.0, c)
	# Beförderungen (Münzen) = goldene Punkte darüber
	for k in b.promotions:
		draw_circle(p + Vector2(-w * 0.5 + 3 + k * 4.0, -1), 1.5, Color(0.95, 0.82, 0.3))


func _paint_hq(p: Vector2) -> void:
	var w := 56.0
	var h := 48.0
	var body := Rect2(p.x - w * 0.5, p.y - h, w, h)
	draw_rect(body, Color(0.82, 0.74, 0.55))
	draw_rect(body, C_OUTLINE, false, 1.5)
	var n := 4
	var bw := w / float(n)
	for k in n:
		draw_rect(Rect2(p.x - w * 0.5 + k * bw, p.y - h - 5, bw - 2, 5), Color(0.70, 0.62, 0.45))
	draw_rect(Rect2(p.x - 5, p.y - 12, 10, 12), C_DOOR)
	_paint_flag(p + Vector2(0, -h - 5), Color(0.90, 0.78, 0.25))


func _paint_mine(p: Vector2) -> void:
	var w := 24.0
	var h := 16.0
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-w * 0.5, 0), p + Vector2(0, -h), p + Vector2(w * 0.5, 0)]),
		Color(0.46, 0.42, 0.48))
	draw_rect(Rect2(p.x - 4, p.y - 10, 8, 10), Color(0.10, 0.09, 0.10))
	# Holzstützen am Eingang
	draw_rect(Rect2(p.x - 6, p.y - 11, 2, 11), Color(0.40, 0.27, 0.15))
	draw_rect(Rect2(p.x + 4, p.y - 11, 2, 11), Color(0.40, 0.27, 0.15))


func _paint_site(p: Vector2, b: WorldState.Building) -> void:
	# Eigene Bauplatz-Grafik bevorzugen (assets/construction/site.png o. <def>_site.png).
	var tex := GameTheme.construction_site_texture(b.def_id)
	if tex != null:
		var sz := _dims(b.size, b.def_id).x * GameTheme.texture_scale()
		draw_texture_rect(tex, Rect2(p.x - sz * 0.5, p.y - sz, sz, sz), false)
		return
	var d := _dims(b.size, b.def_id)
	var rect := Rect2(p.x - d.x * 0.5, p.y - d.y, d.x, d.y)
	draw_rect(rect, Color(0.6, 0.55, 0.4, 0.35))
	var y := Color(0.95, 0.88, 0.35)
	draw_rect(rect, y, false, 1.5)
	draw_line(rect.position, rect.end, y, 1.0)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), y, 1.0)


func _paint_flag(top: Vector2, col: Color) -> void:
	draw_line(top, top + Vector2(0, 12), Color(0.2, 0.2, 0.2), 1.5)
	draw_rect(Rect2(top.x, top.y, 8, 5), col)


func _draw_flags() -> void:
	# Flaggen IMMER exakt auf ihrem Knoten zeichnen — sonst passen Bild und
	# Mausklick/Picking nicht mehr zusammen (Straßen ließen sich nicht verbinden).
	for i in state.flags:
		var f: WorldState.Flag = state.flags[i]
		var p := state.map.node_world(f.pos.x, f.pos.y)
		_paint_flag(p + Vector2(0, -16), Color(0.90, 0.20, 0.20))
