# Contributing To Grenzmark

Thanks for wanting to help.

## Good First Areas

- Add original building sprites in `assets/buildings/`.
- Add unit walk sheets in `assets/units/`.
- Improve terrain transitions and map generation.
- Add missing economy buildings and production chains.
- Add focused tests in `tests/`.
- Improve AI behavior without breaking deterministic simulation.

## Development Rules Of Thumb

- Keep core simulation in `core/` independent from Godot scene nodes.
- Keep rendering, input, and UI in `game/`.
- Prefer deterministic logic: fixed ticks, explicit seeds, no hidden randomness.
- Add tests for shared simulation behavior.
- Keep assets original, permissively licensed, or clearly attributed.

## Assets

Do not submit copyrighted files from commercial games. Original work, generated
work made for this project, or compatible open assets with attribution are fine.

See `assets/README.md` for filenames, sprite sizes, and design notes.

## Tests

Run:

```powershell
.\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_core.gd
```
