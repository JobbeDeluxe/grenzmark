# Größen-Referenz: Original-S2 ↔ Grenzmark

Orientierung für eigene PNGs (Gebäude, Flaggen, Figuren, Waren, Ressourcen), damit
die Bebauung so **dicht** wirkt wie im Original. Quelle für die Original-Werte:
Return-to-the-Roots (`s25client`), die Open-Source-Reimplementierung von Die Siedler 2.

> Die **exakten** Pixelmaße einzelner Original-Sprites stecken in den (urheberrechtlich
> geschützten) LST-Grafikdateien und sind **nicht** im Quellcode. Was authentisch
> belegbar ist — und worauf es für die Dichte wirklich ankommt — ist die **Karten-
> Geometrie** und damit das Verhältnis „Sprite-Größe ↔ Knotenabstand". Genau das steht
> hier. Eigene Assets baut Grenzmark ohnehin selbst (frei lizenziert) — entscheidend ist
> die Proportion, nicht die absolute Pixelzahl.

---

## 1. Karten-Geometrie — der Maßstab für ALLES

| | Knotenabstand X | Knotenabstand Y | px / Höhenstufe | ungerade Zeile versetzt |
|---|---|---|---|---|
| **Original S2** (RTTR `gameData/MapConsts.h`) | **TR_W = 56** | **TR_H = 28** | 5 | +28 (½ TR_W) |
| **Grenzmark** (`core/grid.gd`) | TILE_W = 64 | TILE_H = 32 | 4 | +32 |

**Verhältnis Grenzmark / Original = 64⁄56 = 32⁄28 = 8⁄7 ≈ 1,143.**

- Ein Original-Sprite von *N* px entspricht in Grenzmark *N × 8⁄7* px bei **gleicher Dichte**.
- Umgekehrt: Grenzmark-px × 7⁄8 = „Original-Äquivalent".
- **Die wirklich wichtige Größe ist „Kacheln breit" = gezeichnete px ⁄ 64.** Sie ist
  skalenunabhängig — daran orientieren, nicht an absoluten Pixeln.

---

## 2. Anker & Fußabdruck — wo das Sprite sitzt

- Jedes Gebäude steht auf **einem** Knoten; die **Eingangsflagge** liegt am **SE-Nachbarn**.
- **Tür-Anker** (RTTR `gameData/DoorConsts.h`): der Punkt, an dem der Träger „in der Tür
  verschwindet", liegt je nach Gebäude/Volk bei Y ≈ **−13 … +19 px** relativ zum Knoten.
  Faustregel: **Sprite-Unterkante ≈ am Knoten**, das Sprite wächst nach **oben** (und etwas
  nach links).
- **Belegte Knoten** (= blockiert für Bau/Straße/Träger):
  - HUT / HOUSE / MINE → **1 Knoten** (nur der eigene).
  - CASTLE (HQ, Bauernhof, Schweinezucht, Festung) → **4 Knoten** (eigener + W/NW/NE).
    Das ist **originaltreu** (RTTR `noExtension`, `BlockingManner::Single`) — das große
    Sprite überdeckt genau diese oben-links liegenden Knoten.

---

## 3. Gebäude — Ist-Größen in Grenzmark

`gezeichnete Breite = Skalar × texture_scale` (global **texture_scale = 1,9**; HQ zusätzlich
**hq_scale = 1,35**). Kachel = 64 px. „Orig-Äquiv" = dieselbe Dichte im 56-px-Original.

| Gebäude | Kategorie | Skalar | gez. Breite px | **Kacheln breit** | Orig-Äquiv px (×7⁄8) |
|---|---|---|---|---|---|
| hq | CASTLE | 58 | 149 | 2,32 | 130 |
| fortress | CASTLE | 97 | 184 | 2,88 | 161 |
| farm | CASTLE | 69 | 131 | 2,05 | 115 |
| pigfarm | CASTLE | 68 | 129 | 2,02 | 113 |
| mill | HOUSE | 64 | 122 | 1,90 | 106 |
| slaughterhouse | HOUSE | 64 | 122 | 1,90 | 106 |
| brewery | HOUSE | 59 | 112 | 1,75 | 98 |
| bakery | HOUSE | 55 | 104 | 1,63 | 91 |
| smelter | HOUSE | 54 | 103 | 1,60 | 90 |
| watchtower | HOUSE | 53 | 101 | 1,57 | 88 |
| sawmill | HOUSE | 53 | 101 | 1,57 | 88 |
| smithy | HOUSE | 50 | 95 | 1,48 | 83 |
| coalmine | MINE | 50 | 95 | 1,48 | 83 |
| mint | HOUSE | 49 | 93 | 1,45 | 81 |
| toolmaker | HOUSE | 46 | 87 | 1,37 | 76 |
| goldmine | MINE | 43 | 82 | 1,28 | 71 |
| ironmine | MINE | 43 | 82 | 1,28 | 71 |
| granitemine | MINE | 43 | 82 | 1,28 | 71 |
| woodcutter | HUT | 37 | 70 | 1,10 | 62 |
| catapult | HOUSE | 31 | 59 | 0,92 | 52 |
| well | HUT | 20 | 38 | 0,59 | 33 |

---

## 4. Einordnung & Empfehlung (Dichte)

Original-Anhaltswerte, **relativ zum Knoten** (aus Screenshots/Community, ± grob):

| Klasse | Beispiele | Original ≈ Kacheln breit |
|---|---|---|
| Kleine Hütte | Holzfäller, Förster, Brunnen | ~1,0 – 1,2 |
| Mittleres Haus | Sägewerk, Mühle, Schmelze | ~1,3 – 1,6 |
| Großes Gebäude | Bauernhof, Festung, HQ | ~2,0 – 2,6 |

→ Grenzmark liegt v. a. bei **mittleren Häusern leicht über** dem Original (Sägewerk 1,57
statt ~1,3–1,5). Wer **dichter** will: mittlere Häuser ~10–20 % kleiner (Skalar senken
oder global `texture_scale`). **Achtung:** kleinere Gebäude → **Figuren ggf. auch kleiner**
(`unit_size`), sonst wirken die Menschen im Verhältnis zu groß.

---

## 5. Flaggen, Figuren, Waren, Ressourcen

| Element | Ist in Grenzmark | ≈ Kacheln | Hinweis / Original |
|---|---|---|---|
| Spielflagge / Bauplatz-Icon | 30 px | ~0,47 | Original-Flagge ~0,4–0,5 Knoten hoch. |
| Figur (Träger/Arbeiter/Soldat) | `unit_size = 18` px Höhe | ~0,28 | Original-Figuren ~0,4–0,5 Knoten (≈ 22–28 px Grenzmark) — etwas größer wäre originalnäher. |
| Ware am Flaggenknoten | 8×8 px Icon | ~0,13 | Liegen aktuell als 4er-Raster rechts-oben; Original: dicht ums Flaggenkreuz gestapelt → siehe Issue. |
| Feld (Acker) | 48×30 px (Default) | ~0,75 × 0,94 | Im Design-Editor frei skalierbar (`object_sizes`). |
| Baum / Stein / Erz | tree 40×54 / stone 32–58 / ore 32×27 | — | `object_draw_size` in `game/theme_db.gd`. |

---

## 6. Wie anpassen — ohne Code (alles über `assets/design.json`)

- **Gebäude:** Design-Editor → „Größe" je Gebäude (schreibt `building_sizes`), oder global
  `texture_scale` / `hq_scale` in `design.json`.
- **Felder/Karten-Objekte:** Design-Editor → Kategorie „Karten-Objekte" (`object_sizes`).
- **Figuren:** `unit_size` in `design.json`.
- **Bauplatz-/Flaggen-Icons:** `build_spot_sizes` / `build_spot_offsets`.
- Nach Änderung **Godot neu starten** (`design.json` wird beim Start gelesen).

---

## Quellen (RTTR s25client)

- `libs/s25main/gameData/MapConsts.h` — Knoten-Geometrie (TR_W 56, TR_H 28, Höhe 5).
- `libs/s25main/gameData/DoorConsts.h` — Tür-/Anker-Y je Gebäude & Volk.
- `libs/s25main/world/BQCalculator.h`, `nodeObjs/noExtension.h` — Fußabdruck/Blockierung
  (Burg belegt W/NW/NE; Straßen dürfen sonst dicht an Gebäuden laufen).
