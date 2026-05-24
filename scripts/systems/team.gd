class_name Team
extends RefCounted
## Team identity helpers shared by all combat entities.
##
## Teams map to named physics layers so targeting reduces to a layer/mask check.
## Layer bits (1-based, matching project.godot layer_names):
##   1 world, 2 ground, 3 team_a, 4 team_b, 5 projectile

enum Id { A, B, NEUTRAL }

const LAYER_WORLD := 1 << 0
const LAYER_GROUND := 1 << 1
const LAYER_TEAM_A := 1 << 2
const LAYER_TEAM_B := 1 << 3
const LAYER_PROJECTILE := 1 << 4

## The physics layer bit an entity of `team` lives on.
static func body_layer(team: Id) -> int:
	match team:
		Id.A: return LAYER_TEAM_A
		Id.B: return LAYER_TEAM_B
		_: return LAYER_WORLD

## The mask that selects all enemies of `team` (the other team's body layer).
static func enemy_mask(team: Id) -> int:
	match team:
		Id.A: return LAYER_TEAM_B
		Id.B: return LAYER_TEAM_A
		_: return LAYER_TEAM_A | LAYER_TEAM_B

static func is_enemy(a: Id, b: Id) -> bool:
	if a == Id.NEUTRAL or b == Id.NEUTRAL:
		return false
	return a != b

static func body_color(team: Id) -> Color:
	match team:
		Id.A: return Color(0.25, 0.5, 1.0)
		Id.B: return Color(1.0, 0.35, 0.3)
		_: return Color(0.7, 0.7, 0.7)

static func display_name(team: Id) -> String:
	match team:
		Id.A: return "Player A"
		Id.B: return "Player B"
		_: return "Neutral"
