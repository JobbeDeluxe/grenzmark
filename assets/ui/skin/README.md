# UI-Skin (austauschbare 9-Patch-Grafiken)

Hier liegen die UI-Hintergründe als **9-Patch-PNGs**. Du kannst jede Datei durch
eine eigene Grafik ersetzen, um die Optik ans Original (Holz/Pergament) anzunähern —
ohne Code zu ändern.

## Dateien
| Datei                 | Verwendung                          |
|-----------------------|-------------------------------------|
| `panel.png`           | Standard-Fensterhintergrund         |
| `panel_dark.png`      | dunkles Panel (z. B. Unterbereiche) |
| `panel_header.png`    | Kopfzeilen-Hintergrund              |
| `button.png`          | Button normal                       |
| `button_hover.png`    | Button bei Maus-Hover               |
| `button_pressed.png`  | Button gedrückt                     |
| `button_disabled.png` | Button deaktiviert                  |

## 9-Patch — wichtig
Eine 9-Patch-Grafik wird in 3×3 Bereiche geteilt: die **Ecken bleiben unverändert**,
die **Ränder** werden in eine Richtung gedehnt, die **Mitte** in beide. So skaliert
ein kleines PNG sauber auf beliebig große Fenster.

- Die Eckbreite (in Pixeln) steuerst du in `assets/ui.json` unter `skin`:
  `patch_margin_left/top/right/bottom` (Standard 8).
- `content_margin` = Innenabstand zwischen Rahmen und Inhalt.
- Die mittleren Pixel sollten **gleichmäßig/kachelbar** sein, sonst „verschmiert" das
  Dehnen sichtbare Details. Lege Verzierungen in die **Ecken/Ränder** (< patch_margin).

## Empfohlene Größen
- Panels: ~32×32 px, Ecken 8 px.
- Buttons: ~24×24 px, Ecken 8 px.
Größer geht auch (mehr Detail), solange die Mitte kachelbar bleibt.

## An-/Ausschalten
In `assets/ui.json`:
```json
"skin": { "enabled": true, ... }
```
- `enabled: false` → flacher Farb-Fallback (aus `colors`).
- Fehlt eine einzelne Datei, wird **nur dafür** der Fallback genutzt.

## Nach dem Ersetzen
PNG austauschen, dann Godot einmal starten (importiert automatisch neu).
Die aktuell hier liegenden Dateien sind nur ein **Platzhalter-Set** zum Ersetzen.
