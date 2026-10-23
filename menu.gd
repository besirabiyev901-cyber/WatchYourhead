extends Node

var sound = preload("res://sounds/click_003.ogg")
@onready var music_maker = $"../msucimaker"

@export var music_bus_name := "Music"
@export var press_scale := 0.85       # насколько "сжимается" кнопка при нажатии
@export var press_anim_duration := 0.12

var press_texture = preload("res://Large (2×)/icon_music_disabled.png")
var non_poress_textur = preload("res://Large (2×)/icon_music.png")

## Подстрой пути под свои реальные имена нод в редакторе, если они
## называются иначе, чем "music"/"play"/"exit".
@onready var music: Button = $music
@onready var play_button: Button = $play
@onready var exit_button: Button = $exit
@onready var cred = $credits

var _muted := false

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "music_muted"


func _ready() -> void:
	# pivot_offset нужен каждой кнопке ОТДЕЛЬНО (у каждой свой Control),
	# чтобы scale-анимация шла от её собственного центра, а не от угла.
	for b in [music, play_button, exit_button]:
		if is_instance_valid(b):
			b.pivot_offset = b.size / 2.0

	_muted = _load_muted_setting()
	var bus_idx := AudioServer.get_bus_index(music_bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, _muted)
	else:
		push_warning("[menu_controller.gd] audio bus '%s' not found - create it in Audio Bus Layout" % music_bus_name)

	_update_visual_state()


## Небольшой "punch" - переданная кнопка чуть сжимается и пружинисто
## возвращается к исходному размеру. Чисто визуальная обратная связь.
func _play_press_anim(button: Control) -> void:
	if not is_instance_valid(button):
		return
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * press_scale, press_anim_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, press_anim_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Мьютит/размьючивает ТОЛЬКО шину music_bus_name, затем сохраняет
## новое состояние на диск, чтобы оно не сбрасывалось при перезапуске.
func _toggle_music() -> void:
	var bus_idx := AudioServer.get_bus_index(music_bus_name)
	if bus_idx == -1:
		push_warning("[menu_controller.gd] audio bus '%s' not found - create it in Audio Bus Layout (Audio panel at the bottom of the editor), separate from your SFX bus" % music_bus_name)
		return

	_muted = not _muted
	AudioServer.set_bus_mute(bus_idx, _muted)
	_update_visual_state()
	_save_muted_setting(_muted)
	print("[menu_controller.gd] music %s" % ("MUTED" if _muted else "UNMUTED"))


func _update_visual_state() -> void:
	music.icon = press_texture if _muted else non_poress_textur


func _on_music_pressed() -> void:
	music_maker.stream = sound
	music_maker.play()
	await get_tree().create_timer(0.1).timeout
	_play_press_anim(music)
	_toggle_music()


func _on_play_pressed() -> void:
	_play_press_anim(play_button)
	SceneManager.change_scene("res://scenes/main_scene.tscn")


func _on_exit_pressed() -> void:
	_play_press_anim(exit_button)
	get_tree().quit()


## ------------------- СОХРАНЕНИЕ НАСТРОЙКИ -------------------
func _save_muted_setting(muted: bool) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, muted)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("[menu_controller.gd] failed to save settings.cfg, error code %d" % err)


func _load_muted_setting() -> bool:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		return false
	return config.get_value(SETTINGS_SECTION, SETTINGS_KEY, false)


func _on_credits_pressed() -> void:
	_play_press_anim(cred)
	music_maker.stream = sound
	music_maker.play()
	await get_tree().create_timer(0.1).timeout
	SceneManager.change_scene("res://scenes/credits.tscn")
