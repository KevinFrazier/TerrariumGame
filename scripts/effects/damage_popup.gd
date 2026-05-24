class_name DamagePopup
extends Label3D
## Temporary floating damage number. Spawned by HealthComponent whenever an
## entity takes damage; rises, fades, and frees itself.

@export var rise_speed: float = 1.6
@export var lifetime_sec: float = 0.8
@export var drift: float = 0.6

var _age: float = 0.0
var _vel: Vector3 = Vector3.ZERO

## Spawns a popup into `world_parent` (use the current scene so it outlives the
## victim) at `world_pos`, showing `amount`.
static func spawn(world_parent: Node, world_pos: Vector3, amount: float, color: Color = Color(1, 0.95, 0.4)) -> void:
	if world_parent == null:
		return
	var popup := DamagePopup.new()
	popup.text = str(roundi(amount))
	popup.modulate = color
	world_parent.add_child(popup)
	popup.global_position = world_pos + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	font_size = 48
	outline_size = 12
	outline_modulate = Color(0, 0, 0, 0.9)
	render_priority = 10
	_vel = Vector3(drift * randf_range(-1.0, 1.0), rise_speed, drift * randf_range(-1.0, 1.0))

func _process(delta: float) -> void:
	_age += delta
	global_position += _vel * delta
	modulate.a = clampf(1.0 - _age / lifetime_sec, 0.0, 1.0)
	if _age >= lifetime_sec:
		queue_free()
