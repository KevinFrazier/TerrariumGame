extends Node2D

@onready var title_label: Label = $UI/TitleLabel
@onready var info_label: Label = $UI/InfoLabel

func _ready() -> void:
	title_label.text = "Terrarium Game"
	info_label.text = "Press ESC to quit"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
