class_name GameHUD
extends CanvasLayer
## Per-active-hero HUD: twin virtual sticks (left=move, right=aim), action
## buttons, health + currency readouts, the build menu, and the match-result
## overlay. Feeds stick values into the active hero each frame.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"

var _hero: Hero

@onready var move_stick: VirtualJoystick = $MoveStick
@onready var aim_stick: VirtualJoystick = $AimStick
@onready var fire_button: Button = $Actions/FireButton
@onready var melee_button: Button = $Actions/MeleeButton
@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var currency_label: Label = $TopBar/CurrencyLabel
@onready var team_label: Label = $TopBar/TeamLabel
@onready var build_menu: BuildMenu = $BuildMenu
@onready var result_panel: Panel = $ResultPanel
@onready var result_label: Label = $ResultPanel/VBox/ResultLabel
@onready var back_button: Button = $ResultPanel/VBox/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	result_panel.visible = false
	fire_button.text = "FIRE"
	melee_button.text = "MELEE"
	back_button.pressed.connect(_on_back_pressed)
	EventBus.currency_changed.connect(_on_currency_changed)

func set_active_hero(hero: Hero) -> void:
	_hero = hero
	build_menu.set_active_hero(hero)
	if hero:
		team_label.text = Team.display_name(hero.team)
		currency_label.text = "Gold: %d" % GameState.get_currency(hero.team)

func _process(_delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_hero.set_move_input(move_stick.get_value())
	_hero.set_aim_input(aim_stick.get_value())
	health_bar.value = _hero.health.fraction() * 100.0
	fire_button.modulate.a = lerpf(0.4, 1.0, _hero.get_fire_ready())
	melee_button.modulate.a = lerpf(0.4, 1.0, _hero.get_melee_ready())
	if fire_button.button_pressed:
		_hero.fire()
	if melee_button.button_pressed:
		_hero.melee()

func _on_currency_changed(team: int, amount: int) -> void:
	if _hero and int(_hero.team) == team:
		currency_label.text = "Gold: %d" % amount

func show_match_result(winner: Team.Id) -> void:
	result_label.text = "%s wins!" % Team.display_name(winner)
	result_panel.visible = true
	get_tree().paused = true

func _on_back_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(LOBBY_SCENE)
