extends SceneTree

## Headless-Smoketest: öffnet Gebäudefenster (HQ + ein Produktionsgebäude) und
## lässt einige Frames laufen, damit _update_one_building_window inkl.
## Soll/Ist-Icons und Produktivität durchlaufen wird. Aufruf:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/smoke_building_window.gd

var _frames := 0
var _world: Node = null
var _opened := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://game/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	_world = inst  # Szenenwurzel "World" trägt world.gd direkt


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5 and _world != null:
		var state = _world.get("state")
		if state == null:
			print("Smoketest FEHLER: World.state nicht gefunden")
			quit(1)
			return true
		# Ein Produktionsgebäude dazusetzen, damit die Soll/Ist-Warenzeilen
		# (Eingänge + Ausgang) im Fenster wirklich aufgebaut werden.
		var hq = null
		for i in state.buildings:
			var b = state.buildings[i]
			if b.is_hq and b.owner == 0:
				hq = b
				break
		if hq != null:
			for r in range(2, 7):
				var done := false
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var x: int = hq.pos.x + dx
						var y: int = hq.pos.y + dy
						if state.can_place_building(x, y, WorldState.BQ_HOUSE):
							var saw = state.place_building(x, y, WorldState.BQ_HOUSE,
								false, "sawmill", 0, false)
							if saw != null:
								_world.get("economy").resync()
								done = true
							break
					if done: break
				if done: break
		for i in state.buildings:
			_world.call("_open_building_window", state.buildings[i])
			_opened += 1
			if _opened >= 3:
				break
		print("Smoketest: %d Gebaeudefenster geoeffnet" % _opened)
	if _frames == 8 and _world != null:
		if not _check_placement_and_cancel():
			return true
	if _frames >= 30:
		if _opened == 0:
			print("Smoketest FEHLER: kein Gebaeudefenster geoeffnet")
			quit(1)
			return true
		print("Smoketest: Gebaeudefenster ok")
		quit(0)
		return true
	return false


## Prüft das S2-nahe Bedienverhalten: Einzelplatzierung (nach dem Setzen zurück
## in den Auswahlmodus) und Rechtsklick-Abbruch des Baumodus.
func _check_placement_and_cancel() -> bool:
	var state = _world.get("state")
	var MODE_SELECT: int = _world.get("MODE_SELECT")
	var MODE_BUILD: int = _world.get("MODE_BUILD")

	# Freien, bebaubaren Bauplatz im eigenen Gebiet suchen.
	var spot := Vector2i(-1, -1)
	var hq = null
	for i in state.buildings:
		if state.buildings[i].is_hq and state.buildings[i].owner == 0:
			hq = state.buildings[i]
			break
	if hq != null:
		for r in range(2, 8):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x: int = hq.pos.x + dx
					var y: int = hq.pos.y + dy
					if state.can_place_building(x, y, WorldState.BQ_HOUSE):
						spot = Vector2i(x, y)
						break
				if spot.x >= 0: break
			if spot.x >= 0: break
	if spot.x < 0:
		print("Smoketest FEHLER: kein Bauplatz fuer Platzierungstest gefunden")
		quit(1)
		return false

	# Einzelplatzierung: Gebaeude waehlen -> Bau-Modus, dann Klick setzt einmal
	# und kehrt zurueck in den Auswahlmodus (kein "klebt am Cursor").
	_world.call("_select_building", "woodcutter")
	if int(_world.get("mode")) != MODE_BUILD:
		print("Smoketest FEHLER: _select_building setzt nicht MODE_BUILD")
		quit(1)
		return false
	var before: int = state.buildings.size()
	_world.set("hover", spot)
	_world.call("_handle_click")
	if state.buildings.size() != before + 1:
		print("Smoketest FEHLER: Klick platziert kein Gebaeude")
		quit(1)
		return false
	if int(_world.get("mode")) != MODE_SELECT:
		print("Smoketest FEHLER: nach Platzierung nicht zurueck in MODE_SELECT")
		quit(1)
		return false

	# Rechtsklick-Abbruch: Bau-Modus waehlen, dann Abbruch -> MODE_SELECT.
	_world.call("_select_building", "forester")
	if int(_world.get("mode")) != MODE_BUILD:
		print("Smoketest FEHLER: zweite _select_building setzt nicht MODE_BUILD")
		quit(1)
		return false
	_world.call("_on_right_click_cancel")
	if int(_world.get("mode")) != MODE_SELECT:
		print("Smoketest FEHLER: Rechtsklick bricht Bau-Modus nicht ab")
		quit(1)
		return false

	print("Smoketest: Einzelplatzierung + Rechtsklick-Abbruch ok")
	return true
