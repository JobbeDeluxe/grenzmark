extends SceneTree

## Headless-Messung: Kosten des Bauplatz-Overlays (map_renderer._draw_build_spots).
## Bei jedem Redraw scannt der Renderer (wenn show_build_spots an ist) die GANZE Karte
## und ruft pro Zelle can_place_road_flag + actual_build_spot_bq (bis zu 5 BQ-Checks).
## Das ist der Platzier-Ruckler (#30, Renderer-Punkt). Aufruf:
##   Godot_..._console.exe --headless --path . --script res://tests/bench_buildspots.gd

func _initialize() -> void:
	var map := MapGenerator.generate(96, 96, 1337)
	var state := WorldState.new(map)
	var eco := Economy.new(state)
	# HQ etwa in der Mitte (mit Einfluss → Territorium entsteht).
	var c := _buildable_near(state, 48, 48)
	var hq := state.place_building(c.x, c.y, WorldState.BQ_CASTLE, true, "hq", 9, false)
	if hq == null:
		print("FEHLER: kein HQ platzierbar"); quit(1); return
	eco.resync()
	print("Karte 96x96, Territorium=%d Knoten" % state.territory.size())

	# (a) Voller Ganzkarten-Scan — exakt das, was _draw_build_spots heute tut.
	var t := Time.get_ticks_usec()
	var drawn := 0
	for y in map.height:
		for x in map.width:
			if state.can_place_road_flag(x, y):
				drawn += 1
				continue
			if state.actual_build_spot_bq(x, y) >= WorldState.BQ_FLAG:
				drawn += 1
	var d_full := Time.get_ticks_usec() - t

	# (b) Nur Territorium (Bauplätze gibt es ausschließlich im eigenen Gebiet) — exakt
	# das, was map_renderer._recompute_build_spots jetzt tut.
	t = Time.get_ticks_usec()
	var scanned := 0
	for ti in state.territory:
		scanned += 1
		var tx := int(ti) % map.width
		var ty := int(ti) / map.width
		if state.can_place_road_flag(tx, ty):
			continue
		state.actual_build_spot_bq(tx, ty)
	var d_terr := Time.get_ticks_usec() - t

	# (d) Budgetiert: der Renderer scannt nur SPOT_BUDGET (64) Knoten pro Frame und
	# verteilt den Aufbau über mehrere Frames → das ist der reale Pro-Frame-Hitch.
	var budget := 64
	var per_frame := d_terr * budget / float(max(scanned, 1))
	var frames := int(ceil(scanned / float(budget)))

	print("(a) Vollkarte (alt)        : %7.2f ms  (%d Zellen, %d Spots)" % [d_full / 1000.0, map.width * map.height, drawn])
	print("(b) Territorium, 1 Frame   : %7.2f ms  (%d Zellen)" % [d_terr / 1000.0, scanned])
	print("(c) Cache-Treffer (Sig)    :    ~0.00 ms  (laufender Betrieb, kein Scan)")
	print("(d) budgetiert (%d/Frame)  : %7.2f ms/Frame über %d Frames  <-- realer Hitch" % [budget, per_frame / 1000.0, frames])
	quit(0)


func _buildable_near(state: WorldState, cx: int, cy: int) -> Vector2i:
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if state.map.in_bounds(x, y) and state.can_place_building(x, y, WorldState.BQ_CASTLE):
					return Vector2i(x, y)
	return Vector2i(cx, cy)
