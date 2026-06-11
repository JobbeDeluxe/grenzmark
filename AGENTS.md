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
- **Fremde Änderungen NIE verwerfen — hinterfragen!** Es können **mehrere Agenten
  und Menschen gleichzeitig** an diesem Repo arbeiten (Live-Stream, paralleles
  Testen, Design-Editor). Tauchen beim Commit Änderungen auf, die du **nicht selbst
  gemacht** hast, dann lass sie **ungestaged** — wirf sie **niemals** mit
  `git checkout -- <datei>` / `git restore` / `git reset --hard` weg. Solche
  Änderungen sind, solange nie gestaged, **nicht aus git wiederherstellbar** und
  können echte Nutzerarbeit sein (z. B. `assets/design.json` aus dem Design-Editor).
  Beim selektiven Commit nur die **eigenen** Dateien gezielt `git add`en (kein
  `git add -A`). Achtung: Ein Spiel-/Szene-Smoke-Run kann Asset-Dateien neu
  schreiben (z. B. `assets/design.json` int→float, `assets/goods/*.png`) — das ist
  **kein Freibrief zum Verwerfen**, sondern dem Menschen zu melden, der entscheidet.
- **Commits (Windows-Falle!):** Auf Windows gibt es zwei getrennte Shells — eine
  **Bash**- und eine **PowerShell**-Umgebung. Die PowerShell-Here-String-Syntax
  `@'…'@` ist **nur** PowerShell und **funktioniert nicht im Bash-Tool**: dort
  landet ein verirrtes `@` am Anfang des Betreffs und am Ende der Nachricht.
  → Für **mehrzeilige Commit-Nachrichten** die Botschaft in eine Datei schreiben und
  `git commit -F <datei>` nutzen (oder mehrere `-m "…"`-Flags). Niemals Shell-Syntax
  der einen Umgebung im Tool der anderen verwenden. Commit-Message deutsch.

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
