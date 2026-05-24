extends Node
## Persistent match + per-team data (autoload singleton `GameState`).
## Economy lives here so HUD and build menu read a single source of truth.

const STARTING_CURRENCY := 150
const MAX_TOWERS_PER_TEAM := 3

var local_team: Team.Id = Team.Id.A          ## Which hero the single player drives.
var winner: Team.Id = Team.Id.NEUTRAL
var match_active: bool = false
var selected_tower: TowerDefinition          ## Tower type the build menu/throw will place.

var _currency := {Team.Id.A: 0, Team.Id.B: 0}
var _tower_count := {Team.Id.A: 0, Team.Id.B: 0}

func reset_match() -> void:
	winner = Team.Id.NEUTRAL
	match_active = false
	for t in [Team.Id.A, Team.Id.B]:
		_currency[t] = STARTING_CURRENCY
		_tower_count[t] = 0

func get_currency(team: Team.Id) -> int:
	return _currency.get(team, 0)

func add_currency(team: Team.Id, amount: int) -> void:
	_currency[team] = get_currency(team) + amount
	EventBus.currency_changed.emit(team, _currency[team])

func can_afford(team: Team.Id, cost: int) -> bool:
	return get_currency(team) >= cost

func spend_currency(team: Team.Id, cost: int) -> bool:
	if not can_afford(team, cost):
		return false
	_currency[team] = get_currency(team) - cost
	EventBus.currency_changed.emit(team, _currency[team])
	return true

func get_tower_count(team: Team.Id) -> int:
	return _tower_count.get(team, 0)

func can_build_tower(team: Team.Id) -> bool:
	return get_tower_count(team) < MAX_TOWERS_PER_TEAM

func register_tower(team: Team.Id) -> void:
	_tower_count[team] = get_tower_count(team) + 1

func unregister_tower(team: Team.Id) -> void:
	_tower_count[team] = maxi(get_tower_count(team) - 1, 0)
