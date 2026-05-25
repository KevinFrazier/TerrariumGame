extends Control
## Local lobby placeholder. For the prototype both heroes exist in one match on
## one machine; "Start Match" loads the arena. Each side picks a hero class
## (Warrior/Mage/Archer) here; the arena applies it on spawn. Structured so
## Host/Join networking can replace the single button later.

const ARENA_SCENE := "res://scenes/main/arena.tscn"
const HERO_TYPES: Array[HeroDefinition] = [
	preload("res://resources/heroes/warrior.tres"),
	preload("res://resources/heroes/mage.tres"),
	preload("res://resources/heroes/archer.tres"),
]

@onready var start_button: Button = $Center/VBox/StartButton
@onready var side_button: Button = $Center/VBox/SideButton
@onready var hero_a_button: Button = $Center/VBox/HeroAButton
@onready var hero_b_button: Button = $Center/VBox/HeroBButton

var _hero_idx := {Team.Id.A: 0, Team.Id.B: 1}

func _ready() -> void:
	GameState.local_team = Team.Id.A
	_apply_hero_defs()
	_update_side_label()
	_update_hero_labels()
	start_button.pressed.connect(_on_start_pressed)
	side_button.pressed.connect(_on_side_pressed)
	hero_a_button.pressed.connect(_on_hero_pressed.bind(Team.Id.A))
	hero_b_button.pressed.connect(_on_hero_pressed.bind(Team.Id.B))

func _apply_hero_defs() -> void:
	GameState.hero_defs[Team.Id.A] = HERO_TYPES[_hero_idx[Team.Id.A]]
	GameState.hero_defs[Team.Id.B] = HERO_TYPES[_hero_idx[Team.Id.B]]

func _update_side_label() -> void:
	side_button.text = "Control: %s" % Team.display_name(GameState.local_team)

func _update_hero_labels() -> void:
	hero_a_button.text = "Player A: %s" % HERO_TYPES[_hero_idx[Team.Id.A]].display_name
	hero_b_button.text = "Player B: %s" % HERO_TYPES[_hero_idx[Team.Id.B]].display_name

func _on_side_pressed() -> void:
	GameState.local_team = Team.Id.B if GameState.local_team == Team.Id.A else Team.Id.A
	_update_side_label()

func _on_hero_pressed(team: Team.Id) -> void:
	_hero_idx[team] = (_hero_idx[team] + 1) % HERO_TYPES.size()
	_apply_hero_defs()
	_update_hero_labels()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
