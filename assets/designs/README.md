# Design-Quellen für KI-Grafiken

Dieser Ordner sammelt Quellbilder, Sheets, Previews und Prompts für Grafiken,
aus denen die eigentlichen Spiel-Assets unter `assets/` entstehen. Fertige,
vom Spiel geladene PNGs gehören in die jeweiligen Zielordner, z. B.
`assets/objects/`, `assets/buildings/`, `assets/units/` oder `assets/ui/`.

## Kornfelder für den Bauernhof

Die Feldmechanik ist umgesetzt (Issue #26); diese PNGs sind optional — fehlen sie,
malt das Spiel einen Fallback-Acker. Ziel-Assets:

| Ziel-Datei | Bedeutung | Prompt-Kern |
|---|---|---|
| `assets/objects/field_seed.png` | frisch gesät, dunkler Acker mit Keimen | `freshly sown small medieval wheat field patch, dark tilled soil with tiny green sprouts` |
| `assets/objects/field_young.png` | junges grünes Korn | `young green wheat field patch, short fresh wheat shoots` |
| `assets/objects/field_growing.png` | hoher grüner Bestand | `dense growing wheat field patch, tall green stalks, not ripe yet` |
| `assets/objects/field_ripe.png` | golden, erntebereit | `ripe golden wheat field patch, harvest-ready grain heads` |
| `assets/objects/field_cut.png` | Stoppeln nach der Ernte (umgesetzt) | `cut wheat stubble field patch after harvest` |
| `assets/objects/field_withered.png` | verdorrtes, ungeerntetes Feld (umgesetzt) | `withered dried-out wheat field patch, pale brown collapsed dead stalks, overgrown` |

Gemeinsamer Stil:

```text
top-down dimetric 2.5D view, hand-painted medieval settler game art,
warm saturated colors, soft top-left lighting, clean silhouette,
transparent background, same footprint and camera angle for every growth stage,
single ground patch, no building, no farmer, no text, no border
```

Recherche-Stand für die Mechanik:

- S2/10th-Quellen beschreiben das Feld als gesät -> gewachsen -> reif -> geerntet.
- Öffentlich dokumentiert ist vor allem die Zeit bis zur Reife: 1 Minute 55 Sekunden.
- Bei Grenzmarks 30-Hz-Simulation sind das 3450 Ticks.
- Als spielnahe, gut lesbare Asset-Aufteilung sind 4 sichtbare Phasen vorgesehen:
  `seed -> young -> growing -> ripe`, also als Startwert ca. 1150 Ticks pro
  Übergang.
- Nach der Ernte bleibt RTTR-getreu ein **Stoppelfeld** (`field_cut.png`) liegen,
  das nichts blockiert und nach `field_decay_ticks` verschwindet.
- Ein **reifes, ungeerntetes** Feld verdorrt RTTR-getreu nach `field_wither_ticks`
  zu `field_withered.png` (ebenfalls nicht-blockierende Deko, verschwindet danach).
  Gleiche Kameraperspektive/Footprint wie die Wachstumsphasen, nur fahl/vertrocknet.

Wichtig: Keine Original-Siedler-Dateien oder 1:1-Kopien verwenden. Die Bilder
sollen neu generiert oder selbst erstellt sein und nur das Konzept nachbauen.

## Werkzeug-Icons für Waren 19-30

Seit dem S2-näheren Warenmodell sind die zwölf Werkzeuge eigene Waren. Die
fertigen Spiel-Assets liegen unter `assets/goods/<nummer>.png`; in diesem Ordner
können Quellbilder, Previews und Prompt-Ergebnisse gesammelt werden.

Die aktuellen Platzhalter dürfen nicht beim generischen Werkzeug-Icon bleiben.
Jedes Werkzeug braucht ein eigenes lesbares Motiv, damit Lager-/Inventarfenster
und Warenleisten eindeutig bleiben:

| Ziel-Datei | Bedeutung | Prompt-Kern |
|---|---|---|
| `assets/goods/19.png` | Zange | `blacksmith tongs` |
| `assets/goods/20.png` | Hammer | `carpenter hammer` |
| `assets/goods/21.png` | Axt | `woodcutter axe` |
| `assets/goods/22.png` | Säge | `hand saw` |
| `assets/goods/23.png` | Spitzhacke | `miner pickaxe` |
| `assets/goods/24.png` | Schaufel | `small shovel` |
| `assets/goods/25.png` | Schmelztiegel | `metal crucible` |
| `assets/goods/26.png` | Angel | `fishing rod and line` |
| `assets/goods/27.png` | Sense | `grain scythe` |
| `assets/goods/28.png` | Beil | `butcher cleaver` |
| `assets/goods/29.png` | Nudelholz | `baker rolling pin` |
| `assets/goods/30.png` | Bogen | `wooden bow` |

Gemeinsamer Stil:

```text
single medieval tool icon, flat readable 16x16 game icon, transparent background,
warm hand-painted settler game style, clean silhouette, no text, no border
```
