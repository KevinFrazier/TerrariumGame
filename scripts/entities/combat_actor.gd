class_name CombatActor
extends CharacterBody3D
## Abstract base for self-propelled combat units (Hero, Minion). Owns the shared
## surface those two duplicated — team identity, a HealthComponent, gravity, and
## damage forwarding — plus the slow status effect that towers can inflict.
##
## Subclasses call `tick_slow(delta)` once per `_physics_process` and scale their
## horizontal movement by `speed_mult()`.

@export var team: Team.Id = Team.Id.A

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _slow_mult: float = 1.0
var _slow_timer: float = 0.0

@onready var health: HealthComponent = $HealthComponent

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount, source)

## Current HP — read by Targeter for HP-based targeting priority.
func get_hp() -> float:
	return health.current_hp

## Apply a slow: `factor` is the speed multiplier (e.g. 0.5 = half speed).
## The strongest active slow wins; the timer always refreshes to the new hit.
func apply_slow(factor: float, duration: float) -> void:
	if factor <= 0.0 or factor >= 1.0 or duration <= 0.0:
		return
	_slow_mult = minf(_slow_mult, factor)
	_slow_timer = maxf(_slow_timer, duration)

## Decay the active slow. Call once per physics frame from the subclass.
func tick_slow(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer = maxf(_slow_timer - delta, 0.0)
		if _slow_timer == 0.0:
			_slow_mult = 1.0

## Movement speed multiplier from the current slow (1.0 when unaffected).
func speed_mult() -> float:
	return _slow_mult
