class_name HealthComponent
extends Node
## Reusable health/damage tracker. Attach as a child of any damageable entity
## (Hero, Minion, Tower, Core). The owning entity should forward damage to
## `take_damage()` and react to the `died` / `health_changed` signals.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_hp: float = 100.0
@export var invulnerable: bool = false

var current_hp: float
var _dead: bool = false

func _ready() -> void:
	current_hp = max_hp

func take_damage(amount: float, source: Node = null) -> void:
	if _dead or invulnerable or amount <= 0.0:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(current_hp, max_hp)
	if current_hp <= 0.0:
		_dead = true
		died.emit(source)

func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)

func revive(to_hp: float = -1.0) -> void:
	_dead = false
	current_hp = to_hp if to_hp > 0.0 else max_hp
	health_changed.emit(current_hp, max_hp)

func is_dead() -> bool:
	return _dead

func fraction() -> float:
	return current_hp / max_hp if max_hp > 0.0 else 0.0
