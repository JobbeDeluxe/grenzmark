class_name Economy
extends RefCounted

const Tuning := preload("res://core/tuning.gd")

## Träger-, Waren- und Produktionssimulation — das Wirtschaftsherz.
##
## Lager-zentriertes Modell (wie S2 warenhaus-orientiert ist):
##  - Das HQ ist Hauptlager: Quelle für angeforderte Eingangswaren, Senke für
##    Ausgangswaren und Baustoffe.
##  - Jedes Gebäude fordert fehlende Eingänge vom HQ an (über das Straßennetz)
##    und verschickt seine Ausgänge zum HQ.
##  - Baustellen fordern Bretter/Steine an; sind sie da, wächst der Bau, dann
##    wird das Gebäude aktiv.
##  - Manche Gebäude verbrauchen Terrain-Ressourcen (Bäume, Steine, Erz) oder
##    erzeugen sie (Förster pflanzt Bäume).
##
## Fester Tick (deterministisch) → multiplayer-tauglich.

const CARRIER_SPEED := 0.05    # Segmente pro Tick
const FLAG_CAP := 8            # max. Waren, die auf einer Flagge warten
const BUILD_TIME := 150        # Ticks Bau, sobald alle Materialien da sind
const OUT_CAP := 4             # Ausgangspuffer eines Gebäudes
const FOOD_BUFFER := 2         # Nahrungs-Sollbestand eines Gebäudes mit food_inputs (Minen)
const PROD_WINDOW := 1800      # rollendes Bewertungsfenster (Ticks) für die Produktivität %
const RES_RADIUS := 6          # Suchradius für Baum/Stein/Pflanzplatz
const ORE_RADIUS := 4          # Suchradius für Erz / Wasser
const FARM_RADIUS := 3         # Suchradius für Bauernhof-Felder. RTTR nutzt GetWorkRadius=2,
                               # dort steht das Gebäude aber auf EINEM Knoten. Grenzmarks
                               # Burg-Bauernhof belegt 4 Knoten (pos + 3 Extensions) + Flagge;
                               # die „kein Feld neben Gebäude"-Regel sperrt damit fast den ganzen
                               # inneren Radius-2-Bereich (nur ~3 gleichzeitige Felder). Radius 3
                               # gleicht den größeren Fußabdruck aus → ~8 gleichzeitige Felder,
                               # originalnah „viele Felder". (#7/#26)
const FIELD_MAX_SLOPE := 3     # RTTR/S2: direkte Höhendifferenz > 3 ist nur Flaggenqualität.
const SOLDIER_TICKS := 120     # Ticks, um aus einem Schwert einen Soldaten zu machen
const MARCH_SPEED := 0.07      # Tempo marschierender Soldaten (Segmente/Tick)
const ATTACK_SPEED := 1.3      # Tempo angreifender Soldaten (Weltpixel/Tick)
const PROMO_TICKS := 200       # Münze → Beförderung (Verteidigungsrüstung)
const CATAPULT_TICKS := 260    # Katapult-Schussintervall
const CATAPULT_RANGE := 6      # zusätzliche Reichweite des Katapults (Hex)


class Good:
	extends RefCounted
	var type: int
	var dest: int   # Flaggen-Index (Zielflagge)


# Träger-Zustände
enum { C_IDLE, C_TO_PICKUP, C_CARRYING, C_RETURN }


class Carrier:
	extends RefCounted
	var road: WorldState.Road
	var seg_pos := 0.0       # Position entlang der Straße
	var target := 0.0        # Zielposition
	var state := 0           # C_*
	var pickup_end := 0      # Ende, von dem geholt wird
	var carrying: Good = null
	var active := false      # erst aktiv, wenn der Träger vom HQ angekommen ist
	var dispatched := false  # Träger wurde schon vom HQ losgeschickt (Marsch läuft)
	var has_person := false  # hält einen HELPER aus dem Lager (Issue #9, Rückgabe bei Abriss)


class Marcher:
	extends RefCounted
	var route: Array[Vector2i] = []   # Flaggenfolge HQ → Zielgebäude
	var leg := 0                      # aktuelle Etappe (Straße route[leg]→route[leg+1])
	var pos := 0.0                    # Position entlang der aktuellen Straße
	var nodes: Array[Vector2i] = []   # Knotenpolylinie der aktuellen Etappe
	var dest_building := -1
	# Angreifer laufen geradlinig (querfeldein) statt über Straßen:
	var attack := false
	var attacker_owner := 0
	var from_w := Vector2.ZERO
	var to_w := Vector2.ZERO
	var t := 0.0
	# Träger-Anmarsch vom HQ:
	var purpose_carrier := false
	var car_road: WorldState.Road = null
	var car_end := 0
	# Arbeiter-Anmarsch vom HQ (besetzt ein Gebäude):
	var purpose_worker := false
	var work_bidx := -1
	# Bauarbeiter-Rückweg zur HQ-Tür (nach fertigem Bau): läuft hin und verschwindet.
	var purpose_return := false


## Verirrter Träger: seine Straße wurde abgerissen/geteilt, während er eine Ware
## trug. Statt zu verschwinden, läuft er frei herum (erst unkontrolliert, dann
## gezielt zur nächsten erreichbaren Flagge) und legt die Ware dort wieder ins Netz.
class Stray:
	extends RefCounted
	var good: Good = null
	var pos := Vector2.ZERO       # aktuelle Weltposition
	var facing := Vector2.ZERO
	var heading := Vector2.RIGHT  # Laufrichtung beim Wandern
	var wander_ticks := 0         # Restticks unkontrolliertes Wandern
	var change_dir_in := 0        # Ticks bis zur nächsten Richtungsänderung
	var target_flag := -1         # -1 = noch wandernd; sonst gezielt diese Flagge anlaufen
	var give_up := 0              # Notfall-Countdown bis zur Zwangs-Ablage (kein Warenverlust)


# Tür↔Flagge-Träger (nur HQ/Lager): bewegt Waren zwischen Gebäudetür und Flagge.
enum { H_IDLE, H_OUT, H_FETCH, H_IN, H_RETURN }

# Arbeiter-Phasen eines Ressourcen-Gebäudes (konstante Laufgeschwindigkeit):
# leer wartend → Hinweg → Aktion am Ziel → Rückweg → Pause am Gebäude.
enum { WK_IDLE, WK_OUT, WK_WORK, WK_BACK, WK_WAIT }

# Warum ein Produktionsgebäude gerade NICHT arbeitet (fürs Gebäudefenster).
enum { IDLE_OK, IDLE_OUT_FULL, IDLE_NO_INPUTS, IDLE_NO_RESOURCE, IDLE_NO_OUTPUT }


class HouseCarrier:
	extends RefCounted
	var t := 0.0             # 0 = Tür, 1 = Flagge
	var state := 0           # H_*
	var carrying: Good = null


## Ein Lager (Vorratshaus). Das HQ ist Lager #0; weitere baubare Lager folgen mit
## dem Mehr-Lager-System (#31). Hält Waren UND Personen (S2/RTTR-Inventory) sowie den
## eigenen Tür↔Flagge-Träger. Die hq_*-Aliase unten delegieren auf storages[0], damit
## bestehende Aufrufer unverändert bleiben, während das Routing schrittweise auf die
## ganze Liste verallgemeinert wird.
class Storage:
	extends RefCounted
	var flag_idx := -1                # Flaggen-Index (Anschluss ans Straßennetz)
	var idx := -1                     # Gebäude-Index in state.buildings
	var owner := 0                    # Besitzer (aktuell nur Spieler 0 hat ein Lager)
	var stock: Dictionary = {}        # good -> Anzahl
	var people: Dictionary = {}       # job -> Anzahl (Träger + Spezialisten)
	var outbox: Array = []            # Waren, die der Tür-Träger noch zur Flagge bringt
	var house: HouseCarrier = null    # Tür↔Flagge-Träger dieses Lagers


class BState:
	extends RefCounted
	var idx: int
	var bld: WorldState.Building
	var def: Dictionary
	var flag_idx: int
	var is_construction := false
	var built := 0.0         # Baufortschritt in Material-Wert (0..Zielwert)
	var delivered := {}      # good -> Anzahl (Baustoffe bzw. Eingangslager)
	var incoming := {}       # good -> Anzahl unterwegs
	var construct_progress := 0
	var producing := false
	var work_timer := 0
	var out_stock: Dictionary = {}         # good -> Anzahl im Ausgangspuffer
	                                       # (mehrere Sorten bei Werkzeugmacher/Schmiede)
	var out_cycle := 0                     # Zähler für gleichmäßige Mehrfach-Ausgänge
	var cur_output := -1                   # in diesem Zyklus gewähltes Ausgangsgut
	var worker_target := Vector2i(-1, -1)  # Knoten, zu dem der Arbeiter geht
	var out_yield := true                  # liefert der laufende Gang ein Ausgangsgut?
	                                       # (Bauernhof: Ernte ja, Säen nein — Issue #26)
	var consumed_mid := false              # Ressourcen-Aktion am Wendepunkt erledigt?
	var wphase := 0                        # WK_* — aktuelle Arbeiter-Phase
	var ph_t := 0.0                        # verbleibende Ticks der aktuellen Phase
	var ph_total := 1.0                    # Gesamtticks der aktuellen Phase (Interpolation)
	var staffed := false                   # Arbeiter ist vom HQ angekommen?
	var worker_sent := false               # Arbeiter wurde schon angefordert?
	var has_person := false                # hält eine Person aus dem Lager (Issue #9)
	var person_job := -1                   # welcher Beruf (für Rückgabe bei Abriss)
	var stopped := false                   # Produktion vom Spieler angehalten?
	var prod_active := 0                   # aktive Arbeitsticks im Bewertungsfenster
	var prod_total := 0                    # Gesamtticks im Bewertungsfenster
	var idle_reason := IDLE_OK             # warum WK_IDLE nicht startet (Fensteranzeige)


var state: WorldState
var carriers: Dictionary = {}        # Road -> Carrier
var bstates: Dictionary = {}         # building idx -> BState
var flag_to_building: Dictionary = {}# flag idx -> building idx
var flag_goods: Dictionary = {}      # flag idx -> Array[Good]

# Lager-Liste (#31): das HQ ist Lager #0. Wird in _init mit genau einem Lager
# angelegt; weitere baubare Lager kommen mit dem Mehr-Lager-Routing dazu.
var storages: Array[Storage] = []

# Rückwärtskompatible Sicht auf das Hauptlager (HQ = storages[0]). Solange es nur ein
# Lager gibt, delegieren diese Aliase 1:1 auf storages[0] — bestehende Aufrufer (auch
# Save/Load und UI) bleiben unverändert. Mehr-Lager-Routing verallgemeinert die heißen
# Pfade (_ship_outputs/_request_from_hq/...) schrittweise auf die ganze Liste.
var hq_flag: int:
	get: return storages[0].flag_idx
	set(value): storages[0].flag_idx = value
var hq_idx: int:
	get: return storages[0].idx
	set(value): storages[0].idx = value
var hq_stock: Dictionary:
	get: return storages[0].stock
	set(value): storages[0].stock = value
var hq_people: Dictionary:
	get: return storages[0].people
	set(value): storages[0].people = value
var hq_outbox: Array:
	get: return storages[0].outbox
	set(value): storages[0].outbox = value
var hq_house: HouseCarrier:
	get: return storages[0].house
	set(value): storages[0].house = value
var soldiers := 0                    # ausgebildete Soldaten im HQ (Reserve)
# --- Spieler-Einstellungen (RTTR-Regler, nur Spieler 0; deterministisch) ---
var tool_priority: Dictionary = {}   # Werkzeug-Gut -> Gewicht 0..10 (Werkzeugmacher)
var tool_orders: Dictionary = {}     # Werkzeug-Gut -> noch offene Bestellmenge (Vorrang)
var distribution: Dictionary = {}    # Ware -> { def_id -> Gewicht 0..10 } (#43 Verteilung)
var recruiting_ratio := 10           # Soldaten-Rekrutierungsrate 0..10 (RTTR MilSetting 0)
var mines_accept_beer := false       # Hausregel: Minen nehmen zusätzlich Bier als Nahrung
                                     # (Original: nur Fisch/Fleisch/Brot). Default aus.
var ai_enabled := true               # Gegner-KI aktiv? (zum Testen abschaltbar)
var ai: AIBase = null                # austauschbare Gegner-KI (Plugin)
var marchers: Array[Marcher] = []    # gerade marschierende Soldaten
var strays: Array[Stray] = []        # verirrte Träger (Straße weg, tragen noch Ware)
var _inc_soldiers: Dictionary = {}   # building idx -> unterwegs befindliche Soldaten
var dirty := false                   # Karte muss neu gezeichnet werden

var _hq_inited := false
var _soldier_timer := SOLDIER_TICKS
var _promo_timer := PROMO_TICKS
var _cata_timer := CATAPULT_TICKS
var _helper_timer := 0               # Träger-Nachschub des HQ-Lagers (Issue #33)
var _growing_trees: Dictionary = {} # map idx -> Restticks bis zur nächsten Baumstufe
var _growing_fields: Dictionary = {} # map idx -> Restticks bis nächste Feldstufe / bis Verdorren (#26)
var _decay_fields: Dictionary = {}   # map idx -> Restticks bis Feld-Deko (Stoppel/verdorrt) verschwindet (#26)
var _recruit_accum := 0              # Akkumulator für die Rekrutierungsrate (deterministisch)
var _rng := RandomNumberGenerator.new()  # seeded → deterministisch (Lockstep-tauglich)


func _init(world_state: WorldState) -> void:
	state = world_state
	# Hauptlager (#31): genau ein Lager (das HQ) anlegen, bevor irgendein hq_*-Alias
	# darauf zugreift. Bestand/Personen füllt später _init_hq_stock beim HQ-Fund.
	storages = [Storage.new()]
	ai = DefaultAI.new()  # Standard-Gegner-KI (austauschbar über world)
	_init_settings()
	_rng.seed = 0xA17E57   # fester Seed: gleiche Abläufe auf allen Clients
	_init_tree_growth_from_map()
	_init_field_growth_from_map()
	_init_decay_fields_from_map()


## Standard-Werte der Spieler-Regler (RTTR-nah). Werkzeug-Prioritäten als Gewichte
## (0..10) je Werkzeug; Bestellungen starten leer; Rekrutierung voll.
func _init_settings() -> void:
	tool_priority = Tuning.tool_priority_default()
	tool_orders = {}
	for g in Goods.tools():
		tool_orders[g] = 0
	recruiting_ratio = Tuning.recruiting_ratio_default()
	distribution = Tuning.distribution_default()


## --- Settings-API (von der UI genutzt; clampt auf gültige Bereiche) ---
func set_tool_priority(tool_good: int, weight: int) -> void:
	if Goods.is_tool_good(tool_good):
		tool_priority[tool_good] = clampi(weight, 0, 10)


func set_tool_order(tool_good: int, count: int) -> void:
	if Goods.is_tool_good(tool_good):
		tool_orders[tool_good] = maxi(count, 0)


func set_recruiting_ratio(ratio: int) -> void:
	recruiting_ratio = clampi(ratio, 0, 10)


func set_mines_accept_beer(on: bool) -> void:
	mines_accept_beer = on


## Verteilungsgewicht (0..10) eines Abnehmers für eine knappe Ware setzen (#43).
func set_distribution(good: int, def_id: String, weight: int) -> void:
	if not distribution.has(good):
		return  # nur für mehrfach beanspruchte Waren definiert
	if not (distribution[good] as Dictionary).has(def_id):
		return
	distribution[good][def_id] = clampi(weight, 0, 10)


## Ist die Ware [g] gewichtet verteilt (mehrere konkurrierende Abnehmer, #43)?
func _is_distributed(g: int) -> bool:
	return distribution.has(g)


## Verteilungsgewicht des Abnehmers [def_id] für Ware [g] (0, wenn nicht gelistet).
func _dist_weight(g: int, def_id: String) -> int:
	if not distribution.has(g):
		return 0
	return int((distribution[g] as Dictionary).get(def_id, 0))


# --------------------------------------------------------------------------
#  Synchronisation (nach jedem Bauen/Abreißen)
# --------------------------------------------------------------------------

func resync() -> void:
	# Straßenteilungen: bestehenden Träger auf SEIN Teilstück übernehmen, bevor die
	# generische Diff-Logik ihn (mangels Straße) als verirrt behandeln würde.
	for sp in state.splits:
		_apply_split(sp)
	state.splits.clear()

	# Träger ↔ Straßen
	for r in state.roads:
		if not carriers.has(r):
			var c := Carrier.new()
			c.road = r
			carriers[r] = c
	for r in carriers.keys():
		if not state.roads.has(r):
			# Straße entfernt: trägt der Träger gerade eine Ware, darf sie NICHT
			# verschwinden. Der Träger wird zum „verirrten Träger" (Stray): läuft mit
			# der Ware herum und legt sie an der nächsten erreichbaren Flagge wieder
			# ins Netz — so geht nie eine Ware verloren.
			var old: Carrier = carriers[r]
			if old.carrying != null:
				_spawn_stray(old)
			if old.has_person:
				_return_person(Jobs.HELPER, old.road.owner)  # Träger kehrt ins Lager zurück (#9)
			carriers.erase(r)
	# Unbesetzte Straßen werden NICHT mehr sofort alle gleichzeitig besetzt, sondern
	# nach und nach in `_tick_dispatch()` (gestaffelt) — sonst marschieren bei vielen
	# neuen Straßen 20 Träger auf einmal los.

	# Gebäudezustände ↔ Gebäude
	flag_to_building.clear()
	hq_flag = -1
	hq_idx = -1
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		var bf := state.ensure_flag(b.flag_pos.x, b.flag_pos.y, b.owner)
		if bf == null:
			continue
		if b.is_hq:
			if b.owner == 0:
				hq_idx = i
				hq_flag = state.map.idx(b.flag_pos.x, b.flag_pos.y)
				if not _hq_inited:
					_init_hq_stock()
					_hq_inited = true
				if hq_house == null:
					hq_house = HouseCarrier.new()
			continue
		# Fertiges Lagerhaus (#31): als zusätzliches Lager führen (eigener Bestand +
		# Tür-Träger), NICHT als Produzent/Konsument. Während des Baus läuft es noch über
		# den normalen Baustellen-Pfad (fordert Bretter/Steine an).
		if b.owner == 0 and not b.under_construction and _is_storage_def(b.def_id):
			_register_storage(i, b)
			if bstates.has(i):
				bstates.erase(i)
			continue
		flag_to_building[state.map.idx(b.flag_pos.x, b.flag_pos.y)] = i
		if int(BuildingCatalog.get_def(b.def_id).get("influence", 0)) > 0:
			b.capacity = _capacity_for(b.size)
		if not bstates.has(i):
			var bs := BState.new()
			bs.idx = i
			bs.bld = b
			bs.def = BuildingCatalog.get_def(b.def_id)
			bs.flag_idx = state.map.idx(b.flag_pos.x, b.flag_pos.y)
			bs.is_construction = b.under_construction
			# Bereits fertige Gebäude (geladen/erobert) gelten als besetzt;
			# frisch fertiggestellte holen ihren Arbeiter vom HQ.
			bs.staffed = not b.under_construction
			# Personalmodell (Issue #9): ein fertiges Spieler-Gebäude bindet beim ersten
			# Erfassen (Laden/Eroberung) seinen Produktionsberuf aus dem Lager. Reicht das
			# Personal nicht, bleibt es unbesetzt und fordert später nach. (Bei normal
			# gebauten Gebäuden passiert das erst nach Bauende über _dispatch_worker.)
			if bs.staffed and b.owner == 0:
				var j0 := BuildingCatalog.job_of(b.def_id)
				if j0 >= 0:
					if _take_person(j0, 0):
						bs.has_person = true
						bs.person_job = j0
					else:
						bs.staffed = false
			bstates[i] = bs
		else:
			bstates[i].bld = b
	for i in bstates.keys():
		if not state.buildings.has(i) or state.buildings[i].is_hq:
			var bs_gone: BState = bstates[i]
			if bs_gone.has_person:
				_return_person(bs_gone.person_job, bs_gone.bld.owner)  # Arbeiter kehrt zurück (#9)
			bstates.erase(i)

	# Verschwundene Lagerhäuser (#31): Lager, deren Gebäude weg ist, aus der Liste nehmen
	# (HQ = #0 bleibt immer). Restbestand UND noch nicht ausgelieferte outbox-Waren ins
	# HQ-Lager übernehmen, damit beim Abriss keine Ware verloren geht.
	for si in range(storages.size() - 1, 0, -1):
		var st := storages[si]
		if st.idx < 0 or not state.buildings.has(st.idx) \
				or state.buildings[st.idx].is_hq or state.buildings[st.idx].under_construction:
			for g in st.stock:
				storages[0].stock[g] = int(storages[0].stock.get(g, 0)) + int(st.stock[g])
			for good in st.outbox:
				storages[0].stock[good.type] = int(storages[0].stock.get(good.type, 0)) + 1
			storages.remove_at(si)

	for fi in flag_goods.keys():
		if not state.flags.has(fi):
			# Flagge weg (Abriss): die dort wartenden Waren NICHT verwerfen — sonst
			# bleibt `incoming` beim Zielgebäude hängen und es wird nie nachgefordert.
			# Jede Ware Richtung Ziel umleiten, sonst sicher zurück ins HQ-Lager.
			for g in flag_goods[fi]:
				_rehome_good(g, _flag_world(fi))
			flag_goods.erase(fi)

	state.recompute_territory()
	# Sichtbarkeit NICHT mehr bei jedem resync voll neu berechnen (Issue #30):
	# Aufgedecktes wächst nur und wird beim Platzieren inkrementell ergänzt
	# (place_building/_add_flag/build_road). Voll-Neuberechnung nur beim Laden.
	dirty = true


## Startbestand des HQ-Lagers. S2-Lagermodell (RTTR Inventory): ein Lager hält
## WAREN und PERSONEN. Beides kommt aus [Tuning] (konfigurierbar über tuning.json).
func _init_hq_stock() -> void:
	hq_stock = Tuning.hq_start_goods()
	hq_people = Tuning.hq_start_people()
	soldiers = Tuning.hq_start_soldiers()  # Anfangsbesatzung, hält Militärgebäude sofort
	_helper_timer = Tuning.helper_produce_ticks()  # erster Träger-Nachschub nach einem Takt


## Personenbestand eines Berufs im HQ-Lager (S2-Personalmodell, Issue #9).
func hq_people_count(job: int) -> int:
	return int(hq_people.get(job, 0))


## Entnimmt EINE Person des Berufs [job] aus dem Lager des Besitzers (Issue #9).
## S2-Modell (RTTR Inventory): existiert der Spezialist im Lager, wird er genommen;
## sonst wird er aus einem Träger (HELPER) + dem passenden Werkzeug rekrutiert
## ([Jobs.tool_for]). Berufe ohne Werkzeug (Träger/Müller/Brauer/...) entstehen
## direkt aus einem Träger. Reicht weder Spezialist noch Träger(+Werkzeug), kommt
## false zurück → der Posten (Straße/Gebäude) bleibt unbesetzt und wird später erneut
## versucht. Nur der Spieler (owner 0) hat ein Personen-Lager; Gegner (owner != 0)
## sind im aktuellen Wirtschaftsmodell abstrakt (kein Pool, Issue #24) → immer true.
func _take_person(job: int, owner: int) -> bool:
	if owner != 0:
		return true
	if int(hq_people.get(job, 0)) > 0:
		hq_people[job] = int(hq_people[job]) - 1
		return true
	# Spezialist fehlt → aus einem Träger (+ ggf. Werkzeug) rekrutieren.
	if int(hq_people.get(Jobs.HELPER, 0)) <= 0:
		return false
	var tool := Jobs.tool_for(job)
	if tool == -1:
		hq_people[Jobs.HELPER] = int(hq_people[Jobs.HELPER]) - 1
		return true
	if int(hq_stock.get(tool, 0)) <= 0:
		return false
	hq_people[Jobs.HELPER] = int(hq_people[Jobs.HELPER]) - 1
	hq_stock[tool] = int(hq_stock[tool]) - 1
	return true


## Gibt EINE Person des Berufs [job] ins Lager zurück (Straßen-/Gebäudeabriss,
## Bauarbeiter-Rückkehr). Spezialisten kehren als ihr Beruf zurück — das Werkzeug
## wurde bei der Rekrutierung verbraucht (S2/RTTR-Inventory). Gegner: no-op.
func _return_person(job: int, owner: int) -> void:
	if owner != 0 or job < 0:
		return
	hq_people[job] = int(hq_people.get(job, 0)) + 1


## Gesamtbevölkerung des Spieler-Lagers = Reserve + alle eingesetzten Personen
## (Träger auf Straßen, Arbeiter/Bauarbeiter in Gebäuden, inkl. der gerade vom Lager
## anmarschierenden — diese hängen am Carrier/BState, nicht am Marcher). Für Save:
## gespeichert wird die Gesamtzahl; beim Laden verteilt `resync()` daraus alles neu
## (Träger/Arbeiter laufen wieder los) — deterministisch. (Issue #9)
func total_people() -> Dictionary:
	var tot: Dictionary = hq_people.duplicate()
	for r in carriers:
		var c: Carrier = carriers[r]
		if c.has_person:
			tot[Jobs.HELPER] = int(tot.get(Jobs.HELPER, 0)) + 1
	for i in bstates:
		var bs: BState = bstates[i]
		if bs.has_person:
			tot[bs.person_job] = int(tot.get(bs.person_job, 0)) + 1
	return tot


## Träger-Nachschub des HQ-Lagers (Issue #33). Wie im Original (RTTR
## nobBaseWarehouse::HandleProduceHelperEvent) regelt das Lager seinen Träger-
## Reservebestand auf eine Obergrenze ein: alle [Tuning.helper_produce_ticks] Ticks
## einen HELPER nachschieben, solange unter [Tuning.helper_cap]; darüber abbauen. So
## versiegt die Bevölkerung nicht (eingesetzte Träger werden nachproduziert), ist
## aber rate-begrenzt. Deterministisch (fester Takt, kein Zufall) → lockstep-tauglich.
## Nur das Spieler-Lager (owner 0) hat einen Personen-Pool. Bei Mehr-Lager (#31)
## läuft das später pro Lager → Obergrenze skaliert mit der Lageranzahl wie im Original.
func _tick_helper_production() -> void:
	if hq_flag < 0:
		return  # kein Spieler-Lager (kein/zerstörtes HQ) → kein Nachschub
	if _helper_timer > 0:
		_helper_timer -= 1
		return
	_helper_timer = Tuning.helper_produce_ticks()
	var cap := Tuning.helper_cap()
	var have := int(hq_people.get(Jobs.HELPER, 0))
	if have < cap:
		hq_people[Jobs.HELPER] = have + 1
	elif have > cap:
		hq_people[Jobs.HELPER] = have - 1


# --------------------------------------------------------------------------
#  Ein Tick
# --------------------------------------------------------------------------

func tick() -> void:
	if ai_enabled and ai != null:
		ai.think(self, 1)
	_tick_tree_growth()
	_tick_field_growth()
	_tick_decay_fields()
	_tick_soldiers()
	_tick_promotions()
	_tick_catapults()
	_tick_house_carrier()
	_tick_helper_production()
	_distribute_inputs()  # #43: knappe Mehrfach-Waren gewichtet verteilen (vor Pull der Gebäude)
	for i in state.buildings:
		if bstates.has(i):
			_tick_building(bstates[i])
	_tick_dispatch()
	for r in state.roads:
		if carriers.has(r):
			_tick_carrier(carriers[r])
	_tick_strays()


func _capacity_for(size: int) -> int:
	match size:
		WorldState.BQ_CASTLE: return 6
		WorldState.BQ_HOUSE: return 4
	return 2


func _init_tree_growth_from_map() -> void:
	_growing_trees.clear()
	if state == null or state.map == null:
		return
	for key in state.map.tree_stage:
		var i := int(key)
		if state.map.objects.get(i, -1) != MapData.MO_TREE:
			continue
		var stage := int(state.map.tree_stage[key])
		if stage < MapData.TREE_BIG:
			_growing_trees[i] = float(Tuning.tree_growth_ticks(stage))


## Bestände der zusätzlichen Lagerhäuser (alle Lager außer HQ #0) für Save/Load (#31).
## Schlüssel ist die Flaggenposition (stabil über Lade-Vorgänge), Wert der Warenbestand.
## Das HQ-Lager wird weiter separat über hq_stock gesichert (abwärtskompatibel).
func extra_storages_state() -> Array:
	var w := state.map.width
	var out: Array = []
	for i in range(1, storages.size()):
		var st := storages[i]
		out.append({
			flag = Vector2i(st.flag_idx % w, st.flag_idx / w),
			stock = st.stock.duplicate(),
		})
	return out


## Spielt die mit [extra_storages_state] gesicherten Bestände zurück. Muss NACH resync()
## laufen, weil resync() die Lager erst aus den geladenen Gebäuden anlegt.
func restore_extra_storages(arr: Array) -> void:
	for entry in arr:
		var pos: Vector2i = entry.get("flag", Vector2i(-1, -1))
		var fidx := state.map.idx(pos.x, pos.y)
		if fidx == hq_flag:
			continue
		for st in storages:
			if st.flag_idx == fidx:
				var sd: Dictionary = entry.get("stock", {})
				st.stock = sd.duplicate()
				break


func tree_growth_state() -> Dictionary:
	return _growing_trees.duplicate()


func restore_tree_growth(data: Dictionary) -> void:
	_growing_trees.clear()
	for key in data:
		var i := int(key)
		if state.map.objects.get(i, -1) == MapData.MO_TREE:
			var stage := state.map.tree_stage_at(i % state.map.width, int(i / state.map.width))
			if stage < MapData.TREE_BIG:
				_growing_trees[i] = maxf(float(data[key]), 1.0)
	for key in state.map.tree_stage:
		var i := int(key)
		if _growing_trees.has(i):
			continue
		if state.map.objects.get(i, -1) != MapData.MO_TREE:
			continue
		var stage := int(state.map.tree_stage[key])
		if stage < MapData.TREE_BIG:
			_growing_trees[i] = float(Tuning.tree_growth_ticks(stage))


func _tick_tree_growth() -> void:
	for key in _growing_trees.keys():
		var i := int(key)
		if state.map.objects.get(i, -1) != MapData.MO_TREE:
			_growing_trees.erase(i)
			continue
		var x := i % state.map.width
		var y := int(i / state.map.width)
		var left := float(_growing_trees[i]) - 1.0
		if left > 0.0:
			_growing_trees[i] = left
			continue
		var stage := state.map.tree_stage_at(x, y)
		if stage >= MapData.TREE_BIG:
			_growing_trees.erase(i)
			continue
		stage += 1
		state.map.set_tree_stage(x, y, stage)
		dirty = true
		if stage < MapData.TREE_BIG:
			_growing_trees[i] = float(Tuning.tree_growth_ticks(stage))
		else:
			_growing_trees.erase(i)


# --------------------------------------------------------------------------
#  Feld-Wachstum (Bauernhof, Issue #26) — analog zum Baumwachstum.
#  Felder wachsen seed→young→growing→reif. Ein REIFES Feld bekommt einen
#  Verdorr-Timer (RTTR State::Withering): erntet es niemand, verdorrt es zu
#  einer nicht-blockierenden Deko und verschwindet danach. _growing_fields hält
#  je Knoten die Restticks bis zum nächsten Ereignis (nächste Stufe bzw. Verdorr).
# --------------------------------------------------------------------------

## Restticks des nächsten Ereignisses für ein Feld der Stufe `stage`:
## wächst es noch → Wachstumszeit; ist es reif → Verdorr-Zeit.
func _field_event_ticks(stage: int) -> float:
	if stage < MapData.FIELD_RIPE:
		return float(Tuning.field_growth_ticks(stage))
	return float(Tuning.field_wither_ticks())


func _init_field_growth_from_map() -> void:
	_growing_fields.clear()
	if state == null or state.map == null:
		return
	for key in state.map.field_stage:
		var i := int(key)
		if state.map.objects.get(i, -1) != MapData.MO_FIELD:
			continue
		_growing_fields[i] = _field_event_ticks(int(state.map.field_stage[key]))


func field_growth_state() -> Dictionary:
	return _growing_fields.duplicate()


func restore_field_growth(data: Dictionary) -> void:
	_growing_fields.clear()
	for key in data:
		var i := int(key)
		if state.map.objects.get(i, -1) == MapData.MO_FIELD:
			_growing_fields[i] = maxf(float(data[key]), 1.0)
	for key in state.map.field_stage:
		var i := int(key)
		if _growing_fields.has(i):
			continue
		if state.map.objects.get(i, -1) != MapData.MO_FIELD:
			continue
		_growing_fields[i] = _field_event_ticks(int(state.map.field_stage[key]))


func _tick_field_growth() -> void:
	for key in _growing_fields.keys():
		var i := int(key)
		if state.map.objects.get(i, -1) != MapData.MO_FIELD:
			_growing_fields.erase(i)
			continue
		var x := i % state.map.width
		var y := int(i / state.map.width)
		var left := float(_growing_fields[i]) - 1.0
		if left > 0.0:
			_growing_fields[i] = left
			continue
		var stage := state.map.field_stage_at(x, y)
		if stage >= MapData.FIELD_RIPE:
			# Reifes Feld blieb ungeerntet → es verdorrt (RTTR State::Withering).
			state.map.clear_map_object(x, y)
			_growing_fields.erase(i)
			state.map.set_field_decay(x, y, MapData.FIELD_DECAY_WITHERED)
			_decay_fields[i] = float(Tuning.field_decay_ticks())
			dirty = true
			continue
		stage += 1
		state.map.set_field_stage(x, y, stage)
		_growing_fields[i] = _field_event_ticks(stage)
		dirty = true


# --------------------------------------------------------------------------
#  Feld-Deko (RTTR: abgeerntetes/verdorrtes Feld bleibt als nicht-blockierendes
#  noEnvObject liegen und verschwindet nach kurzer Zeit). Issue #26.
# --------------------------------------------------------------------------

func _init_decay_fields_from_map() -> void:
	_decay_fields.clear()
	if state == null or state.map == null:
		return
	for key in state.map.field_decay:
		_decay_fields[int(key)] = float(Tuning.field_decay_ticks())


func decay_fields_state() -> Dictionary:
	return _decay_fields.duplicate()


func restore_decay_fields(data: Dictionary) -> void:
	_decay_fields.clear()
	for key in data:
		var i := int(key)
		if state.map.field_decay.has(i):
			_decay_fields[i] = maxf(float(data[key]), 1.0)
	for key in state.map.field_decay:
		var i := int(key)
		if not _decay_fields.has(i):
			_decay_fields[i] = float(Tuning.field_decay_ticks())


func _tick_decay_fields() -> void:
	for key in _decay_fields.keys():
		var i := int(key)
		if not state.map.field_decay.has(i):
			_decay_fields.erase(i)
			continue
		var x := i % state.map.width
		var y := int(i / state.map.width)
		# Wird der Knoten anderweitig genutzt (Bau/Flagge/Straße/Objekt), Deko sofort weg.
		if state._occ(x, y) != WorldState.OBJ_NONE or state.has_object(x, y):
			state.map.field_decay.erase(i)
			_decay_fields.erase(i)
			dirty = true
			continue
		var left := float(_decay_fields[i]) - 1.0
		if left > 0.0:
			_decay_fields[i] = left
			continue
		# Deko verschwindet (RTTR: noEnvObject wird entfernt).
		state.map.field_decay.erase(i)
		_decay_fields.erase(i)
		dirty = true


func hq_pos_of(owner: int) -> Vector2i:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq and b.owner == owner:
			return b.pos
	return Vector2i(-1, -1)


## Münzen aus dem HQ befördern eigene Garnisonen (Verteidigungsrüstung).
func _tick_promotions() -> void:
	if hq_flag < 0:
		return
	_promo_timer -= 1
	if _promo_timer > 0:
		return
	_promo_timer = PROMO_TICKS
	if hq_stock.get(Goods.COINS, 0) <= 0:
		return
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0 or b.is_hq or b.influence <= 0 or b.under_construction:
			continue
		if not b.wants_coins:
			continue  # Spieler hat Münzanforderung für dieses Gebäude abgeschaltet
		if b.garrison <= 0 or b.promotions >= b.garrison:
			continue
		if _next_hop(hq_flag, state.map.idx(b.flag_pos.x, b.flag_pos.y)) < 0:
			continue
		hq_stock[Goods.COINS] = hq_stock[Goods.COINS] - 1
		b.promotions += 1
		dirty = true
		return


## Katapulte beschießen das nächste feindliche Militärgebäude in Reichweite.
func _tick_catapults() -> void:
	_cata_timer -= 1
	if _cata_timer > 0:
		return
	_cata_timer = CATAPULT_TICKS
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.def_id != "catapult" or b.under_construction or b.garrison <= 0:
			continue
		var best: WorldState.Building = null
		var best_d := 1 << 30
		for j in state.buildings:
			var p: WorldState.Building = state.buildings[j]
			if p.owner == b.owner or p.influence <= 0 or p.under_construction:
				continue
			var d := WorldState.hex_distance(b.pos, p.pos)
			if d <= b.influence + CATAPULT_RANGE and d < best_d:
				best_d = d
				best = p
		if best != null:
			if best.promotions > 0:
				best.promotions -= 1
			elif best.garrison > 0:
				best.garrison -= 1
			state.recompute_territory()
			dirty = true


## Soldaten ausbilden, Marschierende bewegen, neue Soldaten entsenden.
func _tick_soldiers() -> void:
	if hq_flag < 0:
		return
	_soldier_timer -= 1
	if _soldier_timer <= 0:
		_soldier_timer = SOLDIER_TICKS
		_try_recruit()
	_tick_marchers()
	if soldiers <= 0:
		return
	var w := state.map.width
	var hq_pos := Vector2i(hq_flag % w, hq_flag / w)
	for i in state.buildings:
		if not bstates.has(i):
			continue
		var bs: BState = bstates[i]
		if bs.bld.owner != 0:
			continue
		if bs.is_construction or int(bs.def.get("influence", 0)) <= 0:
			continue
		var inc: int = _inc_soldiers.get(i, 0)
		if bs.bld.garrison + inc >= bs.bld.capacity:
			continue
		var route := state.find_route(hq_pos, Vector2i(bs.flag_idx % w, bs.flag_idx / w))
		if route.size() < 2:
			continue
		# Soldaten losschicken (einer pro Tick).
		var m := Marcher.new()
		m.route = route
		m.dest_building = i
		if not _load_leg(m):
			continue
		soldiers -= 1
		_inc_soldiers[i] = inc + 1
		marchers.append(m)
		return


## Einen Soldaten (Gefreiten) rekrutieren — RTTR-getreu aus
## 1 Schwert + 1 Schild + 1 Bier + 1 Träger (Helper), gedrosselt durch die
## Rekrutierungsrate (0..10). Deterministisch: ein Akkumulator zählt die Rate hoch
## und löst je 10 Punkte genau eine Rekrutierung aus (Rate 10 = jeden Takt, 5 = jeden
## zweiten, 0 = nie). (#41)
func _try_recruit() -> void:
	if recruiting_ratio <= 0:
		return
	if int(hq_stock.get(Goods.SWORD, 0)) <= 0 or int(hq_stock.get(Goods.SHIELD, 0)) <= 0 \
			or int(hq_stock.get(Goods.BEER, 0)) <= 0 or int(hq_people.get(Jobs.HELPER, 0)) <= 0:
		return  # nicht alle vier Zutaten vorhanden → keine Rekrutierung
	_recruit_accum += recruiting_ratio
	if _recruit_accum < 10:
		return
	_recruit_accum -= 10
	hq_stock[Goods.SWORD] = int(hq_stock[Goods.SWORD]) - 1
	hq_stock[Goods.SHIELD] = int(hq_stock[Goods.SHIELD]) - 1
	hq_stock[Goods.BEER] = int(hq_stock[Goods.BEER]) - 1
	hq_people[Jobs.HELPER] = int(hq_people[Jobs.HELPER]) - 1
	soldiers += 1


func _tick_marchers() -> void:
	var done: Array[Marcher] = []
	for m in marchers:
		if m.attack:
			# Geradliniger Angriff.
			var dist := maxf(m.from_w.distance_to(m.to_w), 1.0)
			m.t += ATTACK_SPEED / dist
			if m.t >= 1.0:
				_resolve_attack(m)
				done.append(m)
			continue
		if m.nodes.size() < 2 and not _load_leg(m):
			_drop_marcher(m)
			done.append(m)
			continue
		m.pos += MARCH_SPEED
		if m.pos >= float(m.nodes.size() - 1):
			m.pos = float(m.nodes.size() - 1)
			m.leg += 1
			if m.leg >= m.route.size() - 1:
				_arrive_marcher(m)
				done.append(m)
			elif not _load_leg(m):
				_drop_marcher(m)
				done.append(m)
	for m in done:
		marchers.erase(m)


## Einen Angreifer-Trupp von [param src] gegen [param tgt] schicken.
## Jeder mitgeschickte Soldat zieht einen aus der Garnison von src ab.
func send_attackers(src: WorldState.Building, tgt: WorldState.Building) -> int:
	var n := src.garrison
	if n <= 0:
		return 0
	var from := state.map.node_world(src.pos.x, src.pos.y)
	var to := state.map.node_world(tgt.pos.x, tgt.pos.y)
	var tgt_idx := state.map.idx(tgt.pos.x, tgt.pos.y)
	for k in n:
		var m := Marcher.new()
		m.attack = true
		m.attacker_owner = src.owner
		m.from_w = from
		m.to_w = to
		m.dest_building = tgt_idx
		m.t = -0.18 * k  # gestaffelt loslaufen
		marchers.append(m)
	src.garrison = 0
	state.recompute_territory()
	dirty = true
	return n


func _resolve_attack(m: Marcher) -> void:
	var tgt: WorldState.Building = state.buildings.get(m.dest_building)
	if tgt == null:
		return
	if tgt.owner == m.attacker_owner:
		# Schon in eigener Hand → Angreifer verstärkt die Garnison.
		if tgt.garrison < maxi(tgt.capacity, 1):
			tgt.garrison += 1
		state.recompute_territory()
		dirty = true
		return
	if tgt.promotions > 0:
		tgt.promotions -= 1  # Rüstung (Münz-Beförderung) fängt den Treffer ab
	elif tgt.garrison > 0:
		tgt.garrison -= 1    # ein Verteidiger fällt (1:1)
	if tgt.garrison <= 0 and tgt.promotions <= 0:
		# Erobert → Besitzerwechsel.
		tgt.owner = m.attacker_owner
		tgt.garrison = 1
		tgt.promotions = 0
		resync()  # Simulation an neuen Besitzer anpassen (bstates)
	state.recompute_territory()
	dirty = true


func _load_leg(m: Marcher) -> bool:
	m.nodes = _road_between(m.route[m.leg], m.route[m.leg + 1])
	m.pos = 0.0
	return m.nodes.size() >= 2


func _arrive_marcher(m: Marcher) -> void:
	if m.purpose_carrier:
		_activate_carrier(m.car_road, m.car_end)
		return
	if m.purpose_return:
		return  # Bauarbeiter ist zurück im HQ → verschwindet
	if m.purpose_worker:
		if bstates.has(m.work_bidx):
			bstates[m.work_bidx].staffed = true
		return
	if bstates.has(m.dest_building):
		bstates[m.dest_building].bld.garrison += 1
		state.recompute_territory()
		dirty = true
	_inc_soldiers[m.dest_building] = maxi(0, _inc_soldiers.get(m.dest_building, 0) - 1)


func _drop_marcher(m: Marcher) -> void:
	if m.purpose_carrier:
		# Anmarsch abgebrochen (Straße verändert) → nicht aktivieren, später neu
		# versuchen (resync ruft _dispatch_carrier erneut).
		if carriers.has(m.car_road):
			carriers[m.car_road].dispatched = false
		return
	if m.purpose_return:
		return  # Rückweg abgebrochen → einfach verschwinden
	if m.purpose_worker:
		if bstates.has(m.work_bidx):
			bstates[m.work_bidx].staffed = true  # Fallback: trotzdem besetzen
		return
	soldiers += 1  # Soldat kehrt in die Reserve zurück
	_inc_soldiers[m.dest_building] = maxi(0, _inc_soldiers.get(m.dest_building, 0) - 1)


func _activate_carrier(road: WorldState.Road, end: int) -> void:
	if not carriers.has(road):
		return
	var c: Carrier = carriers[road]
	c.active = true
	c.dispatched = true
	c.seg_pos = 0.0 if end == 0 else float(road.length())
	c.target = float(road.length()) * 0.5
	c.state = C_IDLE


## Ist [def_id] ein Lager-Gebäude (HQ oder baubares Lagerhaus)? Kategorie "lager".
func _is_storage_def(def_id: String) -> bool:
	return String(BuildingCatalog.get_def(def_id).get("category", "")) == "lager"


## Meldet ein fertiges Lagerhaus als zusätzliches Lager an (#31): eigener Tür-Träger,
## eigener (anfangs leerer) Bestand. Idempotent — ein bereits registriertes Lager
## (gleiche Flagge) wird nur aufgefrischt, nicht doppelt angelegt.
func _register_storage(idx: int, b: WorldState.Building) -> void:
	var fidx := state.map.idx(b.flag_pos.x, b.flag_pos.y)
	for st in storages:
		if st.flag_idx == fidx:
			st.idx = idx
			st.owner = b.owner
			if st.house == null:
				st.house = HouseCarrier.new()
			return
	var ns := Storage.new()
	ns.flag_idx = fidx
	ns.idx = idx
	ns.owner = b.owner
	ns.house = HouseCarrier.new()
	storages.append(ns)


## Nächstgelegenes erreichbares Lager von Flagge [from_flag] aus, das [pred] erfüllt
## (#31). Distanz = Hop-Zahl der gecachten [find_route]-Polylinie; bei Gleichstand
## gewinnt der kleinere Lager-Index (deterministisch, lockstep-tauglich). Gibt `null`
## zurück, wenn kein passendes Lager erreichbar ist. Mit nur einem Lager (HQ) liefert
## das stets das HQ, sofern erreichbar und [pred] erfüllt.
func _nearest_storage(from_flag: int, owner: int, pred: Callable) -> Storage:
	var w := state.map.width
	var from_pos := Vector2i(from_flag % w, from_flag / w)
	var best: Storage = null
	var best_cost := INF
	for st in storages:
		if st.flag_idx < 0 or st.owner != owner:
			continue
		if not pred.call(st):
			continue
		var route := state.find_route(from_pos, Vector2i(st.flag_idx % w, st.flag_idx / w))
		if route.is_empty():
			continue
		var cost := float(route.size())
		if cost < best_cost:
			best_cost = cost
			best = st
	return best


## Flaggenposition des HQ eines Besitzers (nicht der Gebäudeknoten!).
func _hq_flag_pos(owner := 0) -> Vector2i:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq and b.owner == owner:
			return b.flag_pos
	return Vector2i(-1, -1)


## Eine Straßenteilung verarbeiten: den bestehenden Träger der alten Straße auf das
## Teilstück übernehmen, auf dem er gerade steht (Ware behält er!). Das andere
## Teilstück bleibt vorerst unbesetzt und wird gestaffelt vom HQ neu besetzt.
func _apply_split(sp: Dictionary) -> void:
	var old: WorldState.Road = sp.old
	if not carriers.has(old):
		return
	var c: Carrier = carriers[old]
	carriers.erase(old)
	if not c.active:
		# Träger war noch gar nicht da (marschiert noch vom HQ) → beide Teilstücke
		# werden normal (gestaffelt) neu besetzt; nichts zu übernehmen. Seinen
		# reservierten Träger gibt er dabei ins Lager zurück (#9).
		if c.has_person:
			_return_person(Jobs.HELPER, c.road.owner)
		return
	var k := int(sp.k)
	var on_r1: bool = c.seg_pos <= float(k)
	var r_keep: WorldState.Road = sp.r1 if on_r1 else sp.r2
	# seg_pos ist in Knotensegmenten: auf r1 unverändert, auf r2 um k verschoben.
	var new_seg := c.seg_pos if on_r1 else c.seg_pos - float(k)
	c.road = r_keep
	c.seg_pos = clampf(new_seg, 0.0, float(r_keep.length()))
	c.active = true
	c.dispatched = true
	if c.carrying != null:
		# Ware zur Flagge weitertragen, die Richtung Ziel führt (vorwärts).
		var e0 := _end_flag(r_keep, 0)
		var e1 := _end_flag(r_keep, 1)
		var rl0 := _route_len(e0, c.carrying.dest)
		var rl1 := _route_len(e1, c.carrying.dest)
		var deliver_end := 1
		if rl0 >= 0 and (rl1 < 0 or rl0 <= rl1):
			deliver_end = 0
		c.pickup_end = 1 - deliver_end
		c.state = C_CARRYING
		c.target = float(r_keep.length()) if deliver_end == 1 else 0.0
	else:
		c.state = C_IDLE
		c.target = float(r_keep.length()) * 0.5
	carriers[r_keep] = c


## Gestaffeltes Besetzen: pro Intervall höchstens EINEN noch unbesetzten Träger vom
## HQ losschicken, damit bei vielen neuen Straßen die Träger nacheinander anlaufen
## (sichtbarer „Strom") statt alle gleichzeitig.
const DISPATCH_INTERVAL := 6   # Ticks zwischen zwei Träger-Anforderungen (~0,2 s)
var _dispatch_cd := 0


func _tick_dispatch() -> void:
	if _dispatch_cd > 0:
		_dispatch_cd -= 1
		return
	for r in carriers:
		var c: Carrier = carriers[r]
		if not c.active and not c.dispatched:
			_dispatch_carrier(c)
			if c.dispatched:        # nur bei Erfolg (mit HQ verbunden) Pause einlegen
				_dispatch_cd = DISPATCH_INTERVAL
				return


## Schickt einen Träger vom HQ zur neuen Straße. OHNE HQ-Verbindung passiert
## nichts — die Straße bleibt unbesetzt, bis sie (später) verbunden ist.
func _dispatch_carrier(c: Carrier) -> void:
	var hq := _hq_flag_pos(c.road.owner)
	if hq.x < 0:
		return
	var best: Array[Vector2i] = []
	var best_end := 0
	for endi in [0, 1]:
		var rp := c.road.a if endi == 0 else c.road.b
		var rt := state.find_route(hq, rp)
		if rt.size() >= 1 and (best.is_empty() or rt.size() < best.size()):
			best = rt
			best_end = endi
	if best.is_empty():
		return  # nicht mit HQ verbunden → unbesetzt lassen
	# S2-Personalmodell (Issue #9): ein Träger braucht einen HELPER aus dem Lager.
	# Ist keiner verfügbar, bleibt die Straße unbesetzt und wird später erneut versucht.
	if not c.has_person:
		if not _take_person(Jobs.HELPER, c.road.owner):
			return
		c.has_person = true
	c.dispatched = true
	if best.size() < 2:
		_activate_carrier(c.road, best_end)  # HQ-Flagge ist schon das Straßenende
		return
	var m := Marcher.new()
	m.purpose_carrier = true
	m.attacker_owner = c.road.owner
	m.car_road = c.road
	m.car_end = best_end
	m.route = best
	m.leg = 0
	if not _load_leg(m):
		c.dispatched = false  # Etappe nicht ladbar → später neu versuchen
		return
	marchers.append(m)


func _road_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	for r in state.roads:
		if r.a == a and r.b == b:
			return r.nodes.duplicate()
		if r.a == b and r.b == a:
			var rev := r.nodes.duplicate()
			rev.reverse()
			return rev
	var empty: Array[Vector2i] = []
	return empty


func marcher_world(m: Marcher) -> Vector2:
	if m.attack:
		return m.from_w.lerp(m.to_w, clampf(m.t, 0.0, 1.0))
	if m.nodes.size() < 2:
		return state.map.node_world(m.route[m.leg].x, m.route[m.leg].y)
	var seg: int = clampi(int(floor(m.pos)), 0, m.nodes.size() - 2)
	var frac: float = clampf(m.pos - seg, 0.0, 1.0)
	var p0 := state.map.node_world(m.nodes[seg].x, m.nodes[seg].y)
	var p1 := state.map.node_world(m.nodes[seg + 1].x, m.nodes[seg + 1].y)
	return p0.lerp(p1, frac)


func marcher_facing(m: Marcher) -> Vector2:
	if m.attack:
		return m.to_w - m.from_w
	if m.nodes.size() < 2:
		return Vector2.ZERO
	var seg: int = clampi(int(floor(m.pos)), 0, m.nodes.size() - 2)
	return state.map.node_world(m.nodes[seg + 1].x, m.nodes[seg + 1].y) \
		- state.map.node_world(m.nodes[seg].x, m.nodes[seg].y)


func _tick_building(bs: BState) -> void:
	if bs.bld.owner != 0:
		_tick_enemy_building_visual(bs)
		return
	if bs.is_construction:
		_tick_construction(bs)
		return
	# Produktionsgebäude brauchen einen Arbeiter, der erst vom HQ kommt.
	if not bs.staffed:
		if int(bs.def.get("influence", 0)) > 0:
			bs.staffed = true  # Militär braucht keinen Produktionsarbeiter
		else:
			if not bs.worker_sent:
				_dispatch_worker(bs)
			return
	_track_productivity(bs)
	if bs.stopped:
		# "Stop" blockiert nur den NÄCHSTEN Arbeitsgang, nicht den laufenden:
		# Ein begonnener Zyklus (Hinweg/Aktion/Rückweg/Wartezeit) wird zu Ende
		# gebracht. Erst wenn der Arbeiter wieder im Haus ist (WK_IDLE), verharrt
		# er dort und startet keinen neuen Gang mehr.
		if bs.wphase != WK_IDLE:
			_tick_work(bs)
		_ship_outputs(bs)  # vorhandene Ausgänge noch abtransportieren
		return
	_request_inputs(bs)
	_tick_work(bs)
	_ship_outputs(bs)


## Produktivität wie S2: Anteil aktiver Arbeitsticks in einem rollenden Fenster.
## Bei vollem Fenster werden beide Zähler halbiert (exponentielles Vergessen) —
## reine Ganzzahlen, damit die Simulation deterministisch bleibt.
func _track_productivity(bs: BState) -> void:
	if int(bs.def.get("output", -1)) == -1 and String(bs.def.get("resource", "")) != "plant_tree":
		return  # Lager / Militär: keine Produktivität
	bs.prod_total += 1
	if bs.producing:
		bs.prod_active += 1
	if bs.prod_total >= PROD_WINDOW:
		bs.prod_total >>= 1
		bs.prod_active >>= 1


## Sichtbare, vereinfachte Gegner-Wirtschaft: Gegnergebäude mischen sich nicht in
## das Spieler-HQ-Lager ein, schicken aber Arbeiter sichtbar vom eigenen HQ und
## lassen Ressourcenarbeiter in ihrer Umgebung arbeiten.
func _tick_enemy_building_visual(bs: BState) -> void:
	if bs.is_construction:
		bs.bld.under_construction = false
		bs.is_construction = false
	if int(bs.def.get("influence", 0)) > 0:
		bs.staffed = true
		return
	if not bs.staffed:
		if not bs.worker_sent:
			_dispatch_worker(bs)
		return
	var resource := String(bs.def.get("resource", ""))
	if resource == "":
		if bs.work_timer > 0:
			bs.work_timer -= 1
		else:
			bs.work_timer = int(bs.def.get("work", 120)) + 120
		return
	match bs.wphase:
		WK_IDLE:
			if bs.work_timer > 0:
				bs.work_timer -= 1
				return
			var tgt := _resource_target(bs)
			if tgt.x < 0:
				bs.work_timer = 180
				return
			bs.worker_target = tgt
			bs.producing = true
			_enter_wphase(bs, WK_OUT, _worker_walk_ticks(bs, tgt))
		WK_OUT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_enter_wphase(bs, WK_WORK, float(Tuning.work_action(bs.bld.def_id, resource)))
		WK_WORK:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_do_resource_action(bs)
				_enter_wphase(bs, WK_BACK, _worker_walk_ticks(bs, bs.worker_target))
		WK_BACK:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_WAIT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				bs.producing = false
				bs.worker_target = Vector2i(-1, -1)
				bs.wphase = WK_IDLE
				bs.work_timer = 120


## Produktion eines Gebäudes anhalten/fortsetzen.
func toggle_production(bld: WorldState.Building) -> bool:
	var bs: BState = bstates.get(state.map.idx(bld.pos.x, bld.pos.y))
	if bs == null:
		return false
	bs.stopped = not bs.stopped
	return bs.stopped


## Schickt einen Arbeiter vom HQ, der das Gebäude besetzt (dann läuft Produktion).
func _dispatch_worker(bs: BState) -> void:
	var hq := _hq_flag_pos(bs.bld.owner)
	var w := state.map.width
	if hq.x < 0:
		bs.staffed = true   # keine HQ (z. B. Testkarte ohne Lager) → sofort besetzen
		bs.worker_sent = true
		return
	var route := state.find_route(hq, Vector2i(bs.flag_idx % w, bs.flag_idx / w))
	if route.size() < 2:
		# Noch nicht ans HQ-Netz angeschlossen: NICHT sofort besetzen, sondern
		# erneut versuchen, sobald eine Straße liegt — der Arbeiter soll sichtbar
		# vom HQ kommen (statt unsichtbar aus dem Nichts zu erscheinen).
		bs.worker_sent = false
		return
	# S2-Personalmodell (Issue #9): den passenden Beruf aus dem Lager holen
	# (Baustelle = Bauarbeiter, fertiges Gebäude = Produktionsberuf). Fehlt das
	# Personal, bleibt das Gebäude unbesetzt und wird später erneut angefordert.
	if not bs.has_person:
		var job := Jobs.BUILDER if bs.is_construction else BuildingCatalog.job_of(bs.bld.def_id)
		if job >= 0:
			if not _take_person(job, bs.bld.owner):
				bs.worker_sent = false
				return
			bs.has_person = true
			bs.person_job = job
	bs.worker_sent = true
	var m := Marcher.new()
	m.purpose_worker = true
	m.attacker_owner = bs.bld.owner
	m.work_bidx = bs.idx
	m.route = route
	m.leg = 0
	if not _load_leg(m):
		bs.staffed = true
		return
	marchers.append(m)


# --- Bau ---

func _tick_construction(bs: BState) -> void:
	var cost: Dictionary = bs.def.get("cost", {})
	# Material immer anfordern (kann schon unterwegs sein).
	for g in cost:
		var need: int = cost[g]
		var have: int = bs.delivered.get(g, 0) + bs.incoming.get(g, 0)
		if have < need:
			_request_from_hq(bs, g, need - have)
	# Bauarbeiter vom HQ holen — ohne ihn wird (noch) nicht gebaut.
	if not bs.staffed:
		if not bs.worker_sent:
			_dispatch_worker(bs)
		return
	# Proportionaler Fortschritt: baut nur so weit, wie Material schon da ist.
	var target := _cost_value(cost)
	if target <= 0.0:
		target = 1.0
	var available := 0.0
	for g in cost:
		available += minf(bs.delivered.get(g, 0), float(cost[g])) * _mat_value(g)
	bs.built = minf(bs.built + target / float(BUILD_TIME), available)
	bs.construct_progress = int(float(BUILD_TIME) * bs.built / target)
	if bs.built >= target - 0.001:
		bs.bld.under_construction = false
		bs.is_construction = false
		_dispatch_builder_return(bs)  # Bauarbeiter läuft sichtbar zurück zum HQ
		# Bauarbeiter kehrt ins Lager zurück (#9); der Produktionsarbeiter wird gleich
		# über _dispatch_worker frisch angefordert (eigener Berufsverbrauch).
		if bs.has_person:
			_return_person(bs.person_job, bs.bld.owner)
			bs.has_person = false
			bs.person_job = -1
		# Fertiges Lagerhaus wird sofort ein aktives Lager (#31): eigener Tür-Träger
		# und Bestand, kein Produktionsarbeiter. Der bstate entfällt (kein Produzent/
		# Konsument). Ohne diesen Hook würde das Lager erst beim nächsten resync greifen.
		if bs.bld.owner == 0 and not bs.bld.is_hq and _is_storage_def(bs.bld.def_id):
			_register_storage(bs.idx, bs.bld)
			bstates.erase(bs.idx)
			dirty = true
			return
		bs.staffed = false      # Bauarbeiter geht; Produktionsarbeiter kommt danach
		bs.worker_sent = false
		bs.delivered.clear()
		bs.incoming.clear()
		state.recompute_territory()
		dirty = true


## Bauarbeiter kehrt nach fertigem Bau von der Baustellenflagge zum HQ zurück.
func _dispatch_builder_return(bs: BState) -> void:
	if not bs.staffed:
		return  # war nie wirklich da (Fallback-Besetzung) → kein Rückläufer
	var hq := _hq_flag_pos()
	if hq.x < 0:
		return
	var w := state.map.width
	var route := state.find_route(Vector2i(bs.flag_idx % w, bs.flag_idx / w), hq)
	if route.size() < 2:
		return
	var m := Marcher.new()
	m.purpose_return = true
	m.route = route
	m.leg = 0
	if not _load_leg(m):
		return
	marchers.append(m)


## Bauphasen-Info für die 2-stufige Bau-Darstellung.
## Stufe 1 = Holzbau (alle Nicht-Stein-Baustoffe), Stufe 2 = Steinbau/Fertigstellung.
## Hat ein Gebäude keinen Stein, wird der Fortschritt gleichmäßig auf beide Stufen
## verteilt (z. B. 2 Holz: Stufe 1 nach dem 1., Stufe 2 nach dem 2. Holz).
func construct_stage_info(bs: BState) -> Dictionary:
	var cost: Dictionary = bs.def.get("cost", {})
	var wood_val := 0.0
	var stone_val := 0.0
	for g in cost:
		var v := float(cost[g]) * _mat_value(g)
		if g == Goods.STONE:
			stone_val += v
		else:
			wood_val += v
	var target := wood_val + stone_val
	if target <= 0.0:
		target = 1.0
	# Stufe-1-Ende: mit Stein = reiner Holzanteil; ohne Stein = halber Bau.
	var stage1_end := wood_val if stone_val > 0.0 else target * 0.5
	if stage1_end <= 0.0:
		stage1_end = target * 0.5
	var built: float = clampf(bs.built, 0.0, target)
	var stage := 1 if built < stage1_end - 0.0001 else 2
	var sfrac := 0.0
	if stage == 1:
		sfrac = clampf(built / stage1_end, 0.0, 1.0)
	else:
		sfrac = clampf((built - stage1_end) / maxf(target - stage1_end, 0.001), 0.0, 1.0)
	return { stage = stage, stage_frac = sfrac, overall = clampf(built / target, 0.0, 1.0) }


## Baustoff-Wert (Stein wertvoller als Holz/Bretter) für den Baufortschritt.
func _mat_value(g: int) -> float:
	return 2.0 if g == Goods.STONE else 1.0


func _cost_value(cost: Dictionary) -> float:
	var v := 0.0
	for g in cost:
		v += float(cost[g]) * _mat_value(g)
	return v


# --- Eingänge anfordern ---

func _request_inputs(bs: BState) -> void:
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		if _is_distributed(g):
			continue  # gewichtet verteilte Ware → zentral über _distribute_inputs (#43)
		var desired: int = int(inputs[g]) * 2
		var have: int = bs.delivered.get(g, 0) + bs.incoming.get(g, 0)
		if have < desired:
			_request_from_hq(bs, g, desired - have)
	# Nahrungsgruppe (ODER): bis zum Sollbestand auffüllen, egal welche Sorte.
	# Verteilte Sorten (z. B. Fisch → Minen) kommen zentral; hier nur der Rest.
	var group := _food_group(bs)
	if not group.is_empty():
		var have_food := 0
		for g in group:
			have_food += int(bs.delivered.get(g, 0)) + int(bs.incoming.get(g, 0))
		if have_food < FOOD_BUFFER:
			_request_food(bs, group, FOOD_BUFFER - have_food)


## Zentrale Warenverteilung (#43): verteilt knappe Waren mit mehreren Abnehmern
## gewichtet (RTTR distributionMap). Läuft einmal pro Tick VOR der Gebäudeschleife,
## damit die Gebäude den Rest (nicht verteilte Eingänge / übrige Nahrung) sehen.
func _distribute_inputs() -> void:
	for g in distribution:
		_distribute_good(int(g))


## Eine verteilte Ware auf die konkurrierenden Abnehmer verteilen: pro Einheit wird
## ein Abnehmer mit Restbedarf gewichtet gezogen (seeded → deterministisch) und aus
## dem nächsten Lager beliefert. Endet, wenn kein Lager die Ware mehr hat.
func _distribute_good(g: int) -> void:
	var reqs: Array = []
	for i in state.buildings:
		if not bstates.has(i):
			continue
		var bs: BState = bstates[i]
		if bs.bld.owner != 0 or bs.is_construction or bs.stopped or not bs.staffed:
			continue
		if not _is_producer(bs):
			continue
		var w := _dist_weight(g, bs.bld.def_id)
		if w <= 0:
			continue
		var deficit := _good_deficit(bs, g)
		if deficit > 0:
			reqs.append({bs = bs, deficit = deficit, weight = w})
	while not reqs.is_empty():
		var total := 0
		for r in reqs:
			if int(r.deficit) > 0:
				total += int(r.weight)
		if total <= 0:
			return  # niemand will mehr
		var roll := _rng.randi() % total
		var pick: Dictionary = {}
		for r in reqs:
			if int(r.deficit) <= 0:
				continue
			roll -= int(r.weight)
			if roll < 0:
				pick = r
				break
		if pick.is_empty() or not _pull_one(pick.bs, g):
			return  # kein Lager hat die Ware mehr → fertig
		pick.deficit = int(pick.deficit) - 1


## Restbedarf eines Gebäudes an Ware [g] (Sollbestand minus vorhandene + unterwegs).
## Für normale Eingänge: doppelter Rezeptbedarf. Für eine verteilte Nahrungssorte:
## der offene Sollbestand der ODER-Gruppe (eine Einheit füllt die Gruppe).
func _good_deficit(bs: BState, g: int) -> int:
	var have := int(bs.delivered.get(g, 0)) + int(bs.incoming.get(g, 0))
	var inputs: Dictionary = bs.def.get("inputs", {})
	if inputs.has(g):
		return int(inputs[g]) * 2 - have
	if _food_group(bs).has(g):
		var have_food := 0
		for fg in _food_group(bs):
			have_food += int(bs.delivered.get(fg, 0)) + int(bs.incoming.get(fg, 0))
		return FOOD_BUFFER - have_food
	return 0


## Ein Stück Ware [g] aus dem nächsten Lager mit Vorrat für [bs] reservieren und in
## dessen outbox legen. Liefert false, wenn kein erreichbares Lager die Ware führt.
func _pull_one(bs: BState, g: int) -> bool:
	var st := _nearest_storage(bs.flag_idx, 0, func(s: Storage) -> bool:
		return int(s.stock.get(g, 0)) > 0 and s.outbox.size() < FLAG_CAP)
	if st == null:
		return false
	st.stock[g] = int(st.stock[g]) - 1
	bs.incoming[g] = bs.incoming.get(g, 0) + 1
	var good := Good.new()
	good.type = g
	good.dest = bs.flag_idx
	st.outbox.append(good)
	return true


## Fordert [amount] Nahrungseinheiten an: pro Stück das nächste Lager, das IRGENDEINE
## Sorte aus der Gruppe vorrätig hat (Gruppenreihenfolge entscheidet die Sorte).
func _request_food(bs: BState, group: Array, amount: int) -> void:
	# Verteilte Sorten (z. B. Fisch → Minen) liefert die zentrale Verteilung; hier
	# nur die frei beziehbaren Sorten der Gruppe greifen (Gruppenreihenfolge zählt).
	for _k in amount:
		var st := _nearest_storage(bs.flag_idx, 0, func(s: Storage) -> bool:
			if s.outbox.size() >= FLAG_CAP:
				return false
			for fg in group:
				if not _is_distributed(int(fg)) and int(s.stock.get(fg, 0)) > 0:
					return true
			return false)
		if st == null:
			return
		var picked := -1
		for fg in group:
			if not _is_distributed(int(fg)) and int(st.stock.get(fg, 0)) > 0:
				picked = int(fg)
				break
		if picked < 0:
			return
		st.stock[picked] = int(st.stock[picked]) - 1
		bs.incoming[picked] = int(bs.incoming.get(picked, 0)) + 1
		var good := Good.new()
		good.type = picked
		good.dest = bs.flag_idx
		st.outbox.append(good)


## Fordert [amount] Stück Ware [g] aus dem nächstgelegenen Lager an, das sie auf
## Vorrat hat (#31). Pro Stück wird neu das nächste passende Lager gewählt — leert
## sich das nähere, übernimmt automatisch das nächstweitere. Mit nur einem Lager
## (HQ) ist das identisch zum bisherigen Verhalten.
func _request_from_hq(bs: BState, g: int, amount: int) -> void:
	# Ware wartet im Lager; dessen Tür-Träger bringt sie zur Flagge hinaus.
	for _k in amount:
		if not _pull_one(bs, g):
			return


# --- Produktion ---

func _tick_work(bs: BState) -> void:
	var resource: String = String(bs.def.get("resource", ""))
	if not _is_producer(bs) and resource != "plant_tree":
		return  # Lager / Militär: keine Produktion
	var gather := resource != ""   # läuft der Arbeiter zu einem Zielknoten?

	match bs.wphase:
		WK_IDLE:
			if _out_total(bs) >= OUT_CAP:
				bs.idle_reason = IDLE_OUT_FULL
				return
			if not _has_inputs(bs):
				bs.idle_reason = IDLE_NO_INPUTS
				return
			# Ausgangsgut dieses Zyklus wählen (Werkzeugmacher/Schmiede gewichtet;
			# sonst das feste output-Gut). -1 bei Produzenten = nichts wählbar
			# (alle Werkzeug-Prioritäten 0) → warten, NICHT Eingänge verbrauchen.
			var chosen := _pick_output(bs)
			if _is_producer(bs) and chosen == -1:
				bs.idle_reason = IDLE_NO_OUTPUT
				return
			bs.cur_output = chosen
			if gather:
				var tgt := _resource_target(bs)
				if tgt.x < 0:
					bs.idle_reason = IDLE_NO_RESOURCE
					return  # nichts zu tun (kein fällbarer Baum / Pflanzplatz / Feld)
				bs.idle_reason = IDLE_OK
				bs.worker_target = tgt
				bs.out_yield = true  # Default; _do_resource_action setzt bei Säen auf false
				_consume_inputs(bs)
				bs.producing = true
				_enter_wphase(bs, WK_OUT, _worker_walk_ticks(bs, tgt))
			else:
				# Stationäre Produktion (z. B. Sägewerk): kein Weg, nur Arbeitszeit.
				bs.idle_reason = IDLE_OK
				bs.worker_target = Vector2i(-1, -1)
				_consume_inputs(bs)
				bs.producing = true
				_enter_wphase(bs, WK_WORK, float(bs.def.get("work", 100)))
		WK_OUT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_enter_wphase(bs, WK_WORK, float(Tuning.work_action(bs.bld.def_id, resource)))
		WK_WORK:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				if gather:
					_do_resource_action(bs)
					_enter_wphase(bs, WK_BACK, _worker_walk_ticks(bs, bs.worker_target))
				else:
					_add_out(bs, bs.cur_output)
					_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_BACK:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				if bs.out_yield:
					_add_out(bs, bs.cur_output)
				_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_WAIT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				bs.producing = false
				bs.worker_target = Vector2i(-1, -1)
				bs.wphase = WK_IDLE


## Kann dieses Gebäude ein Ausgangsgut erzeugen? (festes `output` ODER eine
## nicht-leere `outputs`-Liste — Werkzeugmacher/Schmiede.)
func _is_producer(bs: BState) -> bool:
	if int(bs.def.get("output", -1)) != -1:
		return true
	var outs = bs.def.get("outputs", null)
	return outs is Array and not (outs as Array).is_empty()


## Gesamtzahl der Waren im Ausgangspuffer (über alle Sorten).
func _out_total(bs: BState) -> int:
	var n := 0
	for g in bs.out_stock:
		n += int(bs.out_stock[g])
	return n


## Eine Ware in den Ausgangspuffer legen (good < 0 = nichts, z. B. Säen/Pflanzen).
func _add_out(bs: BState, good: int) -> void:
	if good < 0:
		return
	bs.out_stock[good] = int(bs.out_stock.get(good, 0)) + 1


## Ausgangsgut für den nächsten Produktionszyklus wählen. Werkzeugmacher: nach
## Bestellungen/Prioritäten; Schmiede u. Ä.: feste `outputs` gleichmäßig abwechseln;
## sonst das einzelne `output`-Gut.
func _pick_output(bs: BState) -> int:
	if bool(bs.def.get("produces_tools", false)):
		return _pick_tool()
	var outs = bs.def.get("outputs", null)
	if outs is Array and not (outs as Array).is_empty():
		var arr: Array = outs
		var pick := int(arr[bs.out_cycle % arr.size()])
		bs.out_cycle += 1
		return pick
	return int(bs.def.get("output", -1))


## Werkzeugmacher: ein Werkzeug nach Bestellungen (Vorrang) bzw. Prioritäts-
## Gewichten wählen (RTTR nofMetalworker: gewichteter, hier seeded-deterministischer
## Zufall). -1 = nichts wählbar (alle Prioritäten 0, keine Bestellung) → wartet.
func _pick_tool() -> int:
	# 1) Offene Bestellungen zuerst, gewichtet nach Priorität (mind. 1).
	var ordered: Array = []
	for g in Goods.tools():
		if int(tool_orders.get(g, 0)) > 0:
			var w0 := maxi(int(tool_priority.get(g, 0)), 1)
			for _i in range(w0):
				ordered.append(g)
	if not ordered.is_empty():
		var op := int(ordered[_rng.randi() % ordered.size()])
		tool_orders[op] = int(tool_orders[op]) - 1
		return op
	# 2) Sonst rein nach Prioritäts-Gewichten (Gewicht 0 = nie).
	var arr: Array = []
	for g in Goods.tools():
		var w1 := int(tool_priority.get(g, 0))
		for _i in range(w1):
			arr.append(g)
	if arr.is_empty():
		return -1
	return int(arr[_rng.randi() % arr.size()])


## Eine Arbeiter-Phase starten (Dauer in Ticks, mind. 1).
func _enter_wphase(bs: BState, phase: int, ticks: float) -> void:
	bs.wphase = phase
	bs.ph_total = maxf(ticks, 1.0)
	bs.ph_t = bs.ph_total


## Laufzeit für eine Strecke bei KONSTANTER Geschwindigkeit (Weltpixel/Tick).
func _worker_walk_ticks(bs: BState, target: Vector2i) -> float:
	var a := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
	var b := state.map.node_world(target.x, target.y)
	var resource := String(bs.def.get("resource", ""))
	return maxf(a.distance_to(b) / maxf(Tuning.worker_speed(bs.bld.def_id, resource), 0.1), 1.0)


## Nahrungsgruppe eines Gebäudes (ODER-Eingang, RTTR WaresNeeded): EINE Einheit aus
## der Gruppe sättigt. Minen: Fisch/Fleisch/Brot; optionale Hausregel ergänzt Bier.
## Leer, wenn das Gebäude keine food_inputs hat.
func _food_group(bs: BState) -> Array:
	var fg = bs.def.get("food_inputs", null)
	if not (fg is Array) or (fg as Array).is_empty():
		return []
	var group: Array = (fg as Array).duplicate()
	if mines_accept_beer and not group.has(Goods.BEER):
		group.append(Goods.BEER)
	return group


## Vorrätige Nahrung (Summe über die Gruppe) im Eingangslager des Gebäudes.
func _food_available(bs: BState) -> int:
	var n := 0
	for g in _food_group(bs):
		n += int(bs.delivered.get(g, 0))
	return n


func _has_inputs(bs: BState) -> bool:
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		if bs.delivered.get(g, 0) < int(inputs[g]):
			return false
	# Nahrungsgruppe (ODER): mindestens eine Einheit aus der Gruppe muss da sein.
	if not _food_group(bs).is_empty() and _food_available(bs) < 1:
		return false
	return true


func _consume_inputs(bs: BState) -> void:
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		bs.delivered[g] = bs.delivered.get(g, 0) - int(inputs[g])
	# Nahrungsgruppe: EINE Einheit verbrauchen, deterministisch aus der best-bevorrateten
	# Sorte (Gleichstand → Gruppenreihenfolge).
	var group := _food_group(bs)
	if not group.is_empty():
		var best_g := -1
		var best_n := 0
		for g in group:
			var n := int(bs.delivered.get(g, 0))
			if n > best_n:
				best_n = n
				best_g = g
		if best_g >= 0:
			bs.delivered[best_g] = int(bs.delivered[best_g]) - 1


## Knoten, zu dem der Arbeiter für diesen Produktionszyklus laufen muss.
func _resource_target(bs: BState) -> Vector2i:
	match String(bs.def.get("resource", "")):
		"tree": return _find_mature_tree(bs.bld.pos, RES_RADIUS)
		"stone": return _find_object(bs.bld.pos, MapData.MO_STONE, RES_RADIUS)
		"ore": return _find_deposit(bs.bld.pos, int(bs.def.get("mineral", -1)), ORE_RADIUS)
		"plant_tree": return _find_plant_spot(bs.bld.pos)
		"field": return _find_farm_target(bs.bld.pos)
		"water": return _find_water_edge(bs.bld.pos)
	return Vector2i(-1, -1)


## Aktion am Ziel: Baum/Stein/Erz abbauen bzw. Baum pflanzen.
func _do_resource_action(bs: BState) -> void:
	var n := bs.worker_target
	if n.x < 0:
		return
	match String(bs.def.get("resource", "")):
		"tree":
			if state.map.map_object(n.x, n.y) == MapData.MO_TREE \
					and state.map.tree_stage_at(n.x, n.y) == MapData.TREE_BIG:
				state.map.clear_map_object(n.x, n.y)
				_growing_trees.erase(state.map.idx(n.x, n.y))
				dirty = true
		"stone":
			if state.map.map_object(n.x, n.y) == MapData.MO_STONE:
				var hits := state.map.stone_hits_left_at(n.x, n.y) - 1
				if hits > 0:
					state.map.set_stone_hits_left(n.x, n.y, hits)
				else:
					var stage := state.map.stone_stage_at(n.x, n.y)
					if stage > MapData.STONE_SMALL:
						var new_stage := stage - 1
						state.map.set_stone_stage(n.x, n.y, new_stage)
						state.map.set_stone_hits_left(n.x, n.y, new_stage)
					else:
						state.map.clear_map_object(n.x, n.y)
				dirty = true
		"ore":
			# Unterirdisches Vorkommen abbauen (eine Einheit; bei 0 erschöpft).
			if state.map.take_ore_deposit(n.x, n.y):
				dirty = true
		"water":
			# Einen Fisch fangen (Issue #6); der Fischgrund erschöpft bei 0.
			if state.map.take_fish(n.x, n.y):
				dirty = true
		"plant_tree":
			if not state.has_object(n.x, n.y):
				# Förster pflanzt einen SETZLING, der über mehrere Stufen wächst.
				state.map.set_map_object(n.x, n.y, MapData.MO_TREE)
				state.map.set_tree_stage(n.x, n.y, MapData.TREE_SEED)
				state.map.set_tree_type(n.x, n.y, state.map.deterministic_tree_type(n.x, n.y))
				_growing_trees[state.map.idx(n.x, n.y)] = float(Tuning.tree_growth_ticks(MapData.TREE_SEED))
				dirty = true
		"field":
			# Bauer: reifes Feld ernten (→ Getreide) ODER frisches Feld säen (kein Ertrag).
			var fi := state.map.idx(n.x, n.y)
			if state.map.map_object(n.x, n.y) == MapData.MO_FIELD \
					and state.map.field_stage_at(n.x, n.y) == MapData.FIELD_RIPE:
				# RTTR: abgeerntetes Feld wird durch ein nicht-blockierendes Stoppelfeld
				# (noEnvObject) ersetzt, das nach kurzer Zeit verschwindet.
				state.map.clear_map_object(n.x, n.y)
				_growing_fields.erase(fi)
				state.map.set_field_decay(n.x, n.y, MapData.FIELD_DECAY_CUT)
				_decay_fields[fi] = float(Tuning.field_decay_ticks())
				dirty = true  # out_yield bleibt true → Getreide entsteht in WK_BACK
			elif _is_field_spot(n.x, n.y):
				# Auf einer alten Feld-Deko (Stoppel/verdorrt) darf neu gesät werden.
				state.map.clear_field_decay(n.x, n.y)
				_decay_fields.erase(fi)
				state.map.set_map_object(n.x, n.y, MapData.MO_FIELD)
				state.map.set_field_stage(n.x, n.y, MapData.FIELD_SEED)
				_growing_fields[fi] = float(Tuning.field_growth_ticks(MapData.FIELD_SEED))
				bs.out_yield = false  # Säen liefert kein Getreide
				dirty = true
			else:
				# Ziel zwischenzeitlich entwertet (anderer Hof war schneller) → kein Ertrag.
				bs.out_yield = false


## Fischgrund im Umkreis: ein Küstenknoten mit verbleibendem Fischbestand (Issue #6).
## Erschöpfte Gründe (fish == 0) werden übersprungen → der Fischer wandert weiter
## bzw. die Hütte wartet, wenn nichts mehr in Reichweite ist.
func _find_water_edge(center: Vector2i) -> Vector2i:
	for r in range(1, ORE_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.fish_at(x, y) > 0:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Schickt fertige Ausgangswaren ins nächstgelegene erreichbare Lager (#31). Mit
## nur einem Lager (HQ) ist das Ziel immer das HQ — identisch zum bisherigen Verhalten.
func _ship_outputs(bs: BState) -> void:
	if bs.out_stock.is_empty():
		return
	for output in bs.out_stock.keys():
		while int(bs.out_stock.get(output, 0)) > 0:
			var q: Array = flag_goods.get(bs.flag_idx, [])
			if q.size() >= FLAG_CAP:
				return
			var st := _nearest_storage(bs.flag_idx, 0, func(_s: Storage) -> bool: return true)
			if st == null:
				return
			var good := Good.new()
			good.type = int(output)
			good.dest = st.flag_idx
			_push_good(bs.flag_idx, good)
			bs.out_stock[output] = int(bs.out_stock[output]) - 1


# --- Ressourcensuche ---

func _find_object(center: Vector2i, motype: int, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.map_object(x, y) == motype:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_mature_tree(center: Vector2i, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.map_object(x, y) == MapData.MO_TREE \
						and state.map.tree_stage_at(x, y) == MapData.TREE_BIG:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Unterirdisches Erz-Vorkommen der passenden Sorte im Umkreis suchen
## (mineral < 0 = beliebiges Erz). Liefert den nächstgelegenen Fundknoten.
func _find_deposit(center: Vector2i, mineral: int, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.ore_deposit_amount_at(x, y) <= 0:
					continue
				if mineral < 0 or state.map.ore_deposit_kind_at(x, y) == mineral:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_plant_spot(center: Vector2i) -> Vector2i:
	for r in range(1, RES_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.has_object(x, y) or state._occ(x, y) != WorldState.OBJ_NONE:
					continue
				if state.compute_bq(x, y) >= WorldState.BQ_FLAG \
						and _all_meadow(x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _all_meadow(x: int, y: int) -> bool:
	for t in state.map.terrains_around(x, y):
		if t != Terrain.MEADOW:
			return false
	return true


## Eignet sich der Knoten als neuer Ackerplatz? Original-getreu nach RTTR
## nofFarmer::GetNewFieldPointQuality: keine Straße auf dem Knoten, fruchtbares
## Wiesenterrain, Platz frei (Feld-Deko/Stoppel ist erlaubt — wird übersät) und
## KEIN Getreidefeld/Gebäude/Baustelle direkt daneben (Felder brauchen Lücken).
func _is_field_spot(x: int, y: int) -> bool:
	# Knoten frei: kein blockierendes Objekt, keine Flagge/Straße/Gebäude.
	# (Feld-Deko liegt NICHT in objects → has_object false → darf übersät werden.)
	if state.has_object(x, y) or state._occ(x, y) != WorldState.OBJ_NONE:
		return false
	if not _all_meadow(x, y):
		return false
	if state.map.max_slope(x, y) > FIELD_MAX_SLOPE:
		return false
	# Keine direkten Nachbar-Getreidefelder oder Gebäude/Baustellen.
	for dir in Grid.DIRS:
		var n := state.map.neighbor(x, y, dir)
		if n.x < 0:
			continue
		if state.map.map_object(n.x, n.y) == MapData.MO_FIELD:
			return false
		if state._occ(n.x, n.y) == WorldState.OBJ_BUILDING:
			return false
	return true


## Arbeitsziel des Bauern (RTTR nofFarmhand): im kleinen Umkreis (FARM_RADIUS=2)
## alle gültigen Plätze sammeln — Class1 = reife Felder (ernten), Class2 =
## Saatplätze (säen) — und aus der besten verfügbaren Klasse ZUFÄLLIG (seeded,
## deterministisch) wählen. Ernten geht vor Säen. (-1,-1) → der Hof wartet sichtbar.
func _find_farm_target(center: Vector2i) -> Vector2i:
	var ripe: Array[Vector2i] = []
	var sow: Array[Vector2i] = []
	for r in range(1, FARM_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.map_object(x, y) == MapData.MO_FIELD:
					if state.map.field_stage_at(x, y) == MapData.FIELD_RIPE:
						ripe.append(Vector2i(x, y))
				elif _is_field_spot(x, y):
					sow.append(Vector2i(x, y))
	if not ripe.is_empty():
		return ripe[_rng.randi() % ripe.size()]
	if not sow.is_empty():
		return sow[_rng.randi() % sow.size()]
	return Vector2i(-1, -1)


func _water_near(center: Vector2i) -> bool:
	for r in range(1, ORE_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				for t in state.map.terrains_around(x, y):
					if Terrain.is_water(t):
						return true
	return false


# --------------------------------------------------------------------------
#  Träger-Logik
# --------------------------------------------------------------------------

func _tick_carrier(c: Carrier) -> void:
	if not c.active:
		return  # Träger ist noch auf dem Weg vom HQ
	var segs := float(c.road.length())
	var mid := segs * 0.5

	# Zum Ziel laufen.
	if absf(c.seg_pos - c.target) > 0.0001:
		if c.seg_pos < c.target:
			c.seg_pos = minf(c.seg_pos + CARRIER_SPEED, c.target)
		else:
			c.seg_pos = maxf(c.seg_pos - CARRIER_SPEED, c.target)
		if absf(c.seg_pos - c.target) > 0.0001:
			return  # noch unterwegs

	# Ziel erreicht → je nach Zustand handeln.
	var e0 := _end_flag(c.road, 0)
	var e1 := _end_flag(c.road, 1)
	match c.state:
		C_IDLE:
			# Wartet in der Mitte; sucht eine Ware an beiden Flaggen.
			if _peek_good_for(e0, e1) != null:
				c.pickup_end = 0
				c.target = 0.0
				c.state = C_TO_PICKUP
			elif _peek_good_for(e1, e0) != null:
				c.pickup_end = 1
				c.target = segs
				c.state = C_TO_PICKUP
			else:
				c.target = mid
		C_TO_PICKUP:
			var here := _end_flag(c.road, c.pickup_end)
			var other := _end_flag(c.road, 1 - c.pickup_end)
			var g = _take_good_for(here, other)
			if g != null:
				c.carrying = g
				c.state = C_CARRYING
				c.target = segs if c.pickup_end == 0 else 0.0
			else:
				c.state = C_IDLE
				c.target = mid
		C_CARRYING:
			var deliver_end := 1 if c.pickup_end == 0 else 0
			_deliver(c.carrying, _end_flag(c.road, deliver_end))
			_mark_road_delivery(c.road)
			c.carrying = null
			# Rückweg nutzen: gibt es hier eine Ware zur Gegenseite, gleich mitnehmen.
			var here := _end_flag(c.road, deliver_end)
			var other := _end_flag(c.road, 1 - deliver_end)
			var g2 = _take_good_for(here, other)
			if g2 != null:
				c.carrying = g2
				c.pickup_end = deliver_end
				c.target = 0.0 if deliver_end == 1 else segs
			else:
				c.state = C_RETURN
				c.target = mid
		C_RETURN:
			c.state = C_IDLE
			c.target = mid


func _mark_road_delivery(road: WorldState.Road) -> void:
	road.traffic += 1
	if road.level < WorldState.ROAD_COBBLE and road.traffic >= Tuning.road_upgrade_deliveries():
		road.level = WorldState.ROAD_COBBLE
		dirty = true


# --------------------------------------------------------------------------
#  Waren / Wegewahl
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
#  Verirrte Träger (Stray): Straße weg, Ware bleibt erhalten
# --------------------------------------------------------------------------

const STRAY_WANDER_SPEED := 1.1   # Weltpixel/Tick beim Umherirren
const STRAY_SEEK_SPEED := 1.9     # schneller, sobald gezielt zur Flagge gelaufen wird
const STRAY_WANDER_MIN := 300     # 10 s @30Hz unkontrolliert wandern
const STRAY_WANDER_RANGE := 150   # + bis zu 5 s (zufällig)
const STRAY_GIVEUP := 1800        # 60 s Notfallgrenze (dann Ware zurück ins HQ)
const STRAY_FLAG_SNAP := 24.0     # px: so nah an einer Flagge gilt sie als erreicht


## Aus einem Träger mit Ware einen verirrten Träger machen (Straße verschwand).
## Liegt eine erreichbare Flagge gleich nebenan (Flagge-auf-Straße/Teilung), läuft
## er direkt dorthin (kein Umherirren). Ist das Netz zerschnitten (Abriss), irrt er
## erst ein paar Sekunden unkontrolliert, bevor er gezielt eine Flagge ansteuert.
func _spawn_stray(c: Carrier) -> void:
	var g: Good = c.carrying
	c.carrying = null
	if g == null:
		return
	var s := Stray.new()
	s.good = g
	s.pos = carrier_world(c)
	s.heading = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	s.facing = s.heading
	s.change_dir_in = 12 + _rng.randi() % 24
	s.give_up = STRAY_GIVEUP
	# Gibt es einen Weg zum Ziel über eine nahe Flagge VORWÄRTS? → direkt hinlaufen.
	# Nur wenn das Netz Richtung Ziel zerschnitten ist → erst umherirren.
	var tf := _best_handoff_flag(s.pos, g.dest)
	if tf >= 0:
		s.target_flag = tf
	else:
		s.wander_ticks = STRAY_WANDER_MIN + _rng.randi() % STRAY_WANDER_RANGE
	strays.append(s)


func _tick_strays() -> void:
	if strays.is_empty():
		return
	var done: Array[Stray] = []
	for s in strays:
		if _tick_stray(s):
			done.append(s)
	for s in done:
		strays.erase(s)


## Liefert true, wenn der Stray fertig ist (Ware abgelegt) und entfernt werden soll.
func _tick_stray(s: Stray) -> bool:
	if s.good == null:
		return true
	s.give_up -= 1
	if s.give_up <= 0:
		_dump_good_to_hq(s.good)   # Notfall: Ware sicher zurück ins Lager (kein Verlust)
		s.good = null
		return true

	# Phase 2: gezielt eine gewählte Flagge anlaufen.
	if s.target_flag >= 0:
		var fp := _flag_world(s.target_flag)
		var to := fp - s.pos
		s.facing = to
		if to.length() <= STRAY_SEEK_SPEED:
			s.pos = fp
			if _deposit_stray(s, s.target_flag):
				return true
			s.target_flag = -1    # Flagge weg/voll/nicht routbar → erneut orientieren
			s.wander_ticks = 60
			return false
		s.pos += to.normalized() * STRAY_SEEK_SPEED
		return false

	# Phase 1: unkontrolliert umherirren.
	s.wander_ticks -= 1
	s.change_dir_in -= 1
	if s.change_dir_in <= 0:
		s.heading = s.heading.rotated(_rng.randf_range(-PI * 0.6, PI * 0.6))
		s.change_dir_in = 12 + _rng.randi() % 24
	var np := s.pos + s.heading * STRAY_WANDER_SPEED
	var node := Grid.world_to_node_approx(np)
	if state.map.in_bounds(node.x, node.y) and state.node_walkable(node.x, node.y):
		s.pos = np
		s.facing = s.heading
	else:
		s.heading = -s.heading    # am Rand/Wasser abprallen

	# Stolpert er während des Irrens nah an eine erreichbare Flagge → dort ablegen.
	# Nur physisch nahe Flaggen prüfen (billige Distanz zuerst, Pfadsuche nur dann).
	for fi in state.flags:
		if s.pos.distance_to(_flag_world(fi)) > STRAY_FLAG_SNAP:
			continue
		if _deposit_stray(s, fi):
			return true

	# Wanderzeit abgelaufen → gezielt die beste Flagge Richtung Ziel ansteuern.
	if s.wander_ticks <= 0:
		var tf := _best_handoff_flag(s.pos, s.good.dest)
		if tf >= 0:
			s.target_flag = tf
		else:
			s.wander_ticks = 60   # noch keine erreichbare Flagge → weiter irren
	return false


func _flag_world(fi: int) -> Vector2:
	return state.map.node_world(fi % state.map.width, fi / state.map.width)


## Netz-Distanz (Anzahl Flaggen-Hops) von Flagge [param from_idx] zum Ziel, oder -1
## wenn nicht verbunden. from == dest → 0.
func _route_len(from_idx: int, dest_idx: int) -> int:
	if from_idx == dest_idx:
		return 0
	var fp := Vector2i(from_idx % state.map.width, from_idx / state.map.width)
	var dp := Vector2i(dest_idx % state.map.width, dest_idx / state.map.width)
	var r := state.find_route(fp, dp)
	if r.size() < 2:
		return -1
	return r.size() - 1


## Beste Übergabe-Flagge für eine herumgetragene Ware: die Ware soll VORWÄRTS Richtung
## Ziel weitergegeben werden, nicht zur bloß nächstgelegenen (oft rückwärts gelegenen)
## Flagge. Sucht in wachsenden Radien um [param pos]; innerhalb des kleinsten Radius
## mit erreichbarer Flagge die mit der kürzesten Rest-Route zum Ziel (Gleichstand:
## kürzerer Hinweg). -1 wenn das Ziel von keiner Flagge aus erreichbar ist.
func _best_handoff_flag(pos: Vector2, dest: int) -> int:
	for radius_tiles in [3.0, 6.0, 12.0, 1e9]:
		var max_d: float = float(radius_tiles) * Grid.TILE_W
		var best := -1
		var best_route := 1 << 30
		var best_walk := INF
		for fi in state.flags:
			var walk := pos.distance_to(_flag_world(fi))
			if walk > max_d:
				continue
			var rlen := _route_len(fi, dest)
			if rlen < 0:
				continue
			if rlen < best_route or (rlen == best_route and walk < best_walk):
				best_route = rlen
				best_walk = walk
				best = fi
		if best >= 0:
			return best
	return -1


## Ware des Strays an einer Flagge abgeben. Ist es die Ziel-Flagge, wird die Ware
## direkt ins Gebäude eingebucht (konsumiert); sonst auf die Flagge gelegt, damit ein
## Träger sie weiterträgt. false, wenn die Flagge weg/voll/das Ziel unerreichbar ist.
func _deposit_stray(s: Stray, fi: int) -> bool:
	if not state.flags.has(fi):
		return false
	if fi != s.good.dest:
		if _next_hop(fi, s.good.dest) < 0:
			return false
		if goods_on_flag(fi) >= FLAG_CAP:
			return false
	_deliver(s.good, fi)   # Ziel-Flagge → konsumieren, sonst weiterreichen
	s.good = null
	return true


## Notfall-Ablage: Ware zurück ins HQ-Lager, Ziel-Anforderung zurücksetzen.
func _dump_good_to_hq(g: Good) -> void:
	if g == null:
		return
	if flag_to_building.has(g.dest):
		var bs: BState = bstates.get(flag_to_building[g.dest])
		if bs != null:
			bs.incoming[g.type] = maxi(0, bs.incoming.get(g.type, 0) - 1)
	if hq_flag >= 0:
		hq_stock[g.type] = hq_stock.get(g.type, 0) + 1


## Eine Ware von einer verschwundenen Flagge neu einsortieren: bevorzugt auf eine
## Flagge Richtung Ziel weitergeben (bleibt „unterwegs", incoming unverändert), sonst
## zurück ins HQ-Lager (incoming dort sauber heruntergezählt → wird neu angefordert).
func _rehome_good(g: Good, pos: Vector2) -> void:
	if g == null:
		return
	var fi := _best_handoff_flag(pos, g.dest)
	if fi >= 0 and (fi == g.dest or goods_on_flag(fi) < FLAG_CAP):
		_deliver(g, fi)   # Ziel-Flagge → konsumieren, sonst auf die Flagge legen
	else:
		_dump_good_to_hq(g)


func _deliver(g: Good, flag_idx: int) -> void:
	if flag_idx == g.dest:
		_consume_delivery(g, flag_idx)
	else:
		_push_good(flag_idx, g)


func _consume_delivery(g: Good, flag_idx: int) -> void:
	if flag_idx == hq_flag:
		# Liegt an der HQ-Flagge; der Tür-Träger trägt sie ins Lager hinein.
		_push_good(hq_flag, g)
		return
	if flag_to_building.has(flag_idx):
		var bs: BState = bstates.get(flag_to_building[flag_idx])
		if bs != null:
			bs.delivered[g.type] = bs.delivered.get(g.type, 0) + 1
			bs.incoming[g.type] = maxi(0, bs.incoming.get(g.type, 0) - 1)
			return
	if hq_flag >= 0:
		hq_stock[g.type] = hq_stock.get(g.type, 0) + 1


func _push_good(flag_idx: int, g: Good) -> void:
	flag_goods.get_or_add(flag_idx, []).append(g)


# --------------------------------------------------------------------------
#  HQ-Tür-Träger (Hausträger): trägt Waren zwischen Tür und Flagge des HQ
# --------------------------------------------------------------------------

const HOUSE_SPEED := 0.045


## Tür↔Flagge-Träger jedes Lagers (#31). Jedes Lager (HQ = #0, plus baubare
## Lagerhäuser) hat seinen eigenen Träger, der seine Ausgangswaren (outbox) zur
## Flagge bringt und dort ankommende Eingänge (dest == eigene Flagge) ins Lager holt.
func _tick_house_carrier() -> void:
	for st in storages:
		if st.house == null or st.flag_idx < 0:
			continue
		_tick_one_house_carrier(st)


func _tick_one_house_carrier(st: Storage) -> void:
	var fi := st.flag_idx
	var h := st.house
	match h.state:
		H_IDLE:  # an der Tür
			if not st.outbox.is_empty() and goods_on_flag(fi) < FLAG_CAP:
				h.carrying = st.outbox.pop_front()
				h.state = H_OUT
			elif _has_incoming_at(fi):
				h.state = H_FETCH
		H_OUT:   # Ware Tür → Flagge
			h.t = minf(h.t + HOUSE_SPEED, 1.0)
			if h.t >= 1.0:
				_push_good(fi, h.carrying)
				h.carrying = null
				var g = _take_incoming_at(fi)
				h.carrying = g
				h.state = H_IN if g != null else H_RETURN
		H_FETCH: # leer Tür → Flagge, um Eingang zu holen
			h.t = minf(h.t + HOUSE_SPEED, 1.0)
			if h.t >= 1.0:
				var g = _take_incoming_at(fi)
				h.carrying = g
				h.state = H_IN if g != null else H_RETURN
		H_IN:    # Ware Flagge → Tür (ins Lager)
			h.t = maxf(h.t - HOUSE_SPEED, 0.0)
			if h.t <= 0.0:
				if h.carrying != null:
					st.stock[h.carrying.type] = st.stock.get(h.carrying.type, 0) + 1
				h.carrying = null
				h.state = H_IDLE
		H_RETURN: # leer Flagge → Tür
			h.t = maxf(h.t - HOUSE_SPEED, 0.0)
			if h.t <= 0.0:
				h.state = H_IDLE


## Erste an Flagge [flag_idx] wartende Ware, die in genau dieses Lager soll
## (dest == eigene Flagge).
func _has_incoming_at(flag_idx: int) -> bool:
	for g in flag_goods.get(flag_idx, []):
		if g.dest == flag_idx:
			return true
	return false


func _take_incoming_at(flag_idx: int):
	var q: Array = flag_goods.get(flag_idx, [])
	for k in q.size():
		if q[k].dest == flag_idx:
			var g = q[k]
			q.remove_at(k)
			return g
	return null


## Gebäudeknoten des HQ (für das Zeichnen des Tür-Trägers).
func hq_building_pos() -> Vector2i:
	if hq_idx < 0 or not state.buildings.has(hq_idx):
		return Vector2i(-1, -1)
	return state.buildings[hq_idx].pos


func hq_flag_node() -> Vector2i:
	return Vector2i(hq_flag % state.map.width, hq_flag / state.map.width) if hq_flag >= 0 else Vector2i(-1, -1)


func _take_good_for(flag_idx: int, target_flag_idx: int):
	var queue: Array = flag_goods.get(flag_idx, [])
	for k in queue.size():
		var g: Good = queue[k]
		if _next_hop(flag_idx, g.dest) == target_flag_idx:
			queue.remove_at(k)
			return g
	return null


func _peek_good_for(flag_idx: int, target_flag_idx: int):
	var queue: Array = flag_goods.get(flag_idx, [])
	for g in queue:
		if _next_hop(flag_idx, g.dest) == target_flag_idx:
			return g
	return null


func _next_hop(from_idx: int, dest_idx: int) -> int:
	if from_idx == dest_idx:
		return dest_idx
	var from_pos := Vector2i(from_idx % state.map.width, from_idx / state.map.width)
	var dest_pos := Vector2i(dest_idx % state.map.width, dest_idx / state.map.width)
	var route := state.find_route(from_pos, dest_pos)
	if route.size() < 2:
		return -1
	return state.map.idx(route[1].x, route[1].y)


func _end_flag(r: WorldState.Road, end: int) -> int:
	var p := r.a if end == 0 else r.b
	return state.map.idx(p.x, p.y)


# --------------------------------------------------------------------------
#  Für das Rendering
# --------------------------------------------------------------------------

func carrier_world(c: Carrier) -> Vector2:
	var nodes := c.road.nodes
	var seg: int = clampi(int(floor(c.seg_pos)), 0, nodes.size() - 2)
	var frac: float = clampf(c.seg_pos - seg, 0.0, 1.0)
	var p0 := state.map.node_world(nodes[seg].x, nodes[seg].y)
	var p1 := state.map.node_world(nodes[seg + 1].x, nodes[seg + 1].y)
	return p0.lerp(p1, frac)


func carrier_facing(c: Carrier) -> Vector2:
	if not c.active:
		return Vector2.ZERO
	var d := signf(c.target - c.seg_pos)
	if d == 0.0:
		return Vector2.ZERO
	var nodes := c.road.nodes
	var seg: int = clampi(int(floor(c.seg_pos)), 0, nodes.size() - 2)
	var v := state.map.node_world(nodes[seg + 1].x, nodes[seg + 1].y) \
		- state.map.node_world(nodes[seg].x, nodes[seg].y)
	return v * d


func goods_on_flag(flag_idx: int) -> int:
	return (flag_goods.get(flag_idx, []) as Array).size()


## Menschenlesbarer Status eines Gebäudes (fürs Info-Panel).
func building_status(bld: WorldState.Building) -> String:
	var name := String(BuildingCatalog.get_def(bld.def_id).get("name", "?"))
	if bld.is_hq:
		return "%s — Lager & Soldaten-Reserve: %d" % [name, soldiers]
	var bs: BState = bstates.get(state.map.idx(bld.pos.x, bld.pos.y))
	if bs == null:
		return name
	var s := name
	if bs.is_construction:
		var pct := int(100.0 * bs.construct_progress / float(BUILD_TIME))
		var mats := ""
		for g in bs.def.get("cost", {}):
			mats += "  %s %d/%d" % [Goods.name_of(g), bs.delivered.get(g, 0), int(bs.def.cost[g])]
		return "%s — Baustelle %d%%%s" % [s, pct, mats]
	# Aktiv
	if not bs.staffed:
		return "%s — Arbeiter kommt vom HQ ..." % s
	if bs.stopped:
		return "%s — GESTOPPT (Taste P)" % s
	s += "  [%s]" % ("arbeitet" if bs.producing else "wartet")
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		s += "  %s %d/%d" % [Goods.name_of(g), bs.delivered.get(g, 0), int(inputs[g]) * 2]
	if not _food_group(bs).is_empty():
		s += "  Nahrung %d/%d" % [mini(_food_available(bs), FOOD_BUFFER), FOOD_BUFFER]
	if _is_producer(bs):
		s += "  → Ausgang %d" % _out_total(bs)
	if int(bs.def.get("influence", 0)) > 0:
		s += "  Garnison %d/%d  Rang +%d" % [bld.garrison, bld.capacity, bld.promotions]
	return s


## Strukturierte Daten fürs Gebäudefenster (read-only, UI rendert Icons daraus).
## Liefert:
##   status: String           — kurze Statuszeile
##   warning: String          — Warnzustand ("" wenn keiner)
##   productivity: int        — Auslastung in % (-1 = nicht zutreffend)
##   construction: bool       — Baustelle?
##   inputs: Array[Dictionary]— je {good, have, want}; bei Baustellen die Baustoffe
##   output: Dictionary       — {good, stock, cap} oder {} ohne Ausgang
func building_info(bld: WorldState.Building) -> Dictionary:
	var info := {
		status = building_status(bld), warning = "", productivity = -1,
		construction = false, inputs = [], output = {},
	}
	var bs: BState = bstates.get(state.map.idx(bld.pos.x, bld.pos.y))
	if bs == null or bld.owner != 0:
		return info
	if bs.is_construction:
		info.construction = true
		info.status = "Baustelle %d%%" % int(100.0 * bs.construct_progress / float(BUILD_TIME))
		var cost: Dictionary = bs.def.get("cost", {})
		for g in cost:
			info.inputs.append({good = g,
				have = mini(bs.delivered.get(g, 0), int(cost[g])), want = int(cost[g])})
		if not bs.staffed:
			info.warning = "Bauarbeiter kommt vom HQ ..."
		return info
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		var want := int(inputs[g]) * 2  # Sollbestand = doppelter Rezeptbedarf (Puffer)
		info.inputs.append({good = g, have = mini(bs.delivered.get(g, 0), want), want = want})
	# Nahrungsgruppe als EINE Zeile (Icon = best-bevorratete Sorte, sonst erste).
	var fgroup := _food_group(bs)
	if not fgroup.is_empty():
		var total := 0
		var rep := int(fgroup[0])
		var best := -1
		for g in fgroup:
			var n := int(bs.delivered.get(g, 0))
			total += n
			if n > best:
				best = n
				rep = int(g)
		info.inputs.append({good = rep, have = mini(total, FOOD_BUFFER), want = FOOD_BUFFER})
	var prod := _is_producer(bs)
	if prod:
		var total := _out_total(bs)
		var primary := int(bs.def.get("output", -1))
		if primary == -1:
			var outs = bs.def.get("outputs", [])
			primary = int(outs[0]) if (outs is Array and not (outs as Array).is_empty()) else -1
		if primary != -1:
			info.output = {good = primary, stock = mini(total, OUT_CAP), cap = OUT_CAP}
		# Aufschlüsselung je Sorte für Mehrfach-Ausgänge (Werkzeugmacher/Schmiede).
		var per: Array = []
		for gg in bs.out_stock:
			per.append({good = int(gg), stock = int(bs.out_stock[gg])})
		info.outputs = per
	var is_producer := prod or String(bs.def.get("resource", "")) == "plant_tree"
	if is_producer and bs.staffed:
		info.productivity = 100 * bs.prod_active / maxi(bs.prod_total, 1)
	# Kurzstatus statt der langen Textzeile: Waren stehen als Icons im Fenster,
	# Garnison ergänzt das UI selbst — Doppelung vermeiden.
	if int(bs.def.get("influence", 0)) > 0:
		info.status = ""
	elif is_producer and bs.staffed:
		info.status = "Status: %s" % ("arbeitet" if bs.producing else "wartet")
	if not bs.staffed:
		info.warning = "Arbeiter kommt vom HQ ..."
	elif bs.stopped:
		info.warning = "Produktion gestoppt (Taste P)"
	elif is_producer and bs.wphase == WK_IDLE:
		match bs.idle_reason:
			IDLE_OUT_FULL: info.warning = "Ausgang voll — Abtransport stockt"
			IDLE_NO_INPUTS: info.warning = "Wartet auf Waren"
			IDLE_NO_RESOURCE:
				info.warning = "Keine Fische in Reichweite" \
					if String(bs.def.get("resource", "")) == "water" \
					else "Kein Rohstoff in Reichweite"
			IDLE_NO_OUTPUT: info.warning = "Kein Werkzeug ausgewählt (alle Prioritäten 0)"
	return info


## Hat dieses Gebäude gerade einen sichtbaren, herumlaufenden Arbeiter?
func has_worker(bs: BState) -> bool:
	return bs.producing and bs.worker_target.x >= 0 \
		and (bs.wphase == WK_OUT or bs.wphase == WK_WORK or bs.wphase == WK_BACK)


## Weltposition des Arbeiters über die Arbeitsphasen.
func worker_world(bs: BState) -> Vector2:
	var b := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
	var t := state.map.node_world(bs.worker_target.x, bs.worker_target.y)
	var prog: float = clampf(1.0 - (bs.ph_t / maxf(bs.ph_total, 1.0)), 0.0, 1.0)
	match bs.wphase:
		WK_OUT:
			return b.lerp(t, prog)
		WK_WORK:
			return t
		WK_BACK:
			return t.lerp(b, prog)
	return b


func worker_facing(bs: BState) -> Vector2:
	var b := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
	var t := state.map.node_world(bs.worker_target.x, bs.worker_target.y)
	match bs.wphase:
		WK_OUT, WK_WORK:
			return t - b
		WK_BACK:
			return b - t
	return Vector2.ZERO
