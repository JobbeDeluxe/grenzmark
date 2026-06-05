extends AIBase

## BEISPIEL einer eigenen KI (liegt in res://ai/ und wird automatisch gefunden).
## "Verteidiger": besetzt nur die eigenen Militärgebäude, expandiert nicht und
## greift nie an. Kopiervorlage für eigene Strategien.
##
## Eigene KI bauen:
##  1. Diese Datei kopieren, umbenennen (z. B. res://ai/meine_ki.gd).
##  2. ai_name() und think() anpassen.
##  3. Im Spiel mit Taste J durchschalten.
## Mehr Details: ai/README.md

const TRAIN_TICKS := 120
var reserve := 8
var _train := TRAIN_TICKS


func ai_name() -> String:
	return "Verteidiger"


func think(eco: Economy, owner: int) -> void:
	var state := eco.state
	if eco.hq_pos_of(owner).x < 0:
		return
	_train -= 1
	if _train <= 0:
		_train = TRAIN_TICKS
		reserve = mini(reserve + 1, 60)
	if reserve <= 0:
		return
	# Nur Garnisonen auffüllen — keine Expansion, kein Angriff.
	for i in state.buildings:
		var b: WorldState.Building = state.buildings[i]
		if b.owner != owner or b.is_hq or b.under_construction or b.influence <= 0:
			continue
		if b.garrison < b.capacity:
			b.garrison += 1
			reserve -= 1
			state.recompute_territory()
			eco.dirty = true
			return
