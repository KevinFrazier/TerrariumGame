class_name TowerDefinition
extends Resource
## Data-driven tower stats. Add new .tres files of this type to introduce more
## tower types; the build menu reads `display_name` and `cost`.

@export var display_name: String = "Basic Tower"
@export var cost: int = 75
@export var damage: float = 18.0
@export var attack_range: float = 11.0
@export var fire_rate_per_sec: float = 1.2
@export var max_hp: float = 160.0
@export var scene: PackedScene
