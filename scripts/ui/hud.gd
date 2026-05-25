class_name GameHUD
extends CanvasLayer
## Per-active-hero HUD: twin virtual sticks (left=move, right=aim), action
## buttons, health + currency readouts, the build menu, and the match-result
## overlay. Feeds stick values into the active hero each frame.

const LOBBY_SCENE := "res://scenes/ui/lobby.tscn"
const TOWER_INSPECT_RANGE := 7.0       ## how close the hero must be to inspect a tower
const TOWER_LABEL_SIDE_OFFSET := 2.5   ## metres to the (camera) right of the tower
const TOWER_LABEL_HEIGHT := 3.4        ## metres above the tower base

const VIGNETTE_SHADER := "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 1.0);\nuniform float strength = 0.0;\nvoid fragment() {\n\tvec2 d = UV - vec2(0.5);\n\tfloat r = length(d) * 1.4;\n\tCOLOR = vec4(tint.rgb, smoothstep(0.3, 0.85, r) * strength);\n}\n"

var _hero: Hero
var _tower_label: Label3D  ## world-space inspect panel, floats beside the nearest tower
var _upgrade_tower: Tower   ## own-team tower the floating Upgrade button currently targets
var _vignette: ColorRect
var _core_warn: float = 0.0  ## decaying intensity of the "core under attack" flash
var _status_box: HBoxContainer
var _status_chips: Array[ColorRect] = []
const MAX_STATUS_CHIPS := 12

@onready var move_stick: VirtualJoystick = $MoveStick
@onready var aim_stick: VirtualJoystick = $AimStick
@onready var fire_button: Button = $Actions/FireButton
@onready var tower_button: Button = $Actions/TowerButton
@onready var buff_button: Button = $Actions/BuffButton
@onready var swap_button: Button = $Actions/SwapButton
@onready var upgrade_button: Button = $UpgradeButton
@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var level_label: Label = $LevelLabel
@onready var currency_label: Label = $TopBar/CurrencyLabel
@onready var team_label: Label = $TopBar/TeamLabel
@onready var build_menu: BuildMenu = $BuildMenu
@onready var respawn_panel: Panel = $RespawnPanel
@onready var respawn_countdown: Label = $RespawnPanel/VBox/CountdownLabel
@onready var result_panel: Panel = $ResultPanel
@onready var result_label: Label = $ResultPanel/VBox/ResultLabel
@onready var back_button: Button = $ResultPanel/VBox/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	result_panel.visible = false
	fire_button.text = "FIRE"
	back_button.pressed.connect(_on_back_pressed)
	# Projectile shoots on button press (click). Tower button is a toggle: tap to
	# arm/aim (thumb free to aim), tap again to throw.
	fire_button.button_down.connect(_on_fire_pressed)
	tower_button.toggled.connect(_on_tower_toggled)
	buff_button.pressed.connect(_on_buff_pressed)
	swap_button.pressed.connect(func(): EventBus.swap_control_requested.emit())
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	upgrade_button.visible = false
	# Free-floating Control (no container parent) won't auto-size to its minimum,
	# so give it an explicit size or it renders/clicks as a zero-size rect.
	upgrade_button.size = upgrade_button.custom_minimum_size
	upgrade_button.add_theme_font_size_override("font_size", 18)
	aim_stick.set_sensitivity(GameState.aim_sensitivity)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.core_damaged.connect(_on_core_damaged)
	_build_vignette()
	_build_status_chips()

func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_vignette.material = mat
	add_child(_vignette)
	move_child(_vignette, 0)  # behind the interactive UI

## A pooled row of colored chips, one per active buff/debuff on the active hero.
func _build_status_chips() -> void:
	_status_box = HBoxContainer.new()
	_status_box.position = Vector2(20, 72)
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_theme_constant_override("separation", 4)
	add_child(_status_box)
	for i in MAX_STATUS_CHIPS:
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(42, 20)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.visible = false
		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.BLACK)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(label)
		_status_box.add_child(chip)
		_status_chips.append(chip)

func _update_status_chips() -> void:
	var fx := _hero.get_active_effects()
	for i in _status_chips.size():
		var chip := _status_chips[i]
		if i < fx.size():
			chip.color = fx[i]["color"]
			(chip.get_child(0) as Label).text = fx[i]["name"]
			chip.visible = true
		else:
			chip.visible = false

func _on_buff_pressed() -> void:
	if _hero and is_instance_valid(_hero):
		_hero.activate_buff()

func _on_upgrade_pressed() -> void:
	if _upgrade_tower and is_instance_valid(_upgrade_tower):
		_upgrade_tower.try_upgrade()

func _on_core_damaged(team: int) -> void:
	if _hero and int(_hero.team) == team:
		_core_warn = 0.7

func _on_fire_pressed() -> void:
	if _hero and is_instance_valid(_hero):
		_hero.fire()

func _on_tower_toggled(pressed: bool) -> void:
	if not (_hero and is_instance_valid(_hero)):
		return
	if pressed:
		_hero.set_tower_throw_armed(true)
	else:
		_hero.release_tower_throw()

func set_active_hero(hero: Hero) -> void:
	_hero = hero
	build_menu.set_active_hero(hero)
	if hero:
		team_label.text = Team.display_name(hero.team)
		currency_label.text = "Gold: %d" % GameState.get_currency(hero.team)

func _process(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_hero.set_move_input(move_stick.get_value())
	_hero.set_aim_input(aim_stick.get_value())
	health_bar.value = _hero.health.fraction() * 100.0
	xp_bar.value = _hero.get_xp_fraction() * 100.0
	level_label.text = "Lv %d" % _hero.get_level()
	fire_button.modulate.a = lerpf(0.4, 1.0, _hero.get_fire_ready())
	buff_button.modulate.a = lerpf(0.4, 1.0, _hero.get_buff_ready())
	# Keep the toggle visual in sync (the hero auto-disarms after throwing).
	if tower_button.button_pressed != _hero.is_tower_throw_armed():
		tower_button.set_pressed_no_signal(_hero.is_tower_throw_armed())
	_update_respawn_overlay()
	_update_tower_info()
	_update_vignette(delta)
	_update_status_chips()

## Red low-HP edges, overridden by an orange flash while your core is attacked.
func _update_vignette(delta: float) -> void:
	_core_warn = maxf(_core_warn - delta * 0.8, 0.0)
	var mat := _vignette.material as ShaderMaterial
	var hp := _hero.health.fraction()
	var low := 0.0
	if hp < 0.3 and not _hero.health.is_dead():
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 140.0)
		low = (0.3 - hp) / 0.3 * 0.6 * pulse
	if _core_warn > low:
		mat.set_shader_parameter("tint", Color(1.0, 0.55, 0.1, 1.0))
		mat.set_shader_parameter("strength", _core_warn)
	else:
		mat.set_shader_parameter("tint", Color(1.0, 0.1, 0.1, 1.0))
		mat.set_shader_parameter("strength", low)

## Show a respawn countdown while the active hero is dead.
func _update_respawn_overlay() -> void:
	if _hero.health.is_dead():
		respawn_countdown.text = "Respawning in %d..." % ceili(_hero.get_respawn_remaining())
		respawn_panel.visible = true
	else:
		respawn_panel.visible = false

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
		_hide_upgrade_button()
		return
	_ensure_tower_label()
	if _tower_label == null:
		return
	_tower_label.text = _tower_info_text(nearest)
	_tower_label.modulate = Team.body_color(nearest.team)
	_tower_label.global_position = _tower_label_position(nearest)
	_tower_label.visible = true
	_update_upgrade_button(nearest)

## Float a clickable Upgrade button above your own upgradable towers.
func _update_upgrade_button(tower: Tower) -> void:
	var cam := _hero.camera
	if cam == null or int(tower.team) != int(_hero.team) or not tower.can_upgrade():
		_hide_upgrade_button()
		return
	var cost := tower.get_upgrade_cost()
	var screen := cam.unproject_position(tower.global_position + Vector3.UP * 4.2)
	if cam.is_position_behind(tower.global_position + Vector3.UP * 4.2):
		_hide_upgrade_button()
		return
	_upgrade_tower = tower
	upgrade_button.text = "Upgrade (%d)" % cost
	upgrade_button.disabled = not GameState.can_afford(tower.team, cost)
	upgrade_button.position = screen - upgrade_button.size * 0.5
	upgrade_button.visible = true

func _hide_upgrade_button() -> void:
	_upgrade_tower = null
	upgrade_button.visible = false

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
		if def.upgrade != null:
			var up := def.upgrade
			lines.append("-- Upgrade: %d gold --" % def.upgrade_cost)
			lines.append("Damage: %.0f -> %.0f" % [def.damage, up.damage])
			lines.append("Range: %.0f -> %.0f" % [def.attack_range, up.attack_range])
			lines.append("Fire rate: %.2f -> %.2f/s" % [def.fire_rate_per_sec, up.fire_rate_per_sec])
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
