class_name Hero
extends CharacterBody3D
## Player-controlled hero. Twin-stick: left stick moves (camera-relative), right
## stick orbits the camera around the hero. The hero faces its movement
## direction; fire shoots where the camera looks (assisted toward the nearest
## enemy via the shared Targeter). Only the `controlled` hero reads input and
## owns the camera.

@export var team: Team.Id = Team.Id.A
@export var move_speed: float = 7.0
@export var turn_speed: float = 12.0
@export var fire_cooldown_sec: float = 0.45
@export var melee_cooldown_sec: float = 0.7
@export var melee_damage: float = 25.0
@export var respawn_delay_sec: float = 4.0
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

@export_group("Camera Orbit")
@export var cam_yaw_speed: float = 2.6       ## radians/sec from aim stick x
@export var cam_pitch_speed: float = 1.8     ## radians/sec from aim stick y
@export var cam_pitch_min: float = 0.05      ## near level
@export var cam_pitch_max: float = 1.2       ## steep top-down
@export var cam_pitch_start: float = 0.45    ## ~26 degrees, default tilt

var controlled: bool = false

# Per-frame intent, written by the HUD (touch) and merged with keyboard below.
var _stick_move := Vector2.ZERO
var _stick_aim := Vector2.ZERO

var _facing := Vector3.FORWARD
var _cam_yaw := 0.0
var _cam_pitch := 0.45
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
	_cam_pitch = cam_pitch_start
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
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

	# Right stick orbits the camera around the hero (yaw + pitch).
	_orbit_camera(aim_in, delta)

	# Movement is relative to the (now updated) camera orientation. The camera
	# looks down its local -Z, so "into screen" is -basis.z; the stick's y is
	# negative for forward, making basis.z * y resolve to into-screen movement.
	var basis_xform := camera.global_transform.basis if camera else global_transform.basis
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

	# Hero faces its movement direction (firing temporarily overrides this).
	if move_dir.length_squared() > 0.01:
		_facing = move_dir.normalized()
	_apply_facing(delta)

	if controlled:
		if Input.is_action_pressed("fire"):
			fire()
		if Input.is_action_just_pressed("melee"):
			melee()

# --- camera / facing -------------------------------------------------------
func _orbit_camera(aim_in: Vector2, delta: float) -> void:
	if aim_in.length_squared() > 0.0001:
		_cam_yaw -= aim_in.x * cam_yaw_speed * delta
		_cam_pitch = clampf(_cam_pitch + aim_in.y * cam_pitch_speed * delta, cam_pitch_min, cam_pitch_max)
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)

func _apply_facing(delta: float) -> void:
	if _facing.length_squared() < 0.0001:
		return
	var target_yaw := atan2(_facing.x, _facing.z)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, turn_speed * delta)

## Horizontal direction the camera is looking, used as the default aim.
func _camera_look_dir() -> Vector3:
	if camera == null:
		return _facing
	var look := -camera.global_transform.basis.z
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return _facing
	return look.normalized()

# --- abilities (also called by HUD buttons) --------------------------------
func fire() -> void:
	if _fire_timer > 0.0 or health.is_dead() or projectile_scene == null:
		return
	_fire_timer = fire_cooldown_sec
	var look := _camera_look_dir()
	var shot_dir := look
	var target := targeter.nearest_in_direction(look)
	if target != null:
		var to_target := target.global_position - muzzle.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			shot_dir = to_target.normalized()
	_facing = shot_dir  # turn to face the shot
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
