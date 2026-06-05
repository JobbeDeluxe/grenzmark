class_name DesignPreview
extends Control

## Live-Vorschau eines Gebäudes für den Design-Editor: zeichnet Gebäude, Flagge
## (auf dem SE-Nachbarknoten) und den Eingangsweg zur Tür — genau wie im Spiel,
## nur vergrößert. Liest direkt aus GameTheme (das der Editor live aktualisiert).

const PZ := 2.4  # Vorschau-Zoom

var current_id := "hq"
var compare_id := ""  # optionales Vergleichsobjekt


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.20, 0.16))
	var origin := Vector2(size.x * 0.42, size.y * 0.62)
	var def := BuildingCatalog.get_def(current_id)
	if def.is_empty():
		return

	# Vergleichsobjekt rechts (gleiche Grundlinie), damit Größen vergleichbar sind.
	if compare_id != "" and not BuildingCatalog.get_def(compare_id).is_empty():
		var cpos := Vector2(size.x * 0.75, origin.y)
		_paint_building(compare_id, cpos)
		var lbl := String(BuildingCatalog.get_def(compare_id).get("name", compare_id))
		draw_string(ThemeDB.fallback_font, cpos + Vector2(-30, 16), "Vergleich: " + lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))

	# Flagge: SE-Nachbar eines Knotens (für gerade Zeile = (0,0)->(0,1)).
	var flag_rel := (Grid.node_to_world(0, 1, 0) - Grid.node_to_world(0, 0, 0)) * PZ
	var flag := origin + flag_rel
	var door := origin + GameTheme.entrance_offset(current_id) * PZ

	draw_circle(origin, 3.0, Color(1, 1, 1, 0.5))      # Gebäudeknoten
	draw_circle(flag, 3.0, Color(1, 1, 0.4, 0.6))      # Flaggenknoten
	draw_line(flag, door, Color(0.74, 0.60, 0.36), 4.0, true)  # Eingangsweg

	_paint_building(current_id, origin)

	# Flagge zeichnen
	draw_line(flag, flag + Vector2(0, -18), Color(0.2, 0.2, 0.2), 2.0)
	draw_rect(Rect2(flag.x, flag.y - 18, 11, 7), Color(0.9, 0.2, 0.2))
	draw_circle(door, 3.0, Color(0.3, 0.9, 0.4))       # Türpunkt


## Zeichnet ein Gebäude (mit Offset/Größe aus der Config) an der Grundlinie [param at].
func _paint_building(id: String, at: Vector2) -> void:
	var size_class: int = BuildingCatalog.get_def(id).get("size", WorldState.BQ_HUT)
	var dims := GameTheme.building_dims(size_class, id)
	var o := at + GameTheme.building_offset(id) * PZ
	var tex := GameTheme.building_texture(id)
	if tex != null:
		var sz := dims.x * GameTheme.texture_scale() * PZ
		if id == "hq":
			sz *= GameTheme.hq_scale()
		draw_texture_rect(tex, Rect2(o.x - sz * 0.5, o.y - sz, sz, sz), false)
	else:
		var w := dims.x * PZ
		var h := dims.y * PZ
		draw_rect(Rect2(o.x - w * 0.5, o.y - h, w, h), GameTheme.building_color(id))
		draw_rect(Rect2(o.x - w * 0.5, o.y - h, w, h), Color.BLACK, false, 1.5)