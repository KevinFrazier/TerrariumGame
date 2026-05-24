extends Control
## Local lobby placeholder. For the prototype both heroes exist in one match on
## one machine; "Start Match" loads the arena. Structured so Host/Join networking
## can replace the single button later.

const ARENA_SCENE := "res://scenes/main/arena.tscn"

@onready var start_button: Button = $Center/VBox/StartButton
@onready var side_button: Button = $Center/VBox/SideButton

func _ready() -> void:
	GameState.local_team = Team.Id.A
	_update_side_label()
	start_button.pressed.connect(_on_start_pressed)
	side_button.pressed.connect(_on_side_pressed)

func _update_side_label() -> void:
	side_button.text = "Control: %s" % Team.display_name(GameState.local_team)

func _on_side_pressed() -> void:
	GameState.local_team = Team.Id.B if GameState.local_team == Team.Id.A else Team.Id.A
	_update_side_label()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)
