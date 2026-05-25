class_name HeroDefinition
extends Resource
## Data-driven hero archetype (Warrior / Mage / Archer). Assigned to a Hero, it
## sets the body mesh, core combat stats, projectile, and the temporary buff the
## hero's ability grants.

enum BuffKind { ATTACK_POWER, DAMAGE_REDUCTION, SPEED }

@export var display_name: String = "Warrior"
## Body mesh swapped onto the hero so each class is visually distinct.
@export var body_mesh: Mesh

@export_group("Stats")
@export var max_hp: float = 200.0
@export var move_speed: float = 7.0
@export var melee_damage: float = 25.0
@export var fire_cooldown_sec: float = 0.45

@export_group("Projectile")
@export var projectile_damage: float = 18.0
@export var projectile_speed: float = 28.0
## > 0 makes the shot a small AoE (mage bolt).
@export var projectile_blast_radius: float = 0.0

@export_group("Buff Ability")
@export var buff_kind: BuffKind = BuffKind.DAMAGE_REDUCTION
## Multiplier applied while active. ATTACK_POWER/SPEED use > 1; DAMAGE_REDUCTION
## uses < 1 (incoming damage multiplier, e.g. 0.5 = take half).
@export var buff_magnitude: float = 0.5
@export var buff_duration_sec: float = 5.0
@export var buff_cooldown_sec: float = 12.0
