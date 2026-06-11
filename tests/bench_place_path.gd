extends SceneTree

## Misst den KOMPLETTEN Platzier-Pfad bei laufender Wirtschaft (nicht nur den
## Build-Spot-Scan): place_building, resync, recompute_territory/visibility, der
## Build-Spot-Scan und ein voller tick(). Zeigt, wo der Platzier-Delay herkommt (#30).
##   Godot_..._console.exe --headless --path . --script res://tests/bench_place_path.gd

func _flat_map(w: int, h: int) -> MapData:
	var m := MapData.new(w, h)
	for y in h:
		for x in w:
			m.set_height(x, y, 2)
			m.set_tri(Vector2i(x, y), Grid.TRI_R, Terrain.MEADOW)
			m.set_tri(Vector2i(x, y), Grid.TRI_D, Terrain.MEADOW)
	return m


func _ms(usec: int) -> String:
	return "%7.2f ms" % (usec / 1000.0)


func _initialize() -> void:
	var map := _flat_map(96, 96)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(48, 48, WorldState.BQ_CASTLE, true, "hq", 16, false)
	eco.resync()

	# Ring-Flaggen + Straßen → Träger; danach Gebäude an buildbaren Territoriumsknoten.
	var prev: Vector2i = hq.flag_pos
	for ring in range(2, 12):
		for a in range(0, 360, 22):
			var rad := deg_to_rad(a)
			var x := 48 + int(round(cos(rad) * ring))
			var y := 48 + int(round(sin(rad) * ring))
			if not map.in_bounds(x, y):
				continue
			var f = state.place_flag(x, y)
			if f != null:
				if state.can_build_road(prev, Vector2i(x, y)):
					state.build_road(prev, Vector2i(x, y))
				prev = Vector2i(x, y)

	var defs := ["woodcutter", "forester", "sawmill", "quarry"]
	var di := 0
	var placed := 0
	for ti in state.territory.keys():
		if placed >= 30:
			break
		var tx := int(ti) % map.width
		var ty := int(ti) / map.width
		var id: String = defs[di % defs.size()]
		var d := BuildingCatalog.get_def(id)
		var sz: int = d.get("size", WorldState.BQ_HUT)
		if state.can_place_building(tx, ty, sz):
			state.place_building(tx, ty, sz, false, id, int(d.get("influence", 0)), true)
			di += 1
			placed += 1
	eco.resync()
	for t in 4000:
		eco.tick()
	eco.resync()

	var goods := 0
	for fi in eco.flag_goods:
		goods += (eco.flag_goods[fi] as Array).size()
	print("Aufbau: Gebaeude=%d Strassen=%d Flaggen=%d Traeger=%d bstates=%d Waren=%d Territorium=%d" % [
		state.buildings.size(), state.roads.size(), state.flags.size(),
		eco.carriers.size(), eco.bstates.size(), goods, state.territory.size()])

	# Buildbaren Knoten fürs Test-Platzieren suchen.
	var spot := Vector2i(-1, -1)
	for ti in state.territory.keys():
		var tx := int(ti) % map.width
		var ty := int(ti) / map.width
		if state.can_place_building(tx, ty, WorldState.BQ_HUT):
			spot = Vector2i(tx, ty)
			break
	if spot.x < 0:
		print("kein Bauplatz frei"); quit(1); return

	# (1) place_building selbst.
	var t := Time.get_ticks_usec()
	state.place_building(spot.x, spot.y, WorldState.BQ_HUT, false, "woodcutter", 0, true)
	var d_place := Time.get_ticks_usec() - t

	# (2) resync() (das ruft der Klick-Handler direkt nach place_building).
	t = Time.get_ticks_usec()
	eco.resync()
	var d_resync := Time.get_ticks_usec() - t

	# (3) recompute_territory / (4) recompute_visibility einzeln.
	t = Time.get_ticks_usec(); state.recompute_territory(); var d_terr := Time.get_ticks_usec() - t
	t = Time.get_ticks_usec(); state.recompute_visibility(); var d_vis := Time.get_ticks_usec() - t

	# (5) Build-Spot-Scan (Territorium).
	t = Time.get_ticks_usec()
	for ti in state.territory.keys():
		var tx := int(ti) % map.width
		var ty := int(ti) / map.width
		if state.can_place_road_flag(tx, ty):
			continue
		state.actual_build_spot_bq(tx, ty)
	var d_spots := Time.get_ticks_usec() - t

	# (6) ein voller tick().
	t = Time.get_ticks_usec(); eco.tick(); var d_tick := Time.get_ticks_usec() - t

	print("(1) place_building     : %s" % _ms(d_place))
	print("(2) resync()           : %s   <-- laeuft synchron beim Klick" % _ms(d_resync))
	print("(3) recompute_territory: %s" % _ms(d_terr))
	print("(4) recompute_visibility:%s" % _ms(d_vis))
	print("(5) build-spot scan    : %s" % _ms(d_spots))
	print("(6) ein tick()         : %s" % _ms(d_tick))
	print("Summe Klick-Pfad (1+2) : %s" % _ms(d_place + d_resync))
	quit(0)
