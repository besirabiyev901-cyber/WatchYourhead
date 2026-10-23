extends CharacterBody3D

@export var lane := 0
var moving := false
var select_tween: Tween
var idle_tween: Tween
@export var car_type: String = "B"
@onready var selection: Node = $"../../SelectionManager"
@onready var road: Node3D = $"../../RoadManager"

var base_scale: Vector3
var base_y: float = 0.5

## ------------------- ЗВУК (плейсхолдеры) -------------------
@export var sfx_lane_change: AudioStream
@export var sfx_crash: AudioStream
@onready var _sfx: AudioStreamPlayer3D = _make_sfx_player()

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
	# ВАЖНО: см. комментарий в car.gd - позиция ставится ПОСЛЕ add_child(),
	# поэтому base_y захватываем отложенно (call_deferred), а не здесь.
	call_deferred("_init_idle_bob")
	# FIX #2: раньше искали Area3D только среди прямых детей.
	# Если она лежит глубже (внутри модели), её не находили —
	# ни сигнал клика не подключался, ни группа "car_hitbox" не
	# ставилась, из-за чего input_manager не видел машину. Теперь
	# ищем рекурсивно по всему поддереву.
	for area in _find_all_area3d(self):
		area.add_to_group("car_hitbox")
		if not area.input_event.is_connected(_on_area_3d_input_event):
			area.input_event.connect(_on_area_3d_input_event)


func _find_all_area3d(node: Node) -> Array[Area3D]:
	var found: Array[Area3D] = []
	if node is Area3D:
		found.append(node as Area3D)
	for child in node.get_children():
		found.append_array(_find_all_area3d(child))
	return found


# ---- Selection ----
func set_selected(state: bool) -> void:
	print("[car.gd] %s set_selected(%s)" % [name, state])
	if select_tween:
		select_tween.kill()
	if state:
		select_tween = create_tween().set_loops()
		select_tween.tween_property(self, "scale", base_scale * 1.1, 0.4).set_trans(Tween.TRANS_SINE)
		select_tween.tween_property(self, "scale", base_scale,0.4).set_trans(Tween.TRANS_SINE)
	else:
		select_tween = create_tween()
		select_tween.tween_property(self, "scale", base_scale, 0.15)


# ---- Movement ----
func move_to_lane(new_lane: int, pos: Vector3) -> void:
	print("[car.gd] %s move_to_lane(%d)" % [name, new_lane])
	if moving or new_lane == lane:
		return
	moving = true
	_stop_idle_bob()
	_play_sfx(sfx_lane_change)
	if select_tween:
		select_tween.kill()
	# FIX: было `scale = Vector3.ONE` - жёстко сбрасывало машину к масштабу
	# 1.0 при КАЖДОЙ смене полосы, даже если её реальный масштаб 1.35
	# (medium). Теперь используем base_scale, как в car.gd/car3.gd.
	scale = base_scale
	# Keep the current Y - we only want a flat swipe sideways, no bouncing.
	pos.y = global_position.y
	base_y = pos.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", pos, 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Small tilt in the direction of the swipe, purely cosmetic.
	tween.tween_property(self, "rotation_degrees:z", 10, 0.15)
	await tween.finished
	var tween2 := create_tween()
	tween2.tween_property(self, "rotation_degrees:z", 0, 0.15)
	await tween2.finished
	lane = new_lane
	moving = false
	_start_idle_bob()
	print("[car.gd] %s arrived at lane %d" % [name, lane])


# ---- Death ----
var death_tween: Tween

func die() -> void:
	print("[car.gd] %s die()" % name)
	moving = true  # блокируем move_to_lane() во время анимации смерти
	_stop_idle_bob()
	_play_sfx(sfx_crash)

	if select_tween:
		select_tween.kill()
	if death_tween:
		death_tween.kill()

	# FIX: было жёстко `Vector3.ONE * 1.35` - совпадало с текущим
	# player_medium_car_scale только случайно и переставало работать, если
	# кто-то поменяет масштаб в инспекторе. Теперь считаем от base_scale,
	# как в car.gd/car3.gd - "импакт" +35% сверху РЕАЛЬНОГО масштаба машины.
	var peak_scale := base_scale * 1.35

	# --- Scale идёт одной последовательной цепочкой (импакт -> лёгкая осадка) ---
	death_tween = create_tween()
	death_tween.tween_property(self, "scale", peak_scale, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	death_tween.tween_property(self, "scale", peak_scale * 0.85, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# --- Остальные эффекты идут отдельным параллельным tween ---
	var fx_tween := create_tween()
	fx_tween.set_parallel(true)

	fx_tween.tween_property(self, "rotation_degrees:x", rotation_degrees.x + 480, 0.9)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	fx_tween.tween_property(self, "rotation_degrees:z", rotation_degrees.z + 25, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	fx_tween.tween_property(self, "position:y", position.y - 1.8, 0.9)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if "modulate" in self:
		fx_tween.tween_property(self, "modulate:a", 0.0, 0.9)\
			.set_trans(Tween.TRANS_LINEAR)

	print("[car.gd] %s death anim started" % name)




func _on_area_3d_input_event(camera, event, pos, normal, shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("[car.gd] %s CLICKED, moving=%s" % [name, moving])
		if moving:
			return
		selection.select(self)
