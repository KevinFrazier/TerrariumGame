class_name BuildMenu
extends VBoxContainer
## Tower build UI + placement. One button per tower type — select a type (which
## also arms the hero's throw with it), then tap/click the ground on your own
## half to place it (enforcing currency and the per-team tower cap).

const TOWER_TYPES: Array[TowerDefinition] = [
	preload("res://resources/towers/basic_tower.tres"),
	preload("res://resources/towers/sniper_tower.tres"),
	preload("res://resources/towers/cannon_tower.tres"),
	preload("res://resources/towers/mortar_tower.tres"),
]

var active_hero: Hero
var _placing: bool = false
var _selected: int = 0
var _buttons: Array[Button] = []

@onready var _count_label: Label = $CountLabel
@onready var _hint_label: Label = $HintLabel

func _ready() -> void:
	_build_type_buttons()
	GameState.selected_tower = TOWER_TYPES[_selected]
	EventBus.tower_built.connect(func(_t, _n): _refresh())
	EventBus.currency_changed.connect(func(_t, _a): _refresh())
	_refresh()

func _build_type_buttons() -> void:
	for i in TOWER_TYPES.size():
		var def := TOWER_TYPES[i]
		var button := Button.new()
		button.text = "%s (%d)" % [def.display_name, def.cost]
		button.pressed.connect(_on_type_pressed.bind(i))
		add_child(button)
		# Keep the type buttons above the count/hint labels (defined in the scene).
		move_child(button, i)
		_buttons.append(button)

func set_active_hero(hero: Hero) -> void:
	active_hero = hero
	_placing = false
	_refresh()

func _team() -> Team.Id:
	return active_hero.team if active_hero else Team.Id.A

func _current_def() -> TowerDefinition:
	return TOWER_TYPES[_selected]

func _refresh() -> void:
	var team := _team()
	_count_label.text = "Towers: %d/%d" % [GameState.get_tower_count(team), GameState.MAX_TOWERS_PER_TEAM]
	_update_buttons()
	if not _placing:
		_hint_label.text = ""

func _update_buttons() -> void:
	var team := _team()
	for i in _buttons.size():
		var button := _buttons[i]
		var affordable := GameState.can_afford(team, TOWER_TYPES[i].cost)
		# Brighten the selected type; dim types you can't currently afford.
		var alpha := 1.0 if (i == _selected or affordable) else 0.5
		button.modulate.a = alpha
		button.modulate.v = 1.0 if i == _selected else 0.8

func _set_hint(text: String) -> void:
	_hint_label.text = text

func _on_type_pressed(index: int) -> void:
	if active_hero == null:
		return
	_selected = index
	GameState.selected_tower = TOWER_TYPES[index]
	var team := _team()
	var def := TOWER_TYPES[index]
	if not GameState.can_build_tower(team):
		_placing = false
		_set_hint("Tower limit reached")
	elif not GameState.can_afford(team, def.cost):
		_placing = false
		_set_hint("Need %d gold" % def.cost)
	else:
		_placing = true
		_set_hint("Tap your side to place %s" % def.display_name)
	_update_buttons()

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
	var def := _current_def()
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
	if not GameState.spend_currency(team, def.cost):
		_placing = false
		_set_hint("Not enough gold")
		return
	var tower := def.scene.instantiate() as Tower
	tower.team = team
	tower.definition = def
	active_hero.get_tree().current_scene.add_child(tower)
	tower.global_position = point
	GameState.register_tower(team)
	EventBus.tower_built.emit(int(team), tower)
	_placing = false
	_set_hint("")
