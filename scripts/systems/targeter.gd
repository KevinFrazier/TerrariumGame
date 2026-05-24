class_name Targeter
extends Area3D
## Shared nearest-enemy acquisition used by Hero, Minion, and Tower.
##
## Place as a child of a combat entity and set `team` (usually mirrored from the
## owner). The Area3D's own collision_mask is configured at runtime to the enemy
## team's body layer, so `_enemies` only ever contains valid targets.
##
## Usage:
##   Minion / Tower: `acquire_target()` — pure auto-aim, nearest enemy in range.
##   Hero:           `nearest_in_direction(dir)` — aim-assist toward a direction.

@export var team: Team.Id = Team.Id.NEUTRAL:
	set(value):
		team = value
		_refresh_mask()
@export var detection_radius: float = 12.0:
	set(value):
		detection_radius = value
		if _shape and _shape.shape is SphereShape3D:
			(_shape.shape as SphereShape3D).radius = value

var _shape: CollisionShape3D
var _enemies: Array[Node3D] = []

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	_refresh_mask()
	_ensure_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _ensure_shape() -> void:
	_shape = get_node_or_null("Shape") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Shape"
		add_child(_shape)
	if _shape.shape == null:
		var sphere := SphereShape3D.new()
		sphere.radius = detection_radius
		_shape.shape = sphere

func _refresh_mask() -> void:
	collision_mask = Team.enemy_mask(team)

## Nearest living enemy in range, or null.
func acquire_target() -> Node3D:
	_prune()
	var best: Node3D = null
	var best_dist := INF
	var origin := global_position
	for e in _enemies:
		var d := origin.distance_squared_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best

## Enemy whose direction best matches `dir` (aim-assist). Falls back to the
## nearest enemy when `dir` is zero or nothing is suitably aligned.
func nearest_in_direction(dir: Vector3) -> Node3D:
	_prune()
	if dir.length_squared() < 0.0001:
		return acquire_target()
	var aim := dir.normalized()
	var origin := global_position
	var best: Node3D = null
	var best_score := -1.0
	for e in _enemies:
		var to_e := e.global_position - origin
		to_e.y = 0.0
		if to_e.length_squared() < 0.0001:
			continue
		var dot := aim.dot(to_e.normalized())
		if dot > best_score:
			best_score = dot
			best = e
	# Require the target to be roughly in front (within ~70 degrees).
	if best != null and best_score >= 0.34:
		return best
	return acquire_target()

func has_target() -> bool:
	_prune()
	return not _enemies.is_empty()

func _prune() -> void:
	for i in range(_enemies.size() - 1, -1, -1):
		var e := _enemies[i]
		if not is_instance_valid(e):
			_enemies.remove_at(i)

func _register(node: Node) -> void:
	var n3 := node as Node3D
	if n3 != null and not _enemies.has(n3):
		_enemies.append(n3)

func _unregister(node: Node) -> void:
	var n3 := node as Node3D
	if n3 != null:
		_enemies.erase(n3)

func _on_body_entered(body: Node3D) -> void: _register(body)
func _on_body_exited(body: Node3D) -> void: _unregister(body)
func _on_area_entered(area: Area3D) -> void: _register(area.get_parent())
func _on_area_exited(area: Area3D) -> void: _unregister(area.get_parent())
