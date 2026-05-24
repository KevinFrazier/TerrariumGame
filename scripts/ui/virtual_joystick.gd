class_name VirtualJoystick
extends Control
## Touch/mouse analog stick. Outputs a Vector2 in [-1, 1] where up is -y
## (matching Input.get_vector), so move/aim consumers treat both sources alike.

signal value_changed(value: Vector2)

@export var dead_zone: float = 0.15

var _value: Vector2 = Vector2.ZERO
var _active_pointer: int = -999  # touch index, or -1 for mouse

@onready var _knob: Control = $Knob

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center_knob()

func get_value() -> Vector2:
	return _value

func _radius() -> float:
	return minf(size.x, size.y) * 0.5

func _center_knob() -> void:
	if _knob:
		_knob.position = size * 0.5 - _knob.size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(event.index, event.position)
		elif event.index == _active_pointer:
			_release()
	elif event is InputEventScreenDrag and event.index == _active_pointer:
		_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(-1, event.position)
		elif _active_pointer == -1:
			_release()
	elif event is InputEventMouseMotion and _active_pointer == -1:
		_drag(event.position)

func _begin(pointer: int, local_pos: Vector2) -> void:
	_active_pointer = pointer
	_drag(local_pos)

func _drag(local_pos: Vector2) -> void:
	var center := size * 0.5
	var offset := local_pos - center
	var r := _radius()
	if r <= 0.0:
		return
	var v := offset / r
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < dead_zone:
		v = Vector2.ZERO
	_value = v
	if _knob:
		_knob.position = center + v * r - _knob.size * 0.5
	value_changed.emit(_value)

func _release() -> void:
	_active_pointer = -999
	_value = Vector2.ZERO
	_center_knob()
	value_changed.emit(_value)
