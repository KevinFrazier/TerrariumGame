class_name Minion
extends CharacterBody3D
## Lane creep. Marches along waypoints toward the enemy core; if the shared
## Targeter finds an enemy in range, it stops to attack on a cooldown. Awards a
## bounty to the killer's team on death.

@export var team: Team.Id = Team.Id.A
@export var move_speed: float = 4.0
@export var attack_damage: float = 10.0
@export var attack_cooldown_sec: float = 1.0
@export var attack_range: float = 2.4
@export var bounty: int = 15

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _attack_timer: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var targeter: Targeter = $Targeter
@onready var health: HealthComponent = $HealthComponent
@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("minions")
	collision_layer = Team.body_layer(team) | Team.LAYER_WORLD
	collision_mask = Team.LAYER_WORLD | Team.LAYER_GROUND
	targeter.team = team
	targeter.detection_radius = attack_range + 4.0
	health.died.connect(_on_died)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Team.body_color(team).lightened(0.1)
	mesh.material_override = mat

## World-space waypoints, ending at the enemy core position.
func set_path(points: PackedVector3Array) -> void:
	_path = points
	_path_index = 0

func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	var target := targeter.acquire_target()
	if target != null:
		_face_toward(target.global_position, delta)
		var dist := global_position.distance_to(target.global_position)
		if dist <= attack_range:
			_stop_horizontal()
			_try_attack(target)
		else:
			_move_toward(target.global_position, delta)
	else:
		_advance_along_path(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _advance_along_path(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		_stop_horizontal()
		return
	var goal := _path[_path_index]
	if global_position.distance_to(goal) < 1.0:
		_path_index += 1
		if _path_index >= _path.size():
			_stop_horizontal()
			return
		goal = _path[_path_index]
	_move_toward(goal, delta)

func _move_toward(world_pos: Vector3, delta: float) -> void:
	var dir := world_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		_stop_horizontal()
		return
	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_face_toward(world_pos, delta)

func _face_toward(world_pos: Vector3, delta: float) -> void:
	var dir := world_pos - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 10.0 * delta)

func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func _try_attack(target: Node) -> void:
	if _attack_timer > 0.0:
		return
	if target.has_method("take_damage"):
		_attack_timer = attack_cooldown_sec
		target.take_damage(attack_damage, self)

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

func _on_died(source: Node) -> void:
	var killer_team := team
	if source != null and "team" in source:
		killer_team = source.team
	EventBus.minion_died.emit(int(team), int(killer_team), bounty)
	queue_free()
