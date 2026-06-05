# Grenzmark — Roadmap & Stufenplan

Ein Die-Siedler-2-naher Aufbau in **Godot 4.6.3** mit **GDScript**.
Ziel: zuerst die Original-Mechanik so dicht wie möglich nachbauen, danach
auf Basis der eigenen Programmierung frei erweitern. Später Multiplayer.

Vorbilder (nur als Konzept-Referenz, kein Code-Copy):
- **Return to the Roots (RTTR)** — die getreue S2-Reimplementierung in C++.
- **Widelands** — freies Spiel mit demselben Karten-/Wege-Modell.

---

## Leitprinzipien (warum die Architektur so ist)

1. **Logik strikt vom Rendering trennen.** Alles unter `core/` ist reine
   Simulation ohne Godot-Szenenbaum (nur `RefCounted`). Godot (`game/`)
   zeichnet nur und liest Eingaben. → testbar, später multiplayer-fähig.
2. **Deterministische Simulation.** Keine Zufallszahlen ohne festen Seed,
   keine Fließkomma-Abhängigkeiten in der Spiel-Logik wo vermeidbar. Das ist
   die Voraussetzung für Lockstep-Multiplayer (alle Clients rechnen dasselbe).
3. **Knoten-Gitter wie S2.** Die Karte ist KEIN Quadratraster, sondern ein
   versetztes Dreiecks-/Hex-Gitter: jeder Knoten hat **6 Nachbarn**, jeder
   Knoten besitzt **2 Terrain-Dreiecke**. Genau das macht Straßen & Bauplätze
   aus. (Das war beim ersten Versuch die größte Schmerzquelle — deshalb ist es
   hier das Fundament.)
4. **Straßenbau per Auto-Pfad.** Statt Segment-für-Segment-Gefummel: Startflagge
   wählen, Ziel anklicken, A* legt die Straße. Viel angenehmer als im Original
   und vermeidet genau den Frust von vorher.

---

## Stufenplan

### Stufe 0 — Fundament (DIESE Iteration, läuft bereits) ✅
Das Skelett, auf dem alles aufbaut.
- [x] Projektstruktur, `core/`–`game/`-Trennung
- [x] Karten-Datenmodell: Knoten, Höhen, 6-Nachbar-Gitter, 2 Dreiecke/Knoten
- [x] Geometrie: Knoten↔Bildschirm, die 6 Dreiecke um einen Knoten
- [x] Prozeduraler Karten-Generator (Höhen + Terrain: Wiese/Wasser/Berg/Sand)
- [x] Rendering der Karte als schattierte Dreiecke mit Höhe
- [x] Kamera: Schwenken (rechte/mittlere Maustaste) + Zoom (Mausrad)
- [x] Maus→Knoten-Picking
- [x] **BauQualität (BQ)** pro Knoten: nichts/Flagge/Hütte/Haus/Burg/Mine
- [x] Flaggen setzen (mit Abstandsregel)
- [x] Straßenbau per Auto-Pfad (A* über begehbare freie Knoten)
- [x] Gebäude setzen (mit automatischer Flagge am Eingang)
- [x] Wege-Pfadfindung über das Flaggen-/Straßennetz (Dijkstra)
- [x] HUD: Modus + Knoten-Info (Koordinaten, Terrain, BQ)
- [x] Headless-Selbsttests für die Kern-Geometrie

### Stufe 1 — Karte & Bauen rund machen
- [x] Bäume, Steine, Erz-Vorkommen als Map-Objekte (blockieren Bauen/Straßen)
- [x] Abriss von Flaggen/Straßen/Gebäuden (Modus [9])
- [x] Flagge auf bestehende Straße setzen → teilt die Straße (Kreuzung)
- [x] Mini-Map
- [x] Fenster-Skalierung (Stretch canvas_items) — UI skaliert mit
- [ ] Höhen-Picking exakt (aktuell ignoriert Höhe leicht)
- [ ] Bessere Karten-Generierung (Inseln, Flüsse, Berg-Adern mit Erzen)
- [ ] Rodungs-/Sichtbarkeitsradius beim Bauen

### Stufe 2 — Träger & Warenfluss (Herzstück von S2)
- [x] Träger-Einheiten, einer pro Straße
- [x] Waren erzeugen, auf Flaggen ablegen (mit Kapazitätsgrenze)
- [x] Wegewahl der Waren über das Flaggennetz (kürzeste Route)
- [x] Hauptquartier als Senke/Lager mit Inventar
- [ ] Feinere Stau-/Prioritätslogik, mehrere Träger pro Straße
- [ ] Esel/Boten-Wege später
- [ ] Animierte Lauf-Sprites (4–8 Richtungen)

### Stufe 3 — Wirtschaft & Produktionsketten
- [x] Lagerhaus/HQ als Quelle & Senke (zentrales Inventar)
- [x] Daten-getriebener Gebäude-Katalog mit ~19 Typen
- [x] Produktionsketten: Holz→Bretter; Getreide→Mehl→Brot; Erz+Kohle→Eisen→Schwert; Gold+Kohle→Münzen; Bier; usw.
- [x] Terrain-Ressourcen: Holzfäller fällt Bäume, Förster pflanzt, Steinbruch, Minen verbrauchen Erz, Fischer am Wasser
- [x] Baustelle + Materialanlieferung (Bretter/Steine) + Baufortschritt
- [x] Bauanimation: Gebäude wächst sichtbar aus dem Boden (Gerüst → fertig)
- [x] Bauplatz-Größenlogik wie S2: große Gebäude brauchen Abstand, Nachbar-
      bauplätze schrumpfen (effective_bq); Gebäude optisch nach Größe gestaffelt
- [x] Kurzer Eingangsweg Flagge → Gebäudetür mitgezeichnet (fester Eingangspunkt)
- [x] Gebäudegrößen/Eingang per Config (assets/design.json), nicht hartcodiert
- [x] Bedarf/Angebot über das HQ (Gebäude fordern Eingänge an, liefern Ausgänge)
- [x] Träger stehen mittig auf der Straße und laufen zur Ware (sichtbare Bewegung)
- [x] Träger kommen beim Straßenbau vom HQ übers Netz angelaufen (erst dann aktiv)
- [x] Arbeiter laufen aus dem Gebäude zur Ressource (Baum fällen, Stein, Erz, pflanzen)
- [x] Produktionsarbeiter kommt vom HQ (Gebäude produziert erst nach Ankunft)
- [x] Bauarbeiter-Figur an der Baustelle
- [ ] Mehrere Lagerhäuser, direkte Gebäude→Gebäude-Lieferung, Prioritäten-UI

### Stufe 4 — Militär & Gebiet
- [x] Grenzsteine / Einflussgebiet (Territorium aus Gebäude-Radien)
- [x] Militärgebäude (Wachhaus/Wachturm/Festung) erweitern das Gebiet
- [x] Soldaten: HQ bildet aus Schwertern Soldaten aus, die Militärgebäude besetzen
- [x] Soldaten marschieren sichtbar vom HQ übers Straßennetz zum Gebäude (Marcher)
- [x] Gebiet wird nur mit Besatzung gehalten (Garnison-Anzeige am Gebäude)
- [x] Zweiter Spieler (Gegner) mit eigenem HQ + Militärgebäuden
- [x] Besitzerbasiertes Territorium (Spieler blau / Gegner rot, nächstes Gebäude gewinnt)
- [x] Angriff: eigenes Militärgebäude wählen → Gegnergebäude anklicken → Soldaten greifen an
- [x] Eroberung: bei Garnison 0 wechselt das Gebäude den Besitzer
- [x] Gegner-KI: bildet Soldaten aus, besetzt, expandiert Richtung Spieler, greift an
- [x] KI als austauschbares Plugin (Standard/Passiv + eigene aus res://ai/, Taste J)
- [x] Sieg/Niederlage (HQ erobert → Spielende)
- [x] Soldaten-Beförderung durch Münzen (Verteidigungs-Rüstung am Gebäude)
- [x] Katapult (beschießt feindliche Militärgebäude auf Distanz)
- [x] KI baut eigene Wirtschaftsgebäude (mehr Wirtschaft → schneller Soldaten)
- [x] KI baut keine Militärgebäude auf Bergen (nur Minen erlaubt)
- [ ] KI baut auch Straßen (Gebäude sichtbar vernetzen; aktuell ohne Wege)
- [ ] Soldaten-Ränge mit eigener Grafik/Aufstiegsstufen, mehr Waffenarten

### Stufe 5 — Spielfluss & Inhalt
- [x] Speichern/Laden (Struktur + HQ-Lager) — F2/F3
- [x] In-Game-UI: Bau-Menü als Kategorie-Leiste unten, Minikarte, Vorrats-Anzeige
- [ ] UI weiter wie Original: Icons statt Text, Bau-Vorschau, Statistik-Tabs
- [ ] Hauptmenü, Spielgeschwindigkeit/Pause
- [ ] Spielziele, Sieg/Niederlage
- [ ] KI-Gegner (Single-Player)
- [ ] Ton, Musik, Optionen (RTTR-Stil)

### Stufe 6 — Multiplayer
- [ ] Lockstep-Netzwerkmodell auf Basis der deterministischen Simulation
- [ ] Eingaben als Kommandos synchronisieren, nicht Zustände
- [ ] Lobby, Sync-Prüfung (Checksum pro Tick)

### Stufe 7 — Eigenes Gesicht
- [x] Automatisches Laden austauschbarer Texturen aus `assets/` (sonst Platzhalter)
- [x] Gerichtete Lauf-Animationen (8 Richtungen) per Sprite-Sheet aus assets/units/
- [x] Terrain-Texturierung (assets/terrain/, getilte UVs) — sonst Flächenfarbe
- [ ] Vollständiger eigener Grafiksatz (alle Gebäude/Waren/Einheiten)
- [ ] Eigene Mechanik-Erweiterungen nach Geschmack

## Lücken zu den Originalen (Die Siedler 2 / RTTR) — Prüfliste

Was die Vorbilder haben und uns noch fehlt, grob nach Wichtigkeit. Das ist die
Arbeitsliste, bis das Spiel „vollständig" ist (Ton/Musik kommt ganz zuletzt).

**Bevölkerung & Träger (Kern, hoch):**
- [ ] Echte Einwohnerzahl: Träger/Arbeiter sind begrenzte Bevölkerung aus dem HQ
- [ ] Werkzeuge: Berufe brauchen passendes Werkzeug (Schreiner/Werkzeugmacher)
- [ ] Esel/Eselzüchter: Esel als Träger auf stark genutzten Straßen
- [ ] Straßen-Ausbau zu „Eselstraßen"; mehrere Träger bei Stau

**Fehlende Gebäude (ggü. Original) — Katalog erweitern:**
Vorhanden (21): HQ, Holzfäller, Förster, Sägewerk, Steinbruch, Brunnen, Bauernhof,
Mühle, Bäckerei, Fischerhütte, Kohle-/Eisen-/Goldmine, Eisenschmelze,
Münzprägerei, Brauerei, Schmiede, Wachhaus, Wachturm, Festung, Katapult.
- [ ] Lagerhaus / Vorratshaus (zweites Lager)
- [ ] Jägerhütte (→ Fleisch)
- [ ] Schweinefarm (Getreide + Wasser → Schwein) + Schlachterei (→ Fleisch/Schinken)
- [ ] Eselzüchter (Getreide + Wasser → Esel)
- [ ] Werkzeugmacher/Schlosserei (Eisen + Bretter → Werkzeug)
- [ ] Granitmine (4. Erzsorte) — getrennte Erz-/Bergwerksarten
- [ ] Waffenschmiede mit Schwert UND Schild (statt nur Schwert)
- [ ] Hafen + Werft (Schiffe/Boote)
- [ ] Baracke / weitere Militär-Stufen, Spähturm

**Wirtschaft (hoch):**
- [ ] Mehrere Lagerhäuser/Vorratshäuser mit eigenem Inventar
- [ ] Warenverteilung & Prioritäten (welches Gebäude bekommt was zuerst)
- [x] Gebäude-Produktion an/aus schalten (Taste P am gewählten Gebäude)
- [ ] Produktion drosseln (Prozent), Eingangsmengen begrenzen
- [ ] Direkte Gebäude→Gebäude-Lieferung (nicht alles über HQ)
- [ ] Felder: Bauer pflügt/erntet Getreide-Felder; Schweinezucht; Jäger braucht Tiere
- [ ] 4 Erzsorten im Berg (Kohle/Eisen/Gold/Granit) statt generischem Erz

**Karte & Erkundung (hoch):**
- [ ] Geologen: erkunden Berge auf Vorkommen (Schilder), bevor Minen lohnen
- [ ] Nebel des Krieges / Sichtbarkeit nur im erkundeten Gebiet
- [ ] Erdarbeiter (Planierer) ebnen Bauland; Höhe beeinflusst Bau stärker
- [ ] Tiere (Wild) und nachwachsende Ressourcen, Fisch erschöpft sich

**Militär (mittel):**
- [ ] Soldaten-Ränge mit Stufen (Gefreiter→General), Beförderung sichtbar
- [ ] Angriff mit wählbarer Soldatenzahl; Gebäude-Belagerung
- [ ] Gebäudegrößen-Ausbau (kleines→großes Militärgebäude)
- [ ] Schilde + Schwerter + Bier nötig, um Soldaten im HQ zu rekrutieren

**Wasser & See (mittel):**
- [ ] Häfen, Werften, Schiffe; Warentransport über Wasser
- [ ] Expedition/Besiedlung von Inseln

**Spielfluss & UI (mittel):**
- [ ] Statistik-Bildschirme (Waren, Gebäude, Militär, Produktion)
- [ ] Spielziele/Missionen, Sieg-/Niederlage-Bedingungen wählbar
- [ ] Einstellungen: Verteilung, Werkzeug-Priorität, Militär-Stärke
- [ ] Mehr/stärkere KI-Gegner, Bündnisse

**Multiplayer (später):** Lockstep über die deterministische Simulation.
**Ton/Musik (ganz zuletzt).**

### Render-/Performance-Hinweise (für Wiedereinstieg)
- Zwei Ebenen: `MapRenderer` (statisch, nur bei Bauen/Abriss/Ressourcen neu)
  und `UnitRenderer` (pro Frame: Träger/Arbeiter/Waren/Hover/Vorschau).
  WICHTIG: Bei Mausbewegung NIE den MapRenderer neu zeichnen (sonst ruckelt es).
- Terrain nutzt Vertex-Farben (`draw_polygon` mit Farb-Array) für weiche Übergänge.

---

## Ordnerstruktur

```
core/                 # reine Simulation, KEIN Godot-Szenenbaum
  grid.gd             # Gitter-Geometrie: Nachbarn, Dreiecke, Bildschirm-Koords
  terrain.gd          # Terrain-Typen + Eigenschaften
  map_data.gd         # Karte: Höhen + Terrain pro Knoten
  map_generator.gd    # prozedurale Kartenerzeugung
  world_state.gd      # Spielzustand: Flaggen, Straßen, Gebäude, BQ, Pfadfindung
game/                 # Godot: zeichnen + Eingabe
  world.gd            # Aufbau, Eingabe, Bau-Modi, HUD
  map_renderer.gd     # zeichnet Terrain/Objekte/Highlights
  camera_controller.gd# Schwenken + Zoom
  main.tscn           # Startszene
tests/
  test_core.gd        # Headless-Selbsttests
ROADMAP.md            # dieses Dokument
README.md             # Steuerung & Start
```

## Steuerung
- **Rechte/mittlere Maustaste ziehen**: Karte schwenken  •  **Mausrad**: Zoom
- **Bau-Menü links**: Modus & Gebäude wählen (oder Tasten **1** Flagge, **2** Straße, **9** Abriss, **0** Auswahl)
- **Linksklick**: ausführen (Flagge/Straße/Gebäude/Abriss)
- **F2** Speichern  •  **F3** Laden  •  **F5** Neues Spiel
- **Minikarte unten rechts**: Klick zentriert die Kamera
- **K**: Gegner-KI an/aus (zum Testen)  •  **Leertaste** Pause  •  **+/-** Tempo

## Architektur-Notizen (für Wiedereinstieg)
- `core/economy.gd` ist das Wirtschaftsherz: HQ-zentriert. Gebäude fordern
  Eingänge vom HQ an, liefern Ausgänge zum HQ. `BState` pro Gebäude.
- `core/building_catalog.gd` = alle Gebäudedefinitionen (Kosten/Ein-/Ausgänge/
  Ressource/Einfluss). Neues Gebäude → nur hier ergänzen + Kürzel in `theme_db.gd`.
- `game/theme_db.gd` (class `GameTheme`) = austauschbare Optik (Farben/Kürzel,
  später Texturen). NICHT mit Godots eingebautem `ThemeDB` verwechseln.
- Determinismus: feste 30-Hz-Ticks, keine ungeseedete Zufälligkeit in `core/`.
