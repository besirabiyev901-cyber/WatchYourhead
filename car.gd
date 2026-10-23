extends CharacterBody3D
class_name Car

# "A" = sedan (проходит любой gate), "B" = truck (только medium), "C" = мусоровоз (только big)
@export_enum("A", "B", "C") var car_type: String = "A"
@export var lane := 0

var moving := false
var select_tween: Tween
var death_tween: Tween
var idle_tween: Tween
var base_scale: Vector3
var base_y: float = 0.5

@onready var selection: Node = $"../../SelectionManager"
@onready var road: Node3D = $"../../RoadManager"

## ------------------- ЗВУК (плейсхолдеры) -------------------
## Подставь реальные ассеты в инспекторе, когда появятся - код уже готов
## их проигрывать. Пустое поле (null) просто ничего не делает.
@export var sfx_lane_change: AudioStream
@export var sfx_crash: AudioStream
@onready var _sfx: AudioStreamPlayer3D = _make_sfx_player()

## Лёгкое "покачивание" стоящей машины (мотор работает на холостых) -
## чисто визуальная приправа, отключается сама на время move_to_lane()/die().
@export var idle_bob_enabled := true
@export var idle_bob_amount := 0.03
@export var idle_bob_duration := 1.2

func _make_sfx_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "SFXPlayer"
	p.max_distance = 80.0
	p.volume_db = -6
	add_child(p)
	return p

func _play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx == null:
		return
	_sfx.stream = stream
	_sfx.play()

func _init_idle_bob() -> void:
	base_y = position.y
	_start_idle_bob()

## Вызывается ИЗВНЕ (barrier_manager.gd) когда spawn-flourish твин реально
## закончился - гарантированно правильный base_y, без гонки твинов.
func set_base_y_and_start_bob(y: float) -> void:
	base_y = y
	_start_idle_bob()

func _start_idle_bob() -> void:
	if not idle_bob_enabled:
		return
	if idle_tween:
		idle_tween.kill()
	idle_tween = create_tween().set_loops()
	idle_tween.tween_property(self, "position:y", base_y + idle_bob_amount, idle_bob_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(self, "position:y", base_y, idle_bob_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_idle_bob() -> void:
	if idle_tween:
		idle_tween.kill()
	position.y = base_y

func _ready() -> void:
	add_to_group("cars")
	base_scale = scale
	# ВАЖНО: НЕ читаем position.y здесь напрямую - barrier_manager.gd
	# ставит inst.global_position ПОСЛЕ add_child() (т.е. ПОСЛЕ этого
	# _ready()), так что на этот момент позиция ещё дефолтная/нулевая.
	# call_deferred откладывает захват base_y до конца текущего кадра,
	# когда реальная позиция уже проставлена - иначе покачивание тянуло
	# бы машину к неправильной (нулевой) высоте.
	call_deferred("_init_idle_bob")

	for area in _find_all_area3d(self):
		if not area.input_event.is_connected(_on_area_3d_2_input_event):
			area.input_event.connect(_on_area_3d_2_input_event)
		area.add_to_group("car_hitbox")

func _find_all_area3d(node: Node) -> Array[Area3D]:
	var found: Array[Area3D] = []
	if node is Area3D:
		found.append(node as Area3D)
	for child in node.get_children():
		found.append_array(_find_all_area3d(child))
	return found

func get_size_class() -> String:
	return car_type

func set_selected(state: bool) -> void:
	if select_tween:
		select_tween.kill()
	if state:
		select_tween = create_tween().set_loops()
		select_tween.tween_property(self, "scale", base_scale * 1.1, 0.4).set_trans(Tween.TRANS_SINE)
		select_tween.tween_property(self, "scale", base_scale, 0.4).set_trans(Tween.TRANS_SINE)
	else:
		select_tween = create_tween()
		select_tween.tween_property(self, "scale", base_scale, 0.15)

func move_to_lane(new_lane: int, pos: Vector3) -> void:
	if moving or new_lane == lane:
		return
	moving = true
	_stop_idle_bob()
	if select_tween:
		select_tween.kill()
	scale = base_scale
	_play_sfx(sfx_lane_change)

	pos.y = global_position.y
	base_y = pos.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", pos, 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees:z", 10, 0.15)
	await tween.finished

	var tween2 := create_tween()
	tween2.tween_property(self, "rotation_degrees:z", 0, 0.15)
	await tween2.finished

	lane = new_lane
	moving = false
	_start_idle_bob()

@export var death_scale_multiplier := 1.6

func die() -> void:
	moving = true
	_stop_idle_bob()
	_play_sfx(sfx_crash)
	if select_tween:
		select_tween.kill()
	if death_tween:
		death_tween.kill()

	var peak_scale := base_scale * death_scale_multiplier
	death_tween = create_tween()
	death_tween.tween_property(self, "scale", peak_scale, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	death_tween.tween_property(self, "scale", peak_scale * 0.85, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var fx_tween := create_tween()
	fx_tween.set_parallel(true)
	fx_tween.tween_property(self, "rotation_degrees:x", rotation_degrees.x + 480, 0.9)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fx_tween.tween_property(self, "rotation_degrees:z", rotation_degrees.z + 25, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fx_tween.tween_property(self, "position:y", position.y - 1.8, 0.9)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if "modulate" in self:
		fx_tween.tween_property(self, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_LINEAR)




func _on_area_3d_2_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if moving:
			return
		selection.select(self)
