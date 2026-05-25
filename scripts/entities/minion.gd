class_name Minion
extends CombatActor
## Lane creep. Uses a NavigationAgent3D to find the shortest path across the
## arena's NavigationRegion3D toward the enemy core, routing around structures.
## If the shared Targeter finds an enemy in range, it stops to attack on a
## cooldown. Awards a bounty to the killer's team on death.

@export var move_speed: float = 4.0
@export var attack_damage: float = 10.0
@export var attack_cooldown_sec: float = 1.0
@export var attack_range: float = 2.4
@export var bounty: int = 15

var _destination: Vector3 = Vector3.ZERO
var _attack_timer: float = 0.0

@onready var targeter: Targeter = $Targeter
@onready var mesh: MeshInstance3D = $Mesh
@onready var nav_agent: NavigationAgent3D = $NavAgent

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

## Final goal (the enemy core); the nav agent finds the shortest route there.
func set_destination(world_pos: Vector3) -> void:
	_destination = world_pos
	if is_node_ready():
		nav_agent.target_position = world_pos

func _physics_process(delta: float) -> void:
	tick_slow(delta)
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	var target := targeter.acquire_target()
	if target != null:
		_face_toward(target.global_position, delta)
		var dist := global_position.distance_to(target.global_position)
		if dist <= attack_range:
			_stop_horizontal()
			_try_attack(target)
		else:
			_navigate_to(target.global_position, delta)
	else:
		_navigate_to(_destination, delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

## Steer one step along the agent's path toward `goal`.
func _navigate_to(goal: Vector3, delta: float) -> void:
	nav_agent.target_position = goal
	if nav_agent.is_navigation_finished():
		_stop_horizontal()
		return
	var next := nav_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		_stop_horizontal()
		return
	dir = dir.normalized()
	var spd := move_speed * speed_mult()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	_face_toward(next, delta)

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

func _on_died(source: Node) -> void:
	var killer_team := team
	if source != null and "team" in source:
		killer_team = source.team
	EventBus.minion_died.emit(int(team), int(killer_team), bounty)
	queue_free()
