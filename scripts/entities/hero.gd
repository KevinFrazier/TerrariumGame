class_name Hero
extends CharacterBody3D
## Player-controlled hero. Twin-stick: left stick moves (camera-relative),
## right stick aims facing. Fire shoots a projectile toward the aim direction
## (assisted toward the nearest enemy via the shared Targeter); melee sweeps a
## short arc in front. Only the `controlled` hero reads input and owns the camera.

@export var team: Team.Id = Team.Id.A
@export var move_speed: float = 7.0
@export var turn_speed: float = 12.0
@export var fire_cooldown_sec: float = 0.45
@export var melee_cooldown_sec: float = 0.7
@export var melee_damage: float = 25.0
@export var respawn_delay_sec: float = 4.0
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

var controlled: bool = false

# Per-frame intent, written by the HUD (touch) and merged with keyboard below.
var _stick_move := Vector2.ZERO
var _stick_aim := Vector2.ZERO

var _facing := Vector3.FORWARD
var _fire_timer := 0.0
var _melee_timer := 0.0
var _spawn_transform: Transform3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var body: Node3D = $Body
@onready var mesh: MeshInstance3D = $Body/Mesh
@onready var muzzle: Marker3D = $Body/Muzzle
@onready var targeter: Targeter = $Targeter
@onready var health: HealthComponent = $HealthComponent
@onready var melee_area: Area3D = $Body/MeleeArea

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("heroes")
	_spawn_transform = global_transform
	collision_layer = Team.body_layer(team)
	collision_mask = Team.LAYER_WORLD | Team.LAYER_GROUND
	targeter.team = team
	melee_area.collision_layer = 0
	melee_area.collision_mask = Team.enemy_mask(team)
	melee_area.monitoring = true
	health.died.connect(_on_died)
	_apply_team_tint()
	_set_camera_active(controlled)

func _apply_team_tint() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Team.body_color(team)
	mesh.material_override = mat

func set_controlled(value: bool) -> void:
	controlled = value
	if is_node_ready():
		_set_camera_active(value)

func _set_camera_active(active: bool) -> void:
	if camera:
		camera.current = active

# --- input wiring from HUD -------------------------------------------------
func set_move_input(v: Vector2) -> void:
	_stick_move = v

func set_aim_input(v: Vector2) -> void:
	_stick_aim = v

func _gather_move() -> Vector2:
	if _stick_move.length_squared() > 0.01:
		return _stick_move.limit_length(1.0)
	if controlled:
		return Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector2.ZERO

func _gather_aim() -> Vector2:
	if _stick_aim.length_squared() > 0.01:
		return _stick_aim.limit_length(1.0)
	if controlled:
		return Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	return Vector2.ZERO

# --- main loop -------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_melee_timer = maxf(_melee_timer - delta, 0.0)

	var move_in := _gather_move()
	var aim_in := _gather_aim()

	var basis_xform := camera.global_transform.basis if camera else global_transform.basis
	# Camera looks down its local -Z, so "into screen" is -basis.z. The stick's
	# y is negative for forward, so basis.z * y resolves to into-screen movement.
	var cam_forward := basis_xform.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := basis_xform.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := cam_right * move_in.x + cam_forward * move_in.y
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# Facing: aim stick wins, else movement direction.
	var face_src := Vector3.ZERO
	if aim_in.length_squared() > 0.01:
		face_src = cam_right * aim_in.x + cam_forward * aim_in.y
	elif move_dir.length_squared() > 0.01:
		face_src = move_dir
	if face_src.length_squared() > 0.001:
		_facing = face_src.normalized()
		var target_yaw := atan2(_facing.x, _facing.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, turn_speed * delta)

	if controlled:
		if Input.is_action_pressed("fire"):
			fire()
		if Input.is_action_just_pressed("melee"):
			melee()

# --- abilities (also called by HUD buttons) --------------------------------
func fire() -> void:
	if _fire_timer > 0.0 or health.is_dead() or projectile_scene == null:
		return
	_fire_timer = fire_cooldown_sec
	var shot_dir := _facing
	var target := targeter.nearest_in_direction(_facing)
	if target != null:
		var to_target := target.global_position - muzzle.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			shot_dir = to_target.normalized()
	var p := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	p.setup(team, shot_dir)

func melee() -> void:
	if _melee_timer > 0.0 or health.is_dead():
		return
	_melee_timer = melee_cooldown_sec
	for other in melee_area.get_overlapping_bodies():
		if other.has_method("take_damage"):
			other.take_damage(melee_damage, self)

func get_fire_ready() -> float:
	return 1.0 - (_fire_timer / fire_cooldown_sec) if fire_cooldown_sec > 0.0 else 1.0

func get_melee_ready() -> float:
	return 1.0 - (_melee_timer / melee_cooldown_sec) if melee_cooldown_sec > 0.0 else 1.0

# --- damage / death --------------------------------------------------------
func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

func _on_died(_source: Node) -> void:
	EventBus.hero_died.emit(int(team), self)
	_set_dead_visual(true)
	await get_tree().create_timer(respawn_delay_sec).timeout
	if is_instance_valid(self):
		_respawn()

func _set_dead_visual(dead: bool) -> void:
	body.visible = not dead
	set_physics_process(not dead)
	$CollisionShape3D.disabled = dead
	if dead:
		velocity = Vector3.ZERO

func _respawn() -> void:
	global_transform = _spawn_transform
	health.revive()
	_set_dead_visual(false)
	EventBus.hero_respawned.emit(int(team), self)
