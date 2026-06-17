class_name SaveManager
extends RefCounted

## Benannte Speicherpunkte (#27-Folge). Jeder Spielstand liegt als zwei Dateien in
## `user://saves/`: `<slug>.dat` (Spieldaten via store_var) und `<slug>.json`
## (kleine Metadaten für die Lade-Liste, ohne die große .dat lesen zu müssen).
## Gleicher Name = gleicher Slug = überschreibt den Slot.

const DIR := "user://saves/"
const LEGACY_PATH := "user://settlers_save.dat"   # alter Einzel-Speicherplatz


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## Dateiname-tauglicher Slug aus einem freien Namen.
static func slugify(name: String) -> String:
	var out := ""
	for c in name.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
		# alles andere (Umlaute, Sonderzeichen) wird verworfen
	out = out.lstrip("_").rstrip("_")
	if out.length() > 40:
		out = out.substr(0, 40)
	if out == "":
		out = "spielstand"
	return out


static func dat_path(slug: String) -> String:
	return DIR + slug + ".dat"


static func meta_path(slug: String) -> String:
	return DIR + slug + ".json"


## Schreibt Spieldaten + Metadaten. `data` wird um save_name/saved_at ergänzt.
static func write(slug: String, name: String, data: Dictionary) -> bool:
	ensure_dir()
	var now := int(Time.get_unix_time_from_system())
	data["save_name"] = name
	data["saved_at"] = now
	var f := FileAccess.open(dat_path(slug), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data, true)
	f.close()
	var meta := {
		"slug": slug,
		"name": name,
		"saved_at": now,
		"size": "%dx%d" % [int(data.get("w", 0)), int(data.get("h", 0))],
		"map_type": String(data.get("map_type", "flach")),
		"seed": String(data.get("map_seed_text", "")),
	}
	var mf := FileAccess.open(meta_path(slug), FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(meta))
		mf.close()
	return true


## Liest die Spieldaten eines Slugs (oder {} bei Fehler).
static func read(slug: String) -> Dictionary:
	return read_path(dat_path(slug))


static func read_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var(true)
	f.close()
	return d if d is Dictionary else {}


static func delete(slug: String) -> void:
	for p in [dat_path(slug), meta_path(slug)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Liste aller Spielstände, neueste zuerst. Liest nur die kleinen .json-Metas.
## Der alte Einzel-Speicherplatz wird als „Alter Spielstand" mit aufgeführt.
static func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		for fn in dir.get_files():
			if not fn.ends_with(".json"):
				continue
			var mf := FileAccess.open(DIR + fn, FileAccess.READ)
			if mf == null:
				continue
			var parsed = JSON.parse_string(mf.get_as_text())
			mf.close()
			if parsed is Dictionary:
				parsed["path"] = dat_path(String(parsed.get("slug", fn.get_basename())))
				out.append(parsed)
	if FileAccess.file_exists(LEGACY_PATH):
		out.append({
			"slug": "", "name": "Alter Spielstand", "saved_at": 0,
			"size": "?", "map_type": "?", "seed": "", "path": LEGACY_PATH, "legacy": true,
		})
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


## Pfad des zuletzt gespeicherten Standes (für „Schnell laden"); "" wenn keiner.
static func latest_path() -> String:
	var saves := list_saves()
	return String(saves[0].path) if saves.size() > 0 else ""


## Lesbares Datum für die Liste.
static func format_date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
