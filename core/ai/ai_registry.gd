class_name AIRegistry
extends RefCounted

## Findet verfügbare Gegner-KIs: eingebaute + eigene Skripte aus `res://ai/`.
## Jeder Eintrag ist { id, name, path }. `create(entry)` erzeugt die Instanz.

const USER_AI_DIR := "res://ai/"


static func list() -> Array:
	var out: Array = []
	out.append({ id = "default", name = "Standard", path = "builtin:default" })
	out.append({ id = "passive", name = "Passiv", path = "builtin:passive" })
	# Eigene KIs aus res://ai/ einsammeln.
	var dir := DirAccess.open(USER_AI_DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var path := USER_AI_DIR + f
			var scr = load(path)
			if scr == null:
				continue
			var inst = scr.new()
			if inst is AIBase:
				out.append({ id = f.get_basename(), name = inst.ai_name(), path = path })
	return out


static func create(entry: Dictionary) -> AIBase:
	match String(entry.get("path", "")):
		"builtin:default": return DefaultAI.new()
		"builtin:passive": return PassiveAI.new()
	var scr = load(entry.path)
	if scr != null:
		var inst = scr.new()
		if inst is AIBase:
			return inst
	return DefaultAI.new()
