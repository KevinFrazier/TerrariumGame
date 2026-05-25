class_name Hero
extends CombatActor
## Player-controlled hero. Twin-stick: left stick moves (camera-relative), right
## stick orbits the camera around the hero. The hero faces its movement
## direction; fire shoots where the camera looks (assisted toward the nearest
## enemy via the shared Targeter). Only the `controlled` hero reads input and
## owns the camera.

@export var move_speed: float = 7.0
@export var turn_speed: float = 12.0
@export var fire_cooldown_sec: float = 0.45
@export var melee_cooldown_sec: float = 0.7
@export var melee_damage: float = 25.0
@export var respawn_delay_sec: float = 4.0
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

@export_group("Camera Orbit")
@export var cam_yaw_speed: float = 3.6       ## radians/sec from aim stick x
@export var cam_pitch_speed: float = 2.6     ## radians/sec from aim stick y
@export var cam_pitch_min: float = -1.5708   ## -90 degrees: straight up at the sky
@export var cam_pitch_max: float = 1.5708    ## +90 degrees: straight down at the floor
@export var cam_pitch_start: float = 0.45    ## ~26 degrees, default tilt
@export var cam_shoulder_offset: float = 0.6 ## shift the camera right so the character isn't centered

@export_group("Tower Throw")
@export var throw_speed: float = 16.0        ## initial launch speed of the build arc
@export var trajectory_steps: int = 90
## Fallback when no tower is selected in the build menu.
@export var build_tower_definition: TowerDefinition = preload("res://resources/towers/basic_tower.tres")

var controlled: bool = false

# Per-frame intent, written by the HUD (touch) and merged with keyboard below.
var _stick_move := Vector2.ZERO
var _stick_aim := Vector2.ZERO

var _facing := Vector3.FORWARD
var _cam_yaw := 0.0
var _cam_pitch := 0.45
var _fire_timer := 0.0
var _melee_timer := 0.0
var _throw_armed := false
var _trajectory: MeshInstance3D
var _landing_marker: MeshInstance3D
var _spawn_transform: Transform3D

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var body: Node3D = $Body
@onready var mesh: MeshInstance3D = $Body/Mesh
@onready var muzzle: Marker3D = $Body/Muzzle
@onready var targeter: Targeter = $Targeter
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
	camera_pivot.rotation = Vector3(-_cam_pitch, _cam_yaw, 0.0)
	# Over-the-shoulder: offset the arm sideways (rotates with the camera yaw) so
	# the character sits left of center and its front is visible.
	spring_arm.position.x = cam_shoulder_offset
	_ensure_throw_visuals()
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
	tick_slow(delta)
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_melee_timer = maxf(_melee_timer - delta, 0.0)

	var move_in := _gather_move()
	var aim_in := _gather_aim()

	# Right stick orbits the camera around the hero (yaw + pitch).
	_orbit_camera(aim_in, delta)

	# Movement + aim are relative to the camera's yaw. We derive a horizontal
	# forward from the (always-horizontal) right axis via a cross product, so it
	# stays valid even when the camera pitches straight down (where basis.z would
	# flatten to zero). cam_forward points out of screen; -cam_forward is "into
	# screen", which is both forward movement and the gun aim direction.
	var basis_xform := camera.global_transform.basis if camera else global_transform.basis
	var cam_right := basis_xform.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var cam_forward := cam_right.cross(Vector3.UP)

	var move_dir := cam_right * move_in.x + cam_forward * move_in.y
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	var spd := move_speed * speed_mult()
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# Gun aim follows the camera yaw: the hero faces where the camera looks.
	_facing = -cam_forward
	_apply_facing(delta)

	# Melee fires itself whenever an enemy steps into range.
	_auto_melee()

	if controlled:
		# Hold the tower button to aim the arc, release to throw.
		if Input.is_action_just_pressed("ability_1"):
			set_tower_throw_armed(true)
		elif Input.is_action_just_released("ability_1"):
			release_tower_throw()
		# Projectile fires on release.
		if Input.is_action_just_released("fire"):
			fire()

	if _throw_armed:
		_update_trajectory()
	else:
		_hide_trajectory()

# --- camera / facing -------------------------------------------------------
func _orbit_camera(aim_in: Vector2, delta: float) -> void:
	if aim_in.length_squared() > 0.0001:
		_cam_yaw -= aim_in.x * cam_yaw_speed * delta
		_cam_pitch = clampf(_cam_pitch + aim_in.y * cam_pitch_speed * delta, cam_pitch_min, cam_pitch_max)
	# Negative X rotation tilts the rig downward, so a larger _cam_pitch looks
	# further down (up to straight down at the floor).
	camera_pivot.rotation = Vector3(-_cam_pitch, _cam_yaw, 0.0)

func _apply_facing(delta: float) -> void:
	if _facing.length_squared() < 0.0001:
		return
	var target_yaw := atan2(_facing.x, _facing.z)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, turn_speed * delta)

## Horizontal-or-vertical world direction the camera is looking along.
func _look_dir_3d() -> Vector3:
	if camera:
		var d := -camera.global_transform.basis.z
		if d.length_squared() > 0.0001:
			return d.normalized()
	return _facing

# --- abilities (also called by HUD buttons) --------------------------------
func fire() -> void:
	# Don't shoot while aiming a tower throw; that gesture owns the release.
	if _throw_armed:
		return
	if _fire_timer > 0.0 or health.is_dead() or projectile_scene == null:
		return
	_fire_timer = fire_cooldown_sec
	# Shoot along the camera's full look direction, including pitch, so aiming
	# down sends the shot toward the floor (body yaw still tracks the camera).
	var shot_dir := _look_dir_3d()
	var p := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	p.setup(team, shot_dir)

# --- tower throw ability ---------------------------------------------------
func set_tower_throw_armed(armed: bool) -> void:
	_throw_armed = armed and controlled and not health.is_dead()
	if not _throw_armed:
		_hide_trajectory()

func is_tower_throw_armed() -> bool:
	return _throw_armed

## Throw the tower if currently aiming, then disarm (button released).
func release_tower_throw() -> void:
	if _throw_armed:
		_throw_tower()
	set_tower_throw_armed(false)

func _throw_tower() -> void:
	if _fire_timer > 0.0 or health.is_dead():
		return
	var def: TowerDefinition = GameState.selected_tower if GameState.selected_tower != null else build_tower_definition
	if def == null or projectile_scene == null:
		return
	# Reserve the slot + gold at launch so spam-arming can't exceed the cap.
	if not GameState.can_build_tower(team) or not GameState.can_afford(team, def.cost):
		set_tower_throw_armed(false)
		return
	GameState.spend_currency(team, def.cost)
	GameState.register_tower(team)
	_fire_timer = fire_cooldown_sec

	var p := projectile_scene.instantiate() as Projectile
	p.affected_by_gravity = true
	p.lands_on_ground = true
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	p.setup(team, _look_dir_3d(), 0.0, throw_speed)
	p.landed.connect(_on_throw_landed.bind(def, team))
	set_tower_throw_armed(false)

func _on_throw_landed(position: Vector3, def: TowerDefinition, build_team: Team.Id) -> void:
	# Slot + gold were already reserved at launch; just place the tower.
	var spot := Vector3(clampf(position.x, -34.0, 34.0), 0.0, clampf(position.z, -34.0, 34.0))
	var tower := def.scene.instantiate() as Tower
	tower.team = build_team
	tower.definition = def
	get_tree().current_scene.add_child(tower)
	tower.global_position = spot
	EventBus.tower_built.emit(int(build_team), tower)

func _ensure_throw_visuals() -> void:
	_trajectory = MeshInstance3D.new()
	_trajectory.top_level = true
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.4, 1.0, 0.55)
	line_mat.no_depth_test = true
	_trajectory.material_override = line_mat
	_trajectory.visible = false
	add_child(_trajectory)

	_landing_marker = MeshInstance3D.new()
	_landing_marker.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.1
	_landing_marker.mesh = disc
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.4, 1.0, 0.55, 0.5)
	_landing_marker.material_override = disc_mat
	_landing_marker.visible = false
	add_child(_landing_marker)

func _update_trajectory() -> void:
	if _trajectory == null:
		return
	var start := muzzle.global_position
	var v := _look_dir_3d() * throw_speed
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var landing := start
	var t := 0.0
	for i in trajectory_steps:
		var pt := start + v * t + Vector3(0.0, -0.5 * _gravity * t * t, 0.0)
		im.surface_add_vertex(pt)
		landing = pt
		if pt.y <= 0.0 and i > 0:
			break
		t += 0.06
	im.surface_end()
	_trajectory.mesh = im
	_trajectory.visible = true
	_landing_marker.global_position = Vector3(landing.x, 0.06, landing.z)
	_landing_marker.visible = true

func _hide_trajectory() -> void:
	if _trajectory:
		_trajectory.visible = false
	if _landing_marker:
		_landing_marker.visible = false

# Swing whenever the cooldown is ready and an enemy is in range.
func _auto_melee() -> void:
	if _melee_timer > 0.0 or health.is_dead():
		return
	if melee_area.has_overlapping_bodies():
		melee()

func melee() -> void:
	if _melee_timer > 0.0 or health.is_dead():
		return
	var hit := false
	for other in melee_area.get_overlapping_bodies():
		if other.has_method("take_damage"):
			other.take_damage(melee_damage, self)
			hit = true
	if hit:
		_melee_timer = melee_cooldown_sec

func get_fire_ready() -> float:
	return 1.0 - (_fire_timer / fire_cooldown_sec) if fire_cooldown_sec > 0.0 else 1.0

# --- damage / death --------------------------------------------------------
func _on_died(_source: Node) -> void:
	EventBus.hero_died.emit(int(team), self)
	set_tower_throw_armed(false)
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
