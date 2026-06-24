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
const PROMO_TICKS := 200       # Münze → Beförderung (echte Rangstufe, #52)
# Soldaten-Ränge (#52/#28, RTTR: 5 Stufen 0..4). HP je Rang aus RTTR MilitaryConsts.
const SOLDIER_RANKS := 5
const RANK_MAX := 4
const RANK_HP: Array[int] = [3, 4, 5, 6, 7]
const RANK_NAMES: Array[String] = ["Gefreiter", "Obergefreiter", "Feldwebel", "Offizier", "General"]
# RTTR MILITARY_SETTINGS_SCALE (Nenner je Regler, #52): Verteidiger/Angriff 0..5,
# Besatzung nach Grenznähe 0..8. (Rekrutierung 0..10 = recruiting_ratio, #41.)
const MIL_SCALE_DEFENSE := 5
const MIL_SCALE_ATTACK := 5
const MIL_SCALE_OCCUPY := 8
# Grenzdistanz-Zonen (#52, RTTR MAX_MILITARY_DISTANCE_NEAR/MIDDLE in Knoten zum nächsten
# feindlichen Militärgebäude): <= NEAR = Grenze, <= MIDDLE = Mitte, sonst Inneres.
const MIL_DIST_NEAR := 18
const MIL_DIST_MIDDLE := 26
const CATAPULT_TICKS := 260    # Katapult-Schussintervall
const CATAPULT_RANGE := 6      # zusätzliche Reichweite des Katapults (Hex)
# See-Transport (#46): Schiffe gleichen Hafenbestände derselben Meeres-Komponente aus
# (Waren-Pendeln). SEA_INTERVAL = Ticks zwischen Fähren-Zuweisungen; SEA_BALANCE_MARGIN =
# ab dieser Bestandsdifferenz lohnt eine Fahrt; SHIP_CAPACITY = Laderaum; SHIP_SPEED =
# Weltpixel pro Tick.
const SEA_INTERVAL := 90
const SEA_BALANCE_MARGIN := 2
const SHIP_CAPACITY := 6
const SHIP_SPEED := 1.8
const SHIP_BUILD_CYCLES := 12  # S2/10th: 12 Planken-/Arbeitszyklen bis ein Schiff fertig ist
const SHIP_VISION := 4         # Hex-Sichtradius eines Schiffs (Fog-Aufdeckung, #46/#21)
# Expedition (#46): Materialien, die ein Hafen für die Gründung eines neuen Hafens
# mitschickt (entspricht den Hafen-Baukosten).
const EXPEDITION_BOARDS := 4
const EXPEDITION_STONES := 6


class Good:
	extends RefCounted
	var type: int
	var dest: int   # Flaggen-Index (Zielflagge)


# Träger-Zustände (C_TO_FETCH: leer zur Gebäudeflagge, um einen Ausgang aus dem Haus
# zu holen — Option output_via_carrier, #66).
enum { C_IDLE, C_TO_PICKUP, C_CARRYING, C_RETURN, C_TO_FETCH }

# Tür-Exkursion eines Straßenträgers (#66): an einer Gebäudeflagge verlängert er
# seinen Weg bis in die Tür — trägt die Eingangsware hinein (statt Teleport an der
# Flagge) bzw. holt einen fertigen Ausgang heraus. D_NONE = normaler Straßendienst.
enum { D_NONE, D_IN, D_OUT }


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
	var has_boat := false    # Wasserstraßen-Träger: hält ein verbrauchtes BOOT aus dem Lager
	# Tür-Exkursion (#66): trägt die Ware von der Gebäudeflagge bis in die Tür.
	var dphase := 0          # D_* (D_NONE = kein Tür-Gang)
	var dt := 0.0            # 0 = an der Flagge, 1 = an der Tür
	var dbidx := -1          # Gebäude-Index, der gerade bedient wird
	var dstorage := -1       # #67: Lager-Flagge, aus der gerade geholt wird (-1 = Gebäude)
	var dflag := -1          # Gebäudeflagge (Endknoten, an dem der Träger steht)


class Marcher:
	extends RefCounted
	var route: Array[Vector2i] = []   # Flaggenfolge HQ → Zielgebäude
	var rank := 0                     # Rang des marschierenden Soldaten (#52)
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


# Schiff-Zustände (#46): am Heimathafen angedockt oder auf Fahrt zum Ziel-Hafen.
enum { SHIP_IDLE, SHIP_SAILING }


## Schiff (#46): trägt Waren über See zwischen Häfen DERSELBEN Meeres-Komponente.
## Liegt im IDLE am Heimathafen, bekommt eine Fracht + Ziel-Hafen zugewiesen, segelt den
## See-Pfad ab und bucht die Fracht am Ziel ins Hafenlager ein (Waren-Pendeln). Ein Schiff
## ohne Heimathafen (frisch von der Werft) segelt zuerst leer zum nächsten Hafen.
class Ship:
	extends RefCounted
	var owner := 0
	var pos := Vector2.ZERO              # Weltposition (Rendering/Bewegung)
	var node := Vector2i(-1, -1)         # aktueller Wasserknoten
	var state := 0                       # SHIP_*
	var home := -1                       # Heimathafen (Storage-Flaggen-Index), dort angedockt
	var dest := -1                       # Ziel-Hafen (Storage-Flaggen-Index) der aktuellen Fahrt
	var path: Array[Vector2i] = []       # See-Pfad (Wasserknoten) zum Andockknoten des Ziels
	var path_i := 0
	var cargo: Array = []                # Array[Good] — geladene Waren
	var facing := Vector2.RIGHT
	var expedition := false              # #46: unterwegs, um einen neuen Hafen zu gründen
	var target_point := Vector2i(-1, -1) # Ziel-Hafenpunkt der Expedition
	var raid := false                    # #46: Seeangriff — Soldaten an Bord, greift einen Hafen an
	var raid_soldiers := 0               # mitgeführte Soldaten
	var attack_building := -1            # Ziel-Gebäudeindex (feindlicher Hafen) des Seeangriffs


# Tür↔Flagge-Träger (nur HQ/Lager): bewegt Waren zwischen Gebäudetür und Flagge.
enum { H_IDLE, H_OUT, H_FETCH, H_IN, H_RETURN }

# Arbeiter-Phasen eines Ressourcen-Gebäudes (konstante Laufgeschwindigkeit):
# leer wartend → Hinweg → Aktion am Ziel → Rückweg → Pause am Gebäude.
# WK_DROP_OUT/WK_DROP_BACK (#66): der Arbeiter trägt eine fertige Ware aus der Tür zur
# Flagge und kommt leer zurück (Default-Ausgang, statt Teleport an die Flagge).
enum { WK_IDLE, WK_OUT, WK_WORK, WK_BACK, WK_WAIT, WK_DROP_OUT, WK_DROP_BACK }

# Warum ein Produktionsgebäude gerade NICHT arbeitet (fürs Gebäudefenster).
enum { IDLE_OK, IDLE_OUT_FULL, IDLE_NO_INPUTS, IDLE_NO_RESOURCE, IDLE_NO_OUTPUT }

# Planierer-Phasen an der Baustelle: erst zum naechsten Knoten laufen, dort
# arbeiten/schaufeln, dann weiter. Das bildet RTTR nofPlaner naeher ab als ein
# einzelner Gesamt-Timer.
enum { PLAN_PHASE_WALK, PLAN_PHASE_WORK }


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
	var bld: WorldState.Building = null # Gebäude-Referenz (Garnison-Rückgabe bei Abriss, #69)
	var owner := 0                    # Besitzer (aktuell nur Spieler 0 hat ein Lager)
	var stock: Dictionary = {}        # good -> Anzahl
	var people: Dictionary = {}       # job -> Anzahl (Träger + Spezialisten)
	var outbox: Array = []            # Waren, die der Tür-Träger noch zur Flagge bringt
	var house: HouseCarrier = null    # Tür↔Flagge-Träger dieses Lagers
	var incoming: Dictionary = {}     # #46: zum Lager bestelltes, noch unterwegs befindliches Material
	var expedition_prep := false      # #46: Hafen bereitet eine Expedition vor (ordert Material+Schiff)
	var raid_prep := false            # #46: Hafen bereitet einen Seeangriff vor


class BState:
	extends RefCounted
	var idx: int
	var bld: WorldState.Building
	var def: Dictionary
	var flag_idx: int
	var is_construction := false
	var planing := false     # Einebnungsphase vor dem Bau (Planierer #49)
	var plan_t := 0          # verbleibende Planier-Ticks, sobald der Planierer da ist
	var plan_total := 0      # Gesamt-Planier-Ticks (Laufen + Arbeit an den Knoten)
	var plan_points: Array[Vector2i] = [] # Knoten, an denen der Planierer arbeitet
	var plan_index := 0      # aktueller Eintrag in plan_points
	var plan_phase := 0      # PLAN_PHASE_*: laeuft oder arbeitet
	var plan_step_t := 0     # verbleibende Ticks im aktuellen Lauf-/Arbeitsabschnitt
	var plan_step_total := 1
	var plan_from := Vector2i(-1, -1)
	var plan_to := Vector2i(-1, -1)
	var plan_walk_ticks := 1
	var plan_work_ticks := 1
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
	var carry_good := -1                   # Ware, die der Arbeiter gerade zur Flagge trägt (#66)
	var reserved_idx := -1                 # reservierter Arbeitsplatz-Knoten (Baum/Feld/…), -1 = keiner
	var build_ships := false               # Werft-Modus (#46): Schiffe statt Boote bauen
	var ship_progress := 0                 # Schiff-Baufortschritt in Bootszyklen (Werft)


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
var soldiers := 0                    # ausgebildete Soldaten im HQ (Reserve, = Summe soldier_ranks)
var soldier_ranks: Array[int] = [0, 0, 0, 0, 0]  # Reserve je Rang (#52); Rekruten = Gefreiter (0)
# --- Spieler-Einstellungen (RTTR-Regler, nur Spieler 0; deterministisch) ---
var tool_priority: Dictionary = {}   # Werkzeug-Gut -> Gewicht 0..10 (Werkzeugmacher)
var tool_orders: Dictionary = {}     # Werkzeug-Gut -> noch offene Bestellmenge (Vorrang)
var distribution: Dictionary = {}    # Ware -> { def_id -> Gewicht 0..10 } (#43 Verteilung)
var transport_order: Array = []      # Waren nach Transport-Priorität (Index 0 = zuerst, #43)
var recruiting_ratio := 10           # Soldaten-Rekrutierungsrate 0..10 (RTTR MilSetting 0)
# Militär-Regler (#52, RTTR MilitarySettings). Skalen siehe MIL_SCALE_*; Defaults aus
# Tuning. Verteidigerstärke/Angriffsstärke 0..5, Besatzung nach Grenznähe 0..8.
var mil_defense := 3                  # Verteidigerstärke (RTTR Setting 1): Rangwahl Verteidiger
var mil_attack := 3                   # Angriffsstärke (Setting 3): wie viele Soldaten losziehen
var occupy_interior := 0             # Besatzung Landesinneres (Setting 4)
var occupy_center := 1               # Besatzung Landesmitte (Setting 5)
var occupy_border := 8              # Besatzung Grenzgebiet (Setting 7)
var mines_accept_beer := false       # Hausregel: Minen nehmen zusätzlich Bier als Nahrung
                                     # (Original: nur Fisch/Fleisch/Brot). Default aus.
var output_via_carrier := false      # #66: Ausgang per Straßenträger (Arbeiter füllt nur
                                     # die Haus-Ablage, der Träger holt sie). Default aus =
                                     # Arbeiter trägt die fertige Ware selbst zur Flagge.
var ai_enabled := true               # Gegner-KI aktiv? (zum Testen abschaltbar)
var ai: AIBase = null                # austauschbare Gegner-KI (Plugin)
var ai_by_owner: Dictionary = {}     # owner -> eigene KI-Instanz (mehrere Gegner)
var marchers: Array[Marcher] = []    # gerade marschierende Soldaten
var strays: Array[Stray] = []        # verirrte Träger (Straße weg, tragen noch Ware)
var ships: Array[Ship] = []          # See-Schiffe (#46): Waren-Pendeln zwischen Häfen
var _inc_soldiers: Dictionary = {}   # building idx -> unterwegs befindliche Soldaten
var dirty := false                   # Karte muss neu gezeichnet werden
var terrain_dirty := false           # Gelände-Höhen geändert (Planierer #49) → Terrain neu zeichnen
var terrain_dirty_rect := Rect2i()   # betroffener Knotenbereich (gezieltes Chunk-Redraw statt alle)

var _hq_inited := false
var _soldier_timer := SOLDIER_TICKS
var _promo_timer := PROMO_TICKS
var _cata_timer := CATAPULT_TICKS
var _helper_timer := 0               # Träger-Nachschub des HQ-Lagers (Issue #33)
var _sea_timer := 0                  # nächste Fähren-Zuweisung (#46)
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
	mil_defense = Tuning.mil_defense_default()
	mil_attack = Tuning.mil_attack_default()
	occupy_interior = Tuning.occupy_interior_default()
	occupy_center = Tuning.occupy_center_default()
	occupy_border = Tuning.occupy_border_default()
	distribution = Tuning.distribution_default()
	transport_order = Tuning.transport_order_default()


## --- Settings-API (von der UI genutzt; clampt auf gültige Bereiche) ---
func set_tool_priority(tool_good: int, weight: int) -> void:
	if Goods.is_tool_good(tool_good):
		tool_priority[tool_good] = clampi(weight, 0, 10)


func set_tool_order(tool_good: int, count: int) -> void:
	if Goods.is_tool_good(tool_good):
		tool_orders[tool_good] = maxi(count, 0)


func set_recruiting_ratio(ratio: int) -> void:
	recruiting_ratio = clampi(ratio, 0, 10)


## --- Militär-Regler (#52); clampen auf RTTR-Skalen. ---
func set_mil_defense(v: int) -> void:
	mil_defense = clampi(v, 0, MIL_SCALE_DEFENSE)


func set_mil_attack(v: int) -> void:
	mil_attack = clampi(v, 0, MIL_SCALE_ATTACK)


func set_occupy_interior(v: int) -> void:
	occupy_interior = clampi(v, 0, MIL_SCALE_OCCUPY)


func set_occupy_center(v: int) -> void:
	occupy_center = clampi(v, 0, MIL_SCALE_OCCUPY)


func set_occupy_border(v: int) -> void:
	occupy_border = clampi(v, 0, MIL_SCALE_OCCUPY)


## Setzt alle Militär-Regler auf die RTTR-Standardwerte zurück ("Standard"-Button).
func reset_military_settings() -> void:
	recruiting_ratio = Tuning.recruiting_ratio_default()
	mil_defense = Tuning.mil_defense_default()
	mil_attack = Tuning.mil_attack_default()
	occupy_interior = Tuning.occupy_interior_default()
	occupy_center = Tuning.occupy_center_default()
	occupy_border = Tuning.occupy_border_default()


func set_mines_accept_beer(on: bool) -> void:
	mines_accept_beer = on


## #66: Ausgangsweg umstellen. true = Arbeiter lagert die fertige Ware im Haus, der
## Straßenträger holt sie durch die Tür; false (Default) = Arbeiter trägt selbst zur
## Flagge. Laufende Trag-Gänge laufen nach dem Umschalten regulär aus.
func set_output_via_carrier(on: bool) -> void:
	output_via_carrier = on


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


## Transport-Rang einer Ware (#43): kleiner = wird bei Stau zuerst befördert.
## Nicht gelistete Waren landen hinten (niedrigste Priorität).
func _transport_rank(g: int) -> int:
	var r := transport_order.find(g)
	return r if r >= 0 else transport_order.size()


## Ware in der Transport-Priorität um [dir] verschieben (-1 = höher/früher,
## +1 = tiefer/später). Tauscht mit dem Nachbarn; clampt an den Rändern.
func move_transport(g: int, dir: int) -> void:
	var i := transport_order.find(g)
	if i < 0:
		return
	var j := i + (1 if dir > 0 else -1)
	if j < 0 or j >= transport_order.size():
		return
	var tmp = transport_order[i]
	transport_order[i] = transport_order[j]
	transport_order[j] = tmp


## Ware an die Spitze der Transport-Priorität setzen (#43, „ganz nach oben").
func move_transport_top(g: int) -> void:
	var i := transport_order.find(g)
	if i <= 0:
		return
	transport_order.remove_at(i)
	transport_order.insert(0, g)


## Transport-Priorität auf die Standardreihenfolge zurücksetzen (#43, „zurücksetzen").
func reset_transport_default() -> void:
	transport_order = Tuning.transport_order_default()


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
			if old.has_boat:
				_return_boat(old.road.owner)  # Wasserstraßen-Boot geht zurück ins Lager (#46)
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
			# Planierer-Phase (#49, RTTR nofPlaner): Haus-/Burg-Baustellen auf unebenem
			# Grund werden erst eingeebnet, bevor Material/Bauarbeiter kommen. Ebene
			# Plätze und Hütten/Minen überspringen das (direkt zum Bauarbeiter).
			if b.under_construction and b.owner == 0 and _needs_planing(b):
				_prepare_planing(bs)
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
		var gone := not state.buildings.has(i)
		if gone or state.buildings[i].is_hq:
			var bs_gone: BState = bstates[i]
			if bs_gone.has_person:
				_return_person(bs_gone.person_job, bs_gone.bld.owner)  # Arbeiter kehrt zurück (#9)
			# Garnison eines abgerissenen eigenen Militärgebäudes kehrt rangerhaltend in die
			# HQ-Reserve zurück (#69/#52). Nur echter Abriss (gone), nicht Eroberung
			# (Besitzerwechsel bleibt in state.buildings).
			if gone and bs_gone.bld != null and bs_gone.bld.owner == 0 and bs_gone.bld.garrison > 0:
				var rn := bs_gone.bld.ranks_normalized()
				for r in range(SOLDIER_RANKS):
					soldier_ranks[r] += rn[r]
				soldiers += bs_gone.bld.garrison
				bs_gone.bld.garrison = 0
				bs_gone.bld.ranks = [0, 0, 0, 0, 0]
			_release_target(bs_gone)  # reservierten Arbeitsplatz freigeben (#66)
			bstates.erase(i)

	# Verschwundene Lagerhäuser (#31): Lager, deren Gebäude weg ist, aus der Liste nehmen
	# (HQ = #0 bleibt immer). Restbestand UND noch nicht ausgelieferte outbox-Waren ins
	# HQ-Lager übernehmen, damit beim Abriss keine Ware verloren geht.
	for si in range(storages.size() - 1, 0, -1):
		var st := storages[si]
		var st_gone := st.idx < 0 or not state.buildings.has(st.idx)
		if st_gone or state.buildings[st.idx].is_hq or state.buildings[st.idx].under_construction:
			# Garnison eines abgerissenen eigenen Hafens (#46 militärisches Lager) kehrt
			# in die HQ-Reserve zurück (#69), analog zu Militärgebäuden mit bstate.
			if st_gone and st.bld != null and st.bld.owner == 0 and st.bld.garrison > 0:
				var hr := st.bld.ranks_normalized()
				for r in range(SOLDIER_RANKS):
					soldier_ranks[r] += hr[r]
				soldiers += st.bld.garrison
				st.bld.garrison = 0
				st.bld.ranks = [0, 0, 0, 0, 0]
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
	soldier_ranks = [soldiers, 0, 0, 0, 0]  # Startsoldaten sind Gefreite (#52)
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


## Save-Sicht des HQ-Bestands: eingesetzte Wasserstraßen-Boote mitzählen, damit sie
## beim Laden wieder aus dem Lager zum Fährträger geschickt werden können.
func total_hq_stock() -> Dictionary:
	var tot: Dictionary = hq_stock.duplicate()
	for r in carriers:
		var c: Carrier = carriers[r]
		if c.has_boat and c.road.owner == 0:
			tot[Goods.BOAT] = int(tot.get(Goods.BOAT, 0)) + 1
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
	if ai_enabled:
		if not ai_by_owner.is_empty():
			var owners := ai_by_owner.keys()
			owners.sort()
			for owner in owners:
				var inst: AIBase = ai_by_owner[owner]
				if inst != null:
					inst.think(self, int(owner))
		elif ai != null:
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
	_tick_harbor_prep()  # #46: Expeditions-/Seeangriffs-Vorbereitung an den Häfen
	_tick_ships()


func _capacity_for(size: int) -> int:
	match size:
		WorldState.BQ_CASTLE: return 6
		WorldState.BQ_HOUSE: return 4
	return 2


# --------------------------------------------------------------------------
#  Soldaten-Ränge (#52/#28) — Reserve und Garnison rangweise verwalten
# --------------------------------------------------------------------------

## Reserve-Rangverteilung an [soldiers] angleichen (Fehlbestand = Gefreite, Überhang von
## oben kappen). Nötig, weil soldiers an einigen Stellen direkt verändert wird.
func _reserve_normalize() -> void:
	var s := 0
	for r in soldier_ranks:
		s += r
	if s < soldiers:
		soldier_ranks[0] += soldiers - s
	elif s > soldiers:
		var over := s - soldiers
		var r := RANK_MAX
		while over > 0 and r >= 0:
			var take: int = mini(over, soldier_ranks[r])
			soldier_ranks[r] -= take
			over -= take
			r -= 1


## Einen Soldaten des Rangs [rank] in die HQ-Reserve legen.
func _reserve_add(rank: int) -> void:
	soldier_ranks[clampi(rank, 0, RANK_MAX)] += 1
	soldiers += 1


## Schwächsten Soldaten aus der Reserve nehmen (Gefreite zuerst); Rang zurückgeben oder -1.
func _reserve_take_weakest() -> int:
	if soldiers <= 0:
		return -1
	_reserve_normalize()
	for r in range(SOLDIER_RANKS):
		if soldier_ranks[r] > 0:
			soldier_ranks[r] -= 1
			soldiers -= 1
			return r
	return -1


## Einen Soldaten des Rangs [rank] in die Garnison von [b] aufnehmen.
func _garrison_add(b: WorldState.Building, rank: int) -> void:
	b.ranks = b.ranks_normalized()
	b.ranks[clampi(rank, 0, RANK_MAX)] += 1
	b.garrison += 1


## Schwächsten Garnisonssoldaten aus [b] entfernen und seinen Rang zurückgeben (oder -1).
func _garrison_take_weakest(b: WorldState.Building) -> int:
	if b.garrison <= 0:
		return -1
	b.ranks = b.ranks_normalized()
	for r in range(SOLDIER_RANKS):
		if b.ranks[r] > 0:
			b.ranks[r] -= 1
			b.garrison -= 1
			b.def_hp = 0  # Frontverteidiger neu wählen
			return r
	return -1


## Stärksten Garnisonssoldaten aus [b] entfernen und seinen Rang zurückgeben (oder -1).
func _garrison_take_strongest(b: WorldState.Building) -> int:
	if b.garrison <= 0:
		return -1
	b.ranks = b.ranks_normalized()
	for r in range(RANK_MAX, -1, -1):
		if b.ranks[r] > 0:
			b.ranks[r] -= 1
			b.garrison -= 1
			b.def_hp = 0
			return r
	return -1


## Ein Angreifer-Treffer auf [b]: der stärkste Verteidiger hält Rang+1 Treffer aus (echte
## Ränge ersetzen die alte Münz-„Rüstung", #52). Fällt er, sinkt die Garnison um eins.
func _damage_defender(b: WorldState.Building) -> void:
	if b.garrison <= 0:
		return
	b.ranks = b.ranks_normalized()
	if b.def_hp <= 0:
		var r := RANK_MAX
		while r >= 0 and b.ranks[r] <= 0:
			r -= 1
		if r < 0:
			return
		b.def_rank = r
		b.def_hp = r + 1   # Gefreiter 1 Treffer … General 5 Treffer
	b.def_hp -= 1
	if b.def_hp <= 0:
		b.ranks[b.def_rank] -= 1
		b.garrison -= 1


## Kompakte Rang-Aufschlüsselung einer Garnison für UI/Tooltip, z. B. "1×General, 2×Gefreiter".
func garrison_rank_text(b: WorldState.Building) -> String:
	var rn := b.ranks_normalized()
	var parts: Array[String] = []
	for r in range(RANK_MAX, -1, -1):
		if rn[r] > 0:
			parts.append("%d×%s" % [rn[r], RANK_NAMES[r]])
	return ", ".join(parts)


## Eine Münze befördert in [b] den stärksten noch nicht maximalen Soldaten um einen Rang
## (RTTR: Beförderung von oben). Liefert true, wenn jemand befördert wurde.
func _promote_one(b: WorldState.Building) -> bool:
	if b.garrison <= 0:
		return false
	b.ranks = b.ranks_normalized()
	for r in range(RANK_MAX - 1, -1, -1):
		if b.ranks[r] > 0:
			b.ranks[r] -= 1
			b.ranks[r + 1] += 1
			return true
	return false


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


## Schiffe für Save/Load (#46): Position, Fahrtzustand, Heimat-/Zielhafen (Flaggen-Index,
## stabil), See-Pfad und geladene Waren. Die Fracht wurde aus Lagern entnommen — ohne
## Sicherung ginge sie verloren. Muss NACH resync()/restore_extra_storages geladen werden.
func ships_state() -> Array:
	var out: Array = []
	for s in ships:
		var cargo_types: Array = []
		for g in s.cargo:
			cargo_types.append(g.type)
		out.append({
			owner = s.owner, node = s.node, pos = s.pos, state = s.state,
			home = s.home, dest = s.dest, path = s.path.duplicate(),
			path_i = s.path_i, cargo = cargo_types,
			expedition = s.expedition, target_point = s.target_point,
			raid = s.raid, raid_soldiers = s.raid_soldiers, attack_building = s.attack_building,
		})
	return out


func restore_ships(arr) -> void:
	ships.clear()
	if not (arr is Array):
		return
	for d in arr:
		var s := Ship.new()
		s.owner = int(d.get("owner", 0))
		s.node = d.get("node", Vector2i(-1, -1))
		s.pos = d.get("pos", Vector2.ZERO)
		s.state = int(d.get("state", SHIP_IDLE))
		s.home = int(d.get("home", -1))
		s.dest = int(d.get("dest", -1))
		var path = d.get("path", [])
		if path is Array:
			for p in path:
				s.path.append(p)
		s.path_i = int(d.get("path_i", 0))
		s.expedition = bool(d.get("expedition", false))
		s.target_point = d.get("target_point", Vector2i(-1, -1))
		s.raid = bool(d.get("raid", false))
		s.raid_soldiers = int(d.get("raid_soldiers", 0))
		s.attack_building = int(d.get("attack_building", -1))
		var cargo = d.get("cargo", [])
		if cargo is Array:
			for t in cargo:
				var g := Good.new()
				g.type = int(t)
				g.dest = s.dest
				s.cargo.append(g)
		ships.append(s)


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


## Münzen aus dem HQ befördern eigene Garnisonen rangweise (#52, RTTR Beförderung von oben).
func _tick_promotions() -> void:
	if hq_flag < 0:
		return
	_promo_timer -= 1
	if _promo_timer > 0:
		return
	_promo_timer = PROMO_TICKS
	# Münzen werden vorab vom Straßenträger ins Gebäude geliefert (#66). Eine Beförderung
	# verbraucht eine dort bereits angelieferte Münze (bs.delivered[COINS]).
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0 or b.is_hq or b.influence <= 0 or b.under_construction:
			continue
		if not b.wants_coins:
			continue  # Spieler hat Münzanforderung für dieses Gebäude abgeschaltet
		if b.garrison <= 0 or b.ranks_normalized()[RANK_MAX] >= b.garrison:
			continue  # leer oder schon alle auf Höchstrang → keine Beförderung nötig
		var bs: BState = bstates.get(i)
		if bs == null or int(bs.delivered.get(Goods.COINS, 0)) <= 0:
			continue
		if _promote_one(b):
			bs.delivered[Goods.COINS] = int(bs.delivered[Goods.COINS]) - 1
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
			_damage_defender(best)  # ein Katapultschuss = ein Treffer (#52)
			state.recompute_territory()
			dirty = true


## Grenzdistanz-Zone eines eigenen Militärgebäudes → zugehöriger Besatzungs-Regler
## (#52, RTTR FrontierDistance). Distanz = Hex-Abstand zum nächsten FEINDLICHEN
## Militärgebäude: <= NEAR Grenze, <= MIDDLE Mitte, sonst Inneres. Ohne Feindgebäude
## ist alles Inneres (wie S2: Hinterland dünn besetzen).
func _occupy_setting_for(b: WorldState.Building) -> int:
	var nearest := 1 << 30
	for j in state.buildings:
		var e: WorldState.Building = state.buildings[j]
		if e.owner == b.owner or e.under_construction:
			continue
		if int(BuildingCatalog.get_def(e.def_id).get("influence", 0)) <= 0:
			continue
		nearest = mini(nearest, WorldState.hex_distance(b.pos, e.pos))
	if nearest <= MIL_DIST_NEAR:
		return occupy_border
	if nearest <= MIL_DIST_MIDDLE:
		return occupy_center
	return occupy_interior


## Sollbesatzung eines eigenen Militärgebäudes (#52, RTTR CalcRequiredNumTroops):
## (Kapazität − 1) · Regler / Skala + 1. Immer ≥ 1 (ein Mann hält das Gebäude).
func _required_troops(b: WorldState.Building) -> int:
	var cap: int = b.capacity if b.capacity > 0 else _capacity_for(b.size)
	var setting := _occupy_setting_for(b)
	return (cap - 1) * setting / MIL_SCALE_OCCUPY + 1


## Überzählige Garnison (Besatzung höher als für die Grenz-Zone nötig) kehrt in die
## HQ-Reserve zurück (#52, RTTR RegulateTroops — vereinfacht als sofortige Rückbuchung;
## einquartierte Soldaten sind unsichtbar). Es bleibt immer mindestens 1 Soldat.
func _regulate_garrisons() -> void:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0 or b.is_hq or b.under_construction:
			continue
		if int(BuildingCatalog.get_def(b.def_id).get("influence", 0)) <= 0:
			continue
		if bstates.has(i) and bstates[i].is_construction:
			continue
		var excess := b.garrison - _required_troops(b)
		while excess > 0 and b.garrison > 1:
			# Überzählige rangerhaltend in die Reserve zurück. RTTR: bei hoher
			# Verteidigerstärke gehen die SCHWACHEN zuerst (Starke bleiben an der Front).
			var rank := _garrison_take_weakest(b) if mil_defense * 2 > MIL_SCALE_DEFENSE \
				else _garrison_take_strongest(b)
			if rank < 0:
				break
			_reserve_add(rank)
			excess -= 1
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
	_regulate_garrisons()
	if soldiers <= 0:
		return
	var w := state.map.width
	var hq_pos := Vector2i(hq_flag % w, hq_flag / w)
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0 or b.under_construction:
			continue
		# Militärgebäude UND Hafen (#46): Hafen ist ein Storage (kein bstate), wird hier aber
		# wie ein Militärgebäude vom HQ über Land besetzt, sofern road-verbunden.
		if int(BuildingCatalog.get_def(b.def_id).get("influence", 0)) <= 0:
			continue
		if bstates.has(i) and bstates[i].is_construction:
			continue
		var inc: int = _inc_soldiers.get(i, 0)
		if b.garrison + inc >= _required_troops(b):
			continue  # Sollbesatzung der Grenz-Zone erreicht (#52)
		var route := state.find_route(hq_pos, b.flag_pos)
		if route.size() < 2:
			continue
		# Soldaten losschicken (einer pro Tick) — den schwächsten Rekruten aus der Reserve;
		# Aufstieg erfolgt vor Ort per Münze (#52).
		var m := Marcher.new()
		m.route = route
		m.dest_building = i
		if not _load_leg(m):
			continue
		var send_rank := _reserve_take_weakest()
		if send_rank < 0:
			continue
		m.rank = send_rank
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
	_reserve_add(0)  # frischer Rekrut ist Gefreiter (Rang 0, #52)


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


## Anzahl Soldaten, die [src] für einen Angriff stellt (#52, RTTR GetNumSoldiersForAttack):
## (Garnison−1)·Angriffsstärke/Skala — einer bleibt immer als Besatzung zurück.
func attackers_available(src: WorldState.Building) -> int:
	if src.garrison <= 1:
		return 0
	return (src.garrison - 1) * mil_attack / MIL_SCALE_ATTACK


## Einen Angreifer-Trupp von [param src] gegen [param tgt] schicken. Es ziehen die
## STÄRKSTEN Soldaten los (Angriffsstärke-Regler bestimmt die Anzahl, #52); ein
## Verteidiger bleibt zurück.
func send_attackers(src: WorldState.Building, tgt: WorldState.Building) -> int:
	var n := attackers_available(src)
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
		_garrison_take_strongest(src)  # die Stärksten ziehen in den Angriff
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
	_damage_defender(tgt)  # stärkster Verteidiger hält Rang+1 Treffer aus (#52)
	if tgt.garrison <= 0:
		# Erobert → Besitzerwechsel; frischer Gefreiter besetzt das Gebäude.
		tgt.owner = m.attacker_owner
		tgt.garrison = 1
		tgt.ranks = [1, 0, 0, 0, 0]
		tgt.def_hp = 0
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
		_garrison_add(bstates[m.dest_building].bld, m.rank)
		state.recompute_territory()
		dirty = true
	elif state.buildings.has(m.dest_building):
		# Hafen (#46): Storage ohne bstate, aber militärisch — Garnison direkt am Gebäude.
		_garrison_add(state.buildings[m.dest_building], m.rank)
		state.recompute_territory()
		dirty = true
	else:
		# Ziel-Militärgebäude wurde abgerissen, während der Soldat marschierte (#69):
		# er kehrt rangerhaltend in die HQ-Reserve zurück statt zu verschwinden.
		_reserve_add(m.rank)
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
	_reserve_add(m.rank)  # Soldat kehrt rangerhaltend in die Reserve zurück
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
	# Militärisches Lager (Hafen, #46): Garnison-Kapazität setzen, damit _tick_soldiers es
	# wie ein Militärgebäude vom HQ besetzt. Reine Lagerhäuser (influence 0) bleiben unberührt.
	if int(BuildingCatalog.get_def(b.def_id).get("influence", 0)) > 0 and b.capacity <= 0:
		b.capacity = _capacity_for(b.size)
	var fidx := state.map.idx(b.flag_pos.x, b.flag_pos.y)
	for st in storages:
		if st.flag_idx == fidx:
			st.idx = idx
			st.bld = b
			st.owner = b.owner
			if st.house == null:
				st.house = HouseCarrier.new()
			return
	var ns := Storage.new()
	ns.flag_idx = fidx
	ns.idx = idx
	ns.bld = b
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


## Verbraucht ein Boot (#46) aus dem nächstgelegenen erreichbaren Lager mit Vorrat — für
## den Bau einer Wasserstraße/Fähre. Liefert true, wenn eines abgebucht wurde.
func take_boat_near(flag_idx: int, owner := 0) -> bool:
	var st := _nearest_storage(flag_idx, owner,
		func(s: Storage) -> bool: return int(s.stock.get(Goods.BOAT, 0)) > 0)
	if st == null:
		return false
	st.stock[Goods.BOAT] = int(st.stock[Goods.BOAT]) - 1
	if int(st.stock[Goods.BOAT]) <= 0:
		st.stock.erase(Goods.BOAT)
	return true


## Hat ein erreichbares Lager ein Boot? (UI-Hinweis vor dem Wasserstraßenbau.)
func has_boat_near(flag_idx: int, owner := 0) -> bool:
	return _nearest_storage(flag_idx, owner,
		func(s: Storage) -> bool: return int(s.stock.get(Goods.BOAT, 0)) > 0) != null


func _return_boat(owner: int) -> void:
	if owner != 0:
		return
	hq_stock[Goods.BOAT] = int(hq_stock.get(Goods.BOAT, 0)) + 1


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
		if c.has_boat:
			_return_boat(c.road.owner)
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
	var start_flag := state.map.idx(c.road.a.x, c.road.a.y)
	if c.road.waterway and not c.has_boat and not has_boat_near(start_flag, c.road.owner):
		return  # Wasserstraßen-Träger braucht ein Boot aus einem erreichbaren Lager (#46)
	# S2-Personalmodell (Issue #9): ein Träger braucht einen HELPER aus dem Lager.
	# Ist keiner verfügbar, bleibt die Straße unbesetzt und wird später erneut versucht.
	if not c.has_person:
		if not _take_person(Jobs.HELPER, c.road.owner):
			return
		c.has_person = true
	if c.road.waterway and not c.has_boat:
		if not take_boat_near(start_flag, c.road.owner):
			return
		c.has_boat = true
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
		# gebracht. Danach trägt der Arbeiter im Leerlauf noch fertige Ware zur
		# Flagge hinaus (#66) — _tick_work startet aber keinen neuen Gang mehr.
		_tick_work(bs)
		return
	_request_inputs(bs)
	_tick_work(bs)
	# Im Träger-Modus (#66) holt der Straßenträger die fertige Ware aus dem Haus;
	# im Default-Modus trägt der Arbeiter sie selbst hinaus (in _tick_work).


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
		var job := Jobs.PLANER if bs.planing \
			else (Jobs.BUILDER if bs.is_construction else BuildingCatalog.job_of(bs.bld.def_id))
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

## Braucht die Baustelle [param b] einen Planierer? Nur Haus-/Burg-Plätze (RTTR:
## House/Castle/Harbor) auf unebenem Grund — Hütten/Minen/Flaggen nie, ebene Plätze nie.
func _needs_planing(b: WorldState.Building) -> bool:
	if b.size != WorldState.BQ_HOUSE and b.size != WorldState.BQ_CASTLE:
		return false
	# Ufergebäude (Hafen/Werft) werden bewusst am Wasser gebaut — kein Planieren: die
	# Wasser-Nachbarknoten liegen tiefer, dürfen aber nicht eingeebnet werden (sonst
	# planiert der Planierer ins Wasser). #64-Folge.
	if bool(BuildingCatalog.get_def(b.def_id).get("needs_water", false)):
		return false
	var h0 := state.map.get_height(b.pos.x, b.pos.y)
	for dir in _planing_dirs_for(b.pos):
		var n := state.map.neighbor(b.pos.x, b.pos.y, dir)
		if n.x >= 0 and state.map.get_height(n.x, n.y) != h0:
			return true
	return false


## Planier-Reihenfolge wie RTTR nofPlaner als Konzept: nicht freie Terraformierung,
## sondern Arbeit an den Nachbarknoten rund um eine erlaubte Baustelle. Die SE-Seite
## bleibt frei, weil dort Flagge/Eingang liegen.
func _planing_dirs_for(pos: Vector2i) -> Array[int]:
	var clockwise := _planing_clockwise(pos)
	var dirs: Array[int] = []
	if clockwise:
		dirs = [Grid.SW, Grid.W, Grid.NW, Grid.NE, Grid.E]
	else:
		dirs = [Grid.E, Grid.NE, Grid.NW, Grid.W, Grid.SW]
	return dirs


## S2/RTTR waehlt die Umlaufrichtung zufaellig. Hier deterministisch aus der Position,
## damit Core und spaeterer Lockstep reproduzierbar bleiben.
func _planing_clockwise(pos: Vector2i) -> bool:
	var h := pos.x * 73856093 ^ pos.y * 19349663 ^ state.map.width * 83492791
	return (absi(h) & 1) == 0


func _prepare_planing(bs: BState) -> void:
	bs.plan_points.clear()
	for dir in _planing_dirs_for(bs.bld.pos):
		var n := state.map.neighbor(bs.bld.pos.x, bs.bld.pos.y, dir)
		if n.x >= 0:
			bs.plan_points.append(n)
	if bs.plan_points.is_empty():
		return
	bs.planing = true
	bs.bld.planing = true
	bs.plan_index = 0
	bs.plan_walk_ticks = Tuning.planer_walk_ticks()
	bs.plan_work_ticks = Tuning.planer_work_ticks()
	bs.plan_total = bs.plan_walk_ticks * (bs.plan_points.size() + 1) \
		+ bs.plan_work_ticks * bs.plan_points.size()
	bs.plan_t = bs.plan_total
	_start_plan_walk(bs, bs.bld.pos, bs.plan_points[0])


func _start_plan_walk(bs: BState, from: Vector2i, to: Vector2i) -> void:
	bs.plan_phase = PLAN_PHASE_WALK
	bs.plan_from = from
	bs.plan_to = to
	bs.plan_step_total = maxi(1, bs.plan_walk_ticks)
	bs.plan_step_t = bs.plan_step_total


func _start_plan_work(bs: BState) -> void:
	bs.plan_phase = PLAN_PHASE_WORK
	bs.plan_step_total = maxi(1, bs.plan_work_ticks)
	bs.plan_step_t = bs.plan_step_total


func _flatten_plan_point(bs: BState, p: Vector2i) -> void:
	var h0 := state.map.get_height(bs.bld.pos.x, bs.bld.pos.y)
	if state.map.get_height(p.x, p.y) == h0:
		return
	state.map.set_height(p.x, p.y, h0)
	state.invalidate_routes()
	_mark_terrain_dirty(p, 1)


## Einebnungsphase vor dem eigentlichen Bau (#49). Solange planiert wird, fordert die
## Baustelle KEIN Material und keinen Bauarbeiter an — erst kommt der Planierer.
func _tick_planing(bs: BState) -> void:
	if not bs.staffed:
		if not bs.worker_sent:
			_dispatch_worker(bs)
		return
	if bs.plan_points.is_empty():
		_finish_planing(bs)
		return
	if bs.plan_t > 0:
		bs.plan_t -= 1
	if bs.plan_step_t > 0:
		bs.plan_step_t -= 1
		if bs.plan_step_t > 0:
			return
	if bs.plan_phase == PLAN_PHASE_WALK:
		if bs.plan_index >= bs.plan_points.size():
			_finish_planing(bs)
		else:
			_start_plan_work(bs)
		return
	var here: Vector2i = bs.plan_points[bs.plan_index]
	_flatten_plan_point(bs, here)
	bs.plan_index += 1
	if bs.plan_index >= bs.plan_points.size():
		_start_plan_walk(bs, here, bs.bld.pos)
	else:
		_start_plan_walk(bs, here, bs.plan_points[bs.plan_index])
	return


## Planierphase abgeschlossen: Planierer laeuft heim, danach fordert die Baustelle
## wie gewohnt Material und den Bauarbeiter an.
func _finish_planing(bs: BState) -> void:
	_dispatch_builder_return(bs)       # Planierer laeuft zurueck (gleiche Mechanik wie Bauarbeiter)
	if bs.has_person:
		_return_person(bs.person_job, bs.bld.owner)
		bs.has_person = false
		bs.person_job = -1
	bs.planing = false
	bs.bld.planing = false
	bs.plan_points.clear()
	bs.plan_index = 0
	bs.plan_t = 0
	bs.staffed = false
	bs.worker_sent = false
	dirty = true


## Markiert einen Knotenbereich (Mittelpunkt [param center] ± [param radius]) als
## gelaende-dirty, damit der Renderer nur die betroffenen Terrain-Chunks neu zeichnet.
func _mark_terrain_dirty(center: Vector2i, radius: int) -> void:
	var r := Rect2i(center.x - radius, center.y - radius, radius * 2 + 1, radius * 2 + 1)
	terrain_dirty_rect = r if not terrain_dirty else terrain_dirty_rect.merge(r)
	terrain_dirty = true
	dirty = true


func _tick_construction(bs: BState) -> void:
	if bs.planing:
		_tick_planing(bs)
		return
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
	# Militärgebäude (#66): Münzen werden wie eine Ware vom Lager angefordert und vom
	# Straßenträger in die Tür getragen (statt direkt aus dem HQ-Bestand). Sollbestand =
	# noch nicht auf Höchstrang beförderte Soldaten, eine Münze je Beförderungsschritt.
	if int(bs.def.get("influence", 0)) > 0:
		if bs.bld.wants_coins and bs.bld.garrison > 0:
			var have_c := int(bs.delivered.get(Goods.COINS, 0)) + int(bs.incoming.get(Goods.COINS, 0))
			var want_c := bs.bld.garrison - bs.bld.ranks_normalized()[RANK_MAX]
			if have_c < want_c:
				_request_from_hq(bs, Goods.COINS, want_c - have_c)
		return
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
			# Fallback (#66): noch im Haus liegende Fertigware (konnte vorher nicht zur
			# Flagge — voll/kein Lager) jetzt hinaustragen. Im Träger-Modus
			# (output_via_carrier) holt stattdessen der Straßenträger.
			if _worker_should_carry_out(bs):
				bs.carry_good = _pick_out_to_ship(bs)
				bs.worker_target = Vector2i(-1, -1)   # Start = Tür
				_enter_wphase(bs, WK_DROP_OUT, _worker_haul_ticks(bs))
				return
			if bs.stopped:
				return  # angehalten: keinen neuen Produktionsgang mehr starten
			if _out_total(bs) >= OUT_CAP:
				bs.idle_reason = IDLE_OUT_FULL
				return
			if not _has_inputs(bs):
				bs.idle_reason = IDLE_NO_INPUTS
				return
			# Küstengebäude (Werft, #46): produziert nur mit Wasser in Reichweite. Wie der
			# Fischer baubar überall, arbeitet aber nur an der Küste.
			if bool(bs.def.get("needs_water", false)) and not _water_near(bs.bld.pos):
				bs.idle_reason = IDLE_NO_RESOURCE
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
				_reserve_target(bs, tgt)  # Ziel sperren, bis die Aktion erledigt ist (#66)
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
					_release_target(bs)  # Ziel ist abgebaut/bepflanzt → Reservierung frei (#66)
					if bs.out_yield:
						_add_out(bs, bs.cur_output)  # Ware entsteht am Arbeitsplatz (Baum/Feld)
					# S2 (#66): Mit Ertrag und freier Flagge trägt der Arbeiter die Ware vom
					# Arbeitsplatz DIREKT zur Flagge (Start = worker_target), legt sie ab und
					# geht leer ins Haus. Sonst (Säen / Flagge voll / kein Lager) leer zurück.
					if bs.out_yield and _worker_should_carry_out(bs):
						bs.carry_good = _pick_out_to_ship(bs)
						_enter_wphase(bs, WK_DROP_OUT, _worker_haul_ticks(bs))
					else:
						_enter_wphase(bs, WK_BACK, _worker_walk_ticks(bs, bs.worker_target))
				else:
					_add_out(bs, bs.cur_output)
					# Stationär: fertige Ware sofort aus der Tür zur Flagge tragen (#66).
					if _worker_should_carry_out(bs):
						bs.carry_good = _pick_out_to_ship(bs)
						bs.worker_target = Vector2i(-1, -1)   # Start = Tür
						_enter_wphase(bs, WK_DROP_OUT, _worker_haul_ticks(bs))
					else:
						_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_BACK:  # leerer Rückweg (Säen oder Flagge/Lager belegt → Ware blieb im Haus)
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_DROP_OUT:  # Fertigware vom Arbeitsplatz/Tür zur Flagge tragen + ablegen (#66)
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_drop_output_at_flag(bs, bs.carry_good)
				bs.carry_good = -1
				bs.worker_target = Vector2i(-1, -1)   # Rückweg ist fix Flagge→Tür
				_enter_wphase(bs, WK_DROP_BACK, _worker_walk_ticks(bs, bs.bld.flag_pos))
		WK_DROP_BACK:  # leer von der Flagge zurück ins Haus → dann Pause (#66)
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_WAIT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				bs.producing = false
				bs.worker_target = Vector2i(-1, -1)
				bs.wphase = WK_IDLE


## Soll der Arbeiter jetzt eine fertige Ware aus der Tür zur Flagge tragen (#66)?
## Nur im Default-Modus (nicht output_via_carrier), wenn etwas fertig ist und die
## Flagge noch Platz hat.
func _worker_should_carry_out(bs: BState) -> bool:
	if output_via_carrier:
		return false
	if _out_total(bs) <= 0:
		return false
	if goods_on_flag(bs.flag_idx) >= FLAG_CAP:
		return false
	# Nur losziehen, wenn die Ware auch tatsächlich abgelegt werden kann (erreichbares
	# Lager) — sonst würde der Arbeiter sinnlos pendeln (kein Straßenanschluss).
	return _nearest_storage(bs.flag_idx, 0, func(_s: Storage) -> bool: return true) != null


## Erste fertige Warensorte im Ausgangspuffer (deterministische Schlüsselreihenfolge).
func _pick_out_to_ship(bs: BState) -> int:
	for g in bs.out_stock:
		if int(bs.out_stock[g]) > 0:
			return int(g)
	return -1


## Eine fertige Ware an der Gebäudeflagge ablegen (Richtung nächstes Lager) und aus
## dem Ausgangspuffer nehmen (#66, ersetzt den Teleport in _ship_outputs).
func _drop_output_at_flag(bs: BState, good: int) -> void:
	if good < 0 or int(bs.out_stock.get(good, 0)) <= 0:
		return
	if goods_on_flag(bs.flag_idx) >= FLAG_CAP:
		return
	var st := _nearest_storage(bs.flag_idx, 0, func(_s: Storage) -> bool: return true)
	if st == null:
		return
	var g := Good.new()
	g.type = good
	g.dest = st.flag_idx
	_push_good(bs.flag_idx, g)
	bs.out_stock[good] = int(bs.out_stock[good]) - 1


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
	# Werft im Schiffe-Modus (#46): das "Boot" wird kein Ausgangsgut, sondern fließt in
	# den Schiffsbau. Nach SHIP_BUILD_CYCLES Zyklen (S2/10th: 12 Bretter) läuft ein
	# fertiges Schiff am Andockknoten der Werft vom Stapel.
	if good == Goods.BOAT and String(bs.def.get("id", "")) == "shipyard" and bs.build_ships:
		bs.ship_progress += 1
		if bs.ship_progress >= SHIP_BUILD_CYCLES:
			bs.ship_progress = 0
			# Andock-Radius wie _water_near (ORE_RADIUS), damit jede produktionsfähige
			# Werft auch ein Schiff zu Wasser lassen kann.
			var dock := state.dock_node(bs.bld.pos, ORE_RADIUS)
			if dock.x >= 0:
				_spawn_ship(dock, bs.bld.owner)
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


## Startknoten des Trag-Wegs (#66): der Arbeitsplatz (worker_target), wenn der Arbeiter
## von dort die Ernte direkt zur Flagge trägt — sonst die Haustür.
func _worker_haul_start(bs: BState) -> Vector2i:
	return bs.worker_target if bs.worker_target.x >= 0 else bs.bld.pos


## Laufzeit für den Trag-Weg Startknoten→Flagge (#66).
func _worker_haul_ticks(bs: BState) -> float:
	var a := state.map.node_world(_worker_haul_start(bs).x, _worker_haul_start(bs).y)
	var b := state.map.node_world(bs.bld.flag_pos.x, bs.bld.flag_pos.y)
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
## Reserviert einen Arbeitsplatz-Knoten für dieses Gebäude, damit kein zweiter Arbeiter
## dasselbe Ziel nimmt und der Spieler einen leeren Pflanz-/Saatplatz nicht wegbaut (#66).
func _reserve_target(bs: BState, node: Vector2i) -> void:
	_release_target(bs)
	if node.x < 0:
		return
	bs.reserved_idx = state.map.idx(node.x, node.y)
	state.work_reserved[bs.reserved_idx] = bs.idx


## Gibt den reservierten Arbeitsplatz wieder frei (Aktion erledigt / abgebrochen / Abriss).
func _release_target(bs: BState) -> void:
	if bs.reserved_idx >= 0:
		if int(state.work_reserved.get(bs.reserved_idx, -1)) == bs.idx:
			state.work_reserved.erase(bs.reserved_idx)
		bs.reserved_idx = -1


## Ist dieser Knoten schon von einem ANDEREN Arbeiter belegt (#66)? bs == null (Tests/
## reine Suche) → keine Filterung.
func _node_taken(node: Vector2i, bs: BState) -> bool:
	if bs == null:
		return false
	var i := state.map.idx(node.x, node.y)
	return state.work_reserved.has(i) and int(state.work_reserved[i]) != bs.idx


func _resource_target(bs: BState) -> Vector2i:
	match String(bs.def.get("resource", "")):
		"tree": return _find_mature_tree(bs.bld.pos, RES_RADIUS, bs)
		"stone": return _find_object(bs.bld.pos, MapData.MO_STONE, RES_RADIUS, bs)
		"ore": return _find_deposit(bs.bld.pos, int(bs.def.get("mineral", -1)), ORE_RADIUS, bs)
		"plant_tree": return _find_plant_spot(bs.bld.pos, bs)
		"field": return _find_farm_target(bs.bld.pos, bs)
		"water": return _find_water_edge(bs.bld.pos, bs)
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
			else:
				bs.out_yield = false  # Baum weg (anderer war schneller) → kein Holz (#66)
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
			else:
				bs.out_yield = false  # Stein weg → kein Ertrag (#66)
		"ore":
			# Unterirdisches Vorkommen abbauen (eine Einheit; bei 0 erschöpft).
			if state.map.take_ore_deposit(n.x, n.y):
				dirty = true
			else:
				bs.out_yield = false  # Vorkommen erschöpft → kein Ertrag (#66)
		"water":
			# Einen Fisch fangen (Issue #6); der Fischgrund erschöpft bei 0.
			if state.map.take_fish(n.x, n.y):
				dirty = true
			else:
				bs.out_yield = false  # Fischgrund leer → kein Fisch (#66)
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
				dirty = true  # out_yield bleibt true → Getreide entsteht am Feld (WK_WORK)
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
func _find_water_edge(center: Vector2i, bs: BState = null) -> Vector2i:
	for r in range(1, ORE_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if _node_taken(Vector2i(x, y), bs):
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

func _find_object(center: Vector2i, motype: int, radius: int, bs: BState = null) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if _node_taken(Vector2i(x, y), bs):
					continue
				if state.map.map_object(x, y) == motype:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_mature_tree(center: Vector2i, radius: int, bs: BState = null) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if _node_taken(Vector2i(x, y), bs):
					continue
				if state.map.map_object(x, y) == MapData.MO_TREE \
						and state.map.tree_stage_at(x, y) == MapData.TREE_BIG:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Unterirdisches Erz-Vorkommen der passenden Sorte im Umkreis suchen
## (mineral < 0 = beliebiges Erz). Liefert den nächstgelegenen Fundknoten.
func _find_deposit(center: Vector2i, mineral: int, radius: int, bs: BState = null) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if _node_taken(Vector2i(x, y), bs):
					continue
				if state.map.ore_deposit_amount_at(x, y) <= 0:
					continue
				if mineral < 0 or state.map.ore_deposit_kind_at(x, y) == mineral:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_plant_spot(center: Vector2i, bs: BState = null) -> Vector2i:
	for r in range(1, RES_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if _node_taken(Vector2i(x, y), bs):
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
func _find_farm_target(center: Vector2i, bs: BState = null) -> Vector2i:
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
				if _node_taken(Vector2i(x, y), bs):
					continue  # Feld/Saatplatz schon von einem anderen Bauern beansprucht (#66)
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

const DOOR_SPEED := 0.045   # Tür-Exkursion: Flagge↔Tür-Tempo (wie HOUSE_SPEED)


func _tick_carrier(c: Carrier) -> void:
	if not c.active:
		return  # Träger ist noch auf dem Weg vom HQ
	if c.dphase != D_NONE:
		_tick_carrier_door(c)   # Tür-Exkursion läuft → kein Straßenlauf (#66)
		return
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
			# Option output_via_carrier (#66): liegt an einem Gebäude-Ende ein fertiger
			# Ausgang im Haus, leer dorthin und durch die Tür holen.
			elif _building_output_to_fetch(e0) >= 0 and goods_on_flag(e0) < FLAG_CAP:
				c.dbidx = _building_output_to_fetch(e0)
				c.dflag = e0
				c.target = 0.0
				c.state = C_TO_FETCH
			elif _building_output_to_fetch(e1) >= 0 and goods_on_flag(e1) < FLAG_CAP:
				c.dbidx = _building_output_to_fetch(e1)
				c.dflag = e1
				c.target = segs
				c.state = C_TO_FETCH
			# #67: Liegt am HQ/Lager-Ende wartende Ausgangsware in der outbox, holt der
			# Straßenträger sie selbst durch die Tür — so ziehen mehrere Straßen parallel
			# Nachschub heraus statt sich am einen Tür-Träger des Lagers anzustellen.
			elif _storage_output_to_fetch(e0) and goods_on_flag(e0) < FLAG_CAP:
				c.dstorage = e0
				c.dflag = e0
				c.target = 0.0
				c.state = C_TO_FETCH
			elif _storage_output_to_fetch(e1) and goods_on_flag(e1) < FLAG_CAP:
				c.dstorage = e1
				c.dflag = e1
				c.target = segs
				c.state = C_TO_FETCH
			else:
				c.target = mid
		C_TO_FETCH:
			# An der Gebäudeflagge angekommen → leer durch die Tür, Ausgang holen.
			c.dt = 0.0
			c.dphase = D_IN
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
			var deliver_flag := _end_flag(c.road, deliver_end)
			# Endlieferung in ein Arbeitshaus: der Träger trägt die Ware bis in die Tür
			# (#66), kein Teleport an der Flagge. Sonst normal an die Flagge übergeben.
			var into := _building_for_carry_in(deliver_flag, c.carrying)
			if into >= 0:
				c.dbidx = into
				c.dflag = deliver_flag
				c.dt = 0.0
				c.dphase = D_IN
				return
			# Endlieferung ins HQ/Lager: der Netz-Träger trägt die Ware bis in die Tür
			# (S2-treu), statt sie nur an der Lagerflagge für den Tür-Träger abzulegen.
			var sinto := _storage_for_carry_in(deliver_flag, c.carrying)
			if sinto >= 0:
				c.dstorage = sinto
				c.dflag = deliver_flag
				c.dt = 0.0
				c.dphase = D_IN
				return
			_deliver(c.carrying, deliver_flag)
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


## Ist [flag_idx] die Flagge eines fertigen Arbeitshauses, in das diese Endlieferung
## hineingetragen werden soll (#66)? Gibt den Gebäude-Index zurück, sonst -1.
## Baustellen (Bretter/Steine) behalten den direkten Teleport; HQ/Lager nutzen ihren
## eigenen Tür-Träger.
func _building_for_carry_in(flag_idx: int, g: Good) -> int:
	if g == null or g.dest != flag_idx:
		return -1
	if not flag_to_building.has(flag_idx):
		return -1
	var bidx: int = flag_to_building[flag_idx]
	var bs: BState = bstates.get(bidx)
	if bs == null or bs.is_construction:
		return -1
	return bidx


## Im Träger-Modus (#66, output_via_carrier): hat das Arbeitshaus an [flag_idx] einen
## fertigen Ausgang, den ein Straßenträger jetzt durch die Tür holen soll? Gibt den
## Gebäude-Index zurück, sonst -1. Nur mit erreichbarem Ziellager.
func _building_output_to_fetch(flag_idx: int) -> int:
	if not output_via_carrier:
		return -1
	if not flag_to_building.has(flag_idx):
		return -1
	var bidx: int = flag_to_building[flag_idx]
	var bs: BState = bstates.get(bidx)
	if bs == null or bs.is_construction or _out_total(bs) <= 0:
		return -1
	if _nearest_storage(flag_idx, 0, func(_s: Storage) -> bool: return true) == null:
		return -1
	return bidx


## Nimmt einen fertigen Ausgang aus dem Haus (Träger-Modus, #66) und macht daraus eine
## Ware Richtung nächstes Lager. null, wenn nichts zu holen ist.
func _take_building_output(bs: BState) -> Good:
	if not output_via_carrier or _out_total(bs) <= 0:
		return null
	var good := _pick_out_to_ship(bs)
	if good < 0:
		return null
	var st := _nearest_storage(bs.flag_idx, 0, func(_s: Storage) -> bool: return true)
	if st == null:
		return null
	bs.out_stock[good] = int(bs.out_stock[good]) - 1
	var g := Good.new()
	g.type = good
	g.dest = st.flag_idx
	return g


## Tür-Exkursion eines Straßenträgers (#66): er steht an der Gebäudeflagge und
## verlängert seinen Weg in die Tür. D_IN trägt die Eingangsware hinein und bucht sie
## (delivered++/incoming--); D_OUT bringt ihn leer zur Flagge zurück. Danach nimmt er
## den normalen Straßendienst wieder auf (kein separater Türträger pro Arbeitshaus).
func _tick_carrier_door(c: Carrier) -> void:
	if c.dstorage >= 0:
		_tick_carrier_door_storage(c)   # #67: Exkursion an einem HQ/Lager
		return
	var bs: BState = bstates.get(c.dbidx)
	if bs == null:
		_end_carrier_door(c)   # Gebäude verschwand → Ware retten, Dienst beenden
		return
	match c.dphase:
		D_IN:
			c.dt = minf(c.dt + DOOR_SPEED, 1.0)
			if c.dt >= 1.0:
				if c.carrying != null:
					var ty := int(c.carrying.type)
					bs.delivered[ty] = int(bs.delivered.get(ty, 0)) + 1
					bs.incoming[ty] = maxi(0, int(bs.incoming.get(ty, 0)) - 1)
					c.carrying = null
					_mark_road_delivery(c.road)
				# Option output_via_carrier (#66): einen fertigen Ausgang mit hinausnehmen.
				c.carrying = _take_building_output(bs)
				c.dphase = D_OUT
		D_OUT:
			c.dt = maxf(c.dt - DOOR_SPEED, 0.0)
			if c.dt <= 0.0:
				if c.carrying != null:
					_push_good(c.dflag, c.carrying)
					c.carrying = null
				_resume_carrier_at_flag(c)


## Tür-Exkursion eines Straßenträgers an einem HQ/Lager. Wie beim Arbeitshaus (#66)
## trägt er die Eingangsware sichtbar bis in die Tür und bucht sie ins Lager (D_IN) —
## das ist S2-treu, der Netz-Träger bedient die Lagertür selbst statt sie nur an der
## Flagge abzulegen; danach läuft er leer zurück (D_OUT). Bei aktiver Option
## output_via_carrier nimmt er auf dem Rückweg gleich eine wartende Ausgangsware (outbox)
## mit (#67) — so ziehen mehrere Straßen parallel Nachschub aus dem Lager.
func _tick_carrier_door_storage(c: Carrier) -> void:
	var st := _storage_by_flag(c.dstorage)
	if st == null:
		_end_carrier_door(c)   # Lager verschwand → Ware retten, Dienst beenden
		return
	match c.dphase:
		D_IN:
			c.dt = minf(c.dt + DOOR_SPEED, 1.0)
			if c.dt >= 1.0:
				if c.carrying != null:   # Eingang: Ware ins Lager einbuchen
					st.stock[c.carrying.type] = int(st.stock.get(c.carrying.type, 0)) + 1
					st.incoming[c.carrying.type] = maxi(0, int(st.incoming.get(c.carrying.type, 0)) - 1)
					c.carrying = null
					_mark_road_delivery(c.road)
				# Bei aktiver Option einen fertigen Ausgang gleich mit hinausnehmen (#67).
				c.carrying = _take_storage_output(c.dstorage)
				c.dphase = D_OUT
		D_OUT:
			c.dt = maxf(c.dt - DOOR_SPEED, 0.0)
			if c.dt <= 0.0:
				if c.carrying != null:
					_push_good(c.dflag, c.carrying)
					c.carrying = null
				_resume_carrier_at_flag(c)


## Nach einer Tür-Exkursion steht der Träger an einer Straßen-Endflagge. Statt leer zur
## Mitte zu laufen, nutzt er den Rückweg wie an jeder normalen Flagge: liegt hier eine
## Ware zur Gegenseite (nächster Hop = anderes Straßenende), nimmt er sie gleich mit;
## sonst zurück zur Mitte. Spiegelt das „Rückweg nutzen" der normalen Zustellung.
func _resume_carrier_at_flag(c: Carrier) -> void:
	var flag_idx := c.dflag
	c.dphase = D_NONE
	c.dt = 0.0
	c.dbidx = -1
	c.dstorage = -1
	c.dflag = -1
	var segs := float(c.road.length())
	if flag_idx < 0:
		c.state = C_RETURN
		c.target = segs * 0.5
		return
	var deliver_end := 0 if flag_idx == _end_flag(c.road, 0) else 1
	var other := _end_flag(c.road, 1 - deliver_end)
	var g = _take_good_for(flag_idx, other)
	if g != null:
		c.carrying = g
		c.pickup_end = deliver_end
		c.state = C_CARRYING
		c.target = segs if deliver_end == 0 else 0.0
	else:
		c.state = C_RETURN
		c.target = segs * 0.5


## Beendet die Tür-Exkursion: getragene Ware (Gebäude verschwand) nicht verlieren,
## dann zurück in den normalen Straßendienst (Rückweg zur Straßenmitte).
func _end_carrier_door(c: Carrier) -> void:
	if c.carrying != null:
		if c.dflag >= 0:
			_push_good(c.dflag, c.carrying)
		c.carrying = null
	c.dphase = D_NONE
	c.dt = 0.0
	c.dbidx = -1
	c.dstorage = -1
	c.dflag = -1
	c.state = C_RETURN
	c.target = float(c.road.length()) * 0.5


## #67: Lager (HQ/Lagerhaus) an Flaggen-Index [flag_idx], sonst null.
func _storage_by_flag(flag_idx: int) -> Storage:
	for st in storages:
		if st.flag_idx == flag_idx:
			return st
	return null


## #67: Hat das Lager an [flag_idx] eine wartende Ausgangsware (outbox), die ein
## Straßenträger bei aktiver Option direkt durch die Tür holen soll?
func _storage_output_to_fetch(flag_idx: int) -> bool:
	if not output_via_carrier:
		return false
	var st := _storage_by_flag(flag_idx)
	return st != null and not st.outbox.is_empty()


## Soll diese Endlieferung in ein HQ/Lager hineingetragen werden (S2-treu: der Netz-
## Träger bedient die Lagertür selbst)? Gibt die Lagerflagge zurück, sonst -1. Gilt immer
## (unabhängig von der Ausgangs-Option) — analog zum Arbeitshaus-Eingang (#66).
func _storage_for_carry_in(flag_idx: int, g: Good) -> int:
	if g == null or g.dest != flag_idx:
		return -1
	return flag_idx if _storage_by_flag(flag_idx) != null else -1


## #67: Nimmt die nächste wartende Ausgangsware aus dem Lager an [flag_idx] (FIFO, wie der
## Tür-Träger). Nur bei aktiver Option output_via_carrier. Die Ware trägt bereits ihr Ziel;
## das Routing an der Flagge schickt sie weiter. null, wenn nichts wartet.
func _take_storage_output(flag_idx: int) -> Good:
	if not output_via_carrier:
		return null
	var st := _storage_by_flag(flag_idx)
	if st == null or st.outbox.is_empty():
		return null
	return st.outbox.pop_front()


## Gebäude eines Lagers (HQ/Lagerhaus) an [flag_idx] — für die Tür-Exkursions-Animation
## des Straßenträgers. null, wenn dort kein Lager steht.
func storage_building_at_flag(flag_idx: int) -> WorldState.Building:
	var st := _storage_by_flag(flag_idx)
	if st == null or not state.buildings.has(st.idx):
		return null
	return state.buildings[st.idx]


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


# --------------------------------------------------------------------------
#  See-Schiffe (#46): Waren-Pendeln zwischen Häfen
# --------------------------------------------------------------------------

## Erzeugt ein Schiff an einem befahrbaren Wasserknoten (Werft im Schiffe-Modus / Test).
## Es sucht sich beim nächsten Fähren-Takt selbst einen Heimathafen.
func _spawn_ship(node: Vector2i, owner: int) -> Ship:
	# Stapel-Schutz: kein zweites Schiff auf denselben Knoten setzen.
	if _ship_on_node(node, null):
		var alt := _free_navigable_near(node, null)
		if alt.x >= 0:
			node = alt
	var s := Ship.new()
	s.owner = owner
	s.node = node
	s.pos = state.map.node_world(node.x, node.y)
	s.state = SHIP_IDLE
	s.home = -1
	ships.append(s)
	dirty = true
	return s


## Steht ein (anderes) Schiff auf [node]? Grundlage des Stapel-Schutzes (#): nie zwei
## Schiffe auf demselben Wasserknoten.
func _ship_on_node(node: Vector2i, except_s: Ship) -> bool:
	for o in ships:
		if o == except_s:
			continue
		if o.node == node:
			return true
	return false


## Nächster befahrbarer, von keinem Schiff besetzter Wasserknoten um [node] (Ringe 1..2).
func _free_navigable_near(node: Vector2i, except_s: Ship) -> Vector2i:
	for r in range(1, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := node + Vector2i(dx, dy)
				if state.hex_distance(node, p) != r:
					continue
				if state.node_navigable(p.x, p.y) and not _ship_on_node(p, except_s):
					return p
	return Vector2i(-1, -1)


## Alle fertigen Hafenlager (Storage mit Gebäude-def "harbor").
func _harbor_storages() -> Array[Storage]:
	var out: Array[Storage] = []
	for st in storages:
		if st.idx < 0:
			continue
		var b: WorldState.Building = state.buildings.get(st.idx)
		if b != null and b.def_id == "harbor" and not b.under_construction:
			out.append(st)
	return out


## Andockknoten (befahrbares Wasser) eines Hafenlagers, oder (-1,-1).
func _harbor_dock(st: Storage) -> Vector2i:
	var b: WorldState.Building = state.buildings.get(st.idx)
	if b == null:
		return Vector2i(-1, -1)
	return state.dock_node(b.pos)


func _tick_ships() -> void:
	if ships.is_empty():
		return
	_sea_timer -= 1
	if _sea_timer <= 0:
		_sea_timer = SEA_INTERVAL
		_assign_ships()
	for s in ships:
		if s.state == SHIP_SAILING:
			_advance_ship(s)
		elif _ship_on_node(s.node, s):
			# Stapel-Schutz (#): zwei leerlaufende Schiffe auf demselben Knoten (z. B. am
			# selben Hafen-Dock) — eines auf einen freien Nachbarknoten verholen.
			var alt := _free_navigable_near(s.node, s)
			if alt.x >= 0:
				s.node = alt
				s.pos = state.map.node_world(alt.x, alt.y)
				dirty = true
		# Schiff-Sicht (#46/#21): deckt den Nebel entlang der Route auf (nur Spieler).
		if s.owner == 0 and s.node.x >= 0:
			state.reveal_around(s.node.x, s.node.y, SHIP_VISION)


## Weist leerlaufenden Schiffen Fahrten zu: gleicht Hafenbestände derselben Meeres-
## Komponente aus (größtes Bestandsgefälle zuerst). Heimatlose Schiffe segeln leer zum
## nächsten Hafen.
func _assign_ships() -> void:
	var harbors := _harbor_storages()
	if harbors.is_empty():
		return
	for s in ships:
		if s.state != SHIP_IDLE or s.expedition:
			continue
		if s.home < 0:
			_send_ship_to_nearest_harbor(s, harbors)
		else:
			_assign_ferry(s, harbors)


## Schickt ein heimatloses Schiff (frisch von der Werft) leer zum nächsten erreichbaren Hafen.
func _send_ship_to_nearest_harbor(s: Ship, harbors: Array[Storage]) -> void:
	var best_path: Array[Vector2i] = []
	var best_dest := -1
	for st in harbors:
		var dock := _harbor_dock(st)
		if dock.x < 0:
			continue
		var path := state.find_sea_path(s.node, dock)
		if path.is_empty():
			continue
		if best_path.is_empty() or path.size() < best_path.size():
			best_path = path
			best_dest = st.flag_idx
	if best_dest >= 0:
		s.dest = best_dest
		s.path = best_path
		s.path_i = 1 if best_path.size() > 1 else 0
		s.state = SHIP_SAILING


## Lädt am Heimathafen die Ware mit dem größten Bestandsgefälle zu einem erreichbaren
## Zielhafen und legt ab. Ohne lohnende Fracht bleibt das Schiff liegen.
func _assign_ferry(s: Ship, harbors: Array[Storage]) -> void:
	var src := _storage_by_flag(s.home)
	if src == null:
		return
	var src_dock := _harbor_dock(src)
	if src_dock.x < 0:
		return
	var src_comp := state.sea_component_at(src_dock.x, src_dock.y)
	var best_good := -1
	var best_dest: Storage = null
	var best_diff := SEA_BALANCE_MARGIN - 1
	for st in harbors:
		if st.flag_idx == s.home:
			continue
		var dock := _harbor_dock(st)
		if dock.x < 0 or state.sea_component_at(dock.x, dock.y) != src_comp:
			continue
		for g in src.stock:
			var diff := int(src.stock[g]) - int(st.stock.get(g, 0))
			if diff > best_diff:
				best_diff = diff
				best_good = int(g)
				best_dest = st
	if best_dest == null or best_good < 0:
		return
	var path := state.find_sea_path(src_dock, _harbor_dock(best_dest))
	if path.is_empty():
		return
	# Halbe Differenz laden (Richtung Ausgleich), höchstens Laderaum.
	var amount := mini(SHIP_CAPACITY, (best_diff + 1) / 2)
	for _i in amount:
		if int(src.stock.get(best_good, 0)) <= 0:
			break
		src.stock[best_good] = int(src.stock[best_good]) - 1
		var good := Good.new()
		good.type = best_good
		good.dest = best_dest.flag_idx
		s.cargo.append(good)
	if s.cargo.is_empty():
		return
	s.dest = best_dest.flag_idx
	s.path = path
	s.path_i = 1 if path.size() > 1 else 0
	s.state = SHIP_SAILING


## Bewegt ein fahrendes Schiff entlang seines See-Pfads; am Ziel andocken + entladen.
func _advance_ship(s: Ship) -> void:
	if s.path.is_empty() or s.path_i >= s.path.size():
		_ship_arrived(s)
		return
	var tnode := s.path[s.path_i]
	# Stapel-Schutz (#): nicht in einen bereits von einem anderen Schiff besetzten Knoten
	# fahren — diesen Takt warten. Der Blockierer fährt selbst weiter oder wird (falls
	# leerlaufend) in _tick_ships entzerrt, sodass kein Dauerstau entsteht.
	if tnode != s.node and _ship_on_node(tnode, s):
		return
	var tw := state.map.node_world(tnode.x, tnode.y)
	var d := tw - s.pos
	var dist := d.length()
	if dist <= SHIP_SPEED:
		s.pos = tw
		s.node = tnode
		s.path_i += 1
		if s.path_i >= s.path.size():
			_ship_arrived(s)
	else:
		s.facing = d / dist
		s.pos += s.facing * SHIP_SPEED
	dirty = true


## Ankunft am Ziel: Expedition gründet einen Hafen, sonst normale Fracht-Ankunft.
func _ship_arrived(s: Ship) -> void:
	if s.expedition:
		_found_harbor(s)
	elif s.raid:
		_resolve_sea_raid(s)
	else:
		_ship_arrive(s)


## Schiff hat den Ziel-Hafen erreicht: Fracht ins Hafenlager buchen, dort andocken.
func _ship_arrive(s: Ship) -> void:
	var dst := _storage_by_flag(s.dest)
	if dst != null:
		for g in s.cargo:
			dst.stock[g.type] = int(dst.stock.get(g.type, 0)) + 1
		s.home = s.dest
	else:
		for g in s.cargo:
			_dump_good_to_hq(g)   # Zielhafen verschwand → Fracht retten (kein Verlust)
	s.cargo.clear()
	s.dest = -1
	s.path = []
	s.path_i = 0
	s.state = SHIP_IDLE
	dirty = true


## Liegt auf diesem Hafenpunkt bereits ein Hafen?
func _harbor_at_point(p: Vector2i) -> bool:
	var b: WorldState.Building = state.buildings.get(state.map.idx(p.x, p.y))
	return b != null and b.def_id == "harbor"


## Schaltet die Expeditions-VORBEREITUNG eines Hafens um (#46, wie im Original): ein
## erneuter Klick bricht ab. Während der Vorbereitung ordert der Hafen selbsttätig das
## Baumaterial (Bretter/Steine) und wartet auf ein Schiff; sobald alles da ist, sticht die
## Expedition automatisch in See (siehe _tick_harbor_prep). Liefert "" oder einen Hinweis.
func prepare_expedition(harbor_flag: int, owner := 0) -> String:
	var src := _storage_by_flag(harbor_flag)
	if src == null:
		return "Kein Hafen."
	if src.expedition_prep:
		src.expedition_prep = false
		src.incoming.clear()
		dirty = true
		return "Expedition abgebrochen."
	src.raid_prep = false   # nur EINE Vorbereitung gleichzeitig
	src.expedition_prep = true
	dirty = true
	return ""


func is_expedition_prep(harbor_flag: int) -> bool:
	var st := _storage_by_flag(harbor_flag)
	return st != null and st.expedition_prep


func is_raid_prep(harbor_flag: int) -> bool:
	var st := _storage_by_flag(harbor_flag)
	return st != null and st.raid_prep


## Kurzer Status für die UI: was fehlt der vorbereiteten Expedition noch?
func expedition_status(harbor_flag: int) -> String:
	var src := _storage_by_flag(harbor_flag)
	if src == null or not src.expedition_prep:
		return ""
	var br := int(src.stock.get(Goods.BOARDS, 0))
	var st := int(src.stock.get(Goods.STONE, 0))
	var has_ship := false
	for s in ships:
		if s.state == SHIP_IDLE and not s.expedition and s.home == harbor_flag:
			has_ship = true
			break
	return "Vorbereitung: %d/%d Bretter, %d/%d Steine, Schiff: %s" % [
		mini(br, EXPEDITION_BOARDS), EXPEDITION_BOARDS,
		mini(st, EXPEDITION_STONES), EXPEDITION_STONES, "ja" if has_ship else "nein"]


## Pro Takt: vorbereitende Häfen mit Material versorgen und — sobald alles da ist —
## Expedition/Seeangriff auslösen.
func _tick_harbor_prep() -> void:
	for st in storages:
		if st.idx < 0 or st.owner != 0:
			continue
		var b: WorldState.Building = state.buildings.get(st.idx)
		if b == null or b.def_id != "harbor" or b.under_construction:
			if st.expedition_prep or st.raid_prep:
				st.expedition_prep = false
				st.raid_prep = false
				st.incoming.clear()
			continue
		if st.expedition_prep:
			_order_good_to_storage(st, Goods.BOARDS, EXPEDITION_BOARDS)
			_order_good_to_storage(st, Goods.STONE, EXPEDITION_STONES)
			if start_expedition(st.flag_idx, st.owner) == "":
				st.expedition_prep = false
				st.incoming.clear()
				dirty = true
		elif st.raid_prep:
			_tick_raid_prep(st)


## Ordert fehlendes Material [g] bis [need] zum Lager [dst_st] (Bestand + unterwegs).
func _order_good_to_storage(dst_st: Storage, g: int, need: int) -> void:
	var have := int(dst_st.stock.get(g, 0)) + int(dst_st.incoming.get(g, 0))
	var guard := 0
	while have < need and guard < need:
		if not _pull_to_storage(dst_st, g):
			break
		have += 1
		guard += 1


## Reserviert ein Stück [g] im nächstgelegenen anderen Lager und schickt es zu [dst_st]
## (dest = dessen Flagge → Straßenträger trägt es ins Lager). Zählt `incoming` mit, damit
## nicht über den Bedarf hinaus bestellt wird. false, wenn nirgends vorrätig/erreichbar.
func _pull_to_storage(dst_st: Storage, g: int) -> bool:
	var src := _nearest_storage(dst_st.flag_idx, dst_st.owner, func(s: Storage) -> bool:
		return s != dst_st and int(s.stock.get(g, 0)) > 0 and s.outbox.size() < FLAG_CAP)
	if src == null:
		return false
	src.stock[g] = int(src.stock[g]) - 1
	dst_st.incoming[g] = int(dst_st.incoming.get(g, 0)) + 1
	var good := Good.new()
	good.type = g
	good.dest = dst_st.flag_idx
	src.outbox.append(good)
	return true


## Schaltet die Seeangriffs-VORBEREITUNG eines Hafens um (#46, RTTR-Seeangriff): ein Schiff
## lädt Soldaten aus der Hafen-Garnison und greift den nächsten erreichbaren feindlichen
## Hafen an. Erneuter Klick bricht ab. Liefert "" oder einen Hinweis.
func prepare_raid(harbor_flag: int, owner := 0) -> String:
	var src := _storage_by_flag(harbor_flag)
	if src == null:
		return "Kein Hafen."
	if src.raid_prep:
		src.raid_prep = false
		dirty = true
		return "Seeangriff abgebrochen."
	src.expedition_prep = false   # nur EINE Vorbereitung gleichzeitig
	src.raid_prep = true
	dirty = true
	return ""


## Status der Seeangriffs-Vorbereitung für die UI.
func raid_status(harbor_flag: int) -> String:
	var src := _storage_by_flag(harbor_flag)
	if src == null or not src.raid_prep:
		return ""
	var gar := 0
	var b: WorldState.Building = state.buildings.get(src.idx)
	if b != null:
		gar = b.garrison
	var has_ship := false
	for s in ships:
		if s.state == SHIP_IDLE and not s.expedition and not s.raid and s.home == harbor_flag:
			has_ship = true
			break
	var has_target := _nearest_enemy_harbor(src) != null
	return "Seeangriff: Soldaten %d, Schiff: %s, Ziel: %s" % [
		gar, "ja" if has_ship else "nein", "ja" if has_target else "keins erreichbar"]


## Nächster über See erreichbarer FEINDLicher Hafen (gleiche Meereskomponente). Oder null.
func _nearest_enemy_harbor(src: Storage) -> WorldState.Building:
	var src_dock := _harbor_dock(src)
	if src_dock.x < 0:
		return null
	var src_comp := state.sea_component_at(src_dock.x, src_dock.y)
	var best: WorldState.Building = null
	var best_len := 1 << 30
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.def_id != "harbor" or b.owner == src.owner or b.under_construction:
			continue
		var dock := state.dock_node(b.pos)
		if dock.x < 0 or state.sea_component_at(dock.x, dock.y) != src_comp:
			continue
		var path := state.find_sea_path(src_dock, dock)
		if path.is_empty():
			continue
		if path.size() < best_len:
			best_len = path.size()
			best = b
	return best


## Seeangriff-Vorbereitung pro Takt (#46): sobald Soldaten + Schiff + erreichbares Ziel da
## sind, lädt das Schiff die Soldaten und sticht in See.
func _tick_raid_prep(st: Storage) -> void:
	var b: WorldState.Building = state.buildings.get(st.idx)
	if b == null or b.garrison <= 0:
		return  # noch keine Soldaten in der Garnison — warten
	var ship: Ship = null
	for s in ships:
		if s.state == SHIP_IDLE and not s.expedition and not s.raid and s.home == st.flag_idx:
			ship = s
			break
	if ship == null:
		return  # kein Schiff am Hafen — warten
	var tgt := _nearest_enemy_harbor(st)
	if tgt == null:
		return  # kein erreichbares Ziel — warten
	var src_dock := _harbor_dock(st)
	var tgt_dock := state.dock_node(tgt.pos)
	var path := state.find_sea_path(src_dock, tgt_dock)
	if path.is_empty():
		return
	var n: int = mini(b.garrison, SHIP_CAPACITY)
	b.garrison -= n
	state.recompute_territory()
	ship.raid = true
	ship.raid_soldiers = n
	ship.attack_building = state.map.idx(tgt.pos.x, tgt.pos.y)
	ship.dest = -1
	ship.path = path
	ship.path_i = 1 if path.size() > 1 else 0
	ship.state = SHIP_SAILING
	st.raid_prep = false
	dirty = true


## Schiff hat den feindlichen Hafen erreicht: Soldaten gehen von Bord und greifen an
## (#46). Übersteht der Angriff die Verteidigung, wechselt der Hafen den Besitzer und die
## übrigen Soldaten bilden die neue Garnison — Brückenkopf auf der Insel.
func _resolve_sea_raid(s: Ship) -> void:
	var tgt: WorldState.Building = state.buildings.get(s.attack_building)
	var n := s.raid_soldiers
	s.raid = false
	s.raid_soldiers = 0
	s.attack_building = -1
	s.state = SHIP_IDLE
	s.path = []
	s.path_i = 0
	if tgt == null or n <= 0:
		dirty = true
		return
	if tgt.owner == s.owner:
		# Inzwischen schon eigen → Soldaten verstärken die Garnison.
		tgt.garrison = mini(tgt.garrison + n, maxi(tgt.capacity, 1))
		state.recompute_territory()
		dirty = true
		return
	# Gefecht: jeder mitgebrachte Soldat landet einen Treffer (stärkster Verteidiger zäh, #52).
	while n > 0 and tgt.garrison > 0:
		_damage_defender(tgt)
		n -= 1
	if tgt.garrison <= 0:
		# Erobert → Besitzerwechsel; verbleibende Angreifer bilden die Garnison (Gefreite).
		tgt.owner = s.owner
		tgt.garrison = clampi(n, 1, maxi(tgt.capacity, 1))
		tgt.ranks = [tgt.garrison, 0, 0, 0, 0]
		tgt.def_hp = 0
		var f := state.flag_at(tgt.flag_pos)
		if f != null:
			f.owner = s.owner
		resync()  # Simulation/Lager an neuen Besitzer anpassen
		s.home = state.map.idx(tgt.flag_pos.x, tgt.flag_pos.y)
	state.recompute_territory()
	dirty = true


## Startet eine Expedition (#46): ein am Hafen liegendes Schiff lädt Baumaterial und segelt
## zum nächsten erreichbaren leeren Hafenpunkt derselben See, um dort einen Hafen zu gründen.
## Liefert "" bei Erfolg oder einen Fehlertext (für die UI).
func start_expedition(harbor_flag: int, owner := 0) -> String:
	var src := _storage_by_flag(harbor_flag)
	if src == null:
		return "Kein Hafen."
	if int(src.stock.get(Goods.BOARDS, 0)) < EXPEDITION_BOARDS \
			or int(src.stock.get(Goods.STONE, 0)) < EXPEDITION_STONES:
		return "Zu wenig Material (%d Bretter, %d Steine nötig)." % [EXPEDITION_BOARDS, EXPEDITION_STONES]
	var ship: Ship = null
	for s in ships:
		if s.state == SHIP_IDLE and not s.expedition and s.home == harbor_flag:
			ship = s
			break
	if ship == null:
		return "Kein Schiff am Hafen."
	var src_dock := _harbor_dock(src)
	if src_dock.x < 0:
		return "Kein Andockknoten."
	var src_comp := state.sea_component_at(src_dock.x, src_dock.y)
	var best_point := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	for p in state.map.harbor_point_list():
		if _harbor_at_point(p):
			continue
		var dock := state.dock_node(p)
		if dock.x < 0 or state.sea_component_at(dock.x, dock.y) != src_comp:
			continue
		var path := state.find_sea_path(src_dock, dock)
		if path.is_empty():
			continue
		if best_path.is_empty() or path.size() < best_path.size():
			best_path = path
			best_point = p
	if best_point.x < 0:
		return "Kein erreichbarer freier Hafenpunkt."
	src.stock[Goods.BOARDS] = int(src.stock[Goods.BOARDS]) - EXPEDITION_BOARDS
	src.stock[Goods.STONE] = int(src.stock[Goods.STONE]) - EXPEDITION_STONES
	ship.expedition = true
	ship.target_point = best_point
	ship.dest = -1
	ship.path = best_path
	ship.path_i = 1 if best_path.size() > 1 else 0
	ship.state = SHIP_SAILING
	return ""


## Schiff hat den Ziel-Hafenpunkt erreicht: gründet dort einen Hafen (Kolonie) und macht
## ihn zu seinem neuen Heimathafen.
func _found_harbor(s: Ship) -> void:
	var b := state.found_harbor(s.target_point, s.owner)
	s.expedition = false
	s.target_point = Vector2i(-1, -1)
	s.cargo.clear()
	s.path = []
	s.path_i = 0
	s.state = SHIP_IDLE
	if b != null:
		_register_storage(state.map.idx(b.pos.x, b.pos.y), b)
		s.home = state.map.idx(b.flag_pos.x, b.flag_pos.y)
		if s.owner == 0:
			state.reveal_around(b.pos.x, b.pos.y, SHIP_VISION)
	dirty = true


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
	# Nicht-HQ-Lager (Hafen/Lagerhaus, #46): auf die Lagerflagge legen — der Tür-Träger holt
	# es herein. Früher fiel das fälschlich ins HQ-Lager (Material ging "verloren").
	var st := _storage_by_flag(flag_idx)
	if st != null:
		st.incoming[g.type] = maxi(0, int(st.incoming.get(g.type, 0)) - 1)
		_push_good(flag_idx, g)
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
			# #68: Bei aktiver Outbox-Option ruht der Tür-Träger für den AUSGANG — dann holen
			# ausschließlich die Straßenträger die Ware durch die Tür (kein Konkurrenzbetrieb
			# zwischen Tür- und Straßenträger). Eingänge, die ausnahmsweise an der Flagge
			# liegen geblieben sind, holt er weiterhin als Notnagel herein.
			if not output_via_carrier and not st.outbox.is_empty() and goods_on_flag(fi) < FLAG_CAP:
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
	var k := _best_good_index(queue, flag_idx, target_flag_idx)
	if k < 0:
		return null
	var g: Good = queue[k]
	queue.remove_at(k)
	return g


func _peek_good_for(flag_idx: int, target_flag_idx: int):
	var queue: Array = flag_goods.get(flag_idx, [])
	var k := _best_good_index(queue, flag_idx, target_flag_idx)
	return queue[k] if k >= 0 else null


## Index der Ware in [queue], die als Nächstes Richtung [target_flag_idx] befördert
## wird: unter allen passenden (nächster Hop == Ziel) die mit der höchsten Transport-
## Priorität (#43); bei Gleichstand die zuerst Wartende (FIFO). -1, wenn keine passt.
func _best_good_index(queue: Array, flag_idx: int, target_flag_idx: int) -> int:
	var best := -1
	var best_rank := 0
	for k in queue.size():
		var g: Good = queue[k]
		if _next_hop(flag_idx, g.dest) != target_flag_idx:
			continue
		var rank := _transport_rank(g.type)
		if best < 0 or rank < best_rank:
			best = k
			best_rank = rank
	return best


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
	if c.dphase != D_NONE and c.dflag >= 0:
		# Tür-Exkursion (#66): Position zwischen Flagge (dt 0) und Tür (dt 1). Die exakte
		# Türlage kennt nur das Rendering (entrance_offset); hier reicht die Flagge als
		# sichere Näherung (nur für Stray-Spawn, falls die Straße mitten im Gang wegfällt).
		return state.map.node_world(c.dflag % state.map.width, c.dflag / state.map.width)
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
	if bs.planing:
		return "%s — %s" % [s, "Planierer ebnet ein ..." if bs.staffed else "Planierer kommt vom HQ ..."]
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
		s += "  Garnison %d/%d" % [bld.garrison, bld.capacity]
		var rtext := garrison_rank_text(bld)
		if rtext != "":
			s += "  [%s]" % rtext
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
		if bs.planing:
			info.status = "Planieren"
			info.warning = "Planierer ebnet ein ..." if bs.staffed else "Planierer kommt vom HQ ..."
			return info
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
				if String(bs.def.get("resource", "")) == "water":
					info.warning = "Keine Fische in Reichweite"
				elif bool(bs.def.get("needs_water", false)):
					info.warning = "Kein Wasser in Reichweite"
				else:
					info.warning = "Kein Rohstoff in Reichweite"
			IDLE_NO_OUTPUT: info.warning = "Kein Werkzeug ausgewählt (alle Prioritäten 0)"
	return info


## Hat dieses Gebäude gerade einen sichtbaren, herumlaufenden Arbeiter?
func has_worker(bs: BState) -> bool:
	if bs.wphase == WK_DROP_OUT or bs.wphase == WK_DROP_BACK:
		return true  # Arbeiter trägt fertige Ware zur Flagge (#66)
	return bs.producing and bs.worker_target.x >= 0 \
		and (bs.wphase == WK_OUT or bs.wphase == WK_WORK or bs.wphase == WK_BACK)


## Ware, die der Arbeiter gerade sichtbar trägt (#66), sonst -1.
func worker_carry(bs: BState) -> int:
	return bs.carry_good if bs.wphase == WK_DROP_OUT else -1


## Sichtbarer Arbeiterweg als Polylinie: aus der Tür zum Flaggenknoten, dann zum
## Arbeitsknoten. So tritt der Arbeiter wie in S2 vorne an der Flagge aus seinem Haus,
## statt schnurgerade vom Hausmittelpunkt quer durchs eigene Gebäude zu laufen.
func _worker_path(bs: BState) -> Array:
	return [
		state.map.node_world(bs.bld.pos.x, bs.bld.pos.y),           # Tür/Bodenknoten
		state.map.node_world(bs.bld.flag_pos.x, bs.bld.flag_pos.y), # Eingangsflagge
		state.map.node_world(bs.worker_target.x, bs.worker_target.y),
	]


## Punkt + Laufrichtung auf einer Polylinie bei Bogenlängen-Anteil [param f] (0..1).
func _sample_path(pts: Array, f: float) -> Array:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	if total <= 0.0:
		return [pts[0], Vector2.ZERO]
	var d: float = clampf(f, 0.0, 1.0) * total
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		if d <= seg or i == pts.size() - 2:
			return [a.lerp(b, clampf(d / maxf(seg, 0.0001), 0.0, 1.0)), b - a]
		d -= seg
	return [pts[pts.size() - 1], Vector2.ZERO]


## Weltposition des Arbeiters über die Arbeitsphasen (entlang Tür→Flagge→Ziel).
func worker_world(bs: BState) -> Vector2:
	var prog: float = clampf(1.0 - (bs.ph_t / maxf(bs.ph_total, 1.0)), 0.0, 1.0)
	match bs.wphase:
		WK_OUT:
			return _sample_path(_worker_path(bs), prog)[0]
		WK_WORK:
			return state.map.node_world(bs.worker_target.x, bs.worker_target.y)
		WK_BACK:
			return _sample_path(_worker_path(bs), 1.0 - prog)[0]
		WK_DROP_OUT:  # Tür → Flagge (Ausgang tragen, #66)
			return _sample_path(_worker_haul_path(bs), prog)[0]
		WK_DROP_BACK:  # Flagge → Tür (leer zurück, #66)
			return _sample_path(_worker_door_path(bs), 1.0 - prog)[0]
	return state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)


func worker_facing(bs: BState) -> Vector2:
	var prog: float = clampf(1.0 - (bs.ph_t / maxf(bs.ph_total, 1.0)), 0.0, 1.0)
	match bs.wphase:
		WK_OUT:
			return _sample_path(_worker_path(bs), prog)[1]
		WK_WORK:
			var flag := state.map.node_world(bs.bld.flag_pos.x, bs.bld.flag_pos.y)
			return state.map.node_world(bs.worker_target.x, bs.worker_target.y) - flag
		WK_BACK:
			return -(_sample_path(_worker_path(bs), 1.0 - prog)[1])
		WK_DROP_OUT:
			return _sample_path(_worker_haul_path(bs), prog)[1]
		WK_DROP_BACK:
			return -(_sample_path(_worker_door_path(bs), 1.0 - prog)[1])
	return Vector2.ZERO


## Kurzweg Tür↔Flagge für den leeren Rückweg ins Haus (#66).
func _worker_door_path(bs: BState) -> Array:
	return [
		state.map.node_world(bs.bld.pos.x, bs.bld.pos.y),            # Tür/Bodenknoten
		state.map.node_world(bs.bld.flag_pos.x, bs.bld.flag_pos.y),  # Eingangsflagge
	]


## Trag-Weg zum Ablegen: vom Arbeitsplatz (Baum/Feld) bzw. der Tür direkt zur Flagge
## (#66). Beim Holzfäller/Bauern trägt der Arbeiter so die Ernte vom Arbeitsplatz zur
## Flagge, statt erst leer ins Haus und dann wieder raus.
func _worker_haul_path(bs: BState) -> Array:
	var s := _worker_haul_start(bs)
	return [
		state.map.node_world(s.x, s.y),
		state.map.node_world(bs.bld.flag_pos.x, bs.bld.flag_pos.y),  # Eingangsflagge
	]


# --- Sichtbare Bau-/Planier-Figur an der Baustelle (#49) ---
# In S2 ist der Bauarbeiter bzw. Planierer die GANZE Arbeitszeit an der Baustelle zu
# sehen, nicht nur auf dem Anmarsch. Solange die Baustelle besetzt ist, liefert das hier
# Position/Blickrichtung einer Figur, die der Renderer zeichnet.

## Ist gerade eine sichtbare Figur an dieser Baustelle (Bauarbeiter oder Planierer)?
func has_build_figure(bs: BState) -> bool:
	return bs.is_construction and bs.staffed


## Umrundet die Figur die Baustelle (Planierer) oder werkelt sie am Bau (Bauarbeiter)?
func build_figure_is_planer(bs: BState) -> bool:
	return bs.planing


## Weltposition der Bau-/Planier-Figur.
func build_figure_world(bs: BState) -> Vector2:
	var b := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
	if bs.planing:
		# Planierer laeuft punktweise zu den Nachbarknoten und arbeitet dort.
		var from := state.map.node_world(bs.plan_from.x, bs.plan_from.y)
		var to := state.map.node_world(bs.plan_to.x, bs.plan_to.y)
		if bs.plan_phase == PLAN_PHASE_WALK:
			var prog: float = clampf(1.0 - float(bs.plan_step_t) / maxf(float(bs.plan_step_total), 1.0), 0.0, 1.0)
			return from.lerp(to, prog)
		var swing := sin(float(bs.plan_step_total - bs.plan_step_t) * 0.35)
		return to + Vector2(swing * 2.0, -2.0)
	# Bauarbeiter werkelt seitlich am Bau (kleine Pendelbewegung über den Fortschritt).
	var sway := sin(float(bs.construct_progress) * 0.4)
	return b + Vector2(sway * 7.0 - 6.0, -4.0)


## Blickrichtung der Bau-/Planier-Figur (für die Lauf-/Werkel-Animation).
func build_figure_facing(bs: BState) -> Vector2:
	if bs.planing:
		var from := state.map.node_world(bs.plan_from.x, bs.plan_from.y)
		var to := state.map.node_world(bs.plan_to.x, bs.plan_to.y)
		if bs.plan_phase == PLAN_PHASE_WALK:
			return to - from
		var b := state.map.node_world(bs.bld.pos.x, bs.bld.pos.y)
		return b - to
	return Vector2(sin(float(bs.construct_progress) * 0.4), 0.15)
