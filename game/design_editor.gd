extends Control

## DEV/Design-Editor: Gebäude auswählen, Größe + Eingangspunkt (Tür/Weg-Ende)
## live einstellen und automatisch in assets/design.json speichern.
## Erreichbar über Hauptmenü -> Einstellungen -> Design-Editor.

const DESIGN_PATH := "res://assets/design.json"

var cfg := {}
var ids: Array = []
var current_id := "hq"
var _loading := false

var _preview: DesignPreview
var _w: SpinBox
var _h: SpinBox
var _ox: SpinBox
var _oy: SpinBox
var _ex: SpinBox
var _ey: SpinBox
var _tscale: SpinBox
var _usize: SpinBox
var _compare: OptionButton
var _status: Label

var _bspot_key := "flag"
var _bspot_ox: SpinBox
var _bspot_oy: SpinBox
var _bspot_select: OptionButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Config laden und GameTheme live darauf zeigen lassen.
	cfg = _load_cfg()
	GameTheme._cfg = cfg
	GameTheme._cfg_loaded = true

	ids = ["hq"]
	for id in BuildingCatalog.menu_order():
		ids.append(id)

	var vp := get_viewport_rect().size
	var top_y := 38.0
	var list_w := 156.0
	var side_w := 232.0

	# Titel
	var title := Label.new()
	title.text = "Design-Editor — Größe & Eingang"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	# Gebäudeliste links
	var list := ItemList.new()
	list.position = Vector2(12, top_y)
	list.size = Vector2(list_w, vp.y - top_y - 12)
	for id in ids:
		list.add_item(String(BuildingCatalog.get_def(id).get("name", id)))
	list.item_selected.connect(_on_pick)
	add_child(list)
	list.select(0)

	# Vorschau Mitte
	_preview = DesignPreview.new()
	_preview.position = Vector2(180, top_y)
	_preview.size = Vector2(maxf(260.0, vp.x - list_w - side_w - 64.0), vp.y - top_y - 12)
	add_child(_preview)

	# Regler rechts — in einem ScrollContainer, damit alle Regler (inkl. Bauplatz-
	# Offset + Speichern-Button) auch bei vielen Einträgen erreichbar bleiben.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(vp.x - side_w - 12.0, top_y)
	scroll.size = Vector2(side_w, vp.y - top_y - 12)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(side_w - 18.0, 0)
	panel.add_theme_constant_override("separation", 4)
	scroll.add_child(panel)

	_w = _spin(panel, "Breite", 6, 160, 1)
	_h = _spin(panel, "Höhe", 6, 160, 1)
	_ox = _spin(panel, "Bild-Versatz X (zur Flagge)", -60, 60, 1)
	_oy = _spin(panel, "Bild-Versatz Y", -60, 60, 1)
	_ex = _spin(panel, "Eingang X (Tür)", -60, 60, 1)
	_ey = _spin(panel, "Eingang Y (Tür)", -80, 40, 1)
	_tscale = _spin(panel, "Textur-Skalierung ×10", 5, 60, 1)  # /10
	_usize = _spin(panel, "Einheiten-Höhe", 6, 64, 1)

	# Vergleichsobjekt
	var clabel := Label.new()
	clabel.text = "Vergleichsobjekt"
	clabel.add_theme_font_size_override("font_size", 11)
	panel.add_child(clabel)
	_compare = OptionButton.new()
	_compare.custom_minimum_size = Vector2(206, 26)
	_compare.add_item("— keins —")
	for id in ids:
		_compare.add_item(String(BuildingCatalog.get_def(id).get("name", id)))
	_compare.item_selected.connect(_on_compare)
	panel.add_child(_compare)

	var hint := Label.new()
	hint.text = "Bild-Versatz verschiebt das Sprite.\nEingang = Weg-Ende an der Tür."
	hint.add_theme_font_size_override("font_size", 10)
	panel.add_child(hint)

	# --- Bauplatz-Icon-Offset (Leertaste-Menü) ---
	var sep := HSeparator.new()
	panel.add_child(sep)
	var bspot_title := Label.new()
	bspot_title.text = "Bauplatz-Icon Offset (Leertaste)"
	bspot_title.add_theme_font_size_override("font_size", 12)
	panel.add_child(bspot_title)

	_bspot_select = OptionButton.new()
	_bspot_select.custom_minimum_size = Vector2(206, 26)
	for bt in ["flag", "road_flag", "castle", "house", "hut", "mine", "blocked"]:
		_bspot_select.add_item(bt)
	_bspot_select.item_selected.connect(_on_bspot_pick)
	panel.add_child(_bspot_select)

	_bspot_ox = _spin_bspot(panel, "Offset X", -60, 60, 1)
	_bspot_oy = _spin_bspot(panel, "Offset Y", -60, 60, 1)

	var bspot_hint := Label.new()
	bspot_hint.text = "Verschiebt das Icon vom Knotenmittelpunkt."
	bspot_hint.add_theme_font_size_override("font_size", 10)
	panel.add_child(bspot_hint)

	_select_bspot("flag")

	var save := Button.new()
	save.text = "Speichern"
	save.custom_minimum_size = Vector2(206, 28)
	save.pressed.connect(_save_cfg)
	panel.add_child(save)

	var back := Button.new()
	back.text = "Zurück zum Menü"
	back.custom_minimum_size = Vector2(206, 28)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://game/menu.tscn"))
	panel.add_child(back)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	panel.add_child(_status)

	_select(current_id)


func _on_compare(idx: int) -> void:
	_preview.compare_id = "" if idx == 0 else String(ids[idx - 1])
	_preview.queue_redraw()


func _spin(box: VBoxContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(112, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 10)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(84, 24)
	s.value_changed.connect(_on_value_changed)
	row.add_child(s)
	return s


func _on_pick(idx: int) -> void:
	_select(ids[idx])


func _select(id: String) -> void:
	_preview.bspot_key = ""  # zurück zur Gebäude-Vorschau
	current_id = id
	_preview.current_id = id
	_loading = true
	var dims := GameTheme.building_dims(BuildingCatalog.get_def(id).get("size", WorldState.BQ_HUT), id)
	_w.value = dims.x
	_h.value = dims.y
	var bo := GameTheme.building_offset(id)
	_ox.value = bo.x
	_oy.value = bo.y
	var eo := GameTheme.entrance_offset(id)
	_ex.value = eo.x
	_ey.value = eo.y
	_tscale.value = roundf(GameTheme.texture_scale() * 10.0)
	_usize.value = GameTheme.unit_size()
	_loading = false
	_preview.queue_redraw()


## Nur Live-Vorschau aktualisieren — gespeichert wird erst per Button.
func _on_value_changed(_v: float) -> void:
	if _loading:
		return
	cfg.get_or_add("building_sizes", {})[current_id] = [int(_w.value), int(_h.value)]
	cfg.get_or_add("building_offset", {})[current_id] = [int(_ox.value), int(_oy.value)]
	cfg.get_or_add("entrance", {})[current_id] = [int(_ex.value), int(_ey.value)]
	cfg["texture_scale"] = _tscale.value / 10.0
	cfg["unit_size"] = _usize.value
	GameTheme._cfg = cfg          # Vorschau liest live aus GameTheme
	GameTheme._cfg_loaded = true
	_preview.queue_redraw()
	_status.text = "ungespeichert *"


func _spin_bspot(box: VBoxContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(112, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 10)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo; s.max_value = hi; s.step = step
	s.custom_minimum_size = Vector2(84, 24)
	s.value_changed.connect(_on_bspot_changed)
	row.add_child(s)
	return s


func _on_bspot_pick(idx: int) -> void:
	var types := ["flag", "road_flag", "castle", "house", "hut", "mine", "blocked"]
	_select_bspot(types[idx])


func _select_bspot(key: String) -> void:
	_bspot_key = key
	_preview.bspot_key = key
	_loading = true
	var off := GameTheme.build_spot_offset(key)
	_bspot_ox.value = off.x
	_bspot_oy.value = off.y
	_loading = false
	_preview.queue_redraw()


func _on_bspot_changed(_v: float) -> void:
	if _loading:
		return
	cfg.get_or_add("build_spot_offsets", {})[_bspot_key] = [int(_bspot_ox.value), int(_bspot_oy.value)]
	GameTheme._cfg = cfg
	GameTheme._cfg_loaded = true
	_preview.queue_redraw()
	_status.text = "ungespeichert *"


func _load_cfg() -> Dictionary:
	if FileAccess.file_exists(DESIGN_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
		if parsed is Dictionary:
			return parsed
	return {}


func _save_cfg() -> void:
	var f := FileAccess.open(DESIGN_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cfg, "  "))
		f.close()
		_status.text = "gespeichert ✓"
	else:
		_status.text = "Speichern fehlgeschlagen"
