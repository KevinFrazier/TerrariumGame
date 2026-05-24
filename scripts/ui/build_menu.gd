class_name BuildMenu
extends VBoxContainer
## Tower build UI + placement. Select a tower, then tap/click the ground on your
## own half to place it (enforcing currency and the per-team tower cap).

const BASIC: TowerDefinition = preload("res://resources/towers/basic_tower.tres")

var active_hero: Hero
var _placing: bool = false

@onready var _build_button: Button = $BuildButton
@onready var _count_label: Label = $CountLabel
@onready var _hint_label: Label = $HintLabel

func _ready() -> void:
	_build_button.text = "%s (%d)" % [BASIC.display_name, BASIC.cost]
	_build_button.pressed.connect(_on_build_pressed)
	EventBus.tower_built.connect(func(_t, _n): _refresh())
	EventBus.currency_changed.connect(func(_t, _a): _refresh())
	_refresh()

func set_active_hero(hero: Hero) -> void:
	active_hero = hero
	_placing = false
	_refresh()

func _team() -> Team.Id:
	return active_hero.team if active_hero else Team.Id.A

func _refresh() -> void:
	var team := _team()
	_count_label.text = "Towers: %d/%d" % [GameState.get_tower_count(team), GameState.MAX_TOWERS_PER_TEAM]
	if not _placing:
		_hint_label.text = ""

func _set_hint(text: String) -> void:
	_hint_label.text = text

func _on_build_pressed() -> void:
	if active_hero == null:
		return
	var team := _team()
	if not GameState.can_build_tower(team):
		_set_hint("Tower limit reached")
		return
	if not GameState.can_afford(team, BASIC.cost):
		_set_hint("Need %d gold" % BASIC.cost)
		return
	_placing = not _placing
	_set_hint("Tap your side of the ground" if _placing else "")

func _unhandled_input(event: InputEvent) -> void:
	if not _placing or active_hero == null:
		return
	var screen_pos := Vector2.ZERO
	var do_place := false
	if event is InputEventScreenTouch and event.pressed:
		screen_pos = event.position
		do_place = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		screen_pos = event.position
		do_place = true
	if do_place:
		_try_place(screen_pos)
		get_viewport().set_input_as_handled()

func _try_place(screen_pos: Vector2) -> void:
	var cam := active_hero.camera
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to, Team.LAYER_GROUND)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_set_hint("Aim at the ground")
		return
	var point: Vector3 = hit.position
	var team := _team()
	var on_own_side := point.z < -2.0 if team == Team.Id.A else point.z > 2.0
	if not on_own_side:
		_set_hint("Build on your own side")
		return
	if not GameState.can_build_tower(team):
		_placing = false
		_set_hint("Tower limit reached")
		return
	if not GameState.spend_currency(team, BASIC.cost):
		_placing = false
		_set_hint("Not enough gold")
		return
	var tower := BASIC.scene.instantiate() as Tower
	tower.team = team
	tower.definition = BASIC
	active_hero.get_tree().current_scene.add_child(tower)
	tower.global_position = point
	GameState.register_tower(team)
	EventBus.tower_built.emit(int(team), tower)
	_placing = false
	_set_hint("")
