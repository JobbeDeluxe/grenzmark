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
const RES_RADIUS := 6          # Suchradius für Baum/Stein/Pflanzplatz
const ORE_RADIUS := 4          # Suchradius für Erz / Wasser
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


# Tür↔Flagge-Träger (nur HQ/Lager): bewegt Waren zwischen Gebäudetür und Flagge.
enum { H_IDLE, H_OUT, H_FETCH, H_IN, H_RETURN }

# Arbeiter-Phasen eines Ressourcen-Gebäudes (konstante Laufgeschwindigkeit):
# leer wartend → Hinweg → Aktion am Ziel → Rückweg → Pause am Gebäude.
enum { WK_IDLE, WK_OUT, WK_WORK, WK_BACK, WK_WAIT }


class HouseCarrier:
	extends RefCounted
	var t := 0.0             # 0 = Tür, 1 = Flagge
	var state := 0           # H_*
	var carrying: Good = null


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
	var out_stock := 0
	var worker_target := Vector2i(-1, -1)  # Knoten, zu dem der Arbeiter geht
	var consumed_mid := false              # Ressourcen-Aktion am Wendepunkt erledigt?
	var wphase := 0                        # WK_* — aktuelle Arbeiter-Phase
	var ph_t := 0.0                        # verbleibende Ticks der aktuellen Phase
	var ph_total := 1.0                    # Gesamtticks der aktuellen Phase (Interpolation)
	var staffed := false                   # Arbeiter ist vom HQ angekommen?
	var worker_sent := false               # Arbeiter wurde schon angefordert?
	var stopped := false                   # Produktion vom Spieler angehalten?


var state: WorldState
var carriers: Dictionary = {}        # Road -> Carrier
var bstates: Dictionary = {}         # building idx -> BState
var flag_to_building: Dictionary = {}# flag idx -> building idx
var flag_goods: Dictionary = {}      # flag idx -> Array[Good]
var hq_flag := -1
var hq_idx := -1
var hq_stock: Dictionary = {}        # good -> Anzahl
var hq_outbox: Array = []             # Waren, die der HQ-Träger noch zur Flagge bringt
var hq_house: HouseCarrier = null     # Tür↔Flagge-Träger des HQ
var soldiers := 0                    # ausgebildete Soldaten im HQ (Reserve)
var ai_enabled := true               # Gegner-KI aktiv? (zum Testen abschaltbar)
var ai: AIBase = null                # austauschbare Gegner-KI (Plugin)
var marchers: Array[Marcher] = []    # gerade marschierende Soldaten
var _inc_soldiers: Dictionary = {}   # building idx -> unterwegs befindliche Soldaten
var dirty := false                   # Karte muss neu gezeichnet werden

var _hq_inited := false
var _soldier_timer := SOLDIER_TICKS
var _promo_timer := PROMO_TICKS
var _cata_timer := CATAPULT_TICKS
var _growing_trees: Dictionary = {} # map idx -> Restticks bis zur nächsten Baumstufe


func _init(world_state: WorldState) -> void:
	state = world_state
	ai = DefaultAI.new()  # Standard-Gegner-KI (austauschbar über world)
	_init_tree_growth_from_map()


# --------------------------------------------------------------------------
#  Synchronisation (nach jedem Bauen/Abreißen)
# --------------------------------------------------------------------------

func resync() -> void:
	# Träger ↔ Straßen
	for r in state.roads:
		if not carriers.has(r):
			var c := Carrier.new()
			c.road = r
			carriers[r] = c
	for r in carriers.keys():
		if not state.roads.has(r):
			# Straße entfernt/geteilt: trägt der Träger gerade eine Ware, darf sie
			# NICHT verschwinden — sonst bleibt bs.incoming hängen und es wird nie
			# nachgefordert. Ware zurück ins Netz geben (läuft sofort weiter).
			var old: Carrier = carriers[r]
			if old.carrying != null:
				_return_carried_good(old)
			carriers.erase(r)
	# Noch unbesetzte Straßen versuchen, vom HQ aus zu besetzen (kein Fallback —
	# ohne HQ-Verbindung bleibt die Straße unbesetzt, bis sie verbunden ist).
	for r in carriers:
		var c: Carrier = carriers[r]
		if not c.active and not c.dispatched:
			_dispatch_carrier(c)

	# Gebäudezustände ↔ Gebäude
	flag_to_building.clear()
	hq_flag = -1
	hq_idx = -1
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != 0:
			continue  # Gegner-Gebäude werden nicht simuliert
		if b.is_hq:
			hq_idx = i
			hq_flag = state.map.idx(b.flag_pos.x, b.flag_pos.y)
			if not _hq_inited:
				_init_hq_stock()
				_hq_inited = true
			if hq_house == null:
				hq_house = HouseCarrier.new()
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
			bstates[i] = bs
		else:
			bstates[i].bld = b
	for i in bstates.keys():
		if not state.buildings.has(i) or state.buildings[i].owner != 0:
			bstates.erase(i)

	for fi in flag_goods.keys():
		if not state.flags.has(fi):
			flag_goods.erase(fi)

	state.recompute_territory()
	state.recompute_visibility()
	dirty = true


func _init_hq_stock() -> void:
	hq_stock = {
		Goods.BOARDS: 30, Goods.STONE: 30, Goods.WOOD: 12,
		Goods.TOOLS: 12, Goods.BREAD: 8, Goods.FISH: 6, Goods.WATER: 6,
		Goods.COAL: 6, Goods.GRAIN: 6, Goods.FLOUR: 4, Goods.IRON: 4,
		Goods.SWORD: 3,
	}
	soldiers = 8  # Anfangsbesatzung, damit Militärgebäude sofort gehalten werden


# --------------------------------------------------------------------------
#  Ein Tick
# --------------------------------------------------------------------------

func tick() -> void:
	if ai_enabled and ai != null:
		ai.think(self, 1)
	_tick_tree_growth()
	_tick_soldiers()
	_tick_promotions()
	_tick_catapults()
	_tick_house_carrier()
	for i in state.buildings:
		if bstates.has(i):
			_tick_building(bstates[i])
	for r in state.roads:
		if carriers.has(r):
			_tick_carrier(carriers[r])


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


## Schwerter ausbilden, Marschierende bewegen, neue Soldaten entsenden.
func _tick_soldiers() -> void:
	if hq_flag < 0:
		return
	_soldier_timer -= 1
	if _soldier_timer <= 0:
		_soldier_timer = SOLDIER_TICKS
		if hq_stock.get(Goods.SWORD, 0) > 0:
			hq_stock[Goods.SWORD] = hq_stock[Goods.SWORD] - 1
			soldiers += 1
	_tick_marchers()
	if soldiers <= 0:
		return
	var w := state.map.width
	var hq_pos := Vector2i(hq_flag % w, hq_flag / w)
	for i in state.buildings:
		if not bstates.has(i):
			continue
		var bs: BState = bstates[i]
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


## Flaggenposition des eigenen HQ (nicht der Gebäudeknoten!).
func _hq_flag_pos() -> Vector2i:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq and b.owner == 0:
			return b.flag_pos
	return Vector2i(-1, -1)


## Schickt einen Träger vom HQ zur neuen Straße. OHNE HQ-Verbindung passiert
## nichts — die Straße bleibt unbesetzt, bis sie (später) verbunden ist.
func _dispatch_carrier(c: Carrier) -> void:
	var hq := _hq_flag_pos()
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
	c.dispatched = true
	if best.size() < 2:
		_activate_carrier(c.road, best_end)  # HQ-Flagge ist schon das Straßenende
		return
	var m := Marcher.new()
	m.purpose_carrier = true
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
	if bs.stopped:
		_ship_outputs(bs)  # vorhandene Ausgänge noch abtransportieren
		return
	_request_inputs(bs)
	_tick_work(bs)
	_ship_outputs(bs)


## Produktion eines Gebäudes anhalten/fortsetzen.
func toggle_production(bld: WorldState.Building) -> bool:
	var bs: BState = bstates.get(state.map.idx(bld.pos.x, bld.pos.y))
	if bs == null:
		return false
	bs.stopped = not bs.stopped
	return bs.stopped


## Schickt einen Arbeiter vom HQ, der das Gebäude besetzt (dann läuft Produktion).
func _dispatch_worker(bs: BState) -> void:
	var hq := _hq_flag_pos()
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
	bs.worker_sent = true
	var m := Marcher.new()
	m.purpose_worker = true
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
		var desired: int = int(inputs[g]) * 2
		var have: int = bs.delivered.get(g, 0) + bs.incoming.get(g, 0)
		if have < desired:
			_request_from_hq(bs, g, desired - have)


func _request_from_hq(bs: BState, g: int, amount: int) -> void:
	for k in amount:
		if hq_flag < 0 or hq_stock.get(g, 0) <= 0:
			return
		if _next_hop(hq_flag, bs.flag_idx) < 0:
			return
		if hq_outbox.size() >= FLAG_CAP:
			return
		hq_stock[g] = hq_stock[g] - 1
		bs.incoming[g] = bs.incoming.get(g, 0) + 1
		# Ware wartet im HQ; der Tür-Träger bringt sie zur Flagge hinaus.
		var good := Good.new()
		good.type = g
		good.dest = bs.flag_idx
		hq_outbox.append(good)


# --- Produktion ---

func _tick_work(bs: BState) -> void:
	var output: int = bs.def.get("output", -1)
	var resource: String = String(bs.def.get("resource", ""))
	if output == -1 and resource != "plant_tree":
		return  # Lager / Militär: keine Produktion
	var gather := resource != ""   # läuft der Arbeiter zu einem Zielknoten?

	match bs.wphase:
		WK_IDLE:
			if bs.out_stock >= OUT_CAP:
				return
			if not _has_inputs(bs):
				return
			if gather:
				var tgt := _resource_target(bs)
				if tgt.x < 0:
					return  # nichts zu tun (kein fällbarer Baum / Pflanzplatz)
				bs.worker_target = tgt
				_consume_inputs(bs)
				bs.producing = true
				_enter_wphase(bs, WK_OUT, _worker_walk_ticks(bs, tgt))
			else:
				# Stationäre Produktion (z. B. Sägewerk): kein Weg, nur Arbeitszeit.
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
					if output != -1:
						bs.out_stock += 1
					_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_BACK:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				if output != -1:
					bs.out_stock += 1
				_enter_wphase(bs, WK_WAIT, float(Tuning.work_wait(bs.bld.def_id, resource)))
		WK_WAIT:
			bs.ph_t -= 1.0
			if bs.ph_t <= 0.0:
				bs.producing = false
				bs.worker_target = Vector2i(-1, -1)
				bs.wphase = WK_IDLE


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


func _has_inputs(bs: BState) -> bool:
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		if bs.delivered.get(g, 0) < int(inputs[g]):
			return false
	return true


func _consume_inputs(bs: BState) -> void:
	var inputs: Dictionary = bs.def.get("inputs", {})
	for g in inputs:
		bs.delivered[g] = bs.delivered.get(g, 0) - int(inputs[g])


## Knoten, zu dem der Arbeiter für diesen Produktionszyklus laufen muss.
func _resource_target(bs: BState) -> Vector2i:
	match String(bs.def.get("resource", "")):
		"tree": return _find_mature_tree(bs.bld.pos, RES_RADIUS)
		"stone": return _find_object(bs.bld.pos, MapData.MO_STONE, RES_RADIUS)
		"ore": return _find_ore(bs.bld.pos, int(bs.def.get("mineral", -1)), ORE_RADIUS)
		"plant_tree": return _find_plant_spot(bs.bld.pos)
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
				var stage := state.map.stone_stage_at(n.x, n.y)
				if stage > MapData.STONE_SMALL:
					state.map.set_stone_stage(n.x, n.y, stage - 1)
				else:
					state.map.clear_map_object(n.x, n.y)
				dirty = true
		"ore":
			if state.map.map_object(n.x, n.y) == MapData.MO_ORE:
				state.map.clear_map_object(n.x, n.y)
				dirty = true
		"plant_tree":
			if not state.has_object(n.x, n.y):
				# Förster pflanzt einen SETZLING, der über mehrere Stufen wächst.
				state.map.set_map_object(n.x, n.y, MapData.MO_TREE)
				state.map.set_tree_stage(n.x, n.y, MapData.TREE_SEED)
				state.map.set_tree_type(n.x, n.y, state.map.deterministic_tree_type(n.x, n.y))
				_growing_trees[state.map.idx(n.x, n.y)] = float(Tuning.tree_growth_ticks(MapData.TREE_SEED))
				dirty = true


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
				for t in state.map.terrains_around(x, y):
					if Terrain.is_water(t):
						return Vector2i(x, y)
	return Vector2i(-1, -1)


func _ship_outputs(bs: BState) -> void:
	var output: int = bs.def.get("output", -1)
	if output == -1:
		return
	while bs.out_stock > 0:
		if hq_flag < 0 or _next_hop(bs.flag_idx, hq_flag) < 0:
			return
		var q: Array = flag_goods.get(bs.flag_idx, [])
		if q.size() >= FLAG_CAP:
			return
		var good := Good.new()
		good.type = output
		good.dest = hq_flag
		_push_good(bs.flag_idx, good)
		bs.out_stock -= 1


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


## Erz der passenden Sorte suchen (mineral < 0 = beliebiges Erz).
func _find_ore(center: Vector2i, mineral: int, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := center.x + dx
				var y := center.y + dy
				if not state.map.in_bounds(x, y):
					continue
				if WorldState.hex_distance(center, Vector2i(x, y)) != r:
					continue
				if state.map.map_object(x, y) != MapData.MO_ORE:
					continue
				if mineral < 0 or state.map.ore_kind_at(x, y) == mineral:
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

## Eine Ware, deren Träger gerade verschwindet (Straße geteilt/abgerissen), wieder
## ins Netz geben: bevorzugt auf ein noch existierendes Straßenende, das Richtung
## Ziel zeigt — so wird sie sofort weiterbefördert statt verloren zu gehen.
func _return_carried_good(c: Carrier) -> void:
	var g: Good = c.carrying
	c.carrying = null
	if g == null:
		return
	for endp in [c.road.b, c.road.a]:
		var fi := state.map.idx(endp.x, endp.y)
		if state.flags.has(fi) and _next_hop(fi, g.dest) >= 0:
			_push_good(fi, g)
			return
	# Nicht mehr zustellbar (Ziel abgeschnitten) → zurück ins Lager und beim
	# Zielgebäude als „nicht mehr unterwegs" verbuchen, damit neu angefordert wird.
	if flag_to_building.has(g.dest):
		var bs: BState = bstates.get(flag_to_building[g.dest])
		if bs != null:
			bs.incoming[g.type] = maxi(0, bs.incoming.get(g.type, 0) - 1)
	if hq_flag >= 0:
		hq_stock[g.type] = hq_stock.get(g.type, 0) + 1


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


func _tick_house_carrier() -> void:
	if hq_house == null or hq_flag < 0:
		return
	var h := hq_house
	match h.state:
		H_IDLE:  # an der Tür
			if not hq_outbox.is_empty() and goods_on_flag(hq_flag) < FLAG_CAP:
				h.carrying = hq_outbox.pop_front()
				h.state = H_OUT
			elif _has_hq_incoming():
				h.state = H_FETCH
		H_OUT:   # Ware Tür → Flagge
			h.t = minf(h.t + HOUSE_SPEED, 1.0)
			if h.t >= 1.0:
				_push_good(hq_flag, h.carrying)
				h.carrying = null
				var g = _take_hq_incoming()
				h.carrying = g
				h.state = H_IN if g != null else H_RETURN
		H_FETCH: # leer Tür → Flagge, um Eingang zu holen
			h.t = minf(h.t + HOUSE_SPEED, 1.0)
			if h.t >= 1.0:
				var g = _take_hq_incoming()
				h.carrying = g
				h.state = H_IN if g != null else H_RETURN
		H_IN:    # Ware Flagge → Tür (ins Lager)
			h.t = maxf(h.t - HOUSE_SPEED, 0.0)
			if h.t <= 0.0:
				if h.carrying != null:
					hq_stock[h.carrying.type] = hq_stock.get(h.carrying.type, 0) + 1
				h.carrying = null
				h.state = H_IDLE
		H_RETURN: # leer Flagge → Tür
			h.t = maxf(h.t - HOUSE_SPEED, 0.0)
			if h.t <= 0.0:
				h.state = H_IDLE


## Erste an der HQ-Flagge wartende Ware, die ins Lager soll (dest == HQ-Flagge).
func _has_hq_incoming() -> bool:
	for g in flag_goods.get(hq_flag, []):
		if g.dest == hq_flag:
			return true
	return false


func _take_hq_incoming():
	var q: Array = flag_goods.get(hq_flag, [])
	for k in q.size():
		if q[k].dest == hq_flag:
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
	var output: int = bs.def.get("output", -1)
	if output != -1:
		s += "  → %s (Ausgang %d)" % [Goods.name_of(output), bs.out_stock]
	if int(bs.def.get("influence", 0)) > 0:
		s += "  Garnison %d/%d  Rang +%d" % [bld.garrison, bld.capacity, bld.promotions]
	return s


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
