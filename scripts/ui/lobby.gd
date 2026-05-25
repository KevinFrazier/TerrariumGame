extends Control
## Local lobby placeholder. Both heroes exist in one match on one machine;
## "Start Match" loads the arena. Each side picks a hero class (Warrior/Mage/
## Archer) from an explicit button row; the arena applies it on spawn. Structured
## so Host/Join networking can replace the single button later.

const ARENA_SCENE := "res://scenes/main/arena.tscn"
const HERO_TYPES: Array[HeroDefinition] = [
	preload("res://resources/heroes/warrior.tres"),
	preload("res://resources/heroes/mage.tres"),
	preload("res://resources/heroes/archer.tres"),
]

@onready var start_button: Button = $Center/VBox/StartButton
@onready var side_button: Button = $Center/VBox/SideButton

var _hero_idx := {Team.Id.A: 0, Team.Id.B: 1}
var _class_buttons := {Team.Id.A: [], Team.Id.B: []}

func _ready() -> void:
	GameState.local_team = Team.Id.A
	_build_hero_select()
	_apply_hero_defs()
	_update_side_label()
	_refresh_class_buttons()
	start_button.pressed.connect(_on_start_pressed)
	side_button.pressed.connect(_on_side_pressed)

## One labeled row of Warrior/Mage/Archer buttons per side, inserted under the
## control toggle. Built in code to avoid hand-authoring every button node.
func _build_hero_select() -> void:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	for team in [Team.Id.A, Team.Id.B]:
		var label := Label.new()
		label.text = "%s hero:" % Team.display_name(team)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in HERO_TYPES.size():
			var button := Button.new()
			button.text = HERO_TYPES[i].display_name
			button.toggle_mode = true
			button.pressed.connect(_on_class_pressed.bind(team, i))
			row.add_child(button)
			_class_buttons[team].append(button)
		container.add_child(row)
	var vbox := $Center/VBox
	vbox.add_child(container)
	vbox.move_child(container, 2)  # after Title and SideButton, above Start

func _on_class_pressed(team: Team.Id, index: int) -> void:
	_hero_idx[team] = index
	_apply_hero_defs()
	_refresh_class_buttons()

func _refresh_class_buttons() -> void:
	for team in [Team.Id.A, Team.Id.B]:
		var buttons: Array = _class_buttons[team]
		for i in buttons.size():
			var button := buttons[i] as Button
			var selected: bool = i == int(_hero_idx[team])
			button.set_pressed_no_signal(selected)
			button.modulate.a = 1.0 if selected else 0.65

func _apply_hero_defs() -> void:
	GameState.hero_defs[Team.Id.A] = HERO_TYPES[_hero_idx[Team.Id.A]]
	GameState.hero_defs[Team.Id.B] = HERO_TYPES[_hero_idx[Team.Id.B]]

func _update_side_label() -> void:
	side_button.text = "Control: %s" % Team.display_name(GameState.local_team)

func _on_side_pressed() -> void:
	GameState.local_team = Team.Id.B if GameState.local_team == Team.Id.A else Team.Id.A
	_update_side_label()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
