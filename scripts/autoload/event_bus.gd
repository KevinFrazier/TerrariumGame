extends Node
## Global signal hub (autoload singleton `EventBus`). Lets gameplay systems,
## HUD, and the match manager communicate without hard references.

signal hero_died(team: int, hero: Node)
signal hero_respawned(team: int, hero: Node)
signal minion_died(team: int, killer_team: int, bounty: int)
signal core_destroyed(team: int)
signal tower_built(team: int, tower: Node)
signal currency_changed(team: int, amount: int)
signal match_started()
signal match_ended(winner_team: int)
