class_name Projectile
extends Area3D
## Damage projectile reused by heroes and towers. Optionally arcs under gravity.
## Configure via `setup()` (direct shots) or `launch()` (mortar arc) right after
## instancing, before adding to the tree.
##
## In `lands_on_ground` mode it ignores units, collides only with the
## ground/world, and emits `landed(position)` where it touches down — used by the
## hero's tower-throw ability to decide where to build.
##
## With `blast_radius > 0` it deals splash damage to every enemy in range on
## impact (the cannon/mortar AoE). With `detonate_on_ground` it also explodes on
## terrain, so a lobbed mortar shell still bursts where it lands.

signal landed(position: Vector3)

@export var speed: float = 24.0
@export var damage: float = 12.0
@export var lifetime_sec: float = 4.0
@export var team: Team.Id = Team.Id.NEUTRAL
@export var affected_by_gravity: bool = false  ## toggle a falling gravity arc
@export var lands_on_ground: bool = false      ## collide with ground and emit `landed`
@export var detonate_on_ground: bool = false   ## explode on terrain too (mortar)
@export var blast_radius: float = 0.0          ## > 0 deals splash damage in range
@export var splash_falloff: bool = false       ## taper splash damage toward the edge
@export var slow_factor: float = 0.0           ## speed multiplier applied to hit enemies
@export var slow_duration_sec: float = 0.0
@export var applies_status: bool = false       ## apply a status effect on hit
@export var status_effect: CombatActor.Status = CombatActor.Status.BURN
@export var status_magnitude: float = 0.0
@export var status_duration_sec: float = 0.0

## The unit that fired this shot (hero or tower). Used as the damage source so
## last-hit kill credit (XP, bounty) flows to it rather than the projectile.
var owner_unit: Node = null

const EDGE_DAMAGE_FRACTION := 0.3  ## splash damage at the blast edge when falloff is on

var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _spent: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	collision_layer = Team.LAYER_PROJECTILE
	_refresh_mask()
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)
	if not lands_on_ground:
		_add_trail()

## A short comet trail of fading sparks behind the shot.
func _add_trail() -> void:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 16
	p.lifetime = 0.35
	p.speed_scale = 1.0
	p.direction = Vector3.ZERO
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.28
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	p.mesh.surface_set_material(0, mat)
	add_child(p)

func _refresh_mask() -> void:
	if lands_on_ground:
		# Pass by units, touch down on terrain only.
		collision_mask = Team.LAYER_WORLD | Team.LAYER_GROUND
	else:
		# Enemy bodies (units, towers, cores) all live on the enemy team layer, so
		# this never hits the shooter's own structures.
		var mask := Team.enemy_mask(team)
		if detonate_on_ground:
			mask |= Team.LAYER_WORLD | Team.LAYER_GROUND
		collision_mask = mask

## team: owner's team. direction: world-space aim (normalized internally).
## p_speed >= 0 overrides the launch speed (used by the gravity throw).
func setup(p_team: Team.Id, direction: Vector3, p_damage: float = -1.0, p_speed: float = -1.0) -> void:
	team = p_team
	if p_speed >= 0.0:
		speed = p_speed
	# _ready() ran at add_child() before team/flags were known; refresh the mask.
	_refresh_mask()
	if p_damage >= 0.0:
		damage = p_damage
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	_velocity = dir * speed
	_orient(dir)

## Launch with an explicit initial velocity (used by the mortar's ballistic arc,
## where gravity then curves the shot down onto the target).
func launch(p_team: Team.Id, velocity: Vector3) -> void:
	team = p_team
	_refresh_mask()
	_velocity = velocity
	if velocity.length_squared() > 0.0001:
		_orient(velocity.normalized())

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_sec:
		_resolve(null)
		return
	if affected_by_gravity:
		_velocity.y -= _gravity * delta
	global_position += _velocity * delta
	if affected_by_gravity and _velocity.length_squared() > 0.01:
		_orient(_velocity.normalized())
	# Safety net: if a thrown projectile sails off the edge, treat the fall as a
	# landing so the reserved tower still resolves instead of vanishing.
	if lands_on_ground and global_position.y < -3.0:
		_resolve(null)

## Aim the mesh along `dir`, avoiding a colinear up-vector when shooting straight
## up or down (now possible with the full pitch range).
func _orient(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD
	look_at(global_position + dir, up)

func _on_hit(body: Node3D) -> void:
	_resolve(body)

func _on_area_hit(area: Area3D) -> void:
	_resolve(area.get_parent())

func _resolve(target: Node) -> void:
	if _spent:
		return
	_spent = true
	var scene := get_tree().current_scene
	if blast_radius > 0.0:
		_explode()
		Juice.burst(scene, global_position, Color(1.0, 0.65, 0.2), blast_radius, 0.4)
	elif target != null and target.has_method("take_damage"):
		_apply_hit(target, damage)
		Juice.burst(scene, global_position, Color(1.0, 0.85, 0.4), 0.9, 0.2)
	elif lands_on_ground:
		landed.emit(global_position)
	queue_free()

## Damage (and optionally slow / apply a status to) a single enemy.
func _apply_hit(node: Node, amount: float) -> void:
	if node.has_method("take_damage"):
		# take_damage(amount, source) — towers/heroes share this convention.
		# Credit the firing unit (not the projectile) so kill rewards attribute right.
		node.take_damage(amount, owner_unit if owner_unit != null else self)
	if slow_factor > 0.0 and node.has_method("apply_slow"):
		node.apply_slow(slow_factor, slow_duration_sec)
	if applies_status and node.has_method("apply_status"):
		node.apply_status(status_effect, status_magnitude, status_duration_sec)

## Splash damage every enemy within blast_radius of the impact point.
func _explode() -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = Team.enemy_mask(team)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	for hit in space.intersect_shape(params, 32):
		var c: Object = hit.get("collider")
		if c == null or not c.has_method("take_damage"):
			continue
		var amount := damage
		if splash_falloff:
			var dist := global_position.distance_to((c as Node3D).global_position)
			var frac := clampf(1.0 - dist / blast_radius, 0.0, 1.0)
			amount = damage * lerpf(EDGE_DAMAGE_FRACTION, 1.0, frac)
		_apply_hit(c, amount)
