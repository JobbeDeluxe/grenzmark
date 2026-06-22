class_name MiniMap
extends Control

## Übersichtskarte unten rechts. Zeigt Terrain, Gebiet, Gebäude und den
## sichtbaren Ausschnitt. Klick verschiebt die Kamera.

var state: WorldState
var economy: Economy
var cam: Camera2D
var fog_enabled := false

var _accum := 0.0


func setup(s: WorldState, e: Economy, c: Camera2D) -> void:
	state = s
	economy = e
	cam = c
	queue_redraw()


func set_fog_enabled(on: bool) -> void:
	if fog_enabled == on:
		return
	fog_enabled = on
	queue_redraw()


func shows_node(x: int, y: int) -> bool:
	if state == null or state.map == null or not state.map.in_bounds(x, y):
		return false
	return _should_draw_idx(state.map.idx(x, y))


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.4:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	if state == null:
		return
	var w := state.map.width
	var h := state.map.height
	var sx := size.x / (w + 0.5)
	var sy := size.y / h
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))

	if fog_enabled:
		for key in state.explored:
			var idx := int(key)
			if idx < 0 or idx >= w * h:
				continue
			_draw_map_node(idx % w, int(idx / w), sx, sy)
	else:
		for y in h:
			for x in w:
				_draw_map_node(x, y, sx, sy)

	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if not _should_draw_idx(state.map.idx(b.pos.x, b.pos.y)):
			continue
		var bx := b.pos.x * sx + (sx * 0.5 if (b.pos.y & 1) == 1 else 0.0)
		var dot := Color(1, 1, 0.3) if b.is_hq else Color(1, 1, 1)
		draw_rect(Rect2(bx - 1, b.pos.y * sy - 1, 3, 3), dot)

	# Sichtbarer Ausschnitt
	var g := Grid.world_to_node_approx(cam.position)
	var vis := get_viewport_rect().size / cam.zoom
	var gw := vis.x / Grid.TILE_W
	var gh := vis.y / Grid.TILE_H
	var rx := (g.x - gw * 0.5) * sx
	var ry := (g.y - gh * 0.5) * sy
	draw_rect(Rect2(rx, ry, gw * sx, gh * sy), Color(1, 1, 1, 0.9), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sx := size.x / (state.map.width + 0.5)
		var sy := size.y / state.map.height
		var y := int(event.position.y / sy)
		var off := sx * 0.5 if (y & 1) == 1 else 0.0
		var x := int((event.position.x - off) / sx)
		if state.map.in_bounds(x, y):
			cam.position = state.map.node_world(x, y)
			accept_event()


func _should_draw_idx(idx: int) -> bool:
	return not fog_enabled or state.explored.has(idx)


func _draw_map_node(x: int, y: int, sx: float, sy: float) -> void:
	var t := state.map.get_tri(Vector2i(x, y), Grid.TRI_R)
	var col := GameTheme.terrain_color(t)
	var idx := state.map.idx(x, y)
	if state.territory.has(idx):
		col = col.lerp(Color(0.3, 0.7, 1.0), 0.35)
	# Erkundet, aber aktuell nicht einsehbar → gedimmt (Doppelzustand, #62).
	if fog_enabled and not state.visible.has(idx):
		col = col.darkened(0.55)
	var px := x * sx + (sx * 0.5 if (y & 1) == 1 else 0.0)
	draw_rect(Rect2(px, y * sy, ceilf(sx), ceilf(sy)), col)
