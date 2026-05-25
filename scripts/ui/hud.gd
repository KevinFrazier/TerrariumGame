class_name GameHUD
extends CanvasLayer
## Per-active-hero HUD: twin virtual sticks (left=move, right=aim), action
## buttons, health + currency readouts, the build menu, and the match-result
## overlay. Feeds stick values into the active hero each frame.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const TOWER_INSPECT_RANGE := 7.0       ## how close the hero must be to inspect a tower
const TOWER_LABEL_SIDE_OFFSET := 2.5   ## metres to the (camera) right of the tower
const TOWER_LABEL_HEIGHT := 3.4        ## metres above the tower base

var _hero: Hero
var _tower_label: Label3D  ## world-space inspect panel, floats beside the nearest tower

@onready var move_stick: VirtualJoystick = $MoveStick
@onready var aim_stick: VirtualJoystick = $AimStick
@onready var fire_button: Button = $Actions/FireButton
@onready var tower_button: Button = $Actions/TowerButton
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
	back_button.pressed.connect(_on_back_pressed)
	# Projectile shoots on release; the tower throw arms on press, throws on release.
	fire_button.button_up.connect(_on_fire_released)
	tower_button.button_down.connect(_on_tower_pressed)
	tower_button.button_up.connect(_on_tower_released)
	aim_stick.set_sensitivity(GameState.aim_sensitivity)
	EventBus.currency_changed.connect(_on_currency_changed)

func _on_fire_released() -> void:
	if _hero and is_instance_valid(_hero):
		_hero.fire()

func _on_tower_pressed() -> void:
	if _hero and is_instance_valid(_hero):
		_hero.set_tower_throw_armed(true)

func _on_tower_released() -> void:
	if _hero and is_instance_valid(_hero):
		_hero.release_tower_throw()

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
	_update_tower_info()

## Float a world-space stats panel beside the nearest tower the hero stands by.
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
		if _tower_label and is_instance_valid(_tower_label):
			_tower_label.visible = false
		return
	_ensure_tower_label()
	if _tower_label == null:
		return
	_tower_label.text = _tower_info_text(nearest)
	_tower_label.modulate = Team.body_color(nearest.team)
	_tower_label.global_position = _tower_label_position(nearest)
	_tower_label.visible = true

## Position the panel to the camera's right of the tower, above its base.
func _tower_label_position(tower: Tower) -> Vector3:
	var right := Vector3.RIGHT
	var cam := _hero.camera
	if cam:
		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
	return tower.global_position + right * TOWER_LABEL_SIDE_OFFSET + Vector3.UP * TOWER_LABEL_HEIGHT

func _tower_info_text(tower: Tower) -> String:
	var def := tower.definition
	var lines: Array[String] = []
	lines.append(def.display_name if def else "Tower")
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
	return "\n".join(lines)

func _ensure_tower_label() -> void:
	if _tower_label and is_instance_valid(_tower_label):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_tower_label = Label3D.new()
	_tower_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tower_label.no_depth_test = true
	_tower_label.pixel_size = 0.006
	_tower_label.font_size = 40
	_tower_label.outline_size = 16
	_tower_label.outline_modulate = Color(0, 0, 0, 0.9)
	_tower_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tower_label.visible = false
	scene.add_child(_tower_label)

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
