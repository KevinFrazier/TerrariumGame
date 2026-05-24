class_name Projectile
extends Area3D
## Straight-line damage projectile reused by heroes and towers.
## Configure via `setup()` right after instancing, before adding to the tree.

@export var speed: float = 24.0
@export var damage: float = 12.0
@export var lifetime_sec: float = 4.0
@export var team: Team.Id = Team.Id.NEUTRAL

var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _spent: bool = false

func _ready() -> void:
	collision_layer = Team.LAYER_PROJECTILE
	# Enemy bodies (units, towers, cores) all live on the enemy team layer, so
	# this never hits the shooter's own structures. World is intentionally
	# excluded so a stray shot can't damage your own core/towers.
	collision_mask = Team.enemy_mask(team)
	body_entered.connect(_on_hit)
	area_entered.connect(_on_area_hit)

## team: owner's team. direction: world-space aim (will be flattened/normalized).
func setup(p_team: Team.Id, direction: Vector3, p_damage: float = -1.0) -> void:
	team = p_team
	# _ready() ran at add_child() before team was known, so refresh the mask now.
	collision_mask = Team.enemy_mask(team)
	if p_damage >= 0.0:
		damage = p_damage
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	_velocity = dir * speed
	look_at(global_position + dir, Vector3.UP)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_sec:
		queue_free()
		return
	global_position += _velocity * delta

func _on_hit(body: Node3D) -> void:
	_resolve(body)

func _on_area_hit(area: Area3D) -> void:
	_resolve(area.get_parent())

func _resolve(target: Node) -> void:
	if _spent:
		return
	if target != null and target.has_method("take_damage"):
		# take_damage(amount, source) — towers/heroes share this convention.
		target.take_damage(damage, self)
	_spent = true
	queue_free()
