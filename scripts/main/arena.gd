extends Node3D
## Match orchestrator for the arena scene: configures lane spawners, assigns
## camera/HUD control to one hero (swap with Tab for local PvP testing), routes
## minion bounties into the economy, and resolves win/lose on core destruction.

@onready var core_a: Core = $CoreA
@onready var core_b: Core = $CoreB
@onready var hero_a: Hero = $HeroA
@onready var hero_b: Hero = $HeroB
@onready var spawner_a: WaveSpawner = $SpawnerA
@onready var spawner_b: WaveSpawner = $SpawnerB
@onready var hud: GameHUD = $HUD

var nav_region: NavigationRegion3D
var _path_line_a: MeshInstance3D
var _path_line_b: MeshInstance3D
var _local_hero: Hero

func _ready() -> void:
	GameState.reset_match()
	GameState.match_active = true

	_setup_navigation()
	_configure_lanes()
	EventBus.minion_died.connect(_on_minion_died)
	EventBus.core_destroyed.connect(_on_core_destroyed)
	# Re-bake so freshly built towers become obstacles minions route around.
	EventBus.tower_built.connect(func(_t, _n): _bake_navigation())

	_assign_control(GameState.local_team)

	spawner_a.start()
	spawner_b.start()
	EventBus.match_started.emit()

	# Prime HUD currency readouts.
	EventBus.currency_changed.emit(int(Team.Id.A), GameState.get_currency(Team.Id.A))
	EventBus.currency_changed.emit(int(Team.Id.B), GameState.get_currency(Team.Id.B))

func _configure_lanes() -> void:
	spawner_a.configure(Team.Id.A, core_b.global_position)
	spawner_b.configure(Team.Id.B, core_a.global_position)

## Build a NavigationMesh over the ground, carving holes around static structures
## (cores, towers) so minions path around them. Parsed from static colliders in
## the "navigation_source" group.
func _setup_navigation() -> void:
	# Reuse the scene's region if present, otherwise create one so navigation
	# never depends on a specific scene node existing.
	nav_region = get_node_or_null("NavRegion") as NavigationRegion3D
	if nav_region == null:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "NavRegion"
		add_child(nav_region)
	var nm := NavigationMesh.new()
	# Match the default navigation map cell size/height to register cleanly.
	nm.set_cell_size(0.25)
	nm.set_cell_height(0.25)
	nm.set_agent_radius(0.4)
	nm.set_agent_height(1.2)
	nm.set_agent_max_climb(0.5)
	nm.set_parsed_geometry_type(NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
	nm.set_collision_mask(Team.LAYER_WORLD | Team.LAYER_GROUND)
	nm.set_source_geometry_mode(NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN)
	nm.set_source_group_name(&"navigation_source")
	nav_region.navigation_mesh = nm
	$Ground.add_to_group("navigation_source")
	core_a.add_to_group("navigation_source")
	core_b.add_to_group("navigation_source")
	_bake_navigation()

func _bake_navigation() -> void:
	if nav_region:
		nav_region.bake_navigation_mesh(false)
		_redraw_lane_paths()

## Draw each team's navmesh route (spawner -> enemy core) as a line on the ground.
func _redraw_lane_paths() -> void:
	# Let the navigation map sync the freshly baked mesh before querying it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or nav_region == null:
		return
	var map := nav_region.get_navigation_map()
	NavigationServer3D.map_force_update(map)
	_path_line_a = _draw_lane(_path_line_a, map, spawner_a.global_position, core_b.global_position, Team.Id.A)
	_path_line_b = _draw_lane(_path_line_b, map, spawner_b.global_position, core_a.global_position, Team.Id.B)

func _draw_lane(line: MeshInstance3D, map: RID, from: Vector3, to: Vector3, team: Team.Id) -> MeshInstance3D:
	if line == null:
		line = MeshInstance3D.new()
		line.top_level = true
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := Team.body_color(team)
		c.a = 0.7
		mat.albedo_color = c
		line.material_override = mat
		add_child(line)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var im := ImmediateMesh.new()
	if path.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in path:
			im.surface_add_vertex(p + Vector3.UP * 0.12)
		im.surface_end()
	line.mesh = im
	return line

func _hero_for(team: Team.Id) -> Hero:
	return hero_a if team == Team.Id.A else hero_b

func _assign_control(team: Team.Id) -> void:
	GameState.local_team = team
	_local_hero = _hero_for(team)
	hero_a.set_controlled(team == Team.Id.A)
	hero_b.set_controlled(team == Team.Id.B)
	hud.set_active_hero(_local_hero)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swap_control"):
		var next := Team.Id.B if GameState.local_team == Team.Id.A else Team.Id.A
		_assign_control(next)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _on_minion_died(_dead_team: int, killer_team: int, bounty: int) -> void:
	GameState.add_currency(killer_team as Team.Id, bounty)

func _on_core_destroyed(team: int) -> void:
	if not GameState.match_active:
		return
	GameState.match_active = false
	var winner := Team.Id.B if (team as Team.Id) == Team.Id.A else Team.Id.A
	GameState.winner = winner
	spawner_a.stop()
	spawner_b.stop()
	EventBus.match_ended.emit(int(winner))
	var dead_core := core_a if (team as Team.Id) == Team.Id.A else core_b
	Juice.burst(self, dead_core.global_position + Vector3.UP, Team.body_color(team as Team.Id), 6.0, 0.8)
	# Brief slow-motion punctuates the kill before the result screen.
	Engine.time_scale = 0.3
	await get_tree().create_timer(1.0, true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_match_result(winner)
