class_name DesignPreview
extends Control

## Live-Vorschau eines Gebäudes für den Design-Editor: zeichnet Gebäude, Flagge
## (auf dem SE-Nachbarknoten) und den Eingangsweg zur Tür — genau wie im Spiel,
## nur vergrößert. Liest direkt aus GameTheme (das der Editor live aktualisiert).
## Im bspot_key-Modus zeigt es stattdessen ein Bauplatz-Icon auf einem Knoten.

const PZ := 2.4  # Vorschau-Zoom

var current_id := "hq"
var compare_id := ""  # optionales Vergleichsobjekt
var bspot_key := ""   # wenn gesetzt: Bauplatz-Vorschau statt Gebäude-Vorschau
var obj_key := ""     # wenn gesetzt: Karten-Objekt-Vorschau (z. B. Feld)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.20, 0.16))
	var origin := Vector2(size.x * 0.42, size.y * 0.62)
	if bspot_key != "":
		_draw_bspot_preview(origin)
		return
	if obj_key != "":
		_draw_object_preview(origin)
		return
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


## Bauplatz-Vorschau: Knoten-Raute + Icon an der aktuellen Offset-Position.
func _draw_bspot_preview(origin: Vector2) -> void:
	# Knoten-Raute (wie im Spiel der Hover-Marker)
	var dr := 14.0 * PZ
	var d := PackedVector2Array([
		origin + Vector2(0, -dr), origin + Vector2(dr, 0),
		origin + Vector2(0, dr), origin + Vector2(-dr, 0),
	])
	draw_polyline(d + PackedVector2Array([d[0]]), Color(1, 1, 1, 0.55), 1.5)
	draw_circle(origin, 3.5, Color(1, 1, 0.4, 0.7))

	# Kreuz-Fadenkreuz am Knoten
	draw_line(origin + Vector2(-10, 0) * PZ, origin + Vector2(10, 0) * PZ, Color(1, 1, 0, 0.4), 1.0)
	draw_line(origin + Vector2(0, -10) * PZ, origin + Vector2(0, 10) * PZ, Color(1, 1, 0, 0.4), 1.0)

	# Icon an der Offset-Position
	var off := GameTheme.build_spot_offset(bspot_key) * PZ
	var sz := GameTheme.build_spot_size(bspot_key) * PZ
	var tex := GameTheme.build_spot_texture(bspot_key)
	var icon_c := origin + off
	if tex != null:
		draw_texture_rect(tex, Rect2(icon_c.x - sz.x * 0.5, icon_c.y - sz.y * 0.5, sz.x, sz.y), false)
	else:
		draw_circle(icon_c, sz.x * 0.35, Color(0.8, 0.8, 0.25, 0.9))

	# Verbindungslinie Knoten → Icon-Mitte (zeigt den Versatz)
	if off.length() > 2.0:
		draw_line(origin, icon_c, Color(1, 0.7, 0.3, 0.6), 1.2)

	draw_string(ThemeDB.fallback_font, origin + Vector2(-60, 46) * PZ,
		"Knoten · Offset (%.0f, %.0f)" % [off.x / PZ, off.y / PZ],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))


## Karten-Objekt-Vorschau: Kachel-Raute (64×32) als Größenreferenz + das Objekt-
## Sprite mittig auf dem Knoten, in der aktuell eingestellten Größe.
func _draw_object_preview(origin: Vector2) -> void:
	# Kachel-Raute zur Orientierung (eine Bodenkachel ist TILE_W×TILE_H).
	var hw := Grid.TILE_W * 0.5 * PZ
	var hh := Grid.TILE_H * 0.5 * PZ
	var tile := PackedVector2Array([
		origin + Vector2(0, -hh), origin + Vector2(hw, 0),
		origin + Vector2(0, hh), origin + Vector2(-hw, 0),
	])
	draw_colored_polygon(tile, Color(0.22, 0.34, 0.18))
	draw_polyline(tile + PackedVector2Array([tile[0]]), Color(1, 1, 1, 0.35), 1.5)
	draw_circle(origin, 3.0, Color(1, 1, 1, 0.5))  # Knotenmittelpunkt

	# Objekt-Sprite mittig (Felder werden im Spiel mittig auf dem Knoten gezeichnet).
	var sz := GameTheme.object_draw_size(obj_key) * PZ
	var tex := GameTheme.object_texture(obj_key)
	if tex != null:
		draw_texture_rect(tex, Rect2(origin.x - sz.x * 0.5, origin.y - sz.y * 0.5, sz.x, sz.y), false)
	else:
		var r := Rect2(origin.x - sz.x * 0.5, origin.y - sz.y * 0.5, sz.x, sz.y)
		draw_rect(r, Color(0.42, 0.32, 0.18))
		draw_rect(r, Color(0, 0, 0, 0.6), false, 1.5)

	var base := GameTheme.object_draw_size(obj_key)
	draw_string(ThemeDB.fallback_font, origin + Vector2(-hw, hh + 22.0),
		"%s · %.0f × %.0f px (Kachel 64×32)" % [obj_key, base.x, base.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.85, 0.85))