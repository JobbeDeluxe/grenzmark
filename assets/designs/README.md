# Design-Quellen für KI-Grafiken

Dieser Ordner sammelt Quellbilder, Sheets, Previews und Prompts für Grafiken,
aus denen die eigentlichen Spiel-Assets unter `assets/` entstehen. Fertige,
vom Spiel geladene PNGs gehören in die jeweiligen Zielordner, z. B.
`assets/objects/`, `assets/buildings/`, `assets/units/` oder `assets/ui/`.

## Kornfelder für den Bauernhof

Geplante Ziel-Assets:

| Ziel-Datei | Bedeutung | Prompt-Kern |
|---|---|---|
| `assets/objects/field_seed.png` | frisch gesät, dunkler Acker mit Keimen | `freshly sown small medieval wheat field patch, dark tilled soil with tiny green sprouts` |
| `assets/objects/field_young.png` | junges grünes Korn | `young green wheat field patch, short fresh wheat shoots` |
| `assets/objects/field_growing.png` | hoher grüner Bestand | `dense growing wheat field patch, tall green stalks, not ripe yet` |
| `assets/objects/field_ripe.png` | golden, erntebereit | `ripe golden wheat field patch, harvest-ready grain heads` |
| `assets/objects/field_cut.png` | optional: Stoppeln nach der Ernte | `cut wheat stubble field patch after harvest` |

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
  Übergang. `field_cut.png` ist optional, falls später eine kurze Stoppelphase
  nach der Ernte sichtbar bleiben soll.

Wichtig: Keine Original-Siedler-Dateien oder 1:1-Kopien verwenden. Die Bilder
sollen neu generiert oder selbst erstellt sein und nur das Konzept nachbauen.
