# Grafik-Assets (austauschbar)

Hier kommt deine eigene Grafik hin. **Du musst keinen Code anfassen** — leg die
PNG mit dem richtigen Namen in den richtigen Ordner, und das Spiel nutzt sie
automatisch. Fehlt eine Datei, wird die eingebaute Platzhalter-Form gezeichnet.

## So stellst du eigene Designs bereit (Kurzfassung)
1. PNG (mit Transparenz) erstellen — im Stil von Die Siedler 2 / RTTR.
2. In den passenden Ordner unter `assets/` legen, exakt benannt (siehe Tabelle).
3. Godot einmal öffnen (oder `--headless --import` ausführen) → die PNG wird
   importiert. Fertig, beim nächsten Start ist sie im Spiel.
4. Für **Lauf-Animationen**: Sprite-Sheet nach dem Raster unten in
   `assets/units/` ablegen (4 Phasen × 8 Richtungen).

Du kannst deine fertigen Designs einfach in diese Ordner kopieren. Wenn ein Name
oder Format unklar ist: in der Tabelle bzw. den Abschnitten unten steht für jeden
Typ Ordner, Dateiname und empfohlene Größe.

## Wohin welche Datei?

| Ordner | Dateiname | Inhalt | empf. Größe |
|---|---|---|---|
| `assets/terrain/`   | `water.png`, `meadow.png`, `mountain.png`, `sand.png`, `swamp.png`, `snow.png` | Terrain-Textur (kachelbar) | ~256×256 |
| `assets/buildings/` | `<def_id>.png` | Gebäude-Sprite (Boden = untere Kante) | ~64×64 |
| `assets/objects/`   | `tree.png`, `stone.png`, `ore.png` | Karten-Objekte | ~32×32 |
| `assets/goods/`     | `<nummer>.png` | Waren-Symbol | ~16×16 |
| `assets/units/`     | `carrier.png`, `worker.png`, `soldier.png`, `builder.png` | Lauf-Sprite-Sheet (4×8) | Zelle ~32×32 |

### Gebäude-Größen & Eingang anpassen (ohne Code) — `assets/design.json`
Die Größen sind **nicht fest im Code**, sondern in `assets/design.json` einstellbar:
```json
{
  "texture_scale": 2.0,
  "hq_scale": 1.35,
  "sizes": { "hut":[22,20], "house":[32,30], "castle":[46,44], "mine":[26,22] },
  "entrance": { "default": [0,-6], "hq": [0,-10] }
}
```
Werte ändern → Godot neu starten. Fehlt die Datei, gelten die Standardwerte.

### Eingang & Weg zur Flagge — PRO Gebäude definierbar (modular)
Wie in Die Siedler sitzt die **Eingangsflagge auf dem Knoten unten rechts** vom
Gebäude, und ein **kurzer Weg** führt von der Flagge zur **Tür**. Wohin der Weg
führt, legst du **pro Gebäude** im Abschnitt `"entrance"` fest — ein Punkt in
Pixeln relativ zum Gebäudeknoten:
```json
"entrance": {
  "default":  [0, -6],     // gilt für alle ohne eigenen Eintrag
  "sawmill":  [6, -12],    // z. B. Tür rechts oben im Sägewerk-Sprite
  "hq":       [0, -18]
}
```
So passt der Eingangspunkt exakt zu deinem jeweiligen Sprite (Position **und**
Richtung des Wegs ergeben sich daraus). `def_id` = Katalog-ID (siehe unten). Der
Weg wird automatisch dorthin gezeichnet und ist der Punkt, an dem Träger die
Waren ins Gebäude bringen.

`<def_id>` = ID aus `core/building_catalog.gd`, z. B.
`hq, woodcutter, forester, sawmill, quarry, well, farm, mill, bakery, fishery,`
`coalmine, ironmine, goldmine, smelter, mint, brewery, smithy, guardhouse,`
`watchtower, fortress, catapult`.

`<nummer>` der Waren (aus `core/goods.gd`):
0 Holz · 1 Bretter · 2 Steine · 3 Getreide · 4 Mehl · 5 Wasser · 6 Brot ·
7 Fisch · 8 Fleisch · 9 Kohle · 10 Eisenerz · 11 Eisen · 12 Golderz ·
13 Münzen · 14 Bier · 15 Werkzeug · 16 Schwert · 17 Schild.

## Format
- **PNG** mit Transparenz (Alpha).
- Terrain-PNGs brauchen kein Alpha; sie werden in die Kartendreiecke geklippt.
- Maßstab: ein Karten-Knoten ist 64 px breit (`Grid.TILE_W`), Zeilen 32 px hoch.
- Gebäude werden mittig über dem Knoten gezeichnet, Unterkante am Knotenpunkt.

## Rechtliches (bitte lesen)
- **Keine Original-Die-Siedler-2-Dateien einbinden** (z. B. von der CD) und nicht
  weitergeben — die sind urheberrechtlich geschützt. Lokal zum eigenen Test auf
  dem eigenen Rechner ist deine Sache, aber sie gehören nicht ins Projekt/Repo.
- **Widelands-Grafik** ist Open Source (GPL / CC-BY-SA). Einbau möglich, macht
  abgeleitete Grafik dann aber ebenfalls GPL/CC-BY-SA — bei Veröffentlichung
  Lizenz und Quellenangabe beachten.
- Am saubersten: **eigene** Grafik im Stil von Die Siedler 2 / RTTR.

---

## KI-Prompts zum Erstellen der Grafik

Englische Prompts liefern bei den meisten Bildgeneratoren bessere Ergebnisse.
Wichtig für alle: **transparenter Hintergrund (PNG)**, **gleiche Blickrichtung
und Lichtquelle** (Licht von oben-links), **leicht erhöhte 2.5D-/Dimetrie-
Perspektive**, einheitlicher Maßstab. Negative: `no background, no shadow box,
no text, no border`.

**Gemeinsamer Stil-Baustein (an jeden Prompt anhängen):**
> `, top-down dimetric 2.5D view, hand-painted medieval settler game art,
> warm saturated colors, soft top-left lighting, clean silhouette, centered,
> transparent background, single object, game asset sprite`

**Gebäude (klein/mittel/groß):**
- Holzfäller: `small medieval log cabin with axe and woodpile`
- Sägewerk: `medium medieval sawmill with saw blade and timber`
- Bauernhof: `large medieval farmhouse with grain fields`
- Mühle: `medieval windmill with rotating sails`
- Bäckerei: `medieval bakery with chimney smoke`
- Mine: `mine entrance built into a rocky hillside with wooden supports`
- Schmiede: `medieval blacksmith forge with anvil and chimney`
- Wachturm/Festung: `stone medieval watchtower with battlements and flag`
- Hauptquartier: `large stone medieval keep / castle headquarters with flag`

**Bauzustand (optional, je Gebäude eine Reihe von Stufen):**
> `same building under construction, wooden scaffolding, partially built walls,
> stage 1 of 4 (foundation), stage 2 (walls), stage 3 (roof), stage 4 (finished)`
Ablage später z. B. als `assets/buildings/sawmill_build1.png` … (Loader dafür
kommt, sobald gewünscht).

**Karten-Objekte:**
- `single pine tree`, `cluster of grey boulders`, `rocky ore vein with metallic specks`

**Menschen / Animationen (Sprite-Sheets) — wird automatisch genutzt:**
Ablage: `assets/units/<kind>.png` mit `kind` = `carrier`, `worker`, `soldier`,
`builder`. **Raster: 4 Spalten (Lauf-Phasen) × 8 Zeilen (Richtungen)**, Reihenfolge
der Zeilen im Uhrzeigersinn ab Osten: **E, SE, S, SW, W, NW, N, NE**. Die Zellgröße
wird aus der Bildgröße abgeleitet (Breite/4 × Höhe/8); jede Zelle wird unten am
Knoten zentriert gezeichnet. Fehlt das Sheet, zeichnet das Spiel die Platzhalter-
Figur. (Spaltenzahl 4 / Zeilenzahl 8 sind in `game/theme_db.gd` als `ANIM_FRAMES`
/ `ANIM_DIRS` einstellbar.)

KI-Prompt dafür:
> `tiny medieval <ROLE> walk cycle sprite sheet, 4 frames per row, 8 rows for
> 8 facing directions (E, SE, S, SW, W, NW, N, NE), top-down dimetric, uniform
> cell size, transparent background, pixel-clean` — ROLE z. B. `carrier with
> sack`, `builder with hammer`, `soldier with sword and shield`, `worker`.

**Waren-Icons (16×16):**
> `single medieval resource icon, <NAME>, flat readable icon, transparent
> background` — NAME z. B. `wooden log, wooden planks, stone block, sack of
> grain, flour, loaf of bread, fish, coal lump, iron ore, iron bar, gold ore,
> gold coins, beer mug, sword, shield, tools`.
