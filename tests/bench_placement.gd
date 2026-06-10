extends SceneTree

## Headless-Benchmark: misst, wie teuer das Platzieren (resync + Teilschritte)
## bei wachsender Stadt wird. Aufruf:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/bench_placement.gd

func _flat_map(w: int, h: int) -> MapData:
	var m := MapData.new(w, h)
	for y in h:
		for x in w:
			m.set_height(x, y, 2)
			m.set_tri(Vector2i(x, y), Grid.TRI_R, Terrain.MEADOW)
			m.set_tri(Vector2i(x, y), Grid.TRI_D, Terrain.MEADOW)
	return m


func _initialize() -> void:
	var map := _flat_map(80, 80)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	var hq := state.place_building(40, 40, WorldState.BQ_CASTLE, true, "hq", 9, false)
	eco.resync()

	# Wachsende Stadt: viele Flaggen + Straßen + ein paar Gebäude, dann jeweils
	# die Kosten eines weiteren resync() messen (das passiert bei jedem Platzieren).
	var flags := []
	var prev := hq.flag_pos
	var placed := 0
	for ring in range(2, 14):
		for a in range(0, 360, 20):
			var rad := deg_to_rad(a)
			var x := 40 + int(round(cos(rad) * ring))
			var y := 40 + int(round(sin(rad) * ring))
			if not map.in_bounds(x, y):
				continue
			var f = state.place_flag(x, y)
			if f != null:
				flags.append(Vector2i(x, y))
				if state.can_build_road(prev, Vector2i(x, y)):
					state.build_road(prev, Vector2i(x, y))
				prev = Vector2i(x, y)
				placed += 1
		# Messung bei dieser Stadtgröße.
		var t_total := Time.get_ticks_usec()
		eco.resync()
		var d_total := Time.get_ticks_usec() - t_total

		var t_terr := Time.get_ticks_usec()
		state.recompute_territory()
		var d_terr := Time.get_ticks_usec() - t_terr

		var t_vis := Time.get_ticks_usec()
		state.recompute_visibility()
		var d_vis := Time.get_ticks_usec() - t_vis

		print("Flaggen=%3d Strassen=%3d | resync=%6.2f ms  territory=%5.2f ms  visibility=%5.2f ms"
			% [state.flags.size(), state.roads.size(), d_total / 1000.0,
				d_terr / 1000.0, d_vis / 1000.0])

	# Kosten einer einzelnen find_route bei dieser Netzgröße (für Warenfluss/Tick).
	if flags.size() >= 2:
		var t_route := Time.get_ticks_usec()
		for k in 50:
			state.find_route(hq.flag_pos, flags[flags.size() - 1])
		var d_route := Time.get_ticks_usec() - t_route
		print("find_route x50 = %.2f ms (%.3f ms/Aufruf)  bei %d Strassen"
			% [d_route / 1000.0, d_route / 50000.0, state.roads.size()])
	quit(0)
