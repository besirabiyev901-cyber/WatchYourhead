extends CanvasLayer

@export var press_scale := 0.85       
@export var press_anim_duration := 0.12

var sound = preload("res://sounds/click_003.ogg")
@onready var music_maker = $"../AudioStreamPlayer"

@onready var but = $Button

func _play_press_anim(button: Control) -> void:
	if not is_instance_valid(button):
		return
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * press_scale, press_anim_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, press_anim_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_pressed() -> void:
	_play_press_anim(but)
	music_maker.stream = sound
	music_maker.play()
	await get_tree().create_timer(0.1).timeout
	SceneManager.change_scene("res://scenes/menu.tscn")
