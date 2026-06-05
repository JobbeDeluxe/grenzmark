extends Control

## Einfaches Hauptmenü: Neues Spiel, Laden, Beenden.

const WORLD_SCENE := "res://game/main.tscn"
const SAVE_PATH := "user://settlers_save.dat"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CenterContainer zentriert sein Kind in jeder Fenstergröße.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(240, 240)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "GRENZMARK"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "klassischer Aufbau auf Knoten, Flaggen und Wegen"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	_button(box, "Neues Spiel", _on_new)
	var load_btn := _button(box, "Spiel laden", _on_load)
	load_btn.disabled = not FileAccess.file_exists(SAVE_PATH)
	_button(box, "Design-Editor", _on_editor)
	_button(box, "Beenden", _on_quit)


func _on_editor() -> void:
	get_tree().change_scene_to_file("res://game/design_editor.tscn")


func _button(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _on_new() -> void:
	World.boot_load = false
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_load() -> void:
	World.boot_load = true
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	get_tree().quit()
