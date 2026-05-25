class_name WaveSpawner
extends Node3D
## Spawns timed minion waves at its own position and sends them toward the enemy
## core, where each minion navmesh-paths to the destination. One spawner per team.

@export var team: Team.Id = Team.Id.A
@export var minion_scene: PackedScene = preload("res://scenes/entities/minion.tscn")
@export var wave_interval_sec: float = 12.0
@export var minions_per_wave: int = 4
@export var spacing_sec: float = 0.6
@export var start_delay_sec: float = 3.0
@export var auto_start: bool = false

var _destination: Vector3 = Vector3.ZERO
var _running: bool = false

func _ready() -> void:
	if auto_start:
		start()

## Destination in world space (the enemy core); minions navmesh-path to it.
func configure(p_team: Team.Id, destination: Vector3) -> void:
	team = p_team
	_destination = destination

func start() -> void:
	if _running:
		return
	_running = true
	_run_loop()

func stop() -> void:
	_running = false

func _run_loop() -> void:
	await get_tree().create_timer(start_delay_sec).timeout
	while _running and is_inside_tree():
		_spawn_wave()
		await get_tree().create_timer(wave_interval_sec).timeout

func _spawn_wave() -> void:
	for i in minions_per_wave:
		if not _running:
			return
		_spawn_one()
		await get_tree().create_timer(spacing_sec).timeout

func _spawn_one() -> void:
	if minion_scene == null:
		return
	var m := minion_scene.instantiate() as Minion
	m.team = team
	get_tree().current_scene.add_child(m)
	# Slight lateral scatter so the wave doesn't stack into one column.
	var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	m.global_position = global_position + jitter
	m.set_destination(_destination)
