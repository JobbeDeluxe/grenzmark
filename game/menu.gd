extends Control

## Einfaches Hauptmenü: Neues Spiel, Laden, Beenden.

const WORLD_SCENE := "res://game/main.tscn"
const SAVE_PATH := "user://settlers_save.dat"
const MENU_BACKGROUND_PATH := "res://assets/ui/main_menu_background.png"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_add_background()

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


func _add_background() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(MENU_BACKGROUND_PATH):
		tex = load(MENU_BACKGROUND_PATH) as Texture2D
	if tex == null and FileAccess.file_exists(MENU_BACKGROUND_PATH):
		var image_data := Image.new()
		if image_data.load(MENU_BACKGROUND_PATH) == OK:
			tex = ImageTexture.create_from_image(image_data)
	if tex != null:
		var image := TextureRect.new()
		image.texture = tex
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(image)
	else:
		var fallback := ColorRect.new()
		fallback.color = Color(0.10, 0.14, 0.10)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fallback)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.018, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)


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
