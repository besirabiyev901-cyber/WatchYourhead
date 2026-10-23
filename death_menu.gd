extends CanvasLayer

# =====================================================================
# DeathMenu - "ты врезался" экран между заездами.
# ---------------------------------------------------------------------
# ВАЖНО (фикс "тап не закрывает экран"): раньше @onready-ссылки на
# TitleLabel/StatsLabel/PromptLabel читались через $Path и если сцена
# .tscn хоть немного не совпадала со скриптом (например, обновили один
# файл без другого) - Godot кидал ошибку прямо посреди _ready(), не
# доходя до get_tree().paused = true И/ИЛИ не подключая пульс - а тап
# по экрану либо не снимал паузу, либо экран оставался висеть.
#
# Теперь: 1) критичная логика (pause + возможность закрыть тапом) не
# зависит НИ ОТ ОДНОГО опционального узла; 2) все ссылки на узлы находим
# через get_node_or_null и проверяем на null перед использованием -
# если кто-то поменяет .tscn и уберёт лейблы, экран всё равно откроется
# и закроется по тапу, просто без красивых цифр.
# =====================================================================

signal continue_game

@onready var rect: ColorRect = get_node_or_null("ColorRect")
@onready var title_label: Label = get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
@onready var stats_label: Label = get_node_or_null("CenterContainer/VBoxContainer/StatsLabel")
@onready var prompt_label: Label = get_node_or_null("CenterContainer/VBoxContainer/PromptLabel")
@onready var _audio: AudioStreamPlayer = get_node_or_null("AudioStreamPlayer")

## Плейсхолдеры звука - подставь ассеты в инспекторе, когда появятся.
@export var sfx_show: AudioStream    # звук появления экрана (удар/разбитое стекло)
@export var sfx_tap: AudioStream     # звук тапа "продолжить"

var _prompt_tween: Tween
var _closing := false  # чтобы двойной тап/клик не отправил continue_game дважды


func _ready() -> void:
	# --- КРИТИЧНО, идёт ПЕРВЫМ и ничего не может это сломать ---
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	get_tree().paused = true

	# --- Дальше только косметика, каждый шаг сам себя проверяет на null,
	# так что даже кривая/неполная сцена не помешает тапу закрыть экран ---
	if rect:
		rect.modulate.a = 0.0
		var t = create_tween()
		t.tween_property(rect, "modulate:a", 0.6, 0.25)

	var vbox: Control = get_node_or_null("CenterContainer/VBoxContainer")
	if vbox:
		vbox.scale = Vector2(0.85, 0.85)
		vbox.modulate.a = 0.0
		var t2 := create_tween()
		t2.set_parallel(true)
		t2.tween_property(vbox, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_property(vbox, "modulate:a", 1.0, 0.2)

	_start_prompt_pulse()
	_play(sfx_show)


## Вызывается из barrier_manager.gd::player_hit_barrier() сразу после
## add_child(). Если узлов для статистики нет в сцене - просто выходим,
## ничего не ломаем.
func setup(data: Dictionary) -> void:
	if stats_label == null:
		return
	var run_time: float = data.get("run_time", 0.0)
	var wave_count: int = data.get("wave_count", 0)
	var difficulty_level: int = data.get("difficulty_level", 0)
	stats_label.text = "Продержался: %.1f сек   |   Волна: %d   |   Сложность: %d" % [run_time, wave_count, difficulty_level]


func _start_prompt_pulse() -> void:
	if prompt_label == null:
		return
	if _prompt_tween:
		_prompt_tween.kill()
	prompt_label.modulate.a = 1.0
	_prompt_tween = create_tween().set_loops()
	_prompt_tween.tween_property(prompt_label, "modulate:a", 0.25, 0.6).set_trans(Tween.TRANS_SINE)
	_prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _input(event):
	if _closing:
		return
	if event is InputEventScreenTouch and event.pressed:
		_resume()

	if event is InputEventMouseButton and event.pressed:
		_resume()


func _resume():
	if _closing:
		return
	_closing = true
	if _prompt_tween:
		_prompt_tween.kill()
	_play(sfx_tap)
	get_tree().paused = false
	continue_game.emit()
	queue_free()


func _play(stream: AudioStream) -> void:
	if stream == null or _audio == null:
		return
	_audio.stream = stream
	_audio.play()
