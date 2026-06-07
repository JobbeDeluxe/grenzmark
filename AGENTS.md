# AGENTS.md — Anweisungen für KI-Agenten (und menschliche Mitlesende)

> **TL;DR (English):** Grenzmark is a **100% AI-written** reimplementation of the
> classic build-up gameplay of *Die Siedler II* / *Return to the Roots* / *Widelands*.
> Humans act only as **testers / feedback givers**, not as code authors — that is
> an explicit project goal. Main repo: **https://github.com/JobbeDeluxe/grenzmark**.
> Contribute via Pull Request. **Never copy unlicensed/original game files or do
> 1:1 copies** of protected assets/code — concepts only, original implementation.

## Ziel des Projekts
Grenzmark soll die **Spielmechanik** der Siedler-2-Reihe (und der freien Vorbilder
RTTR/Widelands) möglichst originalgetreu **neu nachbauen** — in Godot 4 / GDScript,
mit **eigenem Code und austauschbaren, frei lizenzierten Assets**.

Besonderheit und ausdrücklicher Wunsch: **Das Spiel wird zu 100 % von KI
geschrieben.** Menschen sind hier **Tester**, geben Feedback und Richtung, aber
der Code (und idealerweise auch die Assets) entstehen durch KI-Agenten. Das ist
gewollt und Teil des Experiments. Die Entwicklung wird teils live gestreamt:
**https://www.twitch.tv/jobbedeluxe**

## Was du als Agent wissen musst
- **Architektur:** `core/` = reine Simulation ohne Godot-Szenenbaum (testbar,
  deterministisch, multiplayer-vorbereitet). `game/` = Rendering, Eingabe, UI.
  UI/Render ruft nur `core/` auf, nie umgekehrt.
- **Determinismus:** keine ungeseedete Zufälligkeit in `core/`; feste 30-Hz-Ticks.
  Voraussetzung für späteren Lockstep-Multiplayer.
- **Gitter:** versetztes Dreiecks-/Hex-Gitter, 6 Nachbarn pro Knoten, 2 Terrain-
  Dreiecke pro Knoten. Flaggen/Straßen/Bauplätze bauen darauf auf.
- **Plan & Stand:** siehe [`ROADMAP.md`](ROADMAP.md) (Stufenplan + Lücken zu den
  Originalen + nächste große Aufgabe: UI in Stufe 8).
- **Bekannte Fehler:** siehe [`KNOWN_BUGS.txt`](KNOWN_BUGS.txt) — vor neuen
  Features bitte prüfen/ergänzen (mit Datum).
- **Assets/Design:** [`assets/README.md`](assets/README.md) beschreibt exakt,
  wie austauschbare Grafik/Animationen/UI-Skins auszusehen haben. Größen/Eingänge
  sind ohne Code über `assets/design.json` (und den Design-Editor im Menü) einstellbar.
- **KI-Plugins:** eigene Gegner-KIs siehe [`ai/README.md`](ai/README.md).

## Arbeitsweise
- **Erst lesen, dann ändern:** ROADMAP, KNOWN_BUGS und die passenden `core/`-Dateien.
- **Tests laufen lassen** (headless), Ergebnis muss grün bleiben:
  ```
  Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_core.gd
  ```
  Für neue Logik möglichst einen Test in `tests/test_core.gd` ergänzen.
- **Doku pflegen:** ROADMAP (erledigt abhaken / Neues ergänzen), bei Bugs die
  KNOWN_BUGS.txt aktualisieren.
- **Sprache:** Code-Kommentare und Doku auf Deutsch (Projektsprache).

## Beitragen (Pull Requests)
1. Branch von `main`, Änderung umsetzen, Tests grün halten.
2. **Pull Request** gegen `main` auf https://github.com/JobbeDeluxe/grenzmark eröffnen.
3. **Im PR angeben, welches KI-Modell/welcher Agent** die Änderung erstellt hat
   (z. B. „Modell/Agent: <Name/Version>") — das ist für dieses Projekt erwünscht.
4. Kurz beschreiben: Was, Warum, welche Tests, welche ROADMAP-Punkte betroffen.

## Rechtliches / Grenzen (wichtig)
- **Keine 1:1-Kopien** von urheberrechtlich geschütztem Material: keine
  Original-Siedler-2-Dateien (Grafik/Töne/Daten von CD), keine kopierten
  Code-Abschnitte aus RTTR/Widelands. **Konzepte als Vorbild ja, Kopie nein.**
- Eigene oder frei lizenzierte Assets verwenden; bei Open-Source-Assets (z. B.
  Widelands, GPL/CC-BY-SA) die Lizenz beachten und kennzeichnen.
- Keine proprietären Dateien ins Repo committen.
