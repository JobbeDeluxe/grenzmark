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
   `assets/units/` ablegen (4 Phasen × 6 Weg-Richtungen).

Du kannst deine fertigen Designs einfach in diese Ordner kopieren. Wenn ein Name
oder Format unklar ist: in der Tabelle bzw. den Abschnitten unten steht für jeden
Typ Ordner, Dateiname und empfohlene Größe.

## Wohin welche Datei?

| Ordner | Dateiname | Inhalt | empf. Größe |
|---|---|---|---|
| `assets/terrain/`   | `water.png`, `meadow.png`, `mountain.png`, `sand.png`, `swamp.png`, `snow.png` | Terrain-Textur (kachelbar) | ~256×256 |
| `assets/roads/`     | `road.png`, optional `<terrain>.png`, `road_cobble.png` | Straßen-Textur, längs gekachelt | ~192×48 |
| `assets/construction/` | `site.png` (Bauplatz), `stage1.png` (Holzbau-Stufe) + optional `<def_id>_site.png` / `<def_id>_stage1.png` | Bauplatz & Baustufe 1 | ~64×64 |
| `assets/buildings/` | `<def_id>.png` | Gebäude-Sprite = **fertiger Bau / Baustufe 2** (Boden = untere Kante) | ~64×64 |
| `assets/objects/`   | `tree_<typ>.png`, `tree_<typ>_seed.png`, `tree_<typ>_small.png`, `field_seed.png`, `field_young.png`, `field_growing.png`, `field_ripe.png`, `stone.png`, `stone_stage2.png`, `stone_stage3.png`, `ore.png` | Karten-Objekte, Baumtypen, Kornfeld- & Stein-Stufen | frei; Bäume werden per Zielhöhe skaliert |
| `assets/goods/`     | `<nummer>.png` | Waren-Symbol | ~16×16 |
| `assets/units/`     | `carrier.png`, `worker.png`, `soldier.png`, `builder.png` (+ `_<spieler>` Varianten) | Lauf-Sprite-Sheet (4×6) | Zelle ~32×32 |
| `assets/ui/`        | `main_menu_background.png`, `flag_<spieler>.png`, `build_spots/*.png` | Hauptmenü, Spielflaggen & Bauhilfe-Symbole | 16:9 / ~64×64 |
| `assets/`           | `ui.json` | UI-Skin/Layouts: Farben, Randabstände, Panel-/Buttongrößen | Text/JSON |

### Waren- und Werkzeug-Icons (`assets/goods/`)
Jede Ware bekommt ein eigenes PNG nach Enum-Nummer aus `core/goods.gd`:
`assets/goods/<nummer>.png`. Das ist bewusst austauschbar; eigene Designs werden
einfach unter demselben Dateinamen abgelegt und nach dem Godot-Import genutzt.

Wichtig für die S2-Werkzeuge: die zwölf Einzelwerkzeuge dürfen nicht dauerhaft das
alte allgemeine `Werkzeug`-Icon wiederverwenden. Die aktuell angehängten IDs
`19` bis `30` brauchen jeweils ein eigenes, klar unterscheidbares Design:
Zange, Hammer, Axt, Säge, Spitzhacke, Schaufel, Schmelztiegel, Angel, Sense,
Beil, Nudelholz und Bogen. Temporäre Kopien des alten Werkzeug-PNGs sind nur
Platzhalter, bis die endgültigen Icons gezeichnet sind.

### UI-Skin & Bedienoberfläche (`assets/ui.json`)
Die In-Game-UI hat eine eigene kleine Skin-Schicht (`game/ui_skin.gd`). Erste
Werte liegen in `assets/ui.json`:
- `layout`: Randabstände, obere Warenleiste, kontextuelles Auswahlfenster,
  untere Hauptleiste, Baufenster, Minikarte, Waren-Iconzellen und Button-Größen.
- `colors`: Panel-, Button-, Schrift- und Akzentfarben.

Das ist die Vorstufe für richtige 9-Patch-Skins: Später kommen Panel-/Button-PNGs,
Zustände (normal/hover/pressed/disabled) und ein kompletter UI-Editor dazu. Schon
jetzt gilt: UI-Farben/Grundmaße ändern → Godot neu starten, kein Code nötig.

### Straßen-Texturen (`assets/roads/`)
Straßen werden **segmentweise entlang der Wegrichtung gekachelt**. Lege `road.png`
als Standard ab; pro Untergrund kannst du zusätzlich eine eigene PNG geben
(`meadow.png`, `mountain.png`, `sand.png`, `swamp.png`) — der jeweilige Boden des
Segments bestimmt die Textur. Fehlt alles, zeichnet das Spiel eine schlichte Linie.
Die Textur sollte **horizontal kachelbar** sein (linke und rechte Kante passen
aneinander); die Laufrichtung der Straße ist die **Breite** (X) der Textur.

Straßen sammeln Transportlast. Nach `road_upgrade_deliveries` Lieferungen aus
`assets/tuning.json` wechselt die Straße sichtbar auf `road_cobble.png`
(Kopfsteinpflaster). Das ist die sichtbare Vorstufe für spätere Esel-/Lastwege.
Auch der kurze Eingangspfad von Gebäudeflagge zur Tür nutzt jetzt die Straßentextur.

### Spieler & Farben — EIGENES PNG pro Spieler (keine Einfärbung)
Jeder Spieler (eigene Seite, Gegner, später bis zu 6) bekommt **seine eigene
Grafik**. Es wird **nichts automatisch eingefärbt** — du zeichnest die Flaggen,
Gebäude und Einheiten in der gewünschten Farbe selbst. Das sieht am besten aus und
ist eindeutig. Schema: an den Basisnamen `_<spielernummer>` anhängen
(`0` = Spieler/eigene Seite, `1` = Gegner, `2`–`5` = weitere Spieler).

| Was | Gemeinsam (alle gleich) | Pro Spieler (überschreibt) |
|---|---|---|
| **Flagge** | `assets/ui/flag.png` | `assets/ui/flag_0.png`, `flag_1.png`, … |
| **Gebäude** | `assets/buildings/<def_id>.png` | `assets/buildings/<def_id>_1.png`, … |
| **Einheiten** | `assets/units/<kind>.png` | `assets/units/<kind>_1.png`, … |

- Liegt **keine** `_<nummer>`-Variante vor, gilt die gemeinsame Datei für alle.
  So musst du z. B. Wirtschaftsgebäude nur einmal zeichnen, aber Militärgebäude
  und Flaggen pro Spieler einfärben.
- Spieler **0** nutzt immer direkt die Basisdatei (kein `_0` nötig, aber erlaubt).
- Aktueller Stand: `flag.png`/`flag_0.png` bis `flag_5.png` sind vorhanden.
  Für Gebäude sind aktuell die roten Gegnervarianten `assets/buildings/*_1.png`
  dort erzeugt, wo die Basisgrafik blaue Spielerflächen enthält. Weitere
  Gebäudefarben (`_2`–`_5`) werden erst festgelegt, wenn das Multiplayer-Farbschema
  entschieden ist.
- Flaggengröße in `assets/design.json` über `"flag_size": [breite, höhe]`
  (Pfahl-Fuß sitzt auf dem Knoten, Bild geht nach oben). Fehlt ein PNG, zeichnet
  das Spiel eine einfache Platzhalter-Flagge in der Spieler-Standardfarbe
  (0 blau, 1 rot, 2 grün, 3 gelb, 4 lila, 5 orange).

KI-Prompt-Tipp für Gegnervarianten: denselben Prompt nehmen und „**with red
banners / red flag / red trim**" (bzw. green/yellow/…) anhängen, damit die Spieler
auf einen Blick unterscheidbar sind.

### Verdeckung (Occlusion) — wichtig fürs Zeichnen
Menschen verschwinden **hinter** Gebäuden und Bäumen, solange ihr Fußpunkt
**oberhalb** (hinter) dem Fußpunkt des Sprites liegt; laufen sie **davor**
(weiter unten), bleiben sie sichtbar. Damit das sauber wirkt:
- **Unterkante = Bodenkontakt**: Der unterste Bildpunkt eines Gebäude-/Baum-PNGs
  ist der Punkt, der auf dem Knoten steht. Keine leere Reserve unten lassen.
- Transparente Pixel zeigen die Person durch — nutze sauberes Alpha (z. B.
  zwischen Ästen), dort scheint ein dahinter laufender Träger korrekt durch.

### Bauhilfe-Symbole (`assets/ui/build_spots/`)
Die Leertaste zeigt nur Plätze, die **tatsächlich im eigenen Gebiet gebaut**
werden können. Nicht baubare Knoten bleiben leer. Die Symbole sind austauschbare
PNG-Sprites mit Transparenz und weichem Schlagschatten:
- `castle.png`, `house.png`, `hut.png`, `mine.png`
- `flag.png` für reine Flaggenplätze
- `road_flag.png` für Flagge-auf-Straße / Straßen teilen

`flag.png` und `road_flag.png` dürfen bewusst identisch sein, damit Flaggen im
Spiel überall gleich aussehen; die getrennten Dateien bleiben nur als optionaler
Skin-Hook erhalten.

Die Größe lässt sich in `assets/design.json` unter `build_spot_sizes` je Symbol
einstellen.

### Karten-Objekte (`assets/objects/`)
Bäume haben jetzt **3 Typen** und **3 Wachstumsstufen**:
- Typen: `oak`, `pine`, `birch`
- Stufen: `seed` = Setzling, `small` = kleiner Baum, ohne Suffix = großer Baum
- Dateinamen: `tree_oak_seed.png`, `tree_oak_small.png`, `tree_oak.png`
  (analog `tree_pine_*` und `tree_birch_*`)
- Legacy-Fallbacks `tree.png`, `tree_seed.png`, `tree_small.png` bleiben gültig.
- Die Baum-PNGs dürfen hochauflösend sein. Das Spiel skaliert sie über
  `assets/design.json` → `object_heights` (`tree_seed`, `tree_small`,
  `tree_big`) und behält dabei das Seitenverhältnis der jeweiligen PNG bei.
  Wichtig: oben und seitlich transparente Reserve lassen; unten sitzt der
  Stammfuß am Bildrand, weil dieser Punkt auf dem Kartenknoten steht.

Die Karte wählt beim Generieren einen zufälligen Baumtyp aus dem Seed. Der Förster
setzt beim Pflanzen deterministisch einen Typ aus der Knotenposition, damit die
Simulation reproduzierbar bleibt. Nur **große Bäume** dürfen gefällt werden.

Steine haben **3 Abbau-Stufen**:
- `stone_stage3.png`: großer Stein, liefert 3 Arbeitsgänge
- `stone_stage2.png`: mittlerer Stein, liefert noch 2 Arbeitsgänge
- `stone.png`: kleiner Stein, liefert den letzten Arbeitsgang und verschwindet

Kornfelder des Bauernhofs (Issue #26, umgesetzt) liegen als eigene austauschbare
PNGs in **4 sichtbaren Wachstumsphasen** vor; fehlen sie, malt das Spiel einen
Fallback-Acker (kein Absturz):
- `field_seed.png`: frisch gesätes Feld / dunkler Acker mit ersten Keimen
- `field_young.png`: junges grünes Korn, niedrige Halme
- `field_growing.png`: dichter, hoher grüner Bestand
- `field_ripe.png`: goldenes reifes Korn, erntebereit
- optional `field_cut.png`: abgeerntete Stoppeln, falls die Mechanik später eine
  kurze Nach-Ernte-Phase statt sofortigem Entfernen nutzt

Mechanik: Öffentliche S2/10th-Quellen nennen **1 Minute 55 Sekunden** vom Säen
bis zur vollen Reife. Bei 30 Hz sind das **3450 Ticks**, mit 4 Phasen verteilt auf
**3 Übergänge à 1150 Ticks** (`field_seed -> field_young -> field_growing ->
field_ripe`). Die Werte stehen in `assets/tuning.json` (`field_growth_stage_ticks`),
nicht hartcodiert.

Feld-PNGs sollten flach am Boden liegen, kachel-/clusterfähig wirken und den
Knoten nicht wie ein hohes Gebäude verdecken. Ideale Quellgröße: ca. 48×32 bis
64×48 px mit Transparenz, leicht dimetrisch, Unterkante am Bodenkontakt.

### Bauplatz & 2-stufiger Baufortschritt (`assets/construction/`)
Der Bau läuft in **zwei sichtbaren Stufen**:
1. **Bauplatz** — solange noch nichts hochgezogen ist, zeigt das Spiel `site.png`
   (statt des gelben Platzhalter-Gerüsts). Pro Gebäude überschreibbar mit
   `<def_id>_site.png`.
2. **Stufe 1 = Holzkonstruktion** — `stage1.png` (oder `<def_id>_stage1.png`)
   „wächst" zuerst aus dem Boden (der Holz-Anteil der Baukosten).
3. **Stufe 2 = fertiger Bau** — danach wächst das normale Gebäude-Sprite aus
   `assets/buildings/<def_id>.png` darüber (der Stein-Anteil).

**Aufteilung der Stufen auf die Baukosten:**
- Gebäude **mit Stein**: Stufe 1 entspricht dem **Holz/Bretter-Anteil**, Stufe 2
  dem **Stein-Anteil** (z. B. 3 Bretter + 2 Stein → Stufe 1 bis alle Bretter da,
  dann Stufe 2 mit dem Stein).
- Gebäude **ohne Stein**: der Fortschritt wird **gleichmäßig halbiert**
  (2 Bretter → Stufe 1 nach dem 1., Stufe 2 nach dem 2. Brett).
- Fehlt `stage1.png`: das Spiel fällt automatisch auf **eine Stufe** zurück und
  zieht alles aus dem fertigen Gebäude-Sprite hoch (wie bisher).

### Balance-Tuning (`assets/tuning.json`)
Zeiten und Laufgeschwindigkeiten liegen in `assets/tuning.json` und können später
direkt aus einem Optionsmenü geändert werden. Alle Zeiten sind **Ticks**; das Spiel
rechnet mit **30 Ticks pro Sekunde**.

Wichtige Felder:
- `worker_speed_default`: Standard-Gehgeschwindigkeit in Weltpixeln pro Tick.
- `worker_speed_by_building`: Gehgeschwindigkeit je `def_id`, z. B.
  `woodcutter` oder `forester`.
- `work_action_ticks_by_building`: Dauer der Aktion am Ziel
  (Baum fällen, Setzling pflanzen, Stein schlagen, Erz abbauen).
- `work_wait_ticks_by_building`: Pause am Gebäude zwischen zwei Arbeitsgängen.
- `tree_growth_stage_ticks`: `[Setzling→kleiner Baum, kleiner Baum→großer Baum]`.
  Erst der große Baum darf vom Holzfäller gefällt werden.
- `field_growth_stage_ticks`: Kornfeld-Wachstum `[gesät→jung, jung→wachsend,
  wachsend→reif]`, Startwert `[1150, 1150, 1150]` = 1:55 min bis zur Ernte (30 Hz).
- `road_upgrade_deliveries`: Anzahl Warenlieferungen über eine Straße bis zum
  sichtbaren Kopfsteinpflaster.

Die aktuellen Defaults orientieren sich an öffentlich dokumentierten Siedler-II-
Werten: Baumwachstum 26 s + 74 s und Produktionszyklen grob im Bereich 45–60 s,
bleiben aber bewusst einstellbar.

### Terrain-Skalierung (`assets/design.json`)
`terrain_uv_world_size` bestimmt, wie groß eine Bodentextur in Weltpixeln gekachelt
wird. Kleinerer Wert = feinere Wiederholung. Standard aktuell: `96.0`, damit Gras
und Details im Verhältnis zu Gebäuden kleiner wirken.

### Untergrund-Arten (Terrain) & Bebaubarkeit
Es gibt **6 Untergründe** (`core/terrain.gd`), angelehnt an Die Siedler 2:

| Typ | Bebaubar? | Begehbar (Straße/Träger)? | Nutzung |
|---|---|---|---|
| **Wiese** (meadow) | ✅ ja | ✅ ja | normale Gebäude, Bäume/Steine |
| **Berg** (mountain) | ⛏ nur Minen | ✅ ja | Erz/Granit, Minen |
| **Sand** (sand) | ❌ nein | ✅ ja | Küsten/Wüste, nur Flaggen/Wege |
| **Sumpf** (swamp) | ❌ nein | ✅ ja | feuchtes Tiefland, nur Wege/Flaggen |
| **Wasser** (water) | ❌ nein | ❌ nein | Meer/Seen, blockiert (später Häfen/Schiffe) |
| **Schnee/Fels** (snow) | ❌ nein | ❌ nein | hohe Gipfel, gesperrt |

Ein Gebäude braucht, dass **alle umliegenden Dreiecke** bebaubar (Wiese) bzw. bei
Minen Berg sind. **Sumpf und Sand sind also bewusst nicht bebaubar**, aber man
kann Straßen darüber legen — genau wie im Original. Der Karten-Generator streut
Sumpf in niedrige, feuchte Bereiche nahe dem Wasser.

### Gebäude-Größen & Eingang anpassen (ohne Code) — `assets/design.json`
Die Größen sind **nicht fest im Code**, sondern in `assets/design.json` einstellbar:
```json
{
  "texture_scale": 2.0,
  "hq_scale": 1.35,
  "unit_size": 18,
  "flag_size": [16, 24],
  "sizes": { "hut":[34,30], "house":[40,36], "castle":[50,46], "mine":[30,26] },
  "building_sizes": { "woodcutter": [37,33] },
  "building_offset": { "woodcutter": [0,0] },
  "entrance": { "default": [0,-6], "hq": [0,-10] },
  "build_spot_offsets": { "flag": [0,-10], "road_flag": [0,-10] }
}
```
- `sizes`: Größe je Größenklasse (hut/house/castle/mine).
- `building_sizes`: einzelne Gebäude individuell überschreiben (per `def_id`).
- `building_offset`: Bild-Versatz eines Gebäudes zur Flagge (Position), per `def_id`.
- `flag_size`: Zeichengröße der Spielflaggen-PNG (Fuß auf dem Knoten).
- `build_spot_offsets`: Versatz der Bauhilfe-Icons (Leertaste) vom Knotenmittel-
  punkt, je Symbol (`flag`, `road_flag`, `castle`, `house`, `hut`, `mine`,
  `blocked`). Damit sitzen z. B. Flaggen-Icons nicht mehr mittig auf dem Knoten,
  sondern an der richtigen Stelle. Bequem per Design-Editor einstellbar (s. u.).
- `unit_size`: Ziel-Höhe der Figuren in px — **stellt zu große Einheiten-Sprites
  passend klein** (das Sheet wird auf diese Höhe skaliert).
- `texture_scale`/`hq_scale`: Skalierung der Gebäude-Sprites.

Werte ändern → Godot neu starten. Fehlt die Datei, gelten die Standardwerte.

### Bequemer: der Design-Editor (Hauptmenü → „Einstellungen" → „Design-Editor")
Statt die JSON von Hand zu editieren, gibt es ein **DEV-Menü mit Live-Vorschau**:
- Links ein Gebäude wählen, in der Mitte siehst du es **mit Flagge und Eingangsweg**.
- Rechts per Regler einstellen: **Breite, Höhe**, **Eingang X/Y** (wo der Weg
  von der Flagge zur Tür endet), **Textur-Skalierung**, **Einheiten-Höhe**.
- Rechts auch: **Bild-Versatz X/Y** (verschiebt das Sprite gegenüber der Flagge)
  und ein **Vergleichsobjekt** (zweites Gebäude daneben, um Größen zu vergleichen).
- Ganz unten: **Bauplatz-Icon Offset** — wähle ein Bauhilfe-Symbol (flag,
  road_flag, …) und verschiebe es per X/Y; die Vorschau zeigt **Knoten + Icon +
  Versatzlinie**, damit Flaggen-Icons richtig sitzen statt mittig auf dem Knoten.
- Änderungen sind **sofort in der Vorschau sichtbar**; auf die Platte geschrieben
  wird **nur per Speichern-Button** in `assets/design.json`
  (`building_sizes`/`building_offset`/`entrance`/`build_spot_offsets`).

So tunst du jedes Gebäude einzeln, ohne Code und ohne die Datei manuell zu öffnen.
Jedes Gebäude ist damit individuell in Größe **und** Eingangspunkt einstellbar.

### Hauptmenü-Hintergrund austauschen
Das Hauptmenü lädt optional `assets/ui/main_menu_background.png`. Du kannst die
Datei jederzeit durch ein eigenes PNG ersetzen; das Bild wird bildschirmfüllend
zugeschnitten und leicht abgedunkelt, damit Titel und Buttons lesbar bleiben.

Empfohlen ist ein 16:9-Bild ohne Schrift, Logos oder UI-Elemente. Fehlt die Datei,
nutzt das Hauptmenü automatisch den einfachen grünen Fallback-Hintergrund.

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

`<def_id>` = ID aus `core/building_catalog.gd`:
`hq, woodcutter, forester, sawmill, quarry, well, farm, mill, bakery, fishery,`
`hunter, pigfarm, slaughterhouse, coalmine, ironmine, goldmine, granitemine,`
`smelter, mint, brewery, smithy, toolmaker, guardhouse, watchtower, fortress,`
`catapult`.

`<nummer>` der Waren (aus `core/goods.gd`):
0 Holz · 1 Bretter · 2 Steine · 3 Getreide · 4 Mehl · 5 Wasser · 6 Brot ·
7 Fisch · 8 Fleisch · 9 Kohle · 10 Eisenerz · 11 Eisen · 12 Golderz ·
13 Münzen · 14 Bier · 15 Werkzeug · 16 Schwert · 17 Schild · 18 Schwein ·
19 Zange · 20 Hammer · 21 Axt · 22 Säge · 23 Spitzhacke · 24 Schaufel ·
25 Schmelztiegel · 26 Angel · 27 Sense · 28 Beil · 29 Nudelholz · 30 Bogen.

## UI-Design (austauschbar & skalierbar) — TEILWEISE UMGESETZT (Stufe 8)

Die Oberfläche soll künftig wie in Die Siedler 2 / RTTR aussehen (Holz-/Pergament-
Paneele, Icon-Buttons, Tooltips) und **als Skin austauschbar** sein. Damit ein
eigener Skin sauber passt, gelten diese Vorgaben (Ablage unter `assets/ui/`):

Aktueller Stand: `assets/ui.json` wird bereits von `game/ui_skin.gd` gelesen und
steuert Farben sowie wichtige Layoutmaße. PNG-basierte 9-Patch-Paneele und
Button-Zustände sind noch der nächste Schritt.

**Paneele/Rahmen (9-Patch):** `assets/ui/panel.png`, `button.png`,
`button_hover.png`, `button_pressed.png`, `button_disabled.png`.
- **9-Patch** heißt: das Bild wird in 3×3 Felder geteilt — die **vier Ecken
  bleiben fix**, **Kanten** werden in einer Richtung, die **Mitte** in beide
  Richtungen gestreckt. So sieht der Rahmen bei **jeder Größe scharf** aus.
- Definiere die **Rand-Ränder** (links/rechts/oben/unten in px) in `assets/ui.json`,
  z. B. `"panel_margin": [12,12,12,12]`. Außerhalb dieser Ränder darf kein wichtiges
  Motiv liegen (wird gestreckt).
- Empfohlene Quellgröße: 48×48–96×96 px, Ecken ~12–16 px.

**Icons:** `assets/ui/icons/<name>.png`, quadratisch (z. B. 32×32, transparent).
Benötigt u. a.: `select, flag, road, demolish, build, stop, stats, settings,
save, load, main_menu, quit, play, pause, faster, slower`. Waren-Icons werden aus
`assets/goods/` wiederverwendet.

Offener UI-Punkt: Wenn im Hauptmenü `Spiel laden` angeboten wird, braucht das
laufende Spiel auch ein erreichbares System-/Spielmenü mit `Spiel speichern`,
`Zurück zum Hauptmenü` und `Beenden` (z. B. über Esc und/oder die Hauptleiste).

**Schrift:** `assets/ui/font.ttf` (optional). Sonst Standardschrift.

**Layout/Skalierung:** `assets/ui.json`, z. B.
```json
{
  "ui_scale": 1.0,
  "font_size": 14,
  "panel_margin": [12,12,12,12],
  "icon_size": 32,
  "colors": { "text": "#f0e6d0", "text_dim": "#b8a884" }
}
```
`ui_scale` skaliert die gesamte Oberfläche; alle Maße sind relativ dazu.

**So muss ein Skin aussehen (Kurz-Checkliste):**
- Paneele/Buttons als **9-Patch-taugliche** PNGs (Motiv-Rand ≤ Margin).
- Vier Button-Zustände in **gleicher Größe** und gleichem Rand.
- Icons im **gleichen quadratischen Raster**, transparent, einheitlicher Stil.
- Farben/Schrift in `ui.json`; nichts hartcodiert.
- Fehlt der Skin, nutzt das Spiel sein Standard-Theme (kein Absturz).

*(Hinweis: Die JSON-Skin-Basis ist umgesetzt; die 9-Patch-PNGs sind noch Planung,
damit du Designs schon passend vorbereiten kannst.)*

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

**Bauplatz & Baustufe 1 (`assets/construction/`) — wird automatisch genutzt:**
Das Spiel zeigt beim Bauen zuerst den **Bauplatz** (`site.png`), zieht dann die
**Holzkonstruktion** (`stage1.png`) hoch und darüber das **fertige Gebäude**
(`assets/buildings/<def_id>.png`). Beide Bauplatz-/Holz-PNGs dürfen generisch
sein (für alle Gebäude) oder pro Gebäude (`<def_id>_site.png` / `<def_id>_stage1.png`).
- Bauplatz: `> medieval building site, flattened dirt plot with wooden stakes,
  ropes and a few planks and stone blocks lying ready, no building yet`
- Holzkonstruktion (Stufe 1): `> medieval timber-frame house skeleton, bare
  wooden support beams and scaffolding, no walls or roof yet, viewed from front`
  (Boden = untere Kante, gleicher Maßstab/Perspektive wie das fertige Gebäude.)

**Straßen (`assets/roads/`) — horizontal kachelbar:**
> `seamless horizontally tileable medieval dirt path / packed earth road
> texture, top-down, trodden ground, small pebbles, left and right edges match`
Pro Untergrund eigene Variante möglich (`mountain.png` = steiniger Pfad,
`sand.png` = sandige Spur, `swamp.png` = matschiger Knüppeldamm/Holzbohlen).

**Terrain-Texturen (`assets/terrain/`) — kachelbar, 6 Typen:**
> `seamless tileable top-down medieval terrain texture, <NAME>` — NAME z. B.
> `lush green meadow grass`, `deep blue water with gentle ripples`, `grey rocky
> mountain stone`, `sandy desert ground`, `dark wet swamp marsh with mud and
> reeds`, `white snow over rock`. (Dateinamen: `meadow/water/mountain/sand/swamp/snow.png`.)

**Karten-Objekte:**
- `single pine tree`, `tiny pine sapling`, `small young pine tree`,
  `cluster of grey boulders`, `rocky ore vein with metallic specks`
- Kornfeld-Phasen:
  - `freshly sown small medieval wheat field patch, dark tilled soil with tiny green sprouts`
  - `young green wheat field patch, short fresh wheat shoots`
  - `dense growing wheat field patch, tall green stalks, not ripe yet`
  - `ripe golden wheat field patch, harvest-ready grain heads`
  - optional `cut wheat stubble field patch after harvest`

Alle Feldphasen: `same camera angle, same footprint, transparent background,
top-down dimetric 2.5D, no text, no border, no building, no farmer`.

**Menschen / Animationen (Sprite-Sheets) — wird automatisch genutzt:**
Ablage: `assets/units/<kind>.png` mit `kind` = `carrier`, `worker`, `soldier`,
`builder`. **Raster: 4 Spalten (Lauf-Phasen) × 6 Zeilen (Weg-Richtungen)**, Reihenfolge
der Zeilen: **NE, E, SE, SW, W, NW**. Die Zellgröße
wird aus der Bildgröße abgeleitet (Breite/4 × Höhe/6); jede Zelle wird unten am
Knoten zentriert gezeichnet. Fehlt das Sheet, zeichnet das Spiel die Platzhalter-
Figur. (Spaltenzahl 4 / Zeilenzahl 6 sind in `game/theme_db.gd` als `ANIM_FRAMES`
/ `ANIM_DIRS` einstellbar.)

KI-Prompt dafür:
> `tiny medieval <ROLE> walk cycle sprite sheet, 4 frames per row, 6 rows for
> 6 road directions (NE, E, SE, SW, W, NW), top-down dimetric, uniform
> cell size, transparent background, pixel-clean` — ROLE z. B. `carrier with
> sack`, `builder with hammer`, `soldier with sword and shield`, `worker`.

**Waren-Icons (16×16):**
> `single medieval resource icon, <NAME>, flat readable icon, transparent
> background` — NAME z. B. `wooden log, wooden planks, stone block, sack of
> grain, flour, loaf of bread, fish, coal lump, iron ore, iron bar, gold ore,
> gold coins, beer mug, sword, shield`.

**Werkzeug-Icons (16×16, eigene Designs statt generischem Werkzeug):**
> `single medieval tool icon, <NAME>, flat readable icon, transparent background`
> — NAME: `blacksmith tongs, carpenter hammer, woodcutter axe, hand saw,
> miner pickaxe, small shovel, metal crucible, fishing rod and line, grain scythe,
> butcher cleaver, baker rolling pin, wooden bow`.
