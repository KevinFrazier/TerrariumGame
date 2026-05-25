class_name Tower
extends StaticBody3D
## Buildable defensive tower. Uses the same Targeter abstraction as heroes and
## minions to auto-acquire a target (by the definition's priority), then fires
## projectiles on a cooldown. Stats — damage, range, fire rate, projectile
## behavior, splash, slow, targeting — all come from the assigned TowerDefinition.
##
## Each tower archetype is its own scene so it can carry unique geometry,
## animations, and audio. This shared script drives behavior and triggers two
## optional per-scene nodes when present: an `AnimationPlayer` (plays "fire") and
## an `AudioStreamPlayer3D` named `FireSound`.

@export var team: Team.Id = Team.Id.A
@export var definition: TowerDefinition
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

var _damage: float = 18.0
var _fire_interval: float = 0.83
var _fire_timer: float = 0.0
var _proj_speed: float = 24.0
var _blast_radius: float = 0.0
var _splash_falloff: bool = false
var _slow_factor: float = 0.0
var _slow_duration: float = 0.0
var _gravity_lob: bool = false
var _priority: Targeter.Priority = Targeter.Priority.NEAREST
var _proj_scene: PackedScene
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var targeter: Targeter = $Targeter
@onready var health: HealthComponent = $HealthComponent
@onready var muzzle: Marker3D = $Muzzle
@onready var mesh: MeshInstance3D = $Mesh
@onready var _anim: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var _fire_sound: AudioStreamPlayer3D = get_node_or_null("FireSound")

var _current_target: Node3D
var _range_ring: MeshInstance3D
var _target_line: MeshInstance3D

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("towers")
	add_to_group("navigation_source")  # minions navmesh-route around towers
	collision_layer = Team.body_layer(team) | Team.LAYER_WORLD
	collision_mask = 0
	_proj_scene = projectile_scene
	_apply_definition()
	targeter.team = team
	health.died.connect(_on_died)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Team.body_color(team).darkened(0.25)
	mesh.material_override = mat
	_build_range_ring()
	_build_target_line()

func _apply_definition() -> void:
	if definition == null:
		return
	_damage = definition.damage
	if definition.fire_rate_per_sec > 0.0:
		_fire_interval = 1.0 / definition.fire_rate_per_sec
	targeter.detection_radius = definition.attack_range
	health.max_hp = definition.max_hp
	health.current_hp = definition.max_hp
	_proj_speed = definition.projectile_speed
	_blast_radius = definition.blast_radius
	_splash_falloff = definition.splash_falloff
	_slow_factor = definition.slow_factor
	_slow_duration = definition.slow_duration_sec
	_gravity_lob = definition.projectile_gravity
	_priority = definition.targeting_priority
	if definition.projectile_scene != null:
		_proj_scene = definition.projectile_scene

func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	# Track the target every frame so the firing line stays current.
	_current_target = targeter.acquire_target(_priority)
	_update_target_line()
	if _current_target != null and _fire_timer <= 0.0:
		_fire_at(_current_target)

## Flat translucent ring on the ground marking the tower's attack range.
func _build_range_ring() -> void:
	var radius := definition.attack_range if definition else targeter.detection_radius
	if radius <= 0.0:
		return
	var inner := maxf(radius - 0.3, 0.05)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segments := 56
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var d := Vector3(cos(a), 0.0, sin(a))
		im.surface_add_vertex(d * inner)
		im.surface_add_vertex(d * radius)
	im.surface_end()
	_range_ring = MeshInstance3D.new()
	_range_ring.mesh = im
	_range_ring.position = Vector3(0.0, 0.06, 0.0)
	_range_ring.material_override = _flat_material(0.28)
	add_child(_range_ring)

## A thin line drawn from the muzzle to the tower's current target.
func _build_target_line() -> void:
	_target_line = MeshInstance3D.new()
	_target_line.top_level = true  # we feed world-space vertices
	_target_line.material_override = _flat_material(0.85)
	_target_line.visible = false
	add_child(_target_line)

func _update_target_line() -> void:
	if _target_line == null:
		return
	if _current_target == null or not is_instance_valid(_current_target):
		_target_line.visible = false
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_add_vertex(muzzle.global_position)
	im.surface_add_vertex((_current_target as Node3D).global_position + Vector3.UP * 0.8)
	im.surface_end()
	_target_line.mesh = im
	_target_line.visible = true

func _flat_material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c := Team.body_color(team)
	c.a = alpha
	mat.albedo_color = c
	return mat

func _fire_at(target: Node3D) -> void:
	if _proj_scene == null:
		return
	_fire_timer = _fire_interval
	var p := _proj_scene.instantiate() as Projectile
	p.damage = _damage
	p.speed = _proj_speed
	p.blast_radius = _blast_radius
	p.splash_falloff = _splash_falloff
	p.slow_factor = _slow_factor
	p.slow_duration_sec = _slow_duration
	if _gravity_lob:
		p.affected_by_gravity = true
		p.detonate_on_ground = true
		get_tree().current_scene.add_child(p)
		p.global_position = muzzle.global_position
		p.launch(team, _ballistic_velocity(target.global_position))
	else:
		var dir := target.global_position - muzzle.global_position
		if dir.length_squared() < 0.0001:
			return
		get_tree().current_scene.add_child(p)
		p.global_position = muzzle.global_position
		p.setup(team, dir.normalized(), _damage, _proj_speed)
	_play_fire_av()

## Solve a launch velocity so a gravity projectile passes through `target` after a
## distance-scaled time of flight (mortar lob).
func _ballistic_velocity(target_pos: Vector3) -> Vector3:
	var to_target := target_pos - muzzle.global_position
	var horizontal := Vector2(to_target.x, to_target.z).length()
	var t := clampf(horizontal / maxf(_proj_speed, 1.0), 0.5, 2.5)
	var vel := Vector3.ZERO
	vel.x = to_target.x / t
	vel.z = to_target.z / t
	vel.y = to_target.y / t + 0.5 * _gravity * t
	return vel

func _play_fire_av() -> void:
	if _anim != null and _anim.has_animation("fire"):
		_anim.stop()
		_anim.play("fire")
	if _fire_sound != null and _fire_sound.stream != null:
		_fire_sound.play()

## Override the targeting preference (e.g. from the build menu) after spawning.
func set_targeting_priority(p: Targeter.Priority) -> void:
	_priority = p

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

func get_hp() -> float:
	return health.current_hp

func _on_died(_source: Node) -> void:
	GameState.unregister_tower(team)
	queue_free()
