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

@export_group("Projectile")
@export var projectile_speed: float = 24.0
## Per-tower projectile visual; falls back to the default when unset.
@export var projectile_scene: PackedScene
## Lob the shot under gravity and detonate on impact/ground (mortar-style).
@export var projectile_gravity: bool = false

@export_group("Area & Effects")
## > 0 deals splash damage to every enemy within this radius of impact.
@export var blast_radius: float = 0.0
## Taper splash damage from full at the center down toward the edge.
@export var splash_falloff: bool = false
## 0 = no slow; otherwise the speed multiplier applied to hit enemies (e.g. 0.5).
@export var slow_factor: float = 0.0
@export var slow_duration_sec: float = 0.0

@export_group("Status Effect")
## When enabled, hits apply `status_effect` to the (CombatActor) target.
@export var applies_status: bool = false
@export var status_effect: CombatActor.Status = CombatActor.Status.BURN
## Effect strength — meaning depends on the effect (burn=dps, vulnerable=mult,
## chill=stacks, weaken=mult, knockback=impulse; ignored for stun/root/silence).
@export var status_magnitude: float = 6.0
@export var status_duration_sec: float = 3.0

@export_group("Targeting")
@export var targeting_priority: Targeter.Priority = Targeter.Priority.NEAREST

@export_group("Upgrade")
## Next-tier definition this tower upgrades into (null = max tier).
@export var upgrade: TowerDefinition
@export var upgrade_cost: int = 0
