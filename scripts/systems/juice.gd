class_name Juice
extends RefCounted
## Stateless game-feel helpers. The visual effects (unit hit-flash, impact/death
## bursts, expanding rings) are GPU shaders; this code just spawns a mesh with the
## right ShaderMaterial and tweens a single 0..1 progress uniform, then frees it.
## Coins stay on CPUParticles3D for GL-Compatibility safety, and hitstop/shake are
## time/transform effects that aren't shader-expressible.

const UNIT_SHADER := preload("res://shaders/unit.gdshader")
const BURST_SHADER := preload("res://shaders/fx_burst.gdshader")
const RING_SHADER := preload("res://shaders/fx_ring.gdshader")

static var _hitstop_active := false

## Team-tinted unit body material with a shader hit-flash. Used by Hero/Minion.
static func make_unit_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = UNIT_SHADER
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("flash", 0.0)
	return mat

## Flash a unit's mesh bright for a moment (hit feedback). Drives the unit
## shader's `flash` uniform; falls back to emission for non-shader materials.
static func flash_mesh(mesh: MeshInstance3D, color: Color = Color(1, 1, 1), dur: float = 0.12) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	var sm := mesh.material_override as ShaderMaterial
	if sm != null and sm.shader == UNIT_SHADER:
		sm.set_shader_parameter("flash", 1.0)
		mesh.create_tween().tween_property(sm, "shader_parameter/flash", 0.0, dur)
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	mesh.create_tween().tween_property(mat, "emission_energy_multiplier", 0.0, dur)

## Expanding, fading sphere (impacts, explosions, death pops) — expansion + fade
## happen in the burst shader.
static func burst(parent: Node, world_pos: Vector3, color: Color, radius: float = 1.0, dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.top_level = true
	mi.material_override = _fx_material(BURST_SHADER, color, radius)
	parent.add_child(mi)
	mi.global_position = world_pos
	_animate_progress(mi, dur)

## Flat expanding ground ring (level-up / buff / tier flourish) — drawn by the
## ring shader on a static flat quad scaled to the final diameter.
static func ring(parent: Node, world_pos: Vector3, color: Color, radius: float = 3.0, dur: float = 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.top_level = true
	mi.rotation.x = -PI / 2.0  # lay flat on the ground, facing up
	mi.material_override = _fx_material(RING_SHADER, color, radius)
	parent.add_child(mi)
	mi.global_position = world_pos + Vector3.UP * 0.1
	_animate_progress(mi, dur)

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
	var coin_mat := StandardMaterial3D.new()
	coin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	coin_mat.albedo_color = Color(1.0, 0.85, 0.2)
	mesh.surface_set_material(0, coin_mat)
	p.mesh = mesh
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

static func _fx_material(shader: Shader, color: Color, radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("t", 0.0)
	return mat

## Tween the shared 0..1 `t` uniform that every fx shader animates on, then free.
static func _animate_progress(mi: MeshInstance3D, dur: float) -> void:
	var tw := mi.create_tween()
	tw.tween_property(mi.material_override, "shader_parameter/t", 1.0, dur)
	tw.tween_callback(mi.queue_free)

static func _free_after(node: Node, secs: float) -> void:
	var t := node.get_tree().create_timer(secs)
	await t.timeout
	if is_instance_valid(node):
		node.queue_free()
