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


## Ticks für den nächsten Feld-Wachstumsschritt (Bauernhof, Issue #26):
## stage 0: gesät -> jung, stage 1: jung -> wachsend, stage 2: wachsend -> reif.
static func field_growth_ticks(stage: int) -> int:
	var stages = _cfg_dict().get("field_growth_stage_ticks", [])
	if stages is Array and stages.size() >= 3:
		var idx := clampi(stage, 0, 2)
		var v = stages[idx]
		if v is float or v is int:
			return maxi(1, int(v))
	return 1150


## Wie lange ein abgeerntetes Stoppelfeld liegen bleibt, bevor es verschwindet
## (RTTR: noEnvObject verdorrt nach ~3000-4000 Frames; hier fester, deterministischer
## Tuning-Wert). Reine Deko — blockiert nichts.
static func field_cut_ticks() -> int:
	return maxi(1, int(_num("field_cut_ticks", 1800)))


## Warenlieferungen über eine Straße bis zur sichtbaren Pflaster-Stufe.
static func road_upgrade_deliveries() -> int:
	return maxi(1, int(_num("road_upgrade_deliveries", 24)))


# --------------------------------------------------------------------------
#  Startinventar des HQ (Waren UND Personen) — S2-Lagermodell
#  Ein Lager hält im Original sowohl Waren als auch Personen (RTTR Inventory =
#  goods[] + people[]). Beides ist hier konfigurierbar; fehlt die JSON-Sektion,
#  gelten die Standardwerte. JSON-Schlüssel sind die String-IDs aus
#  Goods.KEYS bzw. Jobs.KEYS (z. B. "boards", "helper").
# --------------------------------------------------------------------------

## Startwaren des HQ als { Goods.* : Anzahl }. Override via tuning.json
## "hq_start_goods". Enthält auch Werkzeuge für die Erst-Rekrutierung von
## Spezialisten (Träger + Werkzeug -> Beruf).
static func hq_start_goods() -> Dictionary:
	return _resolve_inventory("hq_start_goods", Goods.KEYS, {
		Goods.BOARDS: 30, Goods.STONE: 30, Goods.WOOD: 12,
		Goods.BREAD: 8, Goods.FISH: 6, Goods.WATER: 6, Goods.COAL: 6,
		Goods.GRAIN: 6, Goods.FLOUR: 4, Goods.IRON: 4, Goods.SWORD: 3,
		Goods.HAMMER: 4, Goods.PICKAXE: 4, Goods.AXE: 2, Goods.SAW: 2,
		Goods.SHOVEL: 2, Goods.SCYTHE: 1, Goods.ROD_AND_LINE: 1, Goods.BOW: 1,
		Goods.CLEAVER: 1, Goods.ROLLING_PIN: 1, Goods.CRUCIBLE: 1, Goods.TONGS: 1,
	})


## Startpersonen des HQ als { Jobs.* : Anzahl }. Override via tuning.json
## "hq_start_people". Träger (HELPER) sind der Pool für Wege UND die
## Rekrutierung von Spezialisten.
static func hq_start_people() -> Dictionary:
	return _resolve_inventory("hq_start_people", Jobs.KEYS, {
		Jobs.HELPER: 30,
	})


## Soldaten-Reserve im HQ beim Start (hält Militärgebäude sofort).
static func hq_start_soldiers() -> int:
	return int(_num("hq_start_soldiers", 8))


## Takt des Träger-Nachschubs (Issue #33): alle N Ticks schiebt das HQ-Lager einen
## Träger nach (bei 30 Hz ist 150 ≈ 5 s, Analogon zu RTTR 150 Game-Frames).
static func helper_produce_ticks() -> int:
	return maxi(1, int(_num("helper_produce_ticks", 150)))


## Obergrenze des Träger-Reservebestands im HQ-Lager (Issue #33). Wie RTTR: das
## Lager füllt bis hierher auf und baut darüber ab (~100 pro Lager).
static func helper_cap() -> int:
	return maxi(0, int(_num("helper_cap", 100)))


## tuning.json[json_key] (String-ID -> Anzahl) zu { enum_id: Anzahl } auflösen.
## Fehlt/leer/kein Dictionary -> Kopie der Standardwerte. Unbekannte IDs werden
## ignoriert (vorwärtskompatibel).
static func _resolve_inventory(json_key: String, keys: Array, defaults: Dictionary) -> Dictionary:
	var raw = _cfg_dict().get(json_key)
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return defaults.duplicate()
	var out := {}
	for k in raw:
		var id := int(keys.find(String(k)))
		var v = raw[k]
		if id >= 0 and (v is int or v is float):
			out[id] = int(v)
	return out
