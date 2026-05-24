class_name VirtualJoystick
extends Control
## Touch/mouse analog stick. Outputs a Vector2 in [-1, 1] where up is -y
## (matching Input.get_vector), so move/aim consumers treat both sources alike.
##
## Two modes:
##  - Fixed (default): a stick anchored to its own rect, dragged relative to its
##    center. Used by the move stick.
##  - Floating (`floating = true`): the stick has no fixed home. It reads touches
##    globally via `_unhandled_input` and springs up wherever the player first
##    touches, so aiming works anywhere on screen that another control (the move
##    stick, action buttons, build menu) hasn't already claimed.

signal value_changed(value: Vector2)

@export var dead_zone: float = 0.15
@export var floating: bool = false      ## spawn at the touch point, read input globally
@export var float_radius: float = 90.0  ## drag radius (px) in floating mode

var _value: Vector2 = Vector2.ZERO
var _active_pointer: int = -999  # touch index, or -1 for mouse
var _origin: Vector2 = Vector2.ZERO

@onready var _knob: Control = get_node_or_null("Knob")
@onready var _base: Control = get_node_or_null("Base")

func _ready() -> void:
	if floating:
		# Stay out of GUI hit-testing so touches fall through to _unhandled_input;
		# the move stick and buttons (STOP controls) still claim their own areas.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hide_floating()
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_center_knob()

func get_value() -> Vector2:
	return _value

func _radius() -> float:
	if floating:
		return float_radius
	return minf(size.x, size.y) * 0.5

func _stick_center() -> Vector2:
	return _origin if floating else size * 0.5

func _center_knob() -> void:
	if _knob:
		_knob.position = size * 0.5 - _knob.size * 0.5

func _hide_floating() -> void:
	if _base:
		_base.visible = false
	if _knob:
		_knob.visible = false

func _show_floating_at(pos: Vector2) -> void:
	if _base:
		_base.position = pos - _base.size * 0.5
		_base.visible = true
	if _knob:
		_knob.visible = true

# Fixed mode: events arrive in the control's local rect.
func _gui_input(event: InputEvent) -> void:
	if not floating:
		_handle(event)

# Floating mode: read whatever no other control consumed (positions are global,
# and this control fills the screen, so local == global).
func _unhandled_input(event: InputEvent) -> void:
	if floating:
		_handle(event)

func _handle(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not (floating and _active_pointer != -999):
				_begin(event.index, event.position)
		elif event.index == _active_pointer:
			_release()
	elif event is InputEventScreenDrag and event.index == _active_pointer:
		_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not (floating and _active_pointer != -999):
				_begin(-1, event.position)
		elif _active_pointer == -1:
			_release()
	elif event is InputEventMouseMotion and _active_pointer == -1:
		_drag(event.position)

func _begin(pointer: int, pos: Vector2) -> void:
	_active_pointer = pointer
	if floating:
		_origin = pos
		_show_floating_at(pos)
	_drag(pos)

func _drag(pos: Vector2) -> void:
	var center := _stick_center()
	var offset := pos - center
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
	if floating:
		_hide_floating()
	else:
		_center_knob()
	value_changed.emit(_value)
