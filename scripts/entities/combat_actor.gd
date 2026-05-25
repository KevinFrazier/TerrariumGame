class_name CombatActor
extends CharacterBody3D
## Abstract base for self-propelled combat units (Hero, Minion). Owns the shared
## surface those two duplicated — team identity, a HealthComponent, gravity, and
## damage forwarding — plus the full status-effect + buff layer.
##
## Status effects (slow, burn, poison, stun, root, chill→freeze, vulnerable,
## weaken, silence, knockback) and temporary buffs all live here so heroes and
## minions behave identically when hit. Towers/cores are StaticBody3D and don't
## extend this, so effects only ever land on heroes and minions.
##
## Subclasses call `tick_status(delta)` once per `_physics_process`, scale their
## horizontal movement by `speed_mult()` (0 while immobilized), gate attacks on
## `can_act()` / abilities on `can_use_ability()`, scale dealt damage by
## `damage_mult()`, and add `knockback_velocity()` to their velocity.

## Effect kinds a projectile/ability can request via `apply_status()`.
enum Status { SLOW, BURN, POISON, STUN, ROOT, FREEZE, VULNERABLE, WEAKEN, SILENCE, KNOCKBACK }

const CHILL_SLOW_PER_STACK := 0.15   ## each chill stack removes 15% move speed
const CHILL_FREEZE_STACKS := 4       ## stacks that trigger a freeze
const CHILL_FREEZE_DURATION := 1.2
const DOT_TICK_SEC := 0.5            ## damage-over-time is applied in discrete ticks
const KNOCKBACK_DECAY := 9.0         ## per-second decay of a knockback impulse

const COLOR_DOT := Color(1.0, 0.55, 0.2)
const COLOR_BUFF_ATTACK := Color(1.0, 0.6, 0.2)
const COLOR_BUFF_DEFENSE := Color(0.4, 0.7, 1.0)
const COLOR_BUFF_SPEED := Color(0.4, 1.0, 0.5)
const COLOR_SLOW := Color(0.4, 0.8, 1.0)
const COLOR_FREEZE := Color(0.65, 0.9, 1.0)
const COLOR_BURN := Color(1.0, 0.45, 0.15)
const COLOR_POISON := Color(0.55, 0.9, 0.3)
const COLOR_STUN := Color(1.0, 0.9, 0.3)
const COLOR_ROOT := Color(0.7, 0.5, 0.3)
const COLOR_VULNERABLE := Color(0.9, 0.35, 0.9)
const COLOR_WEAKEN := Color(0.6, 0.6, 0.6)
const COLOR_SILENCE := Color(0.7, 0.4, 1.0)

@export var team: Team.Id = Team.Id.A

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Movement slow (multiplicative, strongest wins).
var _slow_mult: float = 1.0
var _slow_timer: float = 0.0
# Chill stacks escalate into a freeze.
var _chill_stacks: int = 0
var _chill_timer: float = 0.0
var _freeze_timer: float = 0.0
# Hard control.
var _stun_timer: float = 0.0
var _root_timer: float = 0.0
var _silence_timer: float = 0.0
# Damage over time (burn = one source; poison = stacking).
var _burn_dps: float = 0.0
var _burn_timer: float = 0.0
var _poison_stacks: int = 0
var _poison_dps_per_stack: float = 0.0
var _poison_timer: float = 0.0
var _dot_accum: float = 0.0
# Damage modifiers.
var _vuln_mult: float = 1.0     # > 1 increases incoming damage
var _vuln_timer: float = 0.0
var _weaken_mult: float = 1.0   # < 1 reduces outgoing damage
var _weaken_timer: float = 0.0
# Temporary buffs (hero abilities).
var _atk_buff: float = 1.0
var _atk_buff_timer: float = 0.0
var _def_buff: float = 1.0      # < 1 reduces incoming damage
var _def_buff_timer: float = 0.0
var _speed_buff: float = 1.0
var _speed_buff_timer: float = 0.0
# Knockback impulse, decays to zero.
var _knockback: Vector3 = Vector3.ZERO

@onready var health: HealthComponent = $HealthComponent

func take_damage(amount: float, source: Node = null) -> void:
	health.take_damage(amount * incoming_mult(), source)

## Current HP — read by Targeter for HP-based targeting priority.
func get_hp() -> float:
	return health.current_hp

# --- queried by subclasses --------------------------------------------------
## Multiplier on outgoing damage (attack buff up, weaken down).
func damage_mult() -> float:
	return _atk_buff * _weaken_mult

## Multiplier on incoming damage (vulnerable up, defense buff down).
func incoming_mult() -> float:
	return _vuln_mult * _def_buff

## Movement speed multiplier; 0 while stunned/rooted/frozen.
func speed_mult() -> float:
	if is_immobile():
		return 0.0
	var chill := maxf(1.0 - float(_chill_stacks) * CHILL_SLOW_PER_STACK, 0.1)
	return minf(_slow_mult, chill) * _speed_buff

func is_immobile() -> bool:
	return _stun_timer > 0.0 or _root_timer > 0.0 or _freeze_timer > 0.0

## Whether the actor may attack/melee (stun and freeze disable it).
func can_act() -> bool:
	return _stun_timer <= 0.0 and _freeze_timer <= 0.0

## Whether the actor may use abilities (also blocked by silence).
func can_use_ability() -> bool:
	return can_act() and _silence_timer <= 0.0

## Residual knockback velocity for this frame; subclasses add it to `velocity`.
func knockback_velocity() -> Vector3:
	return _knockback

func has_active_buff() -> bool:
	return _atk_buff_timer > 0.0 or _def_buff_timer > 0.0 or _speed_buff_timer > 0.0

## Every active buff and debuff, each as {name, color, buff}. Drives the HUD
## status chips and the unit's status aura. Multiple effects coexist freely.
func get_active_effects() -> Array[Dictionary]:
	var fx: Array[Dictionary] = []
	if _atk_buff_timer > 0.0: fx.append({"name": "ATK", "color": COLOR_BUFF_ATTACK, "buff": true})
	if _def_buff_timer > 0.0: fx.append({"name": "DEF", "color": COLOR_BUFF_DEFENSE, "buff": true})
	if _speed_buff_timer > 0.0: fx.append({"name": "SPD", "color": COLOR_BUFF_SPEED, "buff": true})
	if _freeze_timer > 0.0:
		fx.append({"name": "FRZ", "color": COLOR_FREEZE, "buff": false})
	elif _chill_timer > 0.0:
		fx.append({"name": "CHL", "color": COLOR_FREEZE, "buff": false})
	if _slow_timer > 0.0: fx.append({"name": "SLO", "color": COLOR_SLOW, "buff": false})
	if _burn_timer > 0.0: fx.append({"name": "BRN", "color": COLOR_BURN, "buff": false})
	if _poison_timer > 0.0: fx.append({"name": "PSN", "color": COLOR_POISON, "buff": false})
	if _stun_timer > 0.0: fx.append({"name": "STN", "color": COLOR_STUN, "buff": false})
	if _root_timer > 0.0: fx.append({"name": "ROT", "color": COLOR_ROOT, "buff": false})
	if _vuln_timer > 0.0: fx.append({"name": "VUL", "color": COLOR_VULNERABLE, "buff": false})
	if _weaken_timer > 0.0: fx.append({"name": "WKN", "color": COLOR_WEAKEN, "buff": false})
	if _silence_timer > 0.0: fx.append({"name": "SIL", "color": COLOR_SILENCE, "buff": false})
	return fx

func has_active_effects() -> bool:
	return not get_active_effects().is_empty()

## Average color of all active effects (for the blended status aura).
func blended_effect_color() -> Color:
	var fx := get_active_effects()
	if fx.is_empty():
		return Color.WHITE
	var sum := Color(0, 0, 0)
	for e in fx:
		sum += e["color"] as Color
	return sum / float(fx.size())

# --- per-frame decay --------------------------------------------------------
## Decay every active effect and apply damage-over-time. Call once per physics
## frame from the subclass before moving.
func tick_status(delta: float) -> void:
	_slow_timer = _decay(_slow_timer, delta)
	if _slow_timer == 0.0:
		_slow_mult = 1.0
	_chill_timer = _decay(_chill_timer, delta)
	if _chill_timer == 0.0:
		_chill_stacks = 0
	_freeze_timer = _decay(_freeze_timer, delta)
	_stun_timer = _decay(_stun_timer, delta)
	_root_timer = _decay(_root_timer, delta)
	_silence_timer = _decay(_silence_timer, delta)
	_vuln_timer = _decay(_vuln_timer, delta)
	if _vuln_timer == 0.0:
		_vuln_mult = 1.0
	_weaken_timer = _decay(_weaken_timer, delta)
	if _weaken_timer == 0.0:
		_weaken_mult = 1.0
	_atk_buff_timer = _decay(_atk_buff_timer, delta)
	if _atk_buff_timer == 0.0:
		_atk_buff = 1.0
	_def_buff_timer = _decay(_def_buff_timer, delta)
	if _def_buff_timer == 0.0:
		_def_buff = 1.0
	_speed_buff_timer = _decay(_speed_buff_timer, delta)
	if _speed_buff_timer == 0.0:
		_speed_buff = 1.0
	_burn_timer = _decay(_burn_timer, delta)
	if _burn_timer == 0.0:
		_burn_dps = 0.0
	_poison_timer = _decay(_poison_timer, delta)
	if _poison_timer == 0.0:
		_poison_stacks = 0
	_tick_dot(delta)
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)

func _decay(timer: float, delta: float) -> float:
	return maxf(timer - delta, 0.0)

func _tick_dot(delta: float) -> void:
	var dps := _burn_dps + float(_poison_stacks) * _poison_dps_per_stack
	if dps <= 0.0:
		_dot_accum = 0.0
		return
	_dot_accum += delta
	if _dot_accum >= DOT_TICK_SEC:
		_dot_accum -= DOT_TICK_SEC
		# DoT ignores vulnerability (no incoming_mult) to avoid runaway stacking.
		health.take_damage(dps * DOT_TICK_SEC, null, COLOR_DOT)

# --- status application -----------------------------------------------------
## Generic entry point used by projectiles. `magnitude` meaning is per effect.
func apply_status(effect: Status, magnitude: float, duration: float) -> void:
	match effect:
		Status.SLOW: apply_slow(magnitude, duration)
		Status.BURN: apply_burn(magnitude, duration)
		Status.POISON: apply_poison(magnitude, duration)
		Status.STUN: apply_stun(duration)
		Status.ROOT: apply_root(duration)
		Status.FREEZE: apply_chill(int(maxf(magnitude, 1.0)), duration)
		Status.VULNERABLE: apply_vulnerable(magnitude, duration)
		Status.WEAKEN: apply_weaken(magnitude, duration)
		Status.SILENCE: apply_silence(duration)
		Status.KNOCKBACK: apply_knockback(-global_transform.basis.z * magnitude)

## `factor` is the speed multiplier (e.g. 0.5 = half speed). Strongest wins.
func apply_slow(factor: float, duration: float) -> void:
	if factor <= 0.0 or factor >= 1.0 or duration <= 0.0:
		return
	_slow_mult = minf(_slow_mult, factor)
	_slow_timer = maxf(_slow_timer, duration)

func apply_burn(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_timer = maxf(_burn_timer, duration)

func apply_poison(dps_per_stack: float, duration: float, stacks: int = 1) -> void:
	if dps_per_stack <= 0.0 or duration <= 0.0:
		return
	_poison_dps_per_stack = dps_per_stack
	_poison_stacks += stacks
	_poison_timer = maxf(_poison_timer, duration)

func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)

func apply_root(duration: float) -> void:
	_root_timer = maxf(_root_timer, duration)

## Add chill stacks; reaching the freeze threshold locks the actor down.
func apply_chill(stacks: int, duration: float) -> void:
	if duration <= 0.0:
		return
	_chill_stacks += maxi(stacks, 1)
	_chill_timer = maxf(_chill_timer, duration)
	if _chill_stacks >= CHILL_FREEZE_STACKS:
		_chill_stacks = 0
		_chill_timer = 0.0
		_freeze_timer = maxf(_freeze_timer, CHILL_FREEZE_DURATION)

func apply_vulnerable(mult: float, duration: float) -> void:
	if mult <= 1.0 or duration <= 0.0:
		return
	_vuln_mult = maxf(_vuln_mult, mult)
	_vuln_timer = maxf(_vuln_timer, duration)

func apply_weaken(mult: float, duration: float) -> void:
	if mult <= 0.0 or mult >= 1.0 or duration <= 0.0:
		return
	_weaken_mult = minf(_weaken_mult, mult)
	_weaken_timer = maxf(_weaken_timer, duration)

func apply_silence(duration: float) -> void:
	_silence_timer = maxf(_silence_timer, duration)

func apply_knockback(impulse: Vector3) -> void:
	_knockback += Vector3(impulse.x, 0.0, impulse.z)

# --- buffs (hero abilities) -------------------------------------------------
func apply_attack_buff(mult: float, duration: float) -> void:
	_atk_buff = maxf(mult, 1.0)
	_atk_buff_timer = maxf(_atk_buff_timer, duration)

## `mult` < 1 reduces incoming damage (warrior damage reduction).
func apply_damage_reduction(mult: float, duration: float) -> void:
	_def_buff = clampf(mult, 0.05, 1.0)
	_def_buff_timer = maxf(_def_buff_timer, duration)

func apply_speed_buff(mult: float, duration: float) -> void:
	_speed_buff = maxf(mult, 1.0)
	_speed_buff_timer = maxf(_speed_buff_timer, duration)
