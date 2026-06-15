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
- [x] Gebäude dürfen nicht direkt auf dem eigenen Grenzsaum stehen; Gebäude und
      Eingangsflagge brauchen einen Knoten inneren Gebietsabstand.
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
- [ ] Bessere Karten-Generierung (Inseln, Flüsse, Berg-Adern mit Erzen).
      Wichtig: S2-artige Hex-Pinsel/Brush-Stamps statt langer Dreiecks-Zacken,
      Höhen-/Terrain-Glättung, Granit/Steine als Pakete, unterirdische Erze.
      Erster Schnitt (2026-06-09): Terrain wird als Knoten-/Regionenmaske
      klassifiziert und per Hex-Brush auf Dreiecke gemalt; Kanten-Cleanup bleibt
      als Sicherheitsnetz. Start-Teich nutzt dieselbe Brush-Logik. Steincluster
      statt Einzelstreuung; Spieler/KI bekommen je einen Steincluster im Gebiet.
      Erz unterirdisch (2026-06-10): versteckte Lagerstätten-Schicht, Adern im
      Berg, Mine baut endlich im Umkreis ab. Geologen-/Nebel-Aufdeckung folgt in
      #21. (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/19)
- [x] Test-Teich im Startgebiet (kleiner See nahe HQ), damit Fischerhütte ohne
      Kartenglück getestet werden kann.
- [x] Nebel des Krieges + Sicht umschaltbar (Taste F); Karte wird um eigene
      Gebäude/Flaggen/Straßen aufgedeckt (recompute_visibility). Zusätzlich
      im Hauptmenü als Startoption einstellbar.
- [x] Bauplatz-Anzeige (Leertaste): zeigt nur tatsächlich im eigenen Gebiet
      baubare Plätze; austauschbare PNG-Symbole für Baugrößen, Flaggen,
      und Straßen-Flaggen

### Stufe 2 — Träger & Warenfluss (Herzstück von S2)
- [x] Träger-Einheiten, einer pro Straße
- [x] Waren erzeugen, auf Flaggen ablegen (mit Kapazitätsgrenze)
- [x] Wegewahl der Waren über das Flaggennetz (kürzeste Route)
- [x] Hauptquartier als Senke/Lager mit Inventar
- [ ] Feinere Stau-/Prioritätslogik, mehrere Träger pro Straße
- [ ] Esel/Boten-Wege später
- [ ] Animierte Lauf-Sprites (6 Weg-Richtungen)

### Stufe 3 — Wirtschaft & Produktionsketten
- [x] Lagerhaus/HQ als Quelle & Senke (zentrales Inventar)
- [x] Daten-getriebener Gebäude-Katalog mit ~19 Typen
- [x] Produktionsketten: Holz→Bretter; Getreide→Mehl→Brot; Erz+Kohle→Eisen→Schwert; Gold+Kohle→Münzen; Bier; usw.
- [x] Terrain-Ressourcen: Holzfäller fällt Bäume, Förster pflanzt, Steinbruch, Minen verbrauchen Erz, Fischer fängt endlichen Fisch am Ufer (#6), Bauer sät/erntet Felder (#26)
- [x] Baustelle + Materialanlieferung (Bretter/Steine) + Baufortschritt
- [x] Baufortschritt proportional zum gelieferten Material (Stein wertvoller als Holz)
- [x] Bauarbeiter kommt vom HQ; gebaut wird erst nach seiner Ankunft
- [x] HQ-Tür-Träger: trägt Waren sichtbar aus der HQ-Tür zur Flagge hinaus und
      eingehende Waren von der Flagge ins Lager hinein (Eingangsweg). Nur HQ/Lager;
      normale Gebäude regeln den letzten Schritt selbst (Ware liegt an der Flagge).
- [x] Kein Fallback-Träger mehr: ohne HQ-Verbindung bleibt die Straße unbesetzt
      (Träger kommt, sobald sie ans Netz angeschlossen ist)
- [x] Tür-Träger auch für zusätzliche Lagerhäuser (#31: eigener HouseCarrier je Lager)
- [x] Bauanimation: Gebäude wächst sichtbar aus dem Boden (Gerüst → fertig)
- [x] 2-stufiger Bau: Stufe 1 = Holzkonstruktion (Holzanteil), Stufe 2 = fertiger
      Bau mit Stein. Ohne Stein gleichmäßig halbiert. Eigene PNGs einbindbar
      (assets/construction/stage1.png), sonst Rückfall auf 1 Stufe.
- [x] Bauplatz-Grafik (assets/construction/site.png) statt gelbem Platzhalter
- [x] Bauarbeiter läuft nach Fertigstellung sichtbar zurück zum HQ (purpose_return)
- [x] Bauplatz-Größenlogik wie S2 (RTTR BQCalculator, #29): Footprint
      kandidatengrößen-abhängig — Hütte/Haus dürfen direkt neben ein Gebäude, nur
      Burgen brauchen 2 Knoten Abstand. Burg/HQ belegen zusätzlich ihre 3
      Extension-Knoten oben-links (W/NW/NE). Gebäude optisch nach Größe gestaffelt
- [x] Kurzer Eingangsweg Flagge → Gebäudetür mitgezeichnet (fester Eingangspunkt)
- [x] Gebäudegrößen/Eingang per Config (assets/design.json), nicht hartcodiert
- [x] Jedes Gebäude einzeln einstellbar (Größe & Eingang je def_id)
- [x] Design-Editor im Hauptmenü: Live-Vorschau, Größe/Eingang per Regler,
      automatische Speicherung in design.json
- [x] Bedarf/Angebot über das HQ (Gebäude fordern Eingänge an, liefern Ausgänge)
- [x] Träger stehen mittig auf der Straße und laufen zur Ware (sichtbare Bewegung)
- [x] Träger kommen beim Straßenbau vom HQ übers Netz angelaufen (erst dann aktiv)
- [x] Straßen sammeln Transportlast und wechseln sichtbar auf Kopfsteinpflaster
      (`road_cobble.png`); Esel-/Mehrträger-Mechanik bleibt als nächster Ausbau offen
- [x] Arbeiter laufen aus dem Gebäude zur Ressource (Baum fällen, Stein, Erz, pflanzen)
- [x] Ressource-Arbeiter mit einstellbarer Gehgeschwindigkeit, Aktionszeit und Pause (`assets/tuning.json`)
- [x] Baumwachstum: Setzling → kleiner Baum → großer Baum; nur große Bäume sind fällbar
- [x] Drei Baumtypen (Eiche/Kiefer/Birke) mit eigenen Setzling-/Klein-/Groß-PNGs;
      Generator wählt seeded zufällig, Förster pflanzt deterministisch je Knoten
- [x] Baum-PNGs aus vollständigem Sheet neu extrahiert; Kronen haben oben
      transparente Reserve und werden mit korrektem Seitenverhältnis skaliert
- [x] Steinressourcen mit 3 Abbau-Stufen: groß → mittel → klein → weg, passend
      zu `stone_stage3.png`, `stone_stage2.png`, `stone.png`
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
- [x] KI baut sichtbare eigene Straßen, Gegnerträger und einfache Gegnerarbeiter
      (2026-06-09, Issue #22)
- [ ] Soldaten-Ränge mit eigener Grafik/Aufstiegsstufen, mehr Waffenarten

### Stufe 5 — Spielfluss & Inhalt
- [x] Speichern/Laden (Struktur + HQ-Lager) — F2/F3
- [x] In-Game-UI: kompakte Hauptleiste unten, Minikarte, Vorrats-Anzeige
- [x] Bau-Menü zeigt Gebäude-Sprites als Button-Icons (wenn vorhanden)
- [x] Hauptmenü + Spielgeschwindigkeit/Pause + Sieg/Niederlage (siehe Stufe 4)
- [x] Austauschbares Hauptmenü-Hintergrundbild (`assets/ui/main_menu_background.png`)
- [x] Austauschbare Bauhilfe-Symbole (`assets/ui/build_spots/*.png`)
- [x] Bauhilfe-Symbole optisch überarbeitet: KI-generierte, schwebende
      3D-artige Gebäude-/Flaggenmarker mit Schatten; normale Flagge und
      Straßen-Flagge nutzen denselben Look, nicht baubare Knoten bleiben leer
- [x] Design-Editor (Hauptmenü) für Gebäudegrößen/Position/Eingang
- [ ] Große UI-Überarbeitung → eigene **Stufe 8** (siehe unten)
- [ ] Spielziele/Missionen wählbar; Statistik-Bildschirme
- [ ] Weltseed/Kartenwahl (#27): Zufallsseed anzeigen/eingeben, `DEVMAP` als
      reproduzierbare Entwicklerkarte, Kartenimport und später Editor-Karten
      vorbereiten.
- [ ] Ton, Musik, Optionen (ganz zuletzt)

### Stufe 6 — Multiplayer
- [ ] Lockstep-Netzwerkmodell auf Basis der deterministischen Simulation
- [ ] Eingaben als Kommandos synchronisieren, nicht Zustände
- [ ] Lobby, Sync-Prüfung (Checksum pro Tick)

## Ist/Soll-Abgleich (Stand 2026-06-09)

**Ist jetzt stabil spielbar / erledigt:**
- Kernsimulation mit Karte, BQ/Flaggen/Straßen, HQ-Lager, Warenfluss, Bauarbeiter,
  Trägern, Produktionsarbeitern, KI-Grundaufbau, Militär-Grundlogik und Save/Load.
- Austauschartige Assets: Hauptmenübild, Straßen, Bauplatz, Holzbau-Stufe,
  Baumtypen/-stufen, Stein-Stufen und Bauhilfe-Symbole liegen als PNGs in `assets/`.
- Bauhilfe per Leertaste zeigt Größen/Symbole, Flaggenplätze und Straßen-Flaggen
  nur dort, wo wirklich gebaut werden kann; nicht baubare Knoten bleiben leer.
- Bauhilfe/Gebäudebau respektiert den Grenzsaum: direkt auf der Grenze werden
  keine Gebäude-Bauplätze mehr angeboten.
- Der Hover-Cursor zeigt die Bauplatzgröße direkt am Knoten (Flagge, Hütte, Haus,
  Burg, Mine bzw. Straßen-Flagge), damit die Bauhilfe näher am S2-Gefühl bleibt.
- UI-Skalierung klein/mittel/groß ist im Spiel und im Hauptmenü umschaltbar
  (`user://ui_settings.dat`, Vorgabe über `assets/ui.json`).
- Hauptmenü-Einstellungen speichern Startoptionen für Bauhilfe, Nebel des Krieges
  und KI-Gegner; die Ingame-Schalter schreiben dieselben Optionen zurück.
- Gebäudefenster können parallel offen bleiben; Klick auf ein weiteres Gebäude
  überschreibt nicht mehr das vorige Fenster.
- Straßen haben Trampelpfad-Texturen, texturierte Gebäudeeingänge und eine
  sichtbare Kopfsteinpflaster-Stufe nach Transportlast.

**Soll / auffällige Lücken vor „fühlt sich wie S2 an":**
- **UI ist jetzt der wichtigste nächste Schritt.** Die Logik hat genug Substanz,
  aber Bedienung/Infofenster/Ressourcenanzeige sind noch zu textlastig und nicht
  genug wie ein Siedler-artiges Werkzeugbrett.
- Gebäude-Infofenster haben eine erste parallele Fenster-Version mit Bild,
  Status, Stop/Abriss/Sprung/Angriff. Produktivität, Eingänge/Ausgänge,
  Prioritäten und Lagerstatus brauchen noch eigene Icon-/Register-Ansichten.
- Ressourcen-/Lagerleiste oben ist noch eine Textliste; Waren brauchen Icons,
  Zahlen und klare Warnzustände.
- Bau-/Verwaltungsfenster sind jetzt nur noch bei Bedarf offen und lassen sich
  verschieben/schließen/parken; offen bleiben echte Symbolbuttons und ein
  schönerer austauschbarer 9-Patch-Skin.
- Minikarte braucht Rahmen/Overlay-Schalter; aktuelle Anzeige ist funktional,
  aber nicht in ein UI-System eingebettet.
- Bevölkerung/Werkzeuge/Esel/mehrere Lagerhäuser sind weiter große Mechanik-Lücken,
  aber nach aktuellem Stand weniger dringend als die UI-Grundüberarbeitung.
- Esel/Lastwege: Kopfsteinpflaster ist jetzt sichtbar vorbereitet, aber ein
  eigener Eselträger, Stall/Zucht und mehrere Träger pro Straße fehlen noch.

### Stufe 7 — Eigenes Gesicht
- [x] Automatisches Laden austauschbarer Texturen aus `assets/` (sonst Platzhalter)
- [x] Gerichtete Lauf-Animationen (6 Weg-Richtungen) per Sprite-Sheet aus assets/units/
      Offen: saubere Animationsbilder/Sprite-Sheets für Träger, Arbeiter,
      Soldaten, Flaggen und Gebäude-Arbeitsprozesse sammeln (Issue:
      https://github.com/JobbeDeluxe/grenzmark/issues/12).
- [x] Terrain-Texturierung (assets/terrain/, getilte UVs) — sonst Flächenfarbe
- [x] Straßen-Texturen (assets/roads/road.png + pro Untergrund <terrain>.png,
      segmentweise längs gekachelt) — sonst Linie
- [x] Gebäudeeingangsweg nutzt Straßentextur statt nackter Linie; Terrain-Kachelung
      per `terrain_uv_world_size` feiner skaliert
- [x] Alle 6 Untergründe (Wiese/Berg/Sand/Sumpf/Wasser/Schnee) im Generator
      erzeugt & korrekt genutzt; Sumpf begehbar aber nicht bebaubar (wie S2)
- [x] Spielerfarben als eigene PNGs vorbereitet: Flaggen für Spieler 0-5,
      rote Gegner-Gebäudevarianten (`*_1.png`) für alle blau markierten Gebäude
- [ ] Vollständiger eigener Grafiksatz (alle Gebäude/Waren/Einheiten)
      Aktueller Asset-Audit und Folgearbeit: https://github.com/JobbeDeluxe/grenzmark/issues/13
- [ ] Eigene Mechanik-Erweiterungen nach Geschmack

### Stufe 8 — UI-Überarbeitung (austauschbar & skalierbar) ⭐ NÄCHSTER GROSSER PUNKT

Ziel: weg von schlichten Standard-Buttons/Text hin zu einer **stimmigen Oberfläche
im Stil von Die Siedler 2 / RTTR** (Holz-/Pergament-Paneele, verzierte Rahmen,
Icon-Buttons, Tooltips) — und das **komplett austauschbar über ein Theme/Skin**,
ohne Code, **bei jeder Auflösung scharf** (9-Patch).

GitHub-Arbeitspakete:
- https://github.com/JobbeDeluxe/grenzmark/issues/5 — S2-artiges Fenster- und Hauptleisten-System
- https://github.com/JobbeDeluxe/grenzmark/issues/8 — Austauschbare 9-Patch-UI-Skins und Icon-Set
- https://github.com/JobbeDeluxe/grenzmark/issues/3 — Ressourcen-Icons oben stark verkleinern
- https://github.com/JobbeDeluxe/grenzmark/issues/4 — Kamera-Drag-Regress nach UI-Umbau

**A) Konkrete UI-Bausteine, die schöner/neu werden müssen**
- [x] **Erster UI-Schnitt (2026-06-08):** feste Randleisten statt loser Text-HUDs:
      obere Icon-Warenleiste, kontextuelles Auswahlfenster, untere Hauptleiste
      und gerahmte Minikarte.
- [x] **S2-näherer zweiter UI-Schnitt:** Unten bleiben nur drei Hauptbuttons
      (`Bauen`, `Wirtschaft`, `System`). Das Baufenster klappt nur bei Bedarf auf
      und trennt Wege-/Bauhilfe-Aktionen von den Gebäudekategorien.
- [x] **S2-näheres Baufenster (2026-06-09):** Wege/Flagge/Abriss/Bauhilfe als
      Aktionszeile, darunter vier Gebäudekategorien nach Handbuch:
      Bergwerk, klein, mittel, groß.
- [x] **Baufenster-Politur (2026-06-09):** Aktionszeile und Gebäudekategorien
      nutzen kompakte Symbolbuttons; die Gebäudeauswahl ist ein S2-näheres
      Iconraster mit Kurzlabels und Tooltips statt langer Textbuttons.
- [x] **Bauplatz-Klicklogik:** Wenn die Bauplatzansicht per Leertaste sichtbar
      ist, setzt ein Klick auf Flaggen-/Straßenflaggen-Marker direkt die Flagge;
      Klick auf Hütte/Haus/Burg/Mine öffnet unten ein nach Bauplatzgröße
      gefiltertes Baufenster.
- [x] **Baufenster-Resize/Position (2026-06-09):** Fenstergröße skaliert jetzt
      auch Inhalt, Abstände, Scrollbereich und Rasterspalten; Bauhilfe-Klicks
      öffnen das gefilterte Baufenster nahe am angeklickten Marker, Menü/Hotkey
      weiterhin an der normalen Baufensterposition.
- [x] **Baufenster S2-näher (2026-06-10):** Gebäude als reine Icon-Kacheln
      (kein 2-Buchstaben-Kürzel mehr), hochformatig statt breit-flach (Sprites
      nicht mehr gestaucht), größeres Panel (520×320) und höherer Scrollbereich.
- [x] **Straßen-Kontextmenü (2026-06-10):** Klick auf eine eigene Straße öffnet
      ein Menü „Straße entfernen / Flagge einfügen" (vorher war Straßen-Abriss nur
      über den allgemeinen Abriss-Modus auffindbar).
- [x] **Einstellungsfenster (erste Version):** Taste **S** / Button Optionen zeigt
      alle aktuell auslagerbaren Design-/Tuning-Dateien (`assets/ui.json`,
      `assets/design.json`, `assets/tuning.json`, Bauplatz-/Flaggen-/Spieler-PNGs)
      plus schnelle Toggles für Bauplätze, Nebel, KI und Pause.
- [x] **UI-Skalierung (2026-06-09):** klein/mittel/groß über Systemfenster und
      Hauptmenü-Einstellungen; Auswahl wird in `user://ui_settings.dat` gemerkt.
- [x] **Hauptmenü-Startoptionen (2026-06-09):** Bauhilfe, Nebel und KI-Gegner
      sind vor Spielstart anwählbar und werden persistent gespeichert.
- [x] **Parallele Gebäudefenster (2026-06-09):** jedes angeklickte Gebäude öffnet
      sein eigenes Fenster; vorhandene Fenster werden fokussiert statt überschrieben.
- [~] **Nächster UI-Schnitt (Priorität 1):** Gebäude-Infofenster S2-näher machen.
      Erledigt (2026-06-10): Produktivität in % (rollendes 60-s-Fenster in
      `economy.gd`, deterministisch), Eingangs-/Ausgangswaren als Icon-Zeilen
      mit Soll (gedimmt) / Ist (hell) wie im Original, Warnzustände
      („Wartet auf Waren", „Kein Rohstoff in Reichweite", „Ausgang voll",
      „Produktion gestoppt", „Arbeiter kommt"), Baustellen zeigen Baustoff-
      Soll/Ist. Unterbau: `Economy.building_info()` liefert strukturierte
      Fensterdaten (read-only).
      Ergänzt (2026-06-10): Militärfenster zeigt **Garnison/Rang als Icons**
      (Spielerfarb-Plätze für besetzte/freie Garnison, Münz-Icons je Rang) statt
      Textzeile und hat einen **„Münzen an/aus"**-Schalter (`wants_coins` je
      Gebäude, persistiert; `_tick_promotions` respektiert ihn). Offen:
      Prioritäten, danach die Warenleiste oben weiter ikonisieren.
- [~] **Unterer Rand**: dauerhaft nur Hauptbuttons; Gebäude-/Wirtschafts-/
      Systemdetails liegen in Fenstern. Offen: richtige S2-artige Symbolbuttons
      und schönere Fenster-Skins.
- [x] **Cursor-Bauvorschau**: „Geist" des gewählten Gebäudes am Mauszeiger +
      BQ-Markierung am Knoten (grün=geht/rot=geht nicht), Eingangsflagge/-weg
      schon in der Vorschau (unit_renderer._draw_build_preview).
- [x] **S2-Bediengefühl beim Bauen (2026-06-10):** Gebäude aus dem Baumenü wird
      genau **einmal** gesetzt, danach zurück in den Auswahlmodus (vorher klebte
      der Geist dauerhaft am Cursor). **Rechtsklick** ist jetzt universeller
      Abbrechen/Schließen-Befehl (Bau-/Straßen-/Abrissmodus, Menüs); Rechtsklick
      mit Bewegung schwenkt weiterhin die Kamera (`camera_controller.gd` trennt
      Tap vs. Schwenk über `right_click_tap`).
- [x] **Hover-Bauhilfe (2026-06-09):** der Cursor zeigt am aktuellen Knoten
      sichtbar die zulässige Baugröße bzw. Straßen-Flagge statt nur einen Punkt;
      Diamant/Punkt bleiben am echten Knoten, Icon/Kurzlabel sitzen tiefer.
- [~] **Gebäude-Infofenster** (bei Auswahl): Gebäude-Bild, Status, Produktion
      an/aus, Abreißen, Angriff/Sprung; seit 2026-06-10 zusätzlich Produktivität
      in %, Eingangs-/Ausgangswaren als Soll/Ist-Icons, Warnzustände,
      Garnison/Rang als Icons und Militär-„Münzen an/aus". Offen: Priorität.
- [x] **Ressourcen-/Lagerleiste oben (2026-06-10):** Im Original gibt es keine
      dauerhafte Leiste — sie ist jetzt **standardmäßig aus** und nur über die
      Einstellungen (Button „Warenleiste" bzw. Hauptmenü-Checkbox
      `show_resource_bar`) einblendbar. Die alte Debug-HUD oben links
      (Modus/Knoten-Info) ist **entfernt**; Aktions-Rückmeldungen laufen über eine
      kurz eingeblendete Toast-Zeile.
- [x] **Inventur-Fenster S2-näher (2026-06-10):** HQ-Lager als Waren-**Icon+Zahl**-
      Raster (gedimmt bei 0) plus **Bevölkerung/Berufe**-Liste (aus `hq_people`)
      und Soldaten-Reserve, statt der bisherigen Textliste.
- [ ] **Minikarte** in gerahmtem Panel; Umschalter für Overlays (Gebiet, Bauplätze, Nebel).
- [~] **Statistik-Fenster** (Tabs: Waren/Gebäude/Militär/Produktion) und
      **Einstellungs-Fenster** (Verteilung, Werkzeug-/Militär-Prioritäten).
      Unterbau steht (2026-06-15): `economy.tool_priority` / `tool_orders` /
      `recruiting_ratio` mit Settings-API (`set_tool_priority/-order/-recruiting_ratio`),
      serialisiert. Offen: die Regler-UI selbst (Werkzeug-Prioritäten + Bestellpfeile,
      Militär-Rekrutierungsrate; später Verteilung). Issue #41.
- [ ] **Nachrichten-/Ereignisleiste** (Angriff, „Gebäude fertig", „Lager voll" …).
- [ ] **Tooltips** durchgängig; Cursor-Symbole je Modus (Flagge/Straße/Abriss).

**B) Austauschbares, skalierbares UI-Design (Skin-System)**
- [x] **`assets/ui.json` + `game/ui_skin.gd` als Startpunkt:** Panel-/Buttonfarben,
      Randabstände und Basismasse sind aus dem Code gezogen.
- [ ] Godot-**`Theme`-Ressource** zentral: alle Controls beziehen Styles daraus.
      Skin liegt unter `assets/ui/` und wird beim Start geladen (sonst Standard).
- [ ] Panel-/Button-Hintergründe als **9-Patch** (`StyleBoxTexture`/`NinePatchRect`):
      Ecken bleiben fix, Kanten/Mitte werden gestreckt → **bei jeder Größe scharf**.
- [ ] **Button-Zustände** (normal/hover/pressed/disabled) als 9-Patch bzw. je ein PNG.
- [ ] **Icon-Set** unter `assets/ui/icons/` (build/flag/road/demolish/stop/stats/…),
      Waren-Icons aus `assets/goods/` wiederverwenden.
- [x] **`assets/ui.json`** für Layout: globale UI-Skalierung, Schriftgröße,
      Basis-Panel-Größen und Icon-Rastergröße → ohne Code anpassbar.
- [ ] Fensterpositionen/-Anker noch weiter aus `world.gd` nach `assets/ui.json`
      ziehen.
- [ ] **Eigener UI-Editor/Vorschau** (analog Design-Editor) wäre Bonus.
- [x] **Design-Editor kompakter (2026-06-09):** schmalere Seitenleisten,
      kurze Reglerzeilen und kleinere Bedienelemente, damit er bei normaler
      Fenstergröße ohne störendes Überragen nutzbar bleibt.
- [ ] **Detaillierte Design-Vorgabe** für eigene Skins in `assets/README.md`
      (9-Patch-Ränder, Maße, Zustände, Schrift, Farben) — Pflicht, damit andere
      Skins „einfach passen".

**C) Technisch (für die Umsetzung)**
- UI strikt von der Spiel-Logik trennen (eigene Skin-/Theme-Schicht analog
  `GameTheme`, z. B. `game/ui_skin.gd`). Stretch-Modus bleibt `canvas_items`
  (skaliert die UI mit dem Fenster); 9-Patch hält Rahmen scharf.
- Tooltips/Infofenster lesen aus `core/` (read-only), kein Logik-Code im UI.

**D) Recherche-Abgleich S2 / RTTR (Stand 2026-06-09)**
- Siedler-2-Referenz: Bauplatzansicht per **Space**, separate Hotkeys/Fenster für
  Bauen (**B**), Statistik (**C**), Inventar (**I**), globale Wirtschaft (**L**),
  Minikarte (**M**), Meldungen (**N**), Einstellungen (**S**), UI aus/an (**Y**)
  und HQ-Sprung (**H**). Quelle: Ubisoft-Handbuch/ManualsPlus:
  https://manuals.plus/ubisoft/the-settlers-ii-10th-anniversary-pc-cd-rom-game-manual
- Bedienprinzip daraus: weniger dauerhafte Textleisten, mehr kontextuelle Fenster.
  Klick auf sichtbare Bauplätze soll direkt zum passenden Bau-/Flaggenfenster
  führen; Rechtsklick/Esc später als universelles Schließen/Abbrechen.
- Deutsches S2-Gold-Handbuch: Das Baufenster hat in der zweiten Reihe die
  Gebäudekategorien Bergwerk/kleines/mittleres/großes Haus; die Bauhilfe zeigt
  gelbe Symbole für Fahne, kleines Haus, mittleres Haus, großes Haus, Bergwerk
  und Hafen/Haus. Mittlere/große Bauplätze dürfen kleinere Gebäude aufnehmen,
  umgekehrt nicht.
  Quelle: https://www.mogelpower.de/manuals/Die_Siedler_2_Gold_Deutsch_Manual.pdf
- RTTR-Referenz: Open-Source-S2-Rewrite mit modernen Optionen/Addon-Settings und
  originalnahem Fenster-/Wirtschaftsgefühl, aber ohne Code-Übernahme.
  Quellen: https://github.com/Return-To-The-Roots/s25client und https://www.siedler25.org/
- Für Grenzmark festgelegt: S2-Hotkeys werden als Orientierung übernommen, aber
  die A*-Straßenplanung bleibt vorerst als komfortable Abweichung erhalten.

### Stufe 9 — Zusatz & Feinschliff
- [ ] Träger-Warteverhalten optisch verbessern: wartende Träger stehen aktuell
      direkt auf der Straße; später Warte-/Idle-Animationen oder kleine
      Ausweichpositionen neben der Straße einbauen, damit Wege lebendiger und
      weniger blockiert wirken.

## Lücken zu den Originalen (Die Siedler 2 / RTTR) — Prüfliste

Was die Vorbilder haben und uns noch fehlt, grob nach Wichtigkeit. Das ist die
Arbeitsliste, bis das Spiel „vollständig" ist (Ton/Musik kommt ganz zuletzt).

### Aktueller Abgleich mit Die Siedler 2 (Stand 2026-06-08)

**Schon nah dran / bewusst als Fundament erreicht:**
- [x] S2-artiges 6-Nachbar-Knotengitter mit zwei Terrain-Dreiecken pro Knoten.
- [x] Flaggen-/Straßennetz, Träger, Waren an Flaggen, HQ-Lager und Gebäudeproduktion.
- [x] Bauplatzgrößen, Territorium durch Militärgebäude, Grenzsteine, Nebel,
      Baumwachstum, Förster/Holzfäller und mehrstufige Ressourcen.

**Noch deutlich anders als S2 / RTTR:**
- [ ] Straßenbau ist komfortabler Auto-Pfad per A* statt klassischem Segmentbau.
      Das ist gewollt, aber ein optionaler Klassikmodus wäre ein S2-näherer Ausbau.
- [ ] Warenfluss ist noch zu HQ-zentriert; S2 verteilt zwischen Lagern und
      Gebäuden mit Prioritäten, Einzugsgebieten und lokalen Lagerbeständen.
- [x] Bevölkerung, Berufe und Werkzeuge begrenzen die Wirtschaft (Issue #9):
      Träger = HELPER, Arbeiter = Beruf (sonst HELPER + Werkzeug rekrutiert), Bau =
      BUILDER; ohne Personal bleibt Straße/Gebäude unbesetzt, Abriss gibt zurück.
      Noch offen: Nachschub/Wachstum neuer Siedler über die Zeit.
- [ ] Gebäude-UI fehlt als S2-Hauptgefühl: Produktivität, Warenpuffer,
      Produktion stoppen, Abriss, Militärbesatzung, Prioritäten und Warnungen.
- [ ] Geologe, Späher/Pionier, Planierer und Aussichtsturm/Spähturm fehlen als
      Spezialisten für Erkundung, Bergbau-Info, Gebietsausbau und Höhenarbeit.
      (Geologe/Späher/Nebel-Verzahnung: https://github.com/JobbeDeluxe/grenzmark/issues/21)
- [ ] Militär ist spielbar, aber noch vereinfacht: Rangstufen/Grafiken,
      wählbare Angreiferzahl, Schilde/mehr Waffen und Belagerungsdetails fehlen.
- [ ] Wasser/See-Spiel fehlt komplett: Hafen, Werft, Boote/Schiffe, Expedition
      und Inselbesiedlung.
- [ ] Spielfluss ist noch Sandbox-lastig: Missionen, Kampagne, Kartenwahl,
      Statistikseiten, Nachrichtenlog und Optionsmenüs fehlen.

**Bevölkerung & Träger (Kern, hoch):**
- [x] Echte Einwohnerzahl: Träger/Arbeiter sind begrenzte Bevölkerung aus dem HQ
      (Issue #9) — ohne Personal bleibt Straße/Gebäude unbesetzt, Abriss gibt zurück.
- [x] Werkzeuge: Berufe brauchen passendes Werkzeug zur Rekrutierung (HELPER +
      Werkzeug → Spezialist). Offen bleibt der Nachschub über Werkzeugmacher-Kette.
- [ ] Nachschub/Wachstum: HQ/Lager erzeugt mit der Zeit neue Siedler (S2-Bevölkerung)
- [ ] Esel/Eselzüchter: Esel als Träger auf stark genutzten Straßen
- [ ] Straßen-Ausbau zu „Eselstraßen"; mehrere Träger bei Stau

**Fehlende Gebäude (ggü. Original) — Katalog erweitern:**
Vorhanden (21): HQ, Holzfäller, Förster, Sägewerk, Steinbruch, Brunnen, Bauernhof,
Mühle, Bäckerei, Fischerhütte, Kohle-/Eisen-/Goldmine, Eisenschmelze,
Münzprägerei, Brauerei, Schmiede, Wachhaus, Wachturm, Festung, Katapult.
- [x] Jägerhütte (→ Fleisch)
- [x] Schweinefarm (Getreide + Wasser → Schwein) + Schlachterei (Schwein → Fleisch)
- [x] Werkzeugmacher (Bretter + Eisen → konkrete Einzelwerkzeuge nach Prioritäten/
      Bestellungen, gewichteter seeded-Zufall wie RTTR nofMetalworker)
- [~] 4 Erzsorten (Kohle/Eisen/Gold/Granit) als Adern + Granitmine; jede Mine
      baut nur ihr passendes Mineral ab. Offen: Erz im Normalspiel unterirdisch
      statt sichtbar führen; Sichtbarkeit später über Geologen/Debug.
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/19)
- [x] Lagerhaus / Vorratshaus (zweites Lager) — Stufe 1 (Kern) fertig
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/31)
      `storehouse` baubar (Kategorie „lager", mittlerer Bauplatz, Bretter+Steine);
      Economy führt eine `storages`-Liste (HQ = Lager #0). Waren-Routing bedient das
      NÄCHSTE Lager (`_nearest_storage`, Hop-Distanz der gecachten `find_route`);
      eigener Tür-Träger je Lager; Save/Load der Lagerhaus-Bestände; Abriss räumt das
      Lager ab (Restbestand → HQ). Offen (Stufe 2/3): Ein-/Auslagern-Stopp je Ware,
      Warenausgleich, Personen/Soldaten aus jedem Lager.
- [ ] Eselzüchter (→ Esel) — braucht Esel-auf-Straßen-System
- [x] Waffenschmiede (Schmiede) liefert abwechselnd Schwert UND Schild (RTTR Armory)
- [ ] Hafen + Werft (Schiffe/Boote)
- [ ] Baracke / weitere Militär-Stufen, Spähturm

**Wirtschaft (hoch):**
- [ ] Mehrere Lagerhäuser/Vorratshäuser mit eigenem Inventar
- [ ] Warenverteilung & Prioritäten (welches Gebäude bekommt was zuerst)
- [x] Gebäude-Produktion an/aus schalten (Taste P am gewählten Gebäude)
- [ ] Produktion drosseln (Prozent), Eingangsmengen begrenzen
- [ ] Direkte Gebäude→Gebäude-Lieferung (nicht alles über HQ)
- [x] Felder: Bauer sät/erntet Getreide-Felder (Acker als Map-Objekt, Issue #26),
      original-getreu an RTTR nofFarmer/noGrainfield abgeglichen:
      * Suchradius 2 (RTTR GetWorkRadius), sammelt alle gültigen Plätze und wählt
        seeded ZUFÄLLIG — Class1 (reife Felder ernten) vor Class2 (säen).
      * Saatregel = keine Straße auf dem Knoten, fruchtbare Wiese, kein Feld/Gebäude
        direkt daneben (Felder brauchen Lücken). Säen liefert kein Getreide, erst
        die Ernte. 4 Wachstumsstufen über `field_growth_stage_ticks`.
      * Neben einem wachsenden Feld ist nur eine Flagge möglich (RTTR FlagsAround).
      * Ernte → nicht-blockierendes Stoppelfeld; ungeerntetes reifes Feld verdorrt
        nach `field_wither_ticks`. Beide Deko-Arten verschwinden nach
        `field_decay_ticks` und blockieren nichts (Bau/Säen sofort wieder möglich).
- [x] Produktivitäts-Anzeige je Gebäude (% wie im Original; rollendes Fenster,
      sichtbar im Gebäudefenster)

**Karte & Erkundung (hoch):**
- [ ] Geologen: erkunden Berge & decken die Erzsorte auf (Schilder), bevor Minen lohnen
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/21)
- [x] Nebel des Krieges / Sichtbarkeit nur im erkundeten Gebiet (Taste F);
      auch im Hauptmenü als Startoption einstellbar.
- [ ] Erdarbeiter (Planierer) ebnen Bauland; Höhe beeinflusst Bau stärker
- [x] Fisch als endlicher Kartenbestand statt unendliche Wasserquelle (Issue #6,
      RTTR nofFisher): Küstenknoten (Wasser+Land) bekommen einen versteckten
      Fischvorrat (`fish_per_node`), der Fischer baut ihn ab, erschöpfte Gründe
      werden übersprungen; ist nichts mehr in Reichweite, wartet die Hütte mit
      Warnung „Keine Fische in Reichweite". Save/Load erhält den Bestand.
      Regeneration/Schwärme bleiben optional offen.
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/6)
- [ ] Jäger als echte Naturressource: Wildtiere spawnen nur in/nahe Waldclustern
      außerhalb dichter Bebauung (Startregel: mindestens ca. 10 große Bäume im
      Suchradius), laufen auf der Karte und werden gezielt gejagt statt freier
      Fleischproduktion.
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/7)

**Militär (mittel):**
- [ ] Soldaten-Ränge mit Stufen (Gefreiter→General), Beförderung sichtbar
- [ ] Angriff mit wählbarer Soldatenzahl; Gebäude-Belagerung
- [ ] Gebäudegrößen-Ausbau (kleines→großes Militärgebäude)
- [x] Schilde + Schwerter + Bier + Träger nötig, um Soldaten im HQ zu rekrutieren
      (RTTR: min(Schwert,Schild,Bier,Helper) × Rekrutierungsrate). Rate als Regler-Wert
      vorbereitet; UI-Regler-Seite folgt (Stufe 8). (Issue #41)

**Wasser & See (mittel):**
- [ ] Häfen, Werften, Schiffe; Warentransport über Wasser
- [ ] Expedition/Besiedlung von Inseln

**Spielfluss & UI (mittel):** → gesammelt in **Stufe 8 (UI)** oben; zusätzlich:
- [ ] Spielziele/Missionen, Sieg-/Niederlage-Bedingungen wählbar
- [ ] Mehr/stärkere KI-Gegner, Bündnisse, Schwierigkeitsgrade

**Neu beim Original-Abgleich aufgefallen (offen):**
- [ ] Spähturm/Aussichtsturm: deckt Umgebung im Nebel auf (passt zu Stufe 1 Nebel)
- [ ] Spezial-Einheiten ohne Gebäude: Geologe, Späher, Pionier (Geologe siehe oben)
      (Issue: https://github.com/JobbeDeluxe/grenzmark/issues/21)
- [ ] Eroberte Gebäude brennen kurz / Übergangsanimation
- [ ] Gebäude-Abriss gibt einen Teil der Baustoffe zurück
- [ ] Träger-Stau sichtbar (volle Flagge blockiert), Vorfahrtsregeln an Kreuzungen
- [ ] „Goldene" Grenzsteine je Spielerfarbe (passt zu austauschbarem Grenzstein-Design)

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
  goods.gd            # Warentypen
  map_data.gd         # Karte: Höhen + Terrain + Objekte/Erzsorten pro Knoten
  map_generator.gd    # prozedurale Kartenerzeugung (Insel, Berge, Erzadern)
  building_catalog.gd # alle Gebäudedefinitionen (datengetrieben)
  world_state.gd      # Spielzustand: Flaggen/Straßen/Gebäude/BQ/Territorium/Pfade
  economy.gd          # Wirtschaftsherz: Träger, Waren, Produktion, Soldaten, HQ-Träger
  ai/ai_base.gd       # KI-Schnittstelle (austauschbar)
  ai/ai_default.gd    # Standard-Gegner-KI   ai/ai_passive.gd  ai/ai_registry.gd
game/                 # Godot: zeichnen + Eingabe + UI
  world.gd            # Aufbau, Eingabe, Bau-Modi, HUD, Save/Load
  map_renderer.gd     # statische Ebene (Terrain/Objekte/Gebäude/Gebiet)
  unit_renderer.gd    # dynamische Ebene (Träger/Arbeiter/Soldaten/Hover/Vorschau)
  camera_controller.gd# Schwenken + Zoom
  minimap.gd          # Minikarte
  theme_db.gd         # class GameTheme: austauschbare Optik + Config (design.json)
  menu.gd / menu.tscn # Hauptmenü
  design_editor.gd / design_preview.gd # DEV-Design-Editor (Größe/Position/Eingang)
  main.tscn           # Spiel-Szene
ai/                   # optionale eigene KI-Skripte des Nutzers (.gd)
assets/               # austauschbare Grafik + design.json (siehe assets/README.md)
tests/test_core.gd    # Headless-Selbsttests (aktuell 290)
ROADMAP.md • README.md • assets/README.md • ai/README.md
```

## Steuerung (Stand aktuell)
- **Rechte/mittlere Maustaste ziehen**: Karte schwenken  •  **Mausrad**: Zoom
- **Obere Warenleiste**: standardmäßig **aus** (im Original nicht vorhanden);
  über **System → Warenleiste** bzw. die Hauptmenü-Checkbox einblendbar. Die alte
  Debug-Anzeige oben links ist entfernt; kurze Rückmeldungen erscheinen als Toast.
- **Untere Hauptleiste**: **Bauen**, **Verwaltung**, **System** als Fensterzugriffe
  (Tasten **1** Flagge, **2** Straße, **9** Abriss, **0/Esc** Auswahl/Fenster zu)
- **Linksklick**: ausführen / im Auswahl-Modus Gebäude-Fenster öffnen
  (mehrere bleiben parallel offen), Gegnerangriff über das Gebäudefenster.
  Ein aus dem Baumenü gewähltes Gebäude wird wie im Original **einmal** gesetzt;
  danach zurück in den Auswahlmodus (kein Dauer-Stempelmodus).
- **Rechtsklick (ohne zu ziehen)**: universeller Abbrechen/Schließen wie in S2
  (bricht Bau-/Straßen-/Abrissmodus ab, schließt Kontextmenüs/Fenster).
  Rechtsklick mit Bewegung schwenkt weiterhin die Kamera.
- **Leertaste**: Bauplätze einblenden; bei sichtbaren Markern öffnet Klick auf
  Hütte/Haus/Burg/Mine das passende Baufenster, Flaggenmarker setzen direkt Flaggen
- **B**: Baufenster mit Aktionszeile + Kategorien Bergwerk/Klein/Mittel/Gross
  •  **I**: Wirtschaft/Waren  •  **S**: System/Design-Übersicht
- **M**: Minikarte an/aus  •  **H**: zum HQ springen  •  **Y**: UI an/aus
- **F**: Nebel an/aus  •  **Pause**: pausieren
- **+/-**: Tempo  •  **P**: Produktion des gewählten Gebäudes an/aus
- **K**: Gegner-KI an/aus  •  **J**: Gegner-KI wechseln
- **F2/F3** Speichern/Laden  •  **F5** Neues Spiel
- **Minikarte unten rechts**: Klick zentriert die Kamera
- **Hauptmenü → Einstellungen**: eigene Einstellungsseite mit UI-Größe
  klein/mittel/groß und Startoptionen für Bauhilfe, Nebel und KI
- **Hauptmenü → Design-Editor**: Gebäudegrößen/Position/Eingang live einstellen

## Architektur-Notizen (für Wiedereinstieg)
- `core/economy.gd` ist das Wirtschaftsherz: HQ-zentriert. Gebäude fordern
  Eingänge vom HQ an, liefern Ausgänge zum HQ. `BState` pro Gebäude.
- `core/building_catalog.gd` = alle Gebäudedefinitionen (Kosten/Ein-/Ausgänge/
  Ressource/Einfluss). Neues Gebäude → nur hier ergänzen + Kürzel in `theme_db.gd`.
- `game/theme_db.gd` (class `GameTheme`) = austauschbare Optik (Farben/Kürzel,
  später Texturen). NICHT mit Godots eingebautem `ThemeDB` verwechseln.
- Determinismus: feste 30-Hz-Ticks, keine ungeseedete Zufälligkeit in `core/`.
