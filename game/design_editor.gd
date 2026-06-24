extends Control

## DEV/Design-Editor: in EINER Liste links Gebäude UND Bauplatz-Symbole auswählen,
## rechts Größe/Eingang bzw. Icon-Offset live einstellen und in assets/design.json
## speichern. Erreichbar über Hauptmenü -> Einstellungen -> Design-Editor.

const DESIGN_PATH := "res://assets/design.json"

# Bauplatz-Symbole (Leertaste-Menü) mit deutscher Bezeichnung für die Liste.
const BSPOT_KEYS := ["flag", "road_flag", "castle", "house", "hut", "mine", "harbor", "blocked"]
const BSPOT_NAMES := {
	"flag": "Flagge", "road_flag": "Straßen-Flagge", "castle": "Burg-/HQ-Platz",
	"house": "Haus-Platz", "hut": "Hütte-Platz", "mine": "Minen-Platz",
	"harbor": "Hafen-Platz",
	"blocked": "Gesperrt-Marker",
}

# Karten-Objekte (Felder etc.) — frei skalierbar über design.json "object_sizes".
const OBJ_KEYS := ["field_seed", "field_young", "field_growing", "field_ripe",
	"field_cut", "field_withered"]
const OBJ_NAMES := {
	"field_seed": "Feld – Saat", "field_young": "Feld – jung",
	"field_growing": "Feld – wachsend", "field_ripe": "Feld – reif",
	"field_cut": "Feld – Stoppel", "field_withered": "Feld – verdorrt",
}

var cfg := {}
var ids: Array = []
var current_id := "hq"
var _loading := false

# Listeneinträge: { kind = "header"|"building"|"bspot", key = <id/bspot-key> }
var _entries: Array = []

var _preview: DesignPreview
var _bld_group: VBoxContainer
var _bspot_group: VBoxContainer
var _w: SpinBox
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

var _obj_group: VBoxContainer
var _obj_key := "field_ripe"
var _obj_w: SpinBox
var _obj_h: SpinBox


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
	var list_w := 170.0
	var side_w := 232.0

	# Titel
	var title := Label.new()
	title.text = "Design-Editor — Größe & Eingang"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	# Auswahl-Liste links: Gebäude + Bauplatz-Symbole, je mit Kategorie-Überschrift.
	var list := ItemList.new()
	list.position = Vector2(12, top_y)
	list.size = Vector2(list_w, vp.y - top_y - 12)
	_build_entries(list)
	list.item_selected.connect(_on_pick)
	add_child(list)

	# Vorschau Mitte
	_preview = DesignPreview.new()
	_preview.position = Vector2(196, top_y)
	_preview.size = Vector2(maxf(260.0, vp.x - list_w - side_w - 64.0), vp.y - top_y - 12)
	add_child(_preview)

	# Regler rechts in einem ScrollContainer.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(vp.x - side_w - 12.0, top_y)
	scroll.size = Vector2(side_w, vp.y - top_y - 12)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(side_w - 18.0, 0)
	panel.add_theme_constant_override("separation", 4)
	scroll.add_child(panel)

	# --- Gruppe Gebäude (nur sichtbar, wenn ein Gebäude gewählt ist) ---
	_bld_group = VBoxContainer.new()
	_bld_group.add_theme_constant_override("separation", 4)
	panel.add_child(_bld_group)

	# Eine Größe: das Sprite wird quadratisch & seitenverhältniserhaltend skaliert.
	_w = _spin(_bld_group, "Größe (skaliert ganzes Objekt)", 6, 160, 1)
	_ox = _spin(_bld_group, "Bild-Versatz X (zur Flagge)", -60, 60, 1)
	_oy = _spin(_bld_group, "Bild-Versatz Y", -60, 60, 1)
	_ex = _spin(_bld_group, "Eingang X (Tür)", -60, 60, 1)
	_ey = _spin(_bld_group, "Eingang Y (Tür)", -80, 40, 1)
	_tscale = _spin(_bld_group, "Textur-Skalierung ×10", 5, 60, 1)  # /10, global
	_usize = _spin(_bld_group, "Einheiten-Höhe (global)", 6, 64, 1)

	var clabel := Label.new()
	clabel.text = "Vergleichsobjekt"
	clabel.add_theme_font_size_override("font_size", 11)
	_bld_group.add_child(clabel)
	_compare = OptionButton.new()
	_compare.custom_minimum_size = Vector2(206, 26)
	_compare.add_item("— keins —")
	for id in ids:
		_compare.add_item(String(BuildingCatalog.get_def(id).get("name", id)))
	_compare.item_selected.connect(_on_compare)
	_bld_group.add_child(_compare)

	var hint := Label.new()
	hint.text = "Bild-Versatz verschiebt das Sprite.\nEingang = Weg-Ende an der Tür.\nGröße skaliert das ganze Objekt."
	hint.add_theme_font_size_override("font_size", 10)
	_bld_group.add_child(hint)

	# --- Gruppe Bauplatz-Symbol (nur sichtbar, wenn ein Symbol gewählt ist) ---
	_bspot_group = VBoxContainer.new()
	_bspot_group.add_theme_constant_override("separation", 4)
	panel.add_child(_bspot_group)

	var bspot_title := Label.new()
	bspot_title.text = "Bauplatz-Icon Offset (Leertaste)"
	bspot_title.add_theme_font_size_override("font_size", 12)
	_bspot_group.add_child(bspot_title)
	_bspot_ox = _spin_bspot(_bspot_group, "Offset X", -60, 60, 1)
	_bspot_oy = _spin_bspot(_bspot_group, "Offset Y", -60, 60, 1)
	var bspot_hint := Label.new()
	bspot_hint.text = "Verschiebt das Icon vom Knotenmittelpunkt."
	bspot_hint.add_theme_font_size_override("font_size", 10)
	_bspot_group.add_child(bspot_hint)

	# --- Gruppe Karten-Objekt (nur sichtbar, wenn ein Objekt gewählt ist) ---
	_obj_group = VBoxContainer.new()
	_obj_group.add_theme_constant_override("separation", 4)
	panel.add_child(_obj_group)
	var obj_title := Label.new()
	obj_title.text = "Objekt-Größe (Breite × Höhe)"
	obj_title.add_theme_font_size_override("font_size", 12)
	_obj_group.add_child(obj_title)
	_obj_w = _spin_obj(_obj_group, "Breite (px)", 6, 160, 1)
	_obj_h = _spin_obj(_obj_group, "Höhe (px)", 4, 160, 1)
	var obj_hint := Label.new()
	obj_hint.text = "Skaliert das Objekt-Sprite (z. B. Felder).\nZur Orientierung: eine Kachel ist 64×32."
	obj_hint.add_theme_font_size_override("font_size", 10)
	_obj_group.add_child(obj_hint)

	# --- Immer sichtbar: Speichern / Zurück / Status ---
	var sep := HSeparator.new()
	panel.add_child(sep)
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

	# Startauswahl: erstes Gebäude.
	var first := _first_index_of_kind("building")
	list.select(first)
	_on_pick(first)


## Füllt _entries und die ItemList mit zwei Kategorien (Überschriften nicht wählbar).
func _build_entries(list: ItemList) -> void:
	_entries.clear()
	_add_header(list, "— Gebäude —")
	for id in ids:
		_entries.append({ kind = "building", key = id })
		list.add_item(String(BuildingCatalog.get_def(id).get("name", id)))
	_add_header(list, "— Bauplatz-Symbole —")
	for k in BSPOT_KEYS:
		_entries.append({ kind = "bspot", key = k })
		list.add_item(String(BSPOT_NAMES.get(k, k)))
	_add_header(list, "— Karten-Objekte —")
	for k in OBJ_KEYS:
		_entries.append({ kind = "object", key = k })
		list.add_item(String(OBJ_NAMES.get(k, k)))


func _add_header(list: ItemList, text: String) -> void:
	_entries.append({ kind = "header", key = "" })
	var idx := list.add_item(text)
	list.set_item_selectable(idx, false)
	list.set_item_custom_fg_color(idx, Color(0.6, 0.7, 0.8))


func _first_index_of_kind(kind: String) -> int:
	for i in _entries.size():
		if _entries[i].kind == kind:
			return i
	return 0


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	var e: Dictionary = _entries[idx]
	match e.kind:
		"building":
			_bld_group.visible = true
			_bspot_group.visible = false
			_obj_group.visible = false
			_select(String(e.key))
		"bspot":
			_bld_group.visible = false
			_bspot_group.visible = true
			_obj_group.visible = false
			_select_bspot(String(e.key))
		"object":
			_bld_group.visible = false
			_bspot_group.visible = false
			_obj_group.visible = true
			_select_object(String(e.key))


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


func _select(id: String) -> void:
	_preview.bspot_key = ""  # zurück zur Gebäude-Vorschau
	_preview.obj_key = ""
	current_id = id
	_preview.current_id = id
	_loading = true
	var dims := GameTheme.building_dims(BuildingCatalog.get_def(id).get("size", WorldState.BQ_HUT), id)
	_w.value = dims.x
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
	# Eine Größe: quadratisch, seitenverhältniserhaltend (building_dims liest den Skalar).
	cfg.get_or_add("building_sizes", {})[current_id] = int(_w.value)
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


func _select_bspot(key: String) -> void:
	_bspot_key = key
	_preview.bspot_key = key
	_preview.obj_key = ""
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


func _spin_obj(box: VBoxContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
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
	s.value_changed.connect(_on_obj_changed)
	row.add_child(s)
	return s


func _select_object(key: String) -> void:
	_obj_key = key
	_preview.bspot_key = ""
	_preview.obj_key = key
	_loading = true
	var sz := GameTheme.object_draw_size(key)
	_obj_w.value = roundf(sz.x)
	_obj_h.value = roundf(sz.y)
	_loading = false
	_preview.queue_redraw()


func _on_obj_changed(_v: float) -> void:
	if _loading:
		return
	cfg.get_or_add("object_sizes", {})[_obj_key] = [int(_obj_w.value), int(_obj_h.value)]
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
