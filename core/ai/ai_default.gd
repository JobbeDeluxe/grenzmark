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
		if state._occ(x, y) != WorldState.OBJ_NONE:
			continue
		var bq := state.effective_bq(x, y)
		if bq < size or bq == WorldState.BQ_MINE:
			continue
		var nb := WorldState.Building.new()
		nb.pos = Vector2i(x, y)
		nb.size = size
		nb.def_id = id
		nb.influence = 0
		nb.owner = owner
		nb.under_construction = false
		nb.flag_pos = state.map.neighbor(x, y, Grid.SE)
		var bi := state.map.idx(x, y)
		state.buildings[bi] = nb
		state.occupied[bi] = WorldState.OBJ_BUILDING
		eco.dirty = true
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
		if state._occ(x, y) != WorldState.OBJ_NONE:
			continue
		var bq := state.effective_bq(x, y)
		if bq < WorldState.BQ_HUT or bq == WorldState.BQ_MINE:
			continue  # auf Bergen (BQ_MINE) keine Militärgebäude; Abstand beachtet
		var d := WorldState.hex_distance(Vector2i(x, y), target) if target.x >= 0 else 0
		if d < best_d:
			best_d = d
			best = Vector2i(x, y)
	if best.x < 0:
		return
	var nb := WorldState.Building.new()
	nb.pos = best
	nb.size = WorldState.BQ_HUT
	nb.def_id = "guardhouse"
	nb.influence = 5
	nb.owner = owner
	nb.under_construction = false
	nb.garrison = 0
	nb.capacity = 3
	nb.flag_pos = state.map.neighbor(best.x, best.y, Grid.SE)
	var bi := state.map.idx(best.x, best.y)
	state.buildings[bi] = nb
	state.occupied[bi] = WorldState.OBJ_BUILDING
	state.recompute_territory()
	eco.dirty = true


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
