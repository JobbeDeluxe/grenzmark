class_name CameraController
extends Camera2D

## Schwenken mit rechter/mittlerer Maustaste, Zoom mit dem Mausrad.
## Ein Rechtsklick OHNE nennenswerte Bewegung gilt nicht als Schwenk, sondern als
## universeller Abbrechen/Schließen-Befehl (wie in S2) → `right_click_tap`.

const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0
const DRAG_TAP_MAX := 6.0   # Pixel-Toleranz: darunter ist ein Rechtsklick ein "Tap"

signal right_click_tap

var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				# Rechter Tap (kaum bewegt) = Abbrechen; ein Schwenk emittiert nichts.
				if event.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < DRAG_TAP_MAX:
					right_click_tap.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
