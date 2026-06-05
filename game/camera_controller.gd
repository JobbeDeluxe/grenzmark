class_name CameraController
extends Camera2D

## Schwenken mit rechter/mittlerer Maustaste, Zoom mit dem Mausrad.

const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0

var _dragging := false


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
			_dragging = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
