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
var show_hover_build_marker := false # Bauplatz-Badge nur in explizitem Baukontext
var _anim_time := 0.0
var _font: Font = ThemeDB.fallback_font


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

const BUILDING_SIDE_CLEAR_DEPTH := 22.0
const BUILDING_RIGHT_OCCLUSION_MAX := 30.0
const BUILDING_RIGHT_OCCLUSION_FACTOR := 0.32
const BUILDING_RIGHT_DEPTH_SLOPE := 0.85


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
		var node := map.node_world(b.pos.x, b.pos.y)
		var basep := node + GameTheme.building_offset(b.def_id)
		var sc := GameTheme.texture_scale()
		if b.is_hq:
			sc *= GameTheme.hq_scale()
		var sz := GameTheme.building_dims(b.size, b.def_id).x * sc
		_occluders.append({
			base = basep,
			foot = node,   # Bodenknoten OHNE building_offset → Tiefen-/Seiten-Anker (#39)
			tex = tex,
			w = sz,
			h = sz,
			kind = "building",
			right_core = minf(sz * BUILDING_RIGHT_OCCLUSION_FACTOR, BUILDING_RIGHT_OCCLUSION_MAX),
			clear_depth = BUILDING_SIDE_CLEAR_DEPTH,
		})
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
	# Flaggen sind ebenfalls Okkluder: ein Arbeiter/Träger HINTER einer (Gebäude-)Flagge
	# muss von ihr verdeckt werden — sonst „läuft" er über die Flagge.
	var flag_sz := GameTheme.flag_draw_size()
	for i in state.flags:
		var f: WorldState.Flag = state.flags[i]
		var ftex := GameTheme.flag_texture(f.owner)
		if ftex == null:
			continue
		_occluders.append({ base = map.node_world(f.pos.x, f.pos.y), tex = ftex,
			w = flag_sz.x, h = flag_sz.y })
	# Hinten -> vorne sortieren, damit beim Neuzeichnen ueberlappende Okkluder
	# (z. B. zwei dicht stehende Baeume) ihre korrekte Tiefenreihenfolge behalten.
	_occluders.sort_custom(func(a, b): return a.base.y < b.base.y)


## Verdeckt die Einheit an [param p], indem davorliegende Okkluder erneut über sie
## gezeichnet werden (opake Pixel verdecken, transparente lassen sie durchscheinen).
func _occlude(p: Vector2, exclude_foot := Vector2.INF) -> void:
	# Bounding-Box der Einheit (Sprite-Hoehe + getragene Ware darueber).
	var us := GameTheme.unit_size()
	_occlude_box(p.y, p.x - us * 0.7, p.y - us - 18.0, p.x + us * 0.7, p.y + 3.0, exclude_foot)


## Zeichnet alle Okkluder, die VOR der Bezugslinie [param ref_y] stehen (größeres y),
## beschnitten auf das Rechteck [left,top]..[right,bottom] erneut darüber. Das Beschneiden
## verhindert, dass z. B. ein Baum in voller Größe über benachbarte Sprites „überspillt".
func _occlude_box(ref_y: float, left: float, top: float, right: float, bottom: float,
		exclude_foot := Vector2.INF) -> void:
	for o in _occluders:
		# Tiefenanker = BODENKNOTEN (foot), nicht die optisch weit nach unten reichende
		# Sprite-Unterkante (base): Ein Haus reicht als Sprite tief unter seinen Standknoten;
		# mit base.y verdeckte es Einheiten, die sichtbar DAVOR stehen (Arbeiter vor dem
		# eigenen Haus, #64-Folge). Bäume/Flaggen haben kein foot → base (Sprite = Stand).
		var anchor_y: float = o.get("foot", o.base).y
		if anchor_y <= ref_y:
			continue  # Okkluder steht hinter/neben → Objekt bleibt davor
		# Eigenes Gebäude ausschließen (#64): Tür-Träger läuft vor seinem HQ aus der Tür,
		# soll also nicht vom eigenen HQ verdeckt werden — wohl aber von ANDEREN Gebäuden.
		if exclude_foot != Vector2.INF:
			var ofoot: Vector2 = o.get("foot", o.base)
			if ofoot.distance_to(exclude_foot) < 1.0:
				continue
		if _is_building_side_lane_clear(o, ref_y, (left + right) * 0.5):
			continue
		var ox: float = o.base.x - o.w * 0.5
		var oy: float = o.base.y - o.h
		var ow: float = o.w
		var oh: float = o.h
		var ix0 := maxf(ox, left)
		var iy0 := maxf(oy, top)
		var ix1 := minf(ox + ow, right)
		var iy1 := minf(oy + oh, bottom)
		if ix1 <= ix0 or iy1 <= iy0:
			continue
		# Nur den passenden Textur-Ausschnitt zeichnen, damit nichts ueberspillt.
		var tw := float(o.tex.get_width())
		var th := float(o.tex.get_height())
		var rx := (ix0 - ox) / ow * tw
		var ry := (iy0 - oy) / oh * th
		var rw := (ix1 - ix0) / ow * tw
		var rh := (iy1 - iy0) / oh * th
		draw_texture_rect_region(o.tex, Rect2(ix0, iy0, ix1 - ix0, iy1 - iy0),
			Rect2(rx, ry, rw, rh))


func _is_building_side_lane_clear(o: Dictionary, ref_y: float, center_x: float) -> bool:
	if String(o.get("kind", "")) != "building":
		return false
	# Anker ist der BODENKNOTEN (ohne building_offset), nicht das optisch nach
	# rechts/unten verschobene Sprite. Sonst schiebt ein versetztes Sprite (HQ:
	# +20/+22) seine Okklusion künstlich über die östliche Straße und verschluckt
	# dort laufende Träger (#39). Für Gebäude ohne Offset ist foot == base.
	var foot: Vector2 = o.get("foot", o.base)
	var depth := foot.y - ref_y
	if depth > float(o.get("clear_depth", 0.0)):
		return false
	var side_x := foot.x + float(o.get("right_core", 999999.0)) \
		+ depth * BUILDING_RIGHT_DEPTH_SLOPE
	return center_x > side_x


## Geist-Vorschau des gewählten Gebäudes am Mauszeiger (Stufe 8):
## grün = baubar / rot = nicht baubar, plus Eingangsflagge und kurzer Eingangsweg.
func _draw_build_preview() -> void:
	if build_preview_id == "" or not state.map.in_bounds(hover.x, hover.y):
		return
	var d := BuildingCatalog.get_def(build_preview_id)
	if d.is_empty():
		return
	var size: int = d.get("size", WorldState.BQ_HUT)
	var ok := state.can_place_building(hover.x, hover.y, size, 0,
		int(d.get("influence", 0)))
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
	_unit("carrier", p, facing, 0, carry)
	# Vor dem EIGENEN HQ sichtbar (aus der Tür), aber von anderen davor gebauten
	# Gebäuden korrekt verdeckt (#64).
	_occlude(p, state.map.node_world(hqpos.x, hqpos.y))


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
		var ground := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
		var p := ground + GameTheme.building_offset(def_id)
		var base := _bld_dims(bs.bld.size, def_id)
		var sz := base.x * GameTheme.texture_scale()
		var fin := GameTheme.building_texture(def_id, bs.bld.owner)  # fertiges Gebäude (Stufe 2)
		var stage1 := GameTheme.construction_stage1_texture(def_id)  # Holzbau (Stufe 1)
		var info := economy.construct_stage_info(bs)
		var overall: float = info.overall

		# Planierphase (#49): Statt des (noch nicht begonnenen) Gebäudes eine sichtbare
		# „Baustelle wird eingeebnet"-Markierung zeichnen, damit man sieht, dass hier erst
		# planiert werden muss. Der Planierer laeuft punktweise darum herum (Figur unten).
		if bs.planing:
			_draw_planing_site(ground)
			if economy.has_build_figure(bs):
				_unit("worker", economy.build_figure_world(bs), economy.build_figure_facing(bs), bs.bld.owner)
			continue

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

		# Baustelle liegt auf der dynamischen Ebene über allem — davorstehende Bäume
		# müssen sie verdecken (sonst überdeckt das wachsende Gebäude die Bäume).
		var foot := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y).y
		_occlude_box(foot, p.x - sz * 0.6, p.y - sz, p.x + sz * 0.6, p.y + 4.0)

		# Fortschrittsbalken
		var w := 22.0
		var bar := Vector2(p.x - w * 0.5, p.y - 34)
		draw_rect(Rect2(bar, Vector2(w, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar, Vector2(w * overall, 4)), Color(0.4, 0.85, 0.4))

		# Bauarbeiter sichtbar an der Baustelle (S2: die ganze Bauzeit über, nicht nur
		# auf dem Anmarsch) — solange die Baustelle besetzt ist.
		if economy.has_build_figure(bs):
			_unit("worker", economy.build_figure_world(bs), economy.build_figure_facing(bs), bs.bld.owner)


## Markierung einer noch zu planierenden Haus-/Burg-Baustelle (#49/#65): flaches
## Planierkreuz am Boden. Solange diese sichtbar ist, kommt erst der Planierer,
## bevor das Gebaeude ueberhaupt zu wachsen beginnt.
func _draw_planing_site(g: Vector2) -> void:
	var tex := GameTheme.construction_planing_texture()
	if tex != null:
		var sz := 46.0 * GameTheme.texture_scale()
		draw_texture_rect(tex, Rect2(g.x - sz * 0.5, g.y - sz * 0.62, sz, sz), false)
		return
	# Fallback: schlichtes Planierkreuz, kein Fortschrittsring.
	var dirt := Color(0.46, 0.32, 0.18, 0.9)
	var paint := Color(0.92, 0.88, 0.72, 0.95)
	var shadow := Color(0.0, 0.0, 0.0, 0.25)
	var pad := PackedVector2Array([
		g + Vector2(-18, 1), g + Vector2(0, -8), g + Vector2(18, 1), g + Vector2(0, 10)])
	draw_colored_polygon(pad, dirt)
	draw_line(g + Vector2(-13, -7), g + Vector2(13, 7), shadow, 5.0)
	draw_line(g + Vector2(13, -7), g + Vector2(-13, 7), shadow, 5.0)
	draw_line(g + Vector2(-13, -8), g + Vector2(13, 6), paint, 3.0)
	draw_line(g + Vector2(13, -8), g + Vector2(-13, 6), paint.lightened(0.12), 3.0)


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


# Dichter Original-Warenhaufen rund um den Flaggenfuß (#38).
# Übernommen aus RTTR `noFlag::Draw` (WARES_POS): die Waren liegen in einem flachen
# Fächer abwechselnd links/rechts der Flagge, leicht nach hinten ansteigend — NICHT
# als vertikaler Stapel, der den Pfahl überdeckt. Werte sind die Original-Offsets
# (Anker = Unterkante/Mitte der Ware am Flaggenfuß), ~×1.15 auf den größeren
# Grenzmark-Knoten (64 vs. 56 px) skaliert. Reihenfolge = Waren-Index; gezeichnet
# wird hinten→vorne (Index hoch→0), Index 0 liegt vorn auf. KEIN RNG → deterministisch.
const GOODS_HEAP: Array[Vector2] = [
	Vector2(0, 0), Vector2(-5, 0), Vector2(3, -1), Vector2(-8, -1),
	Vector2(7, -2), Vector2(-12, -2), Vector2(10, -6), Vector2(-15, -6),
]
const GOOD_ICON_DENSE := 9.0   # Haufen-Icons minimal größer („satter", #38)
const GOOD_ICON_GRID := 8.0


func _draw_goods() -> void:
	var map := state.map
	# Darstellung wählbar (#38): Standard „Dicht (Original)", alternativ altes Raster.
	var dense := UISkin.option_bool("goods_cluster_layout", true)
	for fi in economy.flag_goods:
		var queue: Array = economy.flag_goods[fi]
		if queue.is_empty():
			continue
		var x := int(fi) % map.width
		var y := int(fi) / map.width
		var node := map.node_world(x, y)
		var n := mini(queue.size(), Economy.FLAG_CAP)
		if dense:
			# Wie im Original von hinten (höchster Index) nach vorne (Index 0) zeichnen,
			# damit die vorderen Waren die hinteren korrekt überlappen. Offset ist die
			# Unterkante/Mitte der Ware → top-left = Anker − (Icon/2, Icon).
			var anchor := Vector2(GOOD_ICON_DENSE * 0.5, GOOD_ICON_DENSE)
			for k in range(n - 1, -1, -1):
				var gt: int = (queue[k] as Economy.Good).type
				var pos := node + GOODS_HEAP[k] - anchor
				var tex := GameTheme.good_texture(gt)
				if tex != null:
					draw_texture_rect(tex, Rect2(pos, Vector2(GOOD_ICON_DENSE, GOOD_ICON_DENSE)), false)
				else:
					draw_rect(Rect2(pos, Vector2(5, 5)), GameTheme.good_color(gt))
			# Fächer reicht seitlich über den Knoten hinaus → Okklusionsbox anpassen.
			_occlude_box(node.y, node.x - 22.0, node.y - 40.0, node.x + 18.0, node.y + 4.0)
		else:
			var base := node + Vector2(6, -2)
			for k in n:
				var gt: int = (queue[k] as Economy.Good).type
				var off := Vector2(9.0 * (k % 4), -9.0 * (k / 4))
				var tex := GameTheme.good_texture(gt)
				if tex != null:
					draw_texture_rect(tex, Rect2(base + off, Vector2(GOOD_ICON_GRID, GOOD_ICON_GRID)), false)
				else:
					draw_rect(Rect2(base + off, Vector2(5, 5)), GameTheme.good_color(gt))
			# Waren liegen am Flaggenknoten — davorstehende Bäume müssen sie verdecken.
			_occlude_box(node.y, node.x - 2.0, node.y - 40.0, node.x + 42.0, node.y + 4.0)


func _draw_carriers() -> void:
	for r in economy.carriers:
		var c: Economy.Carrier = economy.carriers[r]
		if not c.active:
			continue  # unbesetzte Straße (kein Träger zugeteilt) → nichts zeichnen
		if c.dphase != Economy.D_NONE:
			_draw_carrier_door(c)   # Tür-Exkursion: Flagge↔Tür statt Straßenlauf (#66)
			continue
		var p := economy.carrier_world(c)
		var carry := c.carrying.type if c.carrying != null else -1
		_unit("carrier", p, economy.carrier_facing(c), c.road.owner, carry)
		_occlude(p)


## Straßenträger während seiner Tür-Exkursion (#66): läuft sichtbar zwischen der
## Gebäudeflagge (dt 0) und der Tür (dt 1) und trägt dabei die Ware ins Haus. Vor dem
## bedienten Gebäude sichtbar, von davor gebauten Gebäuden korrekt verdeckt (#64).
func _draw_carrier_door(c: Economy.Carrier) -> void:
	var bs: Economy.BState = economy.bstates.get(c.dbidx)
	if bs == null or c.dflag < 0:
		return
	var bpos := bs.bld.pos
	var fx := c.dflag % state.map.width
	var fy := c.dflag / state.map.width
	var flag := state.map.node_world(fx, fy)
	var door := state.map.node_world(bpos.x, bpos.y) + GameTheme.entrance_offset(bs.bld.def_id)
	var p := flag.lerp(door, clampf(c.dt, 0.0, 1.0))
	var facing := (door - flag) if c.dphase == Economy.D_IN else (flag - door)
	var carry := c.carrying.type if c.carrying != null else -1
	_unit("carrier", p, facing, c.road.owner, carry)
	_occlude(p, state.map.node_world(bpos.x, bpos.y))


func _draw_workers() -> void:
	for i in economy.bstates:
		var bs: Economy.BState = economy.bstates[i]
		if not economy.has_worker(bs):
			continue
		var p := economy.worker_world(bs)
		_unit("worker", p, economy.worker_facing(bs), bs.bld.owner, economy.worker_carry(bs))
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
	if show_hover_build_marker:
		var road_flag := state.can_place_road_flag(hover.x, hover.y)
		var build_bq := state.actual_build_spot_bq(hover.x, hover.y)
		var shown_bq := build_bq if build_bq != WorldState.BQ_NOTHING \
			else (WorldState.BQ_FLAG if road_flag else WorldState.BQ_NOTHING)
		var shown_as_road_flag := road_flag and build_bq == WorldState.BQ_NOTHING
		_draw_hover_build_marker(p, shown_bq, shown_as_road_flag)
	else:
		draw_circle(p, 2.0, Color(1.0, 1.0, 1.0, 0.72))
	if state.map.in_bounds(road_start.x, road_start.y):
		var sp := state.map.node_world(road_start.x, road_start.y)
		draw_circle(sp, 7.0, Color(0.3, 0.6, 1.0, 0.85))


func _draw_hover_build_marker(p: Vector2, bq: int, road_flag := false) -> void:
	var col := _bq_color(bq)
	if bq < WorldState.BQ_FLAG:
		draw_circle(p, 4.0, Color(0.6, 0.6, 0.6, 0.55))
		return
	var key := _bq_key(bq, road_flag)
	var tex := GameTheme.build_spot_texture(key)
	var icon_p := p + Vector2(0.0, 22.0)
	if tex != null:
		var sz := Vector2(22, 22)
		draw_texture_rect(tex, Rect2(icon_p.x - sz.x * 0.5, icon_p.y - sz.y - 8.0, sz.x, sz.y), false,
			Color(1, 1, 1, 0.78))
	else:
		match bq:
			WorldState.BQ_CASTLE:
				draw_rect(Rect2(icon_p.x - 10, icon_p.y - 24, 20, 15), col, false, 2.0)
				draw_rect(Rect2(icon_p.x - 5, icon_p.y - 31, 10, 8), col.lightened(0.15), false, 1.4)
			WorldState.BQ_HOUSE:
				draw_rect(Rect2(icon_p.x - 8, icon_p.y - 22, 16, 12), col, false, 1.8)
				draw_line(icon_p + Vector2(-8, -22), icon_p + Vector2(0, -30), col, 1.5, true)
				draw_line(icon_p + Vector2(8, -22), icon_p + Vector2(0, -30), col, 1.5, true)
			WorldState.BQ_HUT:
				draw_rect(Rect2(icon_p.x - 6, icon_p.y - 20, 12, 10), col, false, 1.7)
			WorldState.BQ_MINE:
				draw_polyline(PackedVector2Array([
					icon_p + Vector2(-9, -10), icon_p + Vector2(9, -10),
					icon_p + Vector2(0, -28), icon_p + Vector2(-9, -10)
				]), col, 1.8, true)
			WorldState.BQ_FLAG:
				draw_line(icon_p + Vector2(0, -24), icon_p + Vector2(0, -10), col, 1.5, true)
				draw_rect(Rect2(icon_p.x, icon_p.y - 24, 9, 6), col)
	var text := "Weg-F" if road_flag else _bq_short(bq)
	var badge := Rect2(icon_p.x + 11, icon_p.y - 31, maxf(30.0, float(text.length()) * 6.2), 14)
	draw_rect(badge, Color(0.05, 0.04, 0.03, 0.72))
	draw_rect(badge, col, false, 1.0)
	draw_string(_font, badge.position + Vector2(3, 10), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.95, 0.82))
	draw_circle(p, 3.0, col)


func _bq_key(bq: int, road_flag := false) -> String:
	if road_flag:
		return "road_flag"
	match bq:
		WorldState.BQ_CASTLE: return "castle"
		WorldState.BQ_HOUSE: return "house"
		WorldState.BQ_HUT: return "hut"
		WorldState.BQ_MINE: return "mine"
		WorldState.BQ_FLAG: return "flag"
	return ""


func _bq_short(bq: int) -> String:
	match bq:
		WorldState.BQ_CASTLE: return "Burg"
		WorldState.BQ_HOUSE: return "Haus"
		WorldState.BQ_HUT: return "Hütte"
		WorldState.BQ_MINE: return "Mine"
		WorldState.BQ_FLAG: return "Flagge"
	return "-"


func _bq_color(bq: int) -> Color:
	match bq:
		WorldState.BQ_CASTLE: return Color(0.2, 0.9, 0.2)
		WorldState.BQ_HOUSE:  return Color(0.7, 0.9, 0.2)
		WorldState.BQ_HUT:    return Color(0.95, 0.85, 0.2)
		WorldState.BQ_MINE:   return Color(0.6, 0.4, 0.9)
		WorldState.BQ_FLAG:   return Color(0.95, 0.55, 0.2)
	return Color(0.6, 0.6, 0.6, 0.6)
