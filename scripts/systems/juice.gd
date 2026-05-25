class_name Juice
extends RefCounted
## Stateless game-feel helpers: hit flashes, impact/death/level-up bursts, muzzle
## flashes, and a global hitstop. All effects are built from primitives so the
## project needs no imported art. Spawned effects parent themselves to the passed
## node (use the current scene) and free themselves when done.

static var _hitstop_active := false

## Flash a unit's mesh bright for a moment (hit feedback).
static func flash_mesh(mesh: MeshInstance3D, color: Color = Color(1, 1, 1), dur: float = 0.12) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	var tw := mesh.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, dur)

## Expanding, fading sphere — used for impacts, explosions, and death pops.
static func burst(parent: Node, world_pos: Vector3, color: Color, radius: float = 1.0, dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mi.mesh = sphere
	mi.material_override = _flat_mat(color, 0.85)
	mi.top_level = true
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.scale = Vector3.ONE * 0.2
	var mat := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

## Flat expanding ground ring (level-up flourish).
static func ring(parent: Node, world_pos: Vector3, color: Color, radius: float = 3.0, dur: float = 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 1.0
	mi.mesh = torus
	mi.material_override = _flat_mat(color, 0.9)
	mi.top_level = true
	mi.rotation.x = PI / 2.0
	parent.add_child(mi)
	mi.global_position = world_pos + Vector3.UP * 0.1
	mi.scale = Vector3.ONE * 0.3
	var mat := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, radius, radius), dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

## Small bright pop at a gun muzzle.
static func muzzle_flash(parent: Node, world_pos: Vector3, color: Color) -> void:
	burst(parent, world_pos, color, 0.6, 0.14)

## Scatter a handful of small "coins" upward (gold pickup feedback on kills).
static func coin_burst(parent: Node, world_pos: Vector3, count: int = 6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.top_level = true
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.18
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	p.mesh = mesh
	p.mesh.surface_set_material(0, _flat_mat(Color(1.0, 0.85, 0.2), 1.0))
	parent.add_child(p)
	p.global_position = world_pos
	_free_after(p, 1.0)

## Briefly slow time for impact weight. Safe to call repeatedly; overlaps are
## ignored. `node` is only used to reach the SceneTree.
static func hitstop(node: Node, scale: float = 0.25, dur: float = 0.06) -> void:
	if _hitstop_active or node == null or not node.is_inside_tree():
		return
	_hitstop_active = true
	Engine.time_scale = scale
	var timer := node.get_tree().create_timer(dur, true, false, true)  # ignore_time_scale
	await timer.timeout
	Engine.time_scale = 1.0
	_hitstop_active = false

static func _flat_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	return mat

static func _free_after(node: Node, secs: float) -> void:
	var t := node.get_tree().create_timer(secs)
	await t.timeout
	if is_instance_valid(node):
		node.queue_free()
