class_name GameHUD
extends CanvasLayer
## Per-active-hero HUD: twin virtual sticks (left=move, right=aim), action
## buttons, health + currency readouts, the build menu, and the match-result
## overlay. Feeds stick values into the active hero each frame.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const TOWER_INSPECT_RANGE := 7.0  ## how close the hero must be to inspect a tower

var _hero: Hero

@onready var move_stick: VirtualJoystick = $MoveStick
@onready var aim_stick: VirtualJoystick = $AimStick
@onready var fire_button: Button = $Actions/FireButton
@onready var melee_button: Button = $Actions/MeleeButton
@onready var tower_button: Button = $Actions/TowerButton
@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var currency_label: Label = $TopBar/CurrencyLabel
@onready var team_label: Label = $TopBar/TeamLabel
@onready var build_menu: BuildMenu = $BuildMenu
@onready var tower_info: PanelContainer = $TowerInfo
@onready var tower_info_name: Label = $TowerInfo/Margin/VBox/NameLabel
@onready var tower_info_details: Label = $TowerInfo/Margin/VBox/DetailsLabel
@onready var result_panel: Panel = $ResultPanel
@onready var result_label: Label = $ResultPanel/VBox/ResultLabel
@onready var back_button: Button = $ResultPanel/VBox/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	result_panel.visible = false
	fire_button.text = "FIRE"
	melee_button.text = "MELEE"
	back_button.pressed.connect(_on_back_pressed)
	tower_button.toggled.connect(_on_tower_toggled)
	EventBus.currency_changed.connect(_on_currency_changed)

func _on_tower_toggled(pressed: bool) -> void:
	if _hero and is_instance_valid(_hero):
		_hero.set_tower_throw_armed(pressed)

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
	# Keep the toggle in sync (the hero disarms itself after a throw).
	if tower_button.button_pressed != _hero.is_tower_throw_armed():
		tower_button.set_pressed_no_signal(_hero.is_tower_throw_armed())
	_update_tower_info()

## Show stats for the nearest tower the hero is standing close to (any team).
func _update_tower_info() -> void:
	var nearest: Tower = null
	var best := TOWER_INSPECT_RANGE
	for t in get_tree().get_nodes_in_group("towers"):
		var tower := t as Tower
		if tower == null or not is_instance_valid(tower):
			continue
		var d := _hero.global_position.distance_to(tower.global_position)
		if d <= best:
			best = d
			nearest = tower
	if nearest == null:
		tower_info.visible = false
		return
	_populate_tower_info(nearest)
	tower_info.visible = true

func _populate_tower_info(tower: Tower) -> void:
	var def := tower.definition
	tower_info_name.text = def.display_name if def else "Tower"
	tower_info_name.modulate = Team.body_color(tower.team)
	var lines: Array[String] = []
	lines.append("Owner: %s" % Team.display_name(tower.team))
	lines.append("HP: %d / %d" % [roundi(tower.health.current_hp), roundi(tower.health.max_hp)])
	if def:
		lines.append("Range: %.0f" % def.attack_range)
		lines.append("Damage: %.0f" % def.damage)
		lines.append("Fire rate: %.2f/s" % def.fire_rate_per_sec)
		if def.blast_radius > 0.0:
			lines.append("Blast radius: %.0f" % def.blast_radius)
		if def.slow_factor > 0.0:
			lines.append("Slow: %d%% for %.1fs" % [roundi((1.0 - def.slow_factor) * 100.0), def.slow_duration_sec])
	tower_info_details.text = "\n".join(lines)

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
