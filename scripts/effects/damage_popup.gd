class_name DamagePopup
extends Label3D
## Temporary floating damage number. Spawned by HealthComponent whenever an
## entity takes damage; rises, fades, and frees itself.

@export var rise_speed: float = 1.6
@export var lifetime_sec: float = 0.8
@export var drift: float = 0.6

var _age: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _scale: float = 1.0

## Spawns a popup into `world_parent` (use the current scene so it outlives the
## victim) at `world_pos`, showing `amount`. `scale` punches up big hits.
static func spawn(world_parent: Node, world_pos: Vector3, amount: float, color: Color = Color(1, 0.95, 0.4), scale: float = 1.0) -> void:
	if world_parent == null:
		return
	var popup := DamagePopup.new()
	popup.text = str(roundi(amount))
	popup.modulate = color
	popup._scale = scale
	world_parent.add_child(popup)
	popup.global_position = world_pos + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	font_size = int(32 * _scale)
	outline_size = 8
	outline_modulate = Color(0, 0, 0, 0.9)
	render_priority = 10
	_vel = Vector3(drift * randf_range(-1.0, 1.0), rise_speed, drift * randf_range(-1.0, 1.0))

func _process(delta: float) -> void:
	_age += delta
	global_position += _vel * delta
	# Quick overshoot "pop" on spawn, then settle.
	var t := _age / lifetime_sec
	var pop := 1.0 + 0.35 * maxf(1.0 - t * 6.0, 0.0)
	pixel_size = 0.003 * pop
	modulate.a = clampf(1.0 - t, 0.0, 1.0)
	if _age >= lifetime_sec:
		queue_free()
