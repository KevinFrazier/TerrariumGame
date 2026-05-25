class_name Hero
extends CombatActor
## Player-controlled hero. Twin-stick: left stick moves (camera-relative), right
## stick orbits the camera around the hero. The hero faces its movement
## direction; fire shoots where the camera looks (assisted toward the nearest
## enemy via the shared Targeter). Only the `controlled` hero reads input and
## owns the camera.

## Class archetype (Warrior/Mage/Archer). When unset, the hero pulls its class
## from GameState (chosen in the lobby), then falls back to the exports below.
@export var definition: HeroDefinition

@export var move_speed: float = 7.0
@export var turn_speed: float = 12.0
@export var fire_cooldown_sec: float = 0.45
@export var melee_cooldown_sec: float = 0.7
@export var melee_damage: float = 25.0
@export var respawn_delay_sec: float = 4.0
@export var projectile_scene: PackedScene = preload("res://scenes/entities/projectile.tscn")

@export_group("Projectile")
@export var projectile_damage: float = 18.0
@export var projectile_speed: float = 28.0
@export var projectile_blast_radius: float = 0.0

@export_group("Buff Ability")
@export var buff_kind: HeroDefinition.BuffKind = HeroDefinition.BuffKind.DAMAGE_REDUCTION
@export var buff_magnitude: float = 0.5
@export var buff_duration_sec: float = 5.0
@export var buff_cooldown_sec: float = 12.0

@export_group("Leveling")
@export var xp_reward: int = 100               ## XP a killer gains for last-hitting this hero
@export var base_xp_to_level: float = 100.0
@export var xp_curve_growth: float = 1.35      ## each level costs this much more XP
## Per-level stat growth weights (fraction of base added per level). Tunable.
@export var melee_growth_per_level: float = 0.08
@export var projectile_growth_per_level: float = 0.08
@export var max_hp_growth_per_level: float = 0.10
@export var buff_growth_per_level: float = 0.05

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
var _buff_cd := 0.0
var _throw_armed := false
var _respawn_countdown: SceneTreeTimer
var _trajectory: MeshInstance3D
var _landing_marker: MeshInstance3D
var _spawn_transform: Transform3D

# Leveling state + the base stats level scaling multiplies from.
var _level := 1
var _xp := 0.0
var _base_melee := 25.0
var _base_projectile_damage := 18.0
var _base_max_hp := 200.0

var _shake := 0.0
var _buff_aura: MeshInstance3D

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
	if definition == null:
		definition = GameState.hero_defs.get(team) as HeroDefinition
	_apply_definition()
	_base_melee = melee_damage
	_base_projectile_damage = projectile_damage
	_base_max_hp = health.max_hp
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_apply_team_tint()
	_cam_pitch = cam_pitch_start
	camera_pivot.rotation = Vector3(-_cam_pitch, _cam_yaw, 0.0)
	# Over-the-shoulder: offset the arm sideways (rotates with the camera yaw) so
	# the character sits left of center and its front is visible.
	spring_arm.position.x = cam_shoulder_offset
	_ensure_throw_visuals()
	_ensure_buff_aura()
	_set_camera_active(controlled)

func _apply_definition() -> void:
	if definition == null:
		return
	move_speed = definition.move_speed
	fire_cooldown_sec = definition.fire_cooldown_sec
	melee_damage = definition.melee_damage
	projectile_damage = definition.projectile_damage
	projectile_speed = definition.projectile_speed
	projectile_blast_radius = definition.projectile_blast_radius
	health.max_hp = definition.max_hp
	health.current_hp = definition.max_hp
	buff_kind = definition.buff_kind
	buff_magnitude = definition.buff_magnitude
	buff_duration_sec = definition.buff_duration_sec
	buff_cooldown_sec = definition.buff_cooldown_sec
	if definition.body_mesh != null:
		mesh.mesh = definition.body_mesh

func _apply_team_tint() -> void:
	mesh.material_override = Juice.make_unit_material(Team.body_color(team))

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
	tick_status(delta)
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_melee_timer = maxf(_melee_timer - delta, 0.0)
	_buff_cd = maxf(_buff_cd - delta, 0.0)
	_update_shake(delta)
	_update_buff_aura()

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
	var kb := knockback_velocity()
	velocity.x = move_dir.x * spd + kb.x
	velocity.z = move_dir.z * spd + kb.z
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
		# Tap to arm/aim (you keep full camera aim while armed); tap again to throw.
		if Input.is_action_just_pressed("ability_1"):
			if _throw_armed:
				release_tower_throw()
			else:
				set_tower_throw_armed(true)
		# Projectile fires on release.
		if Input.is_action_just_released("fire"):
			fire()
		if Input.is_action_just_pressed("ability_2"):
			activate_buff()

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
	if _fire_timer > 0.0 or health.is_dead() or projectile_scene == null or not can_use_ability():
		return
	_fire_timer = fire_cooldown_sec
	# Shoot along the camera's full look direction, including pitch, so aiming
	# down sends the shot toward the floor (body yaw still tracks the camera).
	var shot_dir := _look_dir_3d()
	var p := projectile_scene.instantiate() as Projectile
	p.damage = projectile_damage * damage_mult()
	p.speed = projectile_speed
	p.blast_radius = projectile_blast_radius
	p.splash_falloff = projectile_blast_radius > 0.0
	p.owner_unit = self
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	p.setup(team, shot_dir)
	Juice.muzzle_flash(get_tree().current_scene, muzzle.global_position, Team.body_color(team).lightened(0.3))

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
	tower.set_targeting_priority(GameState.target_priority)
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
	if _melee_timer > 0.0 or health.is_dead() or not can_act():
		return
	if melee_area.has_overlapping_bodies():
		melee()

func melee() -> void:
	if _melee_timer > 0.0 or health.is_dead() or not can_act():
		return
	var hit := false
	for other in melee_area.get_overlapping_bodies():
		if other.has_method("take_damage"):
			other.take_damage(melee_damage * damage_mult(), self)
			hit = true
	if hit:
		_melee_timer = melee_cooldown_sec
		Juice.hitstop(self, 0.45, 0.05)
		shake(0.25)

func get_fire_ready() -> float:
	return 1.0 - (_fire_timer / fire_cooldown_sec) if fire_cooldown_sec > 0.0 else 1.0

# --- buff ability ----------------------------------------------------------
func activate_buff() -> void:
	if _buff_cd > 0.0 or health.is_dead() or not can_use_ability():
		return
	_buff_cd = buff_cooldown_sec
	var mag := _scaled_buff_magnitude()
	match buff_kind:
		HeroDefinition.BuffKind.ATTACK_POWER:
			apply_attack_buff(mag, buff_duration_sec)
		HeroDefinition.BuffKind.DAMAGE_REDUCTION:
			apply_damage_reduction(mag, buff_duration_sec)
		HeroDefinition.BuffKind.SPEED:
			apply_speed_buff(mag, buff_duration_sec)
	Juice.ring(get_tree().current_scene, global_position, blended_effect_color(), 2.6, 0.45)

## Buffs scale with level: > 1 buffs grow, the < 1 damage-reduction buff deepens.
func _scaled_buff_magnitude() -> float:
	var steps := float(_level - 1) * buff_growth_per_level
	if buff_kind == HeroDefinition.BuffKind.DAMAGE_REDUCTION:
		return clampf(buff_magnitude * (1.0 - steps), 0.1, 1.0)
	return buff_magnitude * (1.0 + steps)

## 0..1 readiness of the buff ability (drives the HUD button fade).
func get_buff_ready() -> float:
	return 1.0 - (_buff_cd / buff_cooldown_sec) if buff_cooldown_sec > 0.0 else 1.0

# --- damage / death --------------------------------------------------------
func _on_died(source: Node) -> void:
	if source is Hero and source != self:
		(source as Hero).gain_xp(xp_reward)
	EventBus.hero_died.emit(int(team), self)
	Juice.burst(get_tree().current_scene, global_position + Vector3.UP, Team.body_color(team), 2.4, 0.5)
	set_tower_throw_armed(false)
	_set_dead_visual(true)
	_respawn_countdown = get_tree().create_timer(respawn_delay_sec)
	await _respawn_countdown.timeout
	if is_instance_valid(self):
		_respawn()

func _on_damaged(amount: float, _source: Node) -> void:
	Juice.flash_mesh(mesh)
	if controlled:
		shake(clampf(amount / 40.0, 0.12, 0.7))

# --- leveling --------------------------------------------------------------
func gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	_xp += float(amount)
	while _xp >= _xp_to_next():
		_xp -= _xp_to_next()
		_level += 1
		_on_level_up()

func _xp_to_next() -> float:
	return base_xp_to_level * pow(xp_curve_growth, float(_level - 1))

func _on_level_up() -> void:
	# Scale the hero's own stats off their captured base values.
	melee_damage = _base_melee * (1.0 + float(_level - 1) * melee_growth_per_level)
	projectile_damage = _base_projectile_damage * (1.0 + float(_level - 1) * projectile_growth_per_level)
	var new_max := _base_max_hp * (1.0 + float(_level - 1) * max_hp_growth_per_level)
	var gained := new_max - health.max_hp
	health.max_hp = new_max
	health.heal(maxf(gained, 0.0))  # level-up tops off the new HP gained
	# Minions of this team scale off the team level (applied by the spawner).
	GameState.set_team_level(team, _level)
	EventBus.hero_leveled.emit(int(team), _level)
	Juice.ring(get_tree().current_scene, global_position, Color(1.0, 0.92, 0.4), 3.2, 0.55)
	Juice.burst(get_tree().current_scene, global_position + Vector3.UP, Color(1.0, 0.95, 0.5), 1.8, 0.4)

func get_level() -> int:
	return _level

## 0..1 progress toward the next level (drives the HUD XP bar).
func get_xp_fraction() -> float:
	var need := _xp_to_next()
	return clampf(_xp / need, 0.0, 1.0) if need > 0.0 else 0.0

# --- camera shake ----------------------------------------------------------
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _update_shake(delta: float) -> void:
	_shake = maxf(_shake - delta * 3.0, 0.0)
	if camera:
		camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.25

# --- buff aura -------------------------------------------------------------
func _ensure_buff_aura() -> void:
	_buff_aura = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.7
	ring.outer_radius = 0.95
	_buff_aura.mesh = ring
	_buff_aura.rotation.x = PI / 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	_buff_aura.material_override = mat
	_buff_aura.visible = false
	add_child(_buff_aura)
	_buff_aura.position = Vector3(0.0, 0.1, 0.0)

func _update_buff_aura() -> void:
	if _buff_aura == null:
		return
	# The aura reflects every active buff and debuff at once (blended color).
	var active := has_active_effects()
	_buff_aura.visible = active
	if active:
		var c := blended_effect_color()
		var mat := _buff_aura.material_override as StandardMaterial3D
		mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
		mat.emission = c

## Seconds until this hero respawns (0 when alive). Drives the HUD countdown.
func get_respawn_remaining() -> float:
	if health.is_dead() and _respawn_countdown != null:
		return _respawn_countdown.time_left
	return 0.0

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
