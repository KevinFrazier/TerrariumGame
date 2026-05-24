class_name Projectile
extends Area3D
## Damage projectile reused by heroes and towers. Optionally arcs under gravity.
## Configure via `setup()` right after instancing, before adding to the tree.
##
## In `lands_on_ground` mode it ignores units, collides only with the
## ground/world, and emits `landed(position)` where it touches down — used by the
## hero's tower-throw ability to decide where to build.

signal landed(position: Vector3)

@export var speed: float = 24.0
@export var damage: float = 12.0
@export var lifetime_sec: float = 4.0
@export var team: Team.Id = Team.Id.NEUTRAL
@export var affected_by_gravity: bool = false  ## toggle a falling gravity arc
@export var lands_on_ground: bool = false      ## collide with ground and emit `landed`

var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _spent: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	collision_layer = Team.LAYER_PROJECTILE
	_refresh_mask()
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)

func _refresh_mask() -> void:
	if lands_on_ground:
		# Pass by units, touch down on terrain only.
		collision_mask = Team.LAYER_WORLD | Team.LAYER_GROUND
	else:
		# Enemy bodies (units, towers, cores) all live on the enemy team layer, so
		# this never hits the shooter's own structures.
		collision_mask = Team.enemy_mask(team)

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
	if target != null and target.has_method("take_damage"):
		# take_damage(amount, source) — towers/heroes share this convention.
		target.take_damage(damage, self)
	elif lands_on_ground:
		landed.emit(global_position)
	queue_free()
