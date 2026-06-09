class_name DefaultAI
extends AIBase

## Standard-Gegner: bildet Soldaten aus, besetzt seine Militärgebäude,
## expandiert mit Wachhäusern Richtung Feind und greift in Reichweite an.

const TRAIN_TICKS := 180    # Basis-Intervall für einen Soldaten
const EXPAND_TICKS := 2200  # baut ein neues Wachhaus
const ATTACK_TICKS := 1500  # prüft Angriffe
const ECON_TICKS := 900     # baut ein Wirtschaftsgebäude
const GRACE_TICKS := 5400   # ~3 Min bei 30 Hz: erst danach greift die KI an
const ATTACK_MIN_GARRISON := 4  # nur ab dieser Garnison wird angegriffen
const MAX_MILITARY := 12    # Obergrenze Militärgebäude
const MAX_ECON := 10        # Obergrenze Wirtschaftsgebäude
# Wirtschaftsgebäude, die der Gegner zum Aufbau seiner Siedlung wählt.
const ECON_DEFS := ["woodcutter", "sawmill", "farm", "mill", "bakery",
	"well", "quarry", "brewery"]

var reserve := 4
var _train := TRAIN_TICKS
var _expand := EXPAND_TICKS
var _attack := ATTACK_TICKS
var _econ := ECON_TICKS
var _grace := GRACE_TICKS


func ai_name() -> String:
	return "Standard"


func think(eco: Economy, owner: int) -> void:
	var state := eco.state
	if eco.hq_pos_of(owner).x < 0:
		return

	# Soldaten ausbilden — mehr Wirtschaftsgebäude = schneller.
	_train -= 1
	if _train <= 0:
		var econ := _count(state, owner, false)
		_train = maxi(45, TRAIN_TICKS - 12 * econ)
		reserve = mini(reserve + 1, 50)

	# Eine Garnison pro Tick auffüllen.
	if reserve > 0:
		for i in state.buildings:
			var b: WorldState.Building = state.buildings[i]
			if b.owner != owner or b.is_hq or b.under_construction or b.influence <= 0:
				continue
			if b.garrison < b.capacity:
				b.garrison += 1
				reserve -= 1
				state.recompute_territory()
				eco.dirty = true
				break

	_econ -= 1
	if _econ <= 0:
		_econ = ECON_TICKS
		_do_build_economy(eco, owner)

	_expand -= 1
	if _expand <= 0:
		_expand = EXPAND_TICKS
		_do_expand(eco, owner)

	if _grace > 0:
		_grace -= 1
	_attack -= 1
	if _attack <= 0:
		_attack = ATTACK_TICKS
		if _grace <= 0:
			_do_attack(eco, owner)


## Zählt Gebäude des Besitzers: military=true → Militärgebäude, sonst Wirtschaft.
func _count(state: WorldState, owner: int, military: bool) -> int:
	var n := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != owner or b.is_hq:
			continue
		var is_mil := b.influence > 0
		if is_mil == military:
			n += 1
	return n


## Baut ein Wirtschaftsgebäude im Inneren des eigenen Gebiets.
func _do_build_economy(eco: Economy, owner: int) -> void:
	var state := eco.state
	if _count(state, owner, false) >= MAX_ECON:
		return
	var id: String = ECON_DEFS[_count(state, owner, false) % ECON_DEFS.size()]
	var bdef := BuildingCatalog.get_def(id)
	var size: int = bdef.get("size", WorldState.BQ_HUT)
	var area = state.territory if owner == 0 else state.enemy_territory
	for k in area:
		var x := int(k) % state.map.width
		var y := int(k) / state.map.width
		if not state.can_place_building(x, y, size, owner):
			continue
		var flag_pos := state.map.neighbor(x, y, Grid.SE)
		if not _can_connect_to_network(state, owner, flag_pos):
			continue
		if _place_ai_building(eco, owner, Vector2i(x, y), size, id, 0, 0, 0, false) != null:
			return


func _do_expand(eco: Economy, owner: int) -> void:
	var state := eco.state
	var count := 0
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner == owner and b.influence > 0 and not b.is_hq:
			count += 1
	if count >= MAX_MILITARY:
		return
	# Richtung Gegner (erster fremder HQ).
	var target := Vector2i(-1, -1)
	for o in [0, 1, 2, 3]:
		if o != owner:
			var hp := eco.hq_pos_of(o)
			if hp.x >= 0:
				target = hp
				break
	var border = state.territory if owner == 0 else state.enemy_territory
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for k in border:
		var x := int(k) % state.map.width
		var y := int(k) / state.map.width
		if not state.can_place_building(x, y, WorldState.BQ_HUT, owner):
			continue  # auf Bergen (BQ_MINE) keine Militärgebäude; Abstand beachtet
		var flag_pos := state.map.neighbor(x, y, Grid.SE)
		if not _can_connect_to_network(state, owner, flag_pos):
			continue
		var d := WorldState.hex_distance(Vector2i(x, y), target) if target.x >= 0 else 0
		if d < best_d:
			best_d = d
			best = Vector2i(x, y)
	if best.x < 0:
		return
	_place_ai_building(eco, owner, best, WorldState.BQ_HUT, "guardhouse", 5, 0, 3, false)


func _place_ai_building(eco: Economy, owner: int, pos: Vector2i, size: int,
		def_id: String, influence: int, garrison: int, capacity: int,
		is_hq: bool) -> WorldState.Building:
	var state := eco.state
	var nb := state.place_building(pos.x, pos.y, size, is_hq, def_id, influence, false, owner)
	if nb == null:
		return null
	nb.garrison = garrison
	nb.capacity = capacity
	_connect_to_network(eco, nb)
	state.recompute_territory()
	eco.resync()
	return nb


func _can_connect_to_network(state: WorldState, owner: int, flag_pos: Vector2i) -> bool:
	var hq := _hq_flag_pos(state, owner)
	if hq.x < 0:
		return false
	for fi in state.flags:
		var f: WorldState.Flag = state.flags[fi]
		if f.owner != owner or f.pos == flag_pos:
			continue
		if f.pos != hq and state.find_route(hq, f.pos).size() < 2:
			continue
		if not state.plan_road(f.pos, flag_pos, owner).is_empty():
			return true
	return false


func _connect_to_network(eco: Economy, b: WorldState.Building) -> void:
	if b.is_hq:
		return
	var state := eco.state
	var hq := _hq_flag_pos(state, b.owner)
	if hq.x < 0:
		return
	var best_from := Vector2i(-1, -1)
	var best_len := 1 << 30
	for fi in state.flags:
		var f: WorldState.Flag = state.flags[fi]
		if f.owner != b.owner or f.pos == b.flag_pos:
			continue
		if f.pos != hq and state.find_route(hq, f.pos).size() < 2:
			continue
		var path := state.plan_road(f.pos, b.flag_pos, b.owner)
		if path.is_empty():
			continue
		if path.size() < best_len:
			best_len = path.size()
			best_from = f.pos
	if best_from.x >= 0:
		state.build_road(best_from, b.flag_pos, b.owner)


func _hq_flag_pos(state: WorldState, owner: int) -> Vector2i:
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.is_hq and b.owner == owner:
			return b.flag_pos
	return Vector2i(-1, -1)


func _do_attack(eco: Economy, owner: int) -> void:
	var state := eco.state
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != owner or b.influence <= 0 or b.under_construction \
				or b.garrison < ATTACK_MIN_GARRISON:
			continue
		for j in state.buildings:
			var p: WorldState.Building = state.buildings[j]
			if p.owner == owner or p.influence <= 0 or p.under_construction:
				continue
			if WorldState.hex_distance(b.pos, p.pos) <= b.influence + p.influence + 2:
				eco.send_attackers(b, p)
				return
