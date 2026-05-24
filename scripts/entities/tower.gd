class_name Tower
extends StaticBody3D
## Buildable defensive tower. Uses the same Targeter abstraction as heroes and
## minions to auto-acquire the nearest enemy, then fires projectiles on a
## cooldown. Stats come from an assigned TowerDefinition.

@export var team: Team.Id = Team.Id.A
@export var definition: TowerDefinition
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

var _damage: float = 18.0
var _fire_interval: float = 0.83
var _fire_timer: float = 0.0

@onready var targeter: Targeter = $Targeter
@onready var health: HealthComponent = $HealthComponent
@onready var muzzle: Marker3D = $Muzzle
@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("towers")
	collision_layer = Team.body_layer(team) | Team.LAYER_WORLD
	collision_mask = 0
	_apply_definition()
	targeter.team = team
	health.died.connect(_on_died)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Team.body_color(team).darkened(0.25)
	mesh.material_override = mat

func _apply_definition() -> void:
	if definition == null:
		return
	_damage = definition.damage
	if definition.fire_rate_per_sec > 0.0:
		_fire_interval = 1.0 / definition.fire_rate_per_sec
	targeter.detection_radius = definition.attack_range
	health.max_hp = definition.max_hp
	health.current_hp = definition.max_hp

func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	if _fire_timer > 0.0:
		return
	var target := targeter.acquire_target()
	if target != null:
		_fire_at(target)

func _fire_at(target: Node3D) -> void:
	if projectile_scene == null:
		return
	_fire_timer = _fire_interval
	var dir := target.global_position - muzzle.global_position
	if dir.length_squared() < 0.0001:
		return
	var p := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	p.setup(team, dir.normalized(), _damage)

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

func _on_died(_source: Node) -> void:
	GameState.unregister_tower(team)
	queue_free()
