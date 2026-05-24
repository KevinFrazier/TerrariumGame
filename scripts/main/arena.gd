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

var _local_hero: Hero

func _ready() -> void:
	GameState.reset_match()
	GameState.match_active = true

	_configure_lanes()
	EventBus.minion_died.connect(_on_minion_died)
	EventBus.core_destroyed.connect(_on_core_destroyed)

	_assign_control(GameState.local_team)

	spawner_a.start()
	spawner_b.start()
	EventBus.match_started.emit()

	# Prime HUD currency readouts.
	EventBus.currency_changed.emit(int(Team.Id.A), GameState.get_currency(Team.Id.A))
	EventBus.currency_changed.emit(int(Team.Id.B), GameState.get_currency(Team.Id.B))

func _configure_lanes() -> void:
	var a_to_b: PackedVector3Array = [Vector3(0, 0, 0), core_b.global_position]
	var b_to_a: PackedVector3Array = [Vector3(0, 0, 0), core_a.global_position]
	spawner_a.configure(Team.Id.A, a_to_b)
	spawner_b.configure(Team.Id.B, b_to_a)

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
	hud.show_match_result(winner)
