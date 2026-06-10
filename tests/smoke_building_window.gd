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
	if _frames >= 30:
		if _opened == 0:
			print("Smoketest FEHLER: kein Gebaeudefenster geoeffnet")
			quit(1)
			return true
		print("Smoketest: Gebaeudefenster ok")
		quit(0)
		return true
	return false
