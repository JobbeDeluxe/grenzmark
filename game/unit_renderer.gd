class_name UnitRenderer
extends Node2D

## DYNAMISCHE Ebene (pro Frame): bewegte Träger & Arbeiter, wartende Waren,
## sowie Hover-Marker und Straßen-Vorschau. Günstig zu zeichnen, deshalb stört
## das Neuzeichnen die Bedienung nicht (anders als die Terrain-Ebene).

var economy: Economy
var state: WorldState

# Von World gesetzt:
var hover := Vector2i(-1, -1)
var road_start := Vector2i(-1, -1)
var preview_path: Array[Vector2i] = []
var preview_ok := false
var build_preview_id := ""   # im Bau-Modus: Geist dieses Gebäudes am Mauszeiger
var _anim_time := 0.0


func setup(eco: Economy) -> void:
	economy = eco
	state = eco.state
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()


## Einheit zeichnen: gerichtetes Sprite-Sheet (pro Spieler eigenes PNG) wenn
## vorhanden, sonst Platzhalter-Figur in der Spielerfarbe.
func _unit(kind: String, p: Vector2, facing: Vector2, owner := 0, carrying := -1) -> void:
	var tex := GameTheme.unit_texture(kind, owner)
	if tex == null:
		_figure(p, GameTheme.player_color(owner), carrying)
		return
	var cols := GameTheme.ANIM_FRAMES
	var rows := GameTheme.ANIM_DIRS
	var cw := float(tex.get_width()) / cols    # Zellengröße im Sheet
	var ch := float(tex.get_height()) / rows
	# Auf Ziel-Höhe skalieren (Config), damit große PNGs nicht riesig wirken.
	var target_h := GameTheme.unit_size()
	var sc := target_h / maxf(ch, 1.0)
	var dw := cw * sc
	var dh := ch * sc
	var moving := facing.length() > 0.01
	var diri := _dir6(facing) if moving else 2  # 2 = SE/front-ish idle pose.
	var frame := (int(_anim_time * 7.0) % cols) if moving else 0
	var region := Rect2(frame * cw, diri * ch, cw, ch)
	draw_texture_rect_region(tex, Rect2(p.x - dw * 0.5, p.y - dh, dw, dh), region)
	if carrying >= 0:
		var gt := GameTheme.good_texture(carrying)
		if gt != null:
			draw_texture_rect(gt, Rect2(p.x - 5.0, p.y - dh - 8.0, 10.0, 10.0), false)
		else:
			draw_rect(Rect2(p.x - 2.0, p.y - dh - 6.0, 4.0, 4.0), GameTheme.good_color(carrying))


## Richtungsindex 0..5: NE, E, SE, SW, W, NW.
func _dir6(v: Vector2) -> int:
	if v.length() <= 0.01:
		return 2
	var dirs := [
		Vector2(1.0, -1.0).normalized(), # NE
		Vector2(1.0, 0.0),               # E
		Vector2(1.0, 1.0).normalized(),  # SE
		Vector2(-1.0, 1.0).normalized(), # SW
		Vector2(-1.0, 0.0),              # W
		Vector2(-1.0, -1.0).normalized() # NW
	]
	var n := v.normalized()
	var best := 0
	var best_dot := -999999.0
	for i in range(dirs.size()):
		var dot := n.dot(dirs[i])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


var _occluders: Array = []   # Gebäude/Bäume mit Sprite (für Y-Occlusion); gecacht
var _occ_dirty := true        # neu aufbauen? (von World bei Karten-Änderung gesetzt)


## Von World aufgerufen, wenn sich die statische Karte ändert (Bau/Abriss/Baum).
func invalidate_occluders() -> void:
	_occ_dirty = true


func _draw() -> void:
	if economy == null:
		return
	if _occ_dirty:
		_occ_dirty = false
		_collect_occluders()
	_draw_preview()
	_draw_goods()
	_draw_construction()
	_draw_carriers()
	_draw_workers()
	_draw_marchers()
	_draw_strays()
	# Tür-Träger zuletzt → IMMER im Vordergrund (läuft technisch vor dem Gebäude).
	_draw_house_carrier()
	_draw_build_preview()
	_draw_hover()


## Alle Sprites sammeln, die Einheiten verdecken können (fertige Gebäude + Bäume).
## Eine Einheit wird verdeckt, wenn ihr Fußpunkt HINTER dem Sprite-Fuß liegt
## (kleineres y) und sie im Sprite-Rechteck steht. Läuft sie davor (größeres y),
## bleibt sie sichtbar — wie bei Straßen, die hinter Gebäuden verschwinden.
func _collect_occluders() -> void:
	_occluders.clear()
	var map := state.map
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.under_construction:
			continue
		var tex := GameTheme.building_texture(b.def_id, b.owner)
		if tex == null:
			continue
		var basep := map.node_world(b.pos.x, b.pos.y) + GameTheme.building_offset(b.def_id)
		var sc := GameTheme.texture_scale()
		if b.is_hq:
			sc *= GameTheme.hq_scale()
		var sz := GameTheme.building_dims(b.size, b.def_id).x * sc
		_occluders.append({ base = basep, tex = tex, w = sz, h = sz })
	for i in map.objects:
		if int(map.objects[i]) != MapData.MO_TREE:
			continue
		var x := int(i) % map.width
		var y := int(i) / map.width
		var spr := GameTheme.tree_sprite(map.tree_type_name(map.tree_type_at(x, y)),
			map.tree_stage_at(x, y))
		if spr.tex == null:
			continue
		var sz2: Vector2 = spr.size
		_occluders.append({ base = map.node_world(x, y), tex = spr.tex, w = sz2.x, h = sz2.y })


## Verdeckt die Einheit an [param p], indem davorliegende Okkluder erneut über sie
## gezeichnet werden (opake Pixel verdecken, transparente lassen sie durchscheinen).
func _occlude(p: Vector2) -> void:
	for o in _occluders:
		if o.base.y <= p.y:
			continue  # Okkluder steht hinter/neben der Einheit → Einheit bleibt davor
		if p.y <= o.base.y - o.h:
			continue  # Einheit komplett oberhalb des Sprites → keine Überlappung
		if absf(p.x - o.base.x) > o.w * 0.5 + 2.0:
			continue  # horizontal daneben
		draw_texture_rect(o.tex, Rect2(o.base.x - o.w * 0.5, o.base.y - o.h, o.w, o.h), false)


## Geist-Vorschau des gewählten Gebäudes am Mauszeiger (Stufe 8):
## grün = baubar / rot = nicht baubar, plus Eingangsflagge und kurzer Eingangsweg.
func _draw_build_preview() -> void:
	if build_preview_id == "" or not state.map.in_bounds(hover.x, hover.y):
		return
	var d := BuildingCatalog.get_def(build_preview_id)
	if d.is_empty():
		return
	var size: int = d.get("size", WorldState.BQ_HUT)
	var ok := state.can_place_building(hover.x, hover.y, size)
	var p := state.map.node_world(hover.x, hover.y) + GameTheme.building_offset(build_preview_id)
	var tint := Color(0.45, 1.0, 0.45, 0.55) if ok else Color(1.0, 0.4, 0.4, 0.55)
	var tex := GameTheme.building_texture(build_preview_id)
	if tex != null:
		var sz := _bld_dims(size, build_preview_id).x * GameTheme.texture_scale()
		draw_texture_rect(tex, Rect2(p.x - sz * 0.5, p.y - sz, sz, sz), false, tint)
	else:
		var base := _bld_dims(size, build_preview_id)
		draw_rect(Rect2(p.x - base.x * 0.5, p.y - base.y, base.x, base.y), tint)
	# Eingangsflagge am SE-Nachbarn + kurzer Eingangsweg (wie im fertigen Bau).
	var fl := state.map.neighbor(hover.x, hover.y, Grid.SE)
	if state.map.in_bounds(fl.x, fl.y):
		var fp := state.map.node_world(fl.x, fl.y)
		draw_line(fp, p, Color(1, 1, 1, 0.35), 1.5)
		draw_circle(fp, 3.0, Color(0.95, 0.85, 0.2, 0.7))
	# Markierung am Bauknoten: grün (geht) / rot (geht nicht).
	var mark := Color(0.2, 0.95, 0.2, 0.9) if ok else Color(0.95, 0.2, 0.2, 0.9)
	draw_circle(state.map.node_world(hover.x, hover.y), 5.0, mark)


func _draw_house_carrier() -> void:
	var h: Economy.HouseCarrier = economy.hq_house
	if h == null or economy.hq_idx < 0:
		return
	if h.state == Economy.H_IDLE:
		return  # wartet im HQ → nicht zeichnen (erscheint erst beim Tragen)
	var hqpos := economy.hq_building_pos()
	var flagpos := economy.hq_flag_node()
	if hqpos.x < 0 or flagpos.x < 0:
		return
	var door := state.map.node_world(hqpos.x, hqpos.y) + GameTheme.entrance_offset("hq")
	var flag := state.map.node_world(flagpos.x, flagpos.y)
	var p := door.lerp(flag, clampf(h.t, 0.0, 1.0))
	var facing := (flag - door) if (h.state == Economy.H_OUT or h.state == Economy.H_FETCH) else (door - flag)
	var carry := h.carrying.type if h.carrying != null else -1
	_unit("carrier", p, facing, 0, carry)  # immer Vordergrund, keine Occlusion


## Kleine Menschen-Figur (Körper + Kopf + Schatten).
func _figure(p: Vector2, body: Color, carrying := -1) -> void:
	draw_circle(p + Vector2(0, 1), 3.2, Color(0, 0, 0, 0.22))
	draw_rect(Rect2(p.x - 2.0, p.y - 6.0, 4.0, 6.0), body)
	draw_circle(p + Vector2(0, -7.0), 2.2, Color(0.95, 0.82, 0.62))
	if carrying >= 0:
		var tex := GameTheme.good_texture(carrying)
		if tex != null:
			draw_texture_rect(tex, Rect2(p.x - 5.0, p.y - 16.0, 10.0, 10.0), false)
		else:
			draw_rect(Rect2(p.x - 2.0, p.y - 12.0, 4.0, 4.0), GameTheme.good_color(carrying))


func _draw_construction() -> void:
	for i in economy.bstates:
		var bs: Economy.BState = economy.bstates[i]
		if not bs.is_construction:
			continue
		var def_id: String = bs.bld.def_id
		var p := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y) + GameTheme.building_offset(def_id)
		var base := _bld_dims(bs.bld.size, def_id)
		var sz := base.x * GameTheme.texture_scale()
		var fin := GameTheme.building_texture(def_id, bs.bld.owner)  # fertiges Gebäude (Stufe 2)
		var stage1 := GameTheme.construction_stage1_texture(def_id)  # Holzbau (Stufe 1)
		var info := economy.construct_stage_info(bs)
		var overall: float = info.overall

		if stage1 != null:
			# ZWEI STUFEN: erst Holzkonstruktion, dann fertiger Bau (Stein) darüber.
			if int(info.stage) == 1:
				_grow_tex(stage1, p, sz, maxf(float(info.stage_frac), 0.02))
			else:
				draw_texture_rect(stage1, Rect2(p.x - sz * 0.5, p.y - sz, sz, sz), false)
				if float(info.stage_frac) > 0.02:
					_grow_finished(p, base, sz, fin, def_id, float(info.stage_frac))
		else:
			# EINE STUFE: alles ins fertige PNG aufteilen (wie bisher).
			if overall > 0.02:
				_grow_finished(p, base, sz, fin, def_id, overall)

		# Fortschrittsbalken
		var w := 22.0
		var bar := Vector2(p.x - w * 0.5, p.y - 34)
		draw_rect(Rect2(bar, Vector2(w, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar, Vector2(w * overall, 4)), Color(0.4, 0.85, 0.4))


## Eine Textur von unten nach oben "wachsen" lassen (Baufortschritt).
func _grow_tex(tex: Texture2D, p: Vector2, sz: float, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	var vis := sz * f
	var region := Rect2(0, tex.get_height() * (1.0 - f), tex.get_width(), tex.get_height() * f)
	draw_texture_rect_region(tex, Rect2(p.x - sz * 0.5, p.y - vis, sz, vis), region)


## Fertiges Gebäude wachsend zeichnen — Textur wenn vorhanden, sonst Platzhalter.
func _grow_finished(p: Vector2, base: Vector2, sz: float, fin: Texture2D, def_id: String, frac: float) -> void:
	if fin != null:
		_grow_tex(fin, p, sz, frac)
	else:
		var col := GameTheme.building_color(def_id)
		draw_rect(Rect2(p.x - base.x * 0.5, p.y - base.y * frac, base.x, base.y * frac), col.darkened(0.1))


func _bld_dims(size: int, def_id := "") -> Vector2:
	return GameTheme.building_dims(size, def_id)


func base_offset(size: int) -> float:
	return _bld_dims(size).x * 0.5 + 6.0


func _draw_goods() -> void:
	var map := state.map
	for fi in economy.flag_goods:
		var queue: Array = economy.flag_goods[fi]
		if queue.is_empty():
			continue
		var x := int(fi) % map.width
		var y := int(fi) / map.width
		var base := map.node_world(x, y) + Vector2(6, -2)
		for k in mini(queue.size(), Economy.FLAG_CAP):
			var good_type: int = (queue[k] as Economy.Good).type
			var off := Vector2(9.0 * (k % 4), -9.0 * (k / 4))
			var tex := GameTheme.good_texture(good_type)
			if tex != null:
				draw_texture_rect(tex, Rect2(base + off, Vector2(8, 8)), false)
			else:
				draw_rect(Rect2(base + off, Vector2(5, 5)), GameTheme.good_color(good_type))


func _draw_carriers() -> void:
	for r in economy.carriers:
		var c: Economy.Carrier = economy.carriers[r]
		if not c.active:
			continue  # unbesetzte Straße (kein Träger zugeteilt) → nichts zeichnen
		var p := economy.carrier_world(c)
		var carry := c.carrying.type if c.carrying != null else -1
		_unit("carrier", p, economy.carrier_facing(c), 0, carry)
		_occlude(p)


func _draw_workers() -> void:
	for i in economy.bstates:
		var bs: Economy.BState = economy.bstates[i]
		if not economy.has_worker(bs):
			continue
		var p := economy.worker_world(bs)
		_unit("worker", p, economy.worker_facing(bs), 0)
		_occlude(p)


func _draw_marchers() -> void:
	for m in economy.marchers:
		var p := economy.marcher_world(m)
		var facing := economy.marcher_facing(m)
		if m.purpose_carrier:
			_unit("carrier", p, facing, m.attacker_owner)
		elif m.purpose_worker or m.purpose_return:
			_unit("worker", p, facing, m.attacker_owner)
		else:
			_unit("soldier", p, facing, m.attacker_owner)
		_occlude(p)


## Verirrte Träger (Straße abgerissen): laufen frei mit ihrer Ware herum.
func _draw_strays() -> void:
	for s in economy.strays:
		var p: Vector2 = s.pos
		var carry: int = s.good.type if s.good != null else -1
		_unit("carrier", p, s.facing, 0, carry)
		_occlude(p)


func _draw_preview() -> void:
	if preview_path.size() < 2:
		return
	var pts := PackedVector2Array()
	for n in preview_path:
		pts.append(state.map.node_world(n.x, n.y))
	var col := Color(0.3, 1.0, 0.4, 0.9) if preview_ok else Color(1.0, 0.3, 0.3, 0.9)
	draw_polyline(pts, col, 3.0, true)


func _draw_hover() -> void:
	if not state.map.in_bounds(hover.x, hover.y):
		return
	var p := state.map.node_world(hover.x, hover.y)
	var d := PackedVector2Array([
		p + Vector2(0, -8), p + Vector2(12, 0),
		p + Vector2(0, 8), p + Vector2(-12, 0),
	])
	draw_polyline(d + PackedVector2Array([d[0]]), Color(1, 1, 1, 0.85), 1.5)
	draw_circle(p, 4.0, _bq_color(state.effective_bq(hover.x, hover.y)))
	if state.map.in_bounds(road_start.x, road_start.y):
		var sp := state.map.node_world(road_start.x, road_start.y)
		draw_circle(sp, 7.0, Color(0.3, 0.6, 1.0, 0.85))


func _bq_color(bq: int) -> Color:
	match bq:
		WorldState.BQ_CASTLE: return Color(0.2, 0.9, 0.2)
		WorldState.BQ_HOUSE:  return Color(0.7, 0.9, 0.2)
		WorldState.BQ_HUT:    return Color(0.95, 0.85, 0.2)
		WorldState.BQ_MINE:   return Color(0.6, 0.4, 0.9)
		WorldState.BQ_FLAG:   return Color(0.95, 0.55, 0.2)
	return Color(0.6, 0.6, 0.6, 0.6)
