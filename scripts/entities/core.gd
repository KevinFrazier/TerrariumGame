class_name Core
extends StaticBody3D
## The structure each player defends. Sits on its team's body layer (so enemies
## target it) plus the world layer (so units physically collide with it).
## Destruction ends the match in favor of the other team.

@export var team: Team.Id = Team.Id.A

@onready var health: HealthComponent = $HealthComponent
@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("cores")
	collision_layer = Team.body_layer(team) | Team.LAYER_WORLD
	collision_mask = 0
	health.died.connect(_on_died)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Team.body_color(team).darkened(0.15)
	mat.emission_enabled = true
	mat.emission = Team.body_color(team)
	mat.emission_energy_multiplier = 0.4
	mesh.material_override = mat

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

func get_hp() -> float:
	return health.current_hp

func _on_died(_source: Node) -> void:
	EventBus.core_destroyed.emit(int(team))
