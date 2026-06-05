# Austauschbare Gegner-KI

Die KI ist als Plugin gebaut. Eingebaut sind **Standard** und **Passiv**;
eigene KIs legst du einfach als `.gd`-Datei in **diesen Ordner** (`res://ai/`).
Sie werden beim Start automatisch gefunden und sind im Spiel mit Taste **J**
durchschaltbar (der Name steht oben in der Statusleiste).

## Eigene KI in 3 Schritten
1. `example_defender.gd` kopieren und umbenennen, z. B. `meine_ki.gd`.
2. `ai_name()` und `think()` anpassen.
3. Godot einmal öffnen (importiert das Skript) und im Spiel mit **J** wählen.

## Die Schnittstelle (`core/ai/ai_base.gd`)
```gdscript
extends AIBase

func ai_name() -> String:
    return "Mein Name"      # erscheint in der Auswahl

func think(eco: Economy, owner: int) -> void:
    # Wird jeden Simulations-Tick (30/s) aufgerufen.
    # owner = von dieser KI gesteuerter Besitzer (Gegner = 1).
    # Eigene Timer/Zustände als Member-Variablen halten.
    pass
```

## Was `eco` / der Zustand bietet (die wichtigsten Bausteine)
- `eco.state` — der `WorldState`:
  - `state.buildings` (Dictionary idx → Building mit `.pos, .owner, .influence,
    .is_hq, .garrison, .capacity, .under_construction, .flag_pos, .def_id`)
  - `state.territory` / `state.enemy_territory` (idx → true)
  - `state.compute_bq(x, y)`, `state._occ(x, y)`, `state.recompute_territory()`
  - `state.map` mit `width, height, idx(x,y), in_bounds(x,y), neighbor(x,y,dir)`
- `eco.hq_pos_of(owner)` — Position des HQ eines Besitzers (oder (-1,-1))
- `eco.send_attackers(src, tgt)` — Angriff: schickt die Garnison von `src`
  (eigenes Militärgebäude) gegen `tgt` (fremdes Gebäude); erobert bei Garnison 0
- `eco.dirty = true` — setzen, wenn sich die Karte sichtbar geändert hat
- `WorldState.hex_distance(a, b)` — Distanz zweier Knoten im Hex-Gitter

## Eigene Gebäude bauen (wie die Standard-KI expandiert)
```gdscript
var nb := WorldState.Building.new()
nb.pos = pos; nb.size = WorldState.BQ_HUT; nb.def_id = "guardhouse"
nb.influence = 5; nb.owner = owner; nb.under_construction = false
nb.garrison = 0; nb.capacity = 3
nb.flag_pos = state.map.neighbor(pos.x, pos.y, Grid.SE)
var bi := state.map.idx(pos.x, pos.y)
state.buildings[bi] = nb
state.occupied[bi] = WorldState.OBJ_BUILDING
state.recompute_territory(); eco.dirty = true
```

## Hinweise
- **Determinismus:** keine ungeseedete Zufälligkeit verwenden, sonst bricht
  späterer Lockstep-Multiplayer. Wenn Zufall nötig, festen Seed nutzen.
- `think()` läuft sehr oft — teure Suchen über eigene Timer (Tick-Zähler)
  drosseln, nicht jeden Tick.
- Vorbild für Verhalten: Die Siedler 2 / Return to the Roots.
