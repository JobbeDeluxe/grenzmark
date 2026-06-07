class_name Tuning
extends RefCounted

## ZENTRALE SPIEL-BALANCE (Zeiten/Geschwindigkeiten), austauschbar über
## `assets/tuning.json` — analog zu assets/design.json für die Optik, aber für
## die Spiellogik. Liegt in core/ (KEIN Godot-Szenenbaum), damit die Simulation
## deterministisch und testbar bleibt. Fehlt die Datei, gelten die Standardwerte.
##
## Alle Zeiten in TICKS (das Spiel rechnet mit 30 Ticks/Sekunde).

static var _cfg_loaded := false
static var _cfg := {}


static func _cfg_dict() -> Dictionary:
	if _cfg_loaded:
		return _cfg
	_cfg_loaded = true
	_cfg = {}
	var path := "res://assets/tuning.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_cfg = parsed
	return _cfg


## Zum Neuladen nach Änderung der JSON (z. B. später aus einem Optionsmenü).
static func reload() -> void:
	_cfg_loaded = false
	_cfg = {}


static func _num(key: String, default: float) -> float:
	var v = _cfg_dict().get(key, default)
	return float(v) if (v is float or v is int) else default


static func _num_from_table(table_key: String, def_id: String, resource: String, default: float) -> float:
	var table = _cfg_dict().get(table_key, {})
	if table is Dictionary:
		if def_id != "" and table.has(def_id):
			var by_def = table[def_id]
			if by_def is float or by_def is int:
				return float(by_def)
		if resource != "" and table.has(resource):
			var by_res = table[resource]
			if by_res is float or by_res is int:
				return float(by_res)
	return default


## Laufgeschwindigkeit in WELT-PIXELN pro Tick. Erst pro Gebäude, dann pro
## Ressource, dann Default. So kann später ein Optionsmenü dieselbe JSON ändern.
static func worker_speed(def_id := "", resource := "") -> float:
	var base := _num("worker_speed_default", _num("worker_speed", 1.45))
	return _num_from_table("worker_speed_by_building", def_id, resource, base)


## Dauer der Aktion am Ziel (Baum fällen / pflanzen / Stein / Erz) in Ticks.
static func work_action(def_id := "", resource := "") -> int:
	var base := _num("work_action_ticks_default", _num("work_action_ticks", 450))
	return int(_num_from_table("work_action_ticks_by_building", def_id, resource, base))


## Pause am Gebäude zwischen zwei Arbeitsgängen in Ticks (Arbeiter „verschnauft").
static func work_wait(def_id := "", resource := "") -> int:
	var base := _num("work_wait_ticks_default", _num("work_wait_ticks", 900))
	return int(_num_from_table("work_wait_ticks_by_building", def_id, resource, base))


## Ticks für die nächste Baum-Wachstumsstufe:
## stage 0: Setzling -> kleiner Baum, stage 1: kleiner Baum -> großer Baum.
static func tree_growth_ticks(stage: int) -> int:
	var legacy := int(_num("tree_grow_ticks", 1500))
	var stages = _cfg_dict().get("tree_growth_stage_ticks", [])
	if stages is Array and stages.size() >= 2:
		var idx := clampi(stage, 0, 1)
		var v = stages[idx]
		if v is float or v is int:
			return int(v)
	return legacy


## Warenlieferungen über eine Straße bis zur sichtbaren Pflaster-Stufe.
static func road_upgrade_deliveries() -> int:
	return maxi(1, int(_num("road_upgrade_deliveries", 24)))
