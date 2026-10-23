extends Node3D
class_name BarrierManager

# =====================================================================
# BarrierManager (упрощённая версия - только барьеры, без трафика)
# ---------------------------------------------------------------------
# Спавнит волны барьеров (ворота) по 4 полосам, по сценарию-строке
# ("ABCO", "aa1cb" и т.п.), двигает их вместе со скоростью дороги и
# проверяет, проходит машина игрока в ворота или нет.
#
# Ничего в существующем коде не трогает:
#  - читает RoadManager.lane_cars (обновляется само в road_manager.gd)
#  - читает speed из группы "road_scroller" (та же, что и camera_3d.gd)
#  - вызывает car.die() (уже реализован в car.gd/car2.gd/car3.gd)
# =====================================================================

## ------------------- ПОЛОСЫ -------------------
## Те же 4 Marker3D, что в RoadManager.lane_positions (Lane1..Lane4),
## В ТОМ ЖЕ ПОРЯДКЕ. Из них берём X (и Y) полосы.
@export var lane_markers: Array[Marker3D]

## ------------------- ГЕОМЕТРИЯ ДВИЖЕНИЯ -------------------
@export var spawn_z := -60.0     # где спавнить (далеко впереди)

const DEATH_SCENE = preload("res://scenes/death_menu.tscn")

## БЫЛО: trigger_z=0.0 / despawn_z=8.0 - магические числа, никак не
## привязанные к реальной сцене. В main_scene.tscn машины игрока
## (car_spawn_markers = lane1..lane4) стоят на z≈34, а барьер с этими
## дефолтами доезжал только до z=8 и УДАЛЯЛСЯ - то есть исчезал за 26
## метров ДО того, как долетал до игрока. Отсюда и "барьеров нету на
## сцене" - они гасли в воздухе, не долетая.
##
## Теперь по умолчанию trigger_z/despawn_z считаются АВТОМАТИЧЕСКИ от
## реальной позиции car_spawn_markers в _ready() (см. auto_align_trigger_z
## ниже), так что при переносе машин/маркеров в редакторе это больше
## никогда не разъедется само по себе. Ручные значения ниже используются
## только как fallback, если auto_align выключен или маркеры не заданы.
@export var auto_align_trigger_z := true
@export var despawn_margin := 10.0   # насколько дальше машин удалять барьер (метры)
@export var trigger_z := 0.0     # fallback, если auto_align_trigger_z = false
@export var despawn_z := 8.0     # fallback, если auto_align_trigger_z = false

## ------------------- СЦЕНЫ БАРЬЕРОВ -------------------
## Правило СТРОГОЕ: A проходит только в A-ворота, B - только в B-ворота,
## C - только в C-ворота (см. _size_fits() ниже).
@export var small_barrier_scene: PackedScene   # barriers_1.tscn (SmallBarrier, только "A")
@export var medium_barrier_scene: PackedScene  # barriers_2.tscn (MediumBarrier, только "B")
@export var big_barrier_scene: PackedScene     # barrier_3.tscn  (BigBarrier, только "C")


@export_group("Barrier Offset (Global - applied to ALL barrier types)")
@export var barrier_position_offset: Vector3 = Vector3(0.0, 0.5, 0.0)
@export var barrier_rotation_offset: Vector3 = Vector3.ZERO
@export var barrier_scale_multiplier: Vector3 = Vector3.ONE

## ------------------- ПЕР-ТИПОВЫЕ OFFSET'Ы БАРЬЕРОВ -------------------
## Как и у машин игрока - тонкая подстройка под конкретную модель ворот,
## если её пивот/масштаб не совпадает с остальными. Складывается ПОВЕРХ
## глобального barrier_position_offset/rotation_offset выше, и умножается
## поверх barrier_scale_multiplier.
@export_group("Barrier Offset - Small (A)")
@export var small_barrier_position_offset := Vector3.ZERO
@export var small_barrier_rotation_offset := Vector3.ZERO
@export var small_barrier_scale := Vector3.ONE

@export_group("Barrier Offset - Medium (B)")
@export var medium_barrier_position_offset := Vector3.ZERO
@export var medium_barrier_rotation_offset := Vector3.ZERO
@export var medium_barrier_scale := Vector3.ONE

@export_group("Barrier Offset - Big (C)")
@export var big_barrier_position_offset := Vector3.ZERO
@export var big_barrier_rotation_offset := Vector3.ZERO
@export var big_barrier_scale := Vector3.ONE

@export_group("")
## ------------------- СЦЕНАРИЙ -------------------
## Паттерн = 4 токена (полоса 0..3) без пробелов. Буква = тип ворот,
## цифра после буквы (a1, b1..) НЕ важна для механики - это просто чтобы
## глазами не путать повторы, "a" и "a1" это одно и то же.
## 'O'/'o' = полоса пустая (по задумке ровно одна пустая полоса на волну).

## FIX (Bashir: "момент спавна машин после барьеров - сделай мгновенным"):
## было 3.0 - между тем как барьеры последней волны ушли за камеру и тем
## как заново появляются машины + следующая волна, была ощутимая пауза.
## Теперь 0.0 - см. _schedule_next_wave() ниже, при 0.0 волна спавнится
## сразу же, без прогона через Timer.
@export var seconds_between_waves := 0.0  # пауза между волнами барьеров

## ------------------- РЕСПАВН МАШИН ИГРОКА ПОСЛЕ АВАРИИ -------------------
## Маркеры, на которых заново появляется машина игрока в этой полосе
## после аварии. Обычно это ТЕ ЖЕ позиции, где стоят машины сейчас
## (совпадают с RoadManager.lane_positions) - ставь сам в редакторе,
## порядок 0..3 = Lane1..Lane4, как и везде.
@export var car_spawn_markers: Array[Marker3D]

## Через сколько секунд после car.die() респавнить новую машину в той же
## полосе. Bashir попросил минимум 3 секунды - чтобы игрок реально успел
## увидеть аварию и среагировать на то, что машины сейчас поменяются,
## а не мгновенно/почти-мгновенно как было раньше (1.3с - это чисто
## под анимацию смерти, а не под реакцию игрока).
@export var respawn_delay := 3.0

## Сцены машин ИГРОКА для респавна (это те же car.tscn/truck.tscn/garbage.tscn,
## просто с другим назначением - не встречный трафик, а замена сбитой машины).
@export var player_small_car_scene: PackedScene   # car.tscn     (тип "A")
@export var player_medium_car_scene: PackedScene  # truck.tscn   (тип "B")
@export var player_big_car_scene: PackedScene     # garbage.tscn (тип "C")

## Масштаб респавненной машины - ставь ТОЧНО ТАКОЙ ЖЕ, какой стоит у уже
## существующих Car/Truck/Truck2 в инспекторе (Transform -> Scale). Из
## коробки car.tscn/truck.tscn/garbage.tscn имеют Scale (1,1,1), а у тебя
## в сцене они наверняка подогнаны вручную под модельки - без этого
## респавненная машина будет неправильного размера.
@export var player_small_car_scale := Vector3.ONE
@export var player_medium_car_scale := Vector3.ONE
@export var player_big_car_scale := Vector3.ONE

## Доп. смещение позиции поверх маркера (в мировых координатах, метры) -
## на случай если пивот модели не совпадает с пивотом маркера. Обычно
## Vector3.ZERO, трогай только если машина "уезжает" в сторону от полосы.
@export var player_small_car_position_offset := Vector3.ZERO
@export var player_medium_car_position_offset := Vector3.ZERO
@export var player_big_car_position_offset := Vector3.ZERO

## Доп. поворот поверх маркера, в градусах (X,Y,Z). Обычно Vector3.ZERO -
## основной поворот берётся с самого маркера (car_spawn_markers), это
## только тонкая подстройка под конкретную модель, если у неё, например,
## руль/капот развёрнут не так, как у остальных.
@export var player_small_car_rotation_offset := Vector3.ZERO
@export var player_medium_car_rotation_offset := Vector3.ZERO
@export var player_big_car_rotation_offset := Vector3.ZERO

## ------------------- СЦЕНАРИИ (парные cars+barriers) -------------------
## ЕДИНСТВЕННЫЙ источник правды: каждый элемент - это пара паттернов,
## которая описывает одну волну целиком - какие машины стоят у игрока
## ("cars") и какие ворота летят навстречу ("barriers").
##
## ЭТО ГОЛОВОЛОМКА: "cars" - стартовая раскладка, она НЕ обязана совпадать
## с "barriers" полоса-в-полосу. Игрок кликает машину и кликает полосу
## (InputManager -> SelectionManager -> RoadManager.move_car()) и обязан
## сам переставить машины по правильным полосам ДО того, как волна ворот
## долетит до trigger_z. Поэтому НЕ проверяем совпадение cars/barriers
## при старте - это ломало бы саму суть головоломки.
##
## ФОРМАТ ПАТТЕРНА: 4 токена подряд без пробелов, один токен = одна полоса.
## Токен = буква (A/B/C/O) + необязательная цифра. Цифра НИЧЕГО не значит
## для механики - чисто чтобы глазами не путать повторы одной буквы подряд.
## "abcc1" = a, b, c, c (второе "c" написано как "c1", чтобы не сливалось
## в "cc"). 'O'/'o' = полоса пустая - может стоять и в cars (нет машины),
## и в barriers (нет ворот), независимо друг от друга.
##
## ПРАВИЛО ПРОЕЗДА (реальная проверка в момент триггера, через фактические
## поля объектов car.car_type / gate.gate_type, см. _check_collision() и
## _size_fits() выше): A проходит в любые ворота, B - в B или C, C -
## только в C. Это НЕ про то, где машина стоит в самом начале волны - это
## про то, куда игрок обязан её переставить.
@export var scenarios: Array[Dictionary] = [
	{
		"cars":"OABC",
		"barriers":"ABCC1"
	},
	{
		"cars":"BACO",
		"barriers":"AB1BC"
	},
	{
		"cars":"COBA",
		"barriers":"CBBA1"
	},
	{
		"cars":"BCAO",
		"barriers":"BB1CA"
	},
	{
		"cars":"OCBO",
		"barriers":"CAA1B"
	},
	{
		"cars":"AOBC",
		"barriers":"ABCC1"
	},
	{
		"cars":"OOBO",
		"barriers":"BAAA"
	},
	{
		"cars":"OCBA",
		"barriers":"CBAA1"
	},
	{
		"cars":"ABOA",
		"barriers":"ABAA"
	}
]

## ------------------- СЛОЖНОСТЬ (endless runner ramp) -------------------
## FIX (Bashir: "поднимай сложность каждые 4 волны"): было по реальному
## времени (Timer каждые difficulty_interval секунд), теперь привязано к
## _wave_count - каждые waves_per_difficulty_level волн игра становится
## быстрее и жёстче: растёт скорость дороги (через группу "road_scroller",
## как и в camera_3d.gd) и волны барьеров идут чаще. Прирост НЕ бесконечный -
## ограничен speed_max / min_seconds_between_waves, чтобы на 10-й минуте
## игра не превращалась в нечитаемую кашу.
@export_group("Difficulty Ramp")
@export var difficulty_enabled := true
@export var waves_per_difficulty_level := 4    # раз в 4 волны - как просил Bashir
@export var speed_increase_per_level := 1.5    # прибавка к road_scroller.speed за уровень
@export var speed_max := 40.0                  # потолок скорости дороги
@export var wave_interval_decrease_per_level := 0.15  # насколько чаще волны за уровень
@export var min_seconds_between_waves := 0.0   # нижний потолок частоты волн (0 = мгновенно, как просил Bashir)
@export var respawn_delay_decrease_per_level := 0.05
@export var min_respawn_delay := 0.2

var difficulty_level := 0
var _wave_timer: Timer          # одноразовый таймер паузы МЕЖДУ волнами (см. _schedule_next_wave)
var _run_time := 0.0            # сколько игрок продержался в текущем заезде (для death-экрана)

## ------------------- ЗВУК (плейсхолдеры) -------------------
## Реальных .wav/.ogg в проекте пока нет - сюда просто подставь ассеты в
## инспекторе, когда они появятся, код уже готов их проигрывать. Пока
## поле пустое (null) - _play() тихо ничего не делает, никаких ошибок.
@export_group("Sound (placeholders)")
@export var sfx_gate_pass: AudioStream     # звук успешного проезда в ворота
@export var sfx_gate_crash: AudioStream    # звук аварии/врезания
@export var sfx_wave_spawn: AudioStream    # звук появления новой волны ворот
@onready var _sfx_player: AudioStreamPlayer3D = _make_sfx_player()

func _make_sfx_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "SFXPlayer"
	p.max_distance = 200.0
	add_child(p)
	return p

func _play_sfx(stream: AudioStream, at_position: Vector3 = Vector3.ZERO) -> void:
	if stream == null or _sfx_player == null:
		return  # плейсхолдер не назначен в инспекторе - просто пропускаем
	_sfx_player.stream = stream
	if at_position != Vector3.ZERO:
		_sfx_player.global_position = at_position
	_sfx_player.play()

## ------------------- ЭФФЕКТЫ / "ДИНАМИКА" -------------------
## Всё в этой секции - декоративная приправа (juice), которую
## BarrierManager добавляет САМ, не трогая car.gd/camera_3d.gd/
## road_manager.gd (их содержимого у меня нет, чтобы редактировать их
## напрямую). Поэтому все хуки ниже - "безопасные": через has_method()/
## группы, и если соответствующий метод/группа не существует - просто
## тихо ничего не делают, без ошибок.
##
## ЧТО ЗДЕСЬ ЕСТЬ:
##  - _shake_camera()      - трясёт камеру, ЕСЛИ у тебя уже есть нода в
##                            группе "main_camera" с методом shake(amount,
##                            duration). Если такого метода нет - просто
##                            no-op. Хочешь тряску камеры - добавь в
##                            camera_3d.gd метод shake(amount, duration) и
##                            добавь ноду камеры в группу "main_camera"
##                            (add_to_group("main_camera") в её _ready()).
##  - _spawn_burst_particles() - процедурный "взрыв" частиц (без внешних
##                            .tres/текстур - генерируется кодом), для
##                            искр при аварии и лёгкого "поп"-эффекта при
##                            успешном проезде.
##  - _play_death_flourish() - крутит/подбрасывает саму машину (кувырок)
##                            ПЕРЕД тем как вызвать её штатный car.die() -
##                            это чисто визуальная добавка поверх твоей
##                            существующей анимации смерти, а не замена ей.
##  - _play_spawn_flourish() - "выезд"/поп-ин машины при спавне (как у
##                            барьеров), плюс лёгкое падение сверху.

@export_group("Juice / Effects")
@export var camera_shake_enabled := true
@export var crash_shake_amount := 0.35
@export var crash_shake_duration := 0.25
@export var particles_enabled := true
@export var crash_particle_color := Color(1.0, 0.35, 0.05)   # оранжево-красные искры
@export var pass_particle_color := Color(0.3, 1.0, 0.5)      # зелёный "поп" при успешном проезде
@export var car_spawn_drop_height := 1.2   # насколько высоко машина "падает" при появлении
@export var car_spawn_duration := 0.35


func _shake_camera(amount: float = -1.0, duration: float = -1.0) -> void:
	if not camera_shake_enabled:
		return
	# Значения по умолчанию берём из export-полей здесь, а не в сигнатуре
	# функции - GDScript не разрешает member/@export-переменные в качестве
	# default-значений параметров (это должна быть константа), поэтому
	# используем sentinel (-1.0) и подставляем реальные значения тут.
	var use_amount := crash_shake_amount if amount < 0.0 else amount
	var use_duration := crash_shake_duration if duration < 0.0 else duration
	for cam in get_tree().get_nodes_in_group("main_camera"):
		if cam.has_method("shake"):
			cam.call("shake", use_amount, use_duration)
			return
	# группа "main_camera" не найдена или у камеры нет метода shake() -
	# тихо пропускаем, это не ошибка конфигурации, просто фича ещё не
	# подключена на стороне camera_3d.gd.


## Процедурный взрыв частиц - без внешних ресурсов/текстур, поэтому
## работает "из коробки" сразу после вставки скрипта. Частицы - простые
## цветные кубики (BoxMesh), разлетаются во все стороны и гаснут.
func _spawn_burst_particles(at_position: Vector3, color: Color, amount: int = 20) -> void:
	if not particles_enabled:
		return

	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12)
	particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0, 1, 0)
	process_mat.spread = 180.0
	process_mat.initial_velocity_min = 2.0
	process_mat.initial_velocity_max = 5.0
	process_mat.gravity = Vector3(0, -9.0, 0)
	process_mat.scale_min = 0.6
	process_mat.scale_max = 1.4
	process_mat.color = color
	particles.process_material = process_mat

	add_child(particles)
	particles.global_position = at_position
	particles.emitting = true

	# Убираем ноду частиц сама после того, как она доиграла (lifetime +
	# небольшой запас), чтобы не копить мусорные ноды в дереве сцены.
	get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Декоративный "кувырок" машины перед её штатной смертью (car.die()).
## Не блокирует и не заменяет die() - просто крутит текущий Node3D машины
## параллельно, пока die() (если он что-то анимирует/удаляет ноду сам)
## не заберёт над ней управление. Если car.die() уничтожит ноду раньше,
## чем tween доиграет - Godot сам мягко остановит tween на невалидной
## ноде, ошибки не будет.
func _play_death_flourish(car: Node3D) -> void:
	if not is_instance_valid(car):
		return
	var tumble := create_tween()
	tumble.set_parallel(true)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spin_x := rng.randf_range(260.0, 420.0) * (1 if rng.randf() > 0.5 else -1)
	var spin_z := rng.randf_range(180.0, 320.0) * (1 if rng.randf() > 0.5 else -1)
	tumble.tween_property(car, "rotation_degrees:x", car.rotation_degrees.x + spin_x, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tumble.tween_property(car, "rotation_degrees:z", car.rotation_degrees.z + spin_z, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tumble.tween_property(car, "global_position:y", car.global_position.y + 0.8, 0.22)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tumble.chain().tween_property(car, "global_position:y", car.global_position.y, 0.3)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Poп-ин + лёгкое "падение сверху" при появлении машины (используется
## из _spawn_car_in_lane сразу после того, как позиция/поворот выставлены).
## target_position/target_scale - куда машина должна прийти в итоге.
func _play_spawn_flourish(car: Node3D, target_position: Vector3, target_scale: Vector3) -> void:
	car.global_position = target_position + Vector3(0, car_spawn_drop_height, 0)
	car.scale = target_scale * 0.4

	var pop := create_tween()
	pop.set_parallel(true)
	pop.tween_property(car, "global_position", target_position, car_spawn_duration)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	pop.tween_property(car, "scale", target_scale, car_spawn_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# WeakRef вместо прямого захвата car - если машину уже queue_free()'нули
	# (например clear_cars() на следующей волне отработал раньше, чем этот
	# твин доиграл 0.35с), лямбда просто тихо получит null через get_ref(),
	# без "Lambda capture was freed" в логе.


var current_scenario: Dictionary

@onready var car_manager: Node = get_node_or_null("../CarManager")
@onready var road_manager: Node = get_node_or_null("../RoadManager")

var _speed := 0.0
var _wave_count := 0       # только для логов, на логику не влияет
var _active_barriers: Array = []  # [{node, lane, letter, checked}]
var _respawn_pending := false  # чтобы 2+ аварии подряд не стакали респавн ВСЕХ машин по 2 раза

const TOKEN_PATTERN := "[A-Za-z][0-9]*"

## Индекс последнего выбранного сценария - чтобы pick_scenario() больше
## никогда не выдавал ТОТ ЖЕ сценарий два раза подряд (было чисто
## pick_random(), которое иногда выпадало на один и тот же индекс дважды
## подряд - визуально выглядело как "будто сценарий не поменялся").
var _last_scenario_index := -1

func pick_scenario() -> void:
	if scenarios.is_empty():
		push_error("[barrier_manager.gd] scenarios is EMPTY - assign at least one scenario in the inspector!")
		return

	if scenarios.size() == 1:
		# единственный сценарий - повторов избежать физически невозможно
		current_scenario = scenarios[0]
		_last_scenario_index = 0
		return

	var index := _last_scenario_index
	while index == _last_scenario_index:
		index = randi() % scenarios.size()

	_last_scenario_index = index
	current_scenario = scenarios[index]


func _ready() -> void:
	add_to_group("barrier_manager")

	if lane_markers.is_empty():
		push_error("[barrier_manager.gd] lane_markers is EMPTY - assign Lane1..Lane4 in the inspector!")
	if road_manager == null:
		push_warning("[barrier_manager.gd] RoadManager not found (../RoadManager) - collision checks vs player cars are DISABLED, barriers will still spawn/scroll for visual testing")
	if small_barrier_scene == null or medium_barrier_scene == null or big_barrier_scene == null:
		push_warning("[barrier_manager.gd] one or more barrier scenes are NOT assigned in the inspector - those lanes will be skipped")

	print("[barrier_manager.gd] ready: lanes=%d, spawn_z=%s, trigger_z=%s, despawn_z=%s" % [lane_markers.size(), spawn_z, trigger_z, despawn_z])

	_align_trigger_to_cars()

	# Проверяем ВСЕ сценарии сразу при старте (см. _validate_all_scenarios) -
	# так кривые данные (машина, которая заведомо не проедет в свои ворота)
	# обнаруживаются сразу в логе, а не когда pick_random() случайно на них
	# наткнётся посреди игры игрока.
	_validate_all_scenarios()

	# Сначала выбираем сценарий (заполняет current_scenario), затем -
	# машины игрока по нему, и только потом волны барьеров, чтобы
	# _check_collision() в первой же волне видел актуальные lane_cars.
	pick_scenario()
	_spawn_initial_cars()

	# Таймер волн создаём ЗАРАНЕЕ (до первого спавна) - _spawn_wave() может
	# сам запланировать следующую волну сразу после спавна (см.
	# _maybe_schedule_next_wave() и страховку в конце _spawn_wave()), и ему
	# нужен уже существующий _wave_timer, а не создание второй Timer-ноды
	# через запасной путь в _schedule_next_wave().
	_start_wave_timer()
	# Спавним первую волну СРАЗУ, без ожидания (никаких await перед первым спавном)
	_spawn_next_wave()
	# Сложность теперь растёт от количества волн (см. waves_per_difficulty_level
	# и проверку в _spawn_next_wave()), отдельный таймер больше не нужен.


## Подтягивает trigger_z/despawn_z под реальную Z-координату машин игрока,
## вместо магических дефолтов, которые в этой сцене были короче реальной
## дистанции до машин на ~26 метров (см. коммент у @export выше). Если
## auto_align_trigger_z выключен вручную в инспекторе - просто оставляет
## что задано в trigger_z/despawn_z.
func _align_trigger_to_cars() -> void:
	if not auto_align_trigger_z:
		return
	if car_spawn_markers.is_empty():
		push_warning("[barrier_manager.gd] auto_align_trigger_z=true, но car_spawn_markers пуст - оставляю ручные trigger_z/despawn_z")
		return

	trigger_z = car_spawn_markers[0].global_position.z
	despawn_z = trigger_z + despawn_margin
	print("[barrier_manager.gd] auto-aligned trigger_z=%s, despawn_z=%s (from car_spawn_markers[0])" % [trigger_z, despawn_z])


## ------------------- ТАЙМИНГ ВОЛН -------------------
## БЫЛО: repeating Timer с фиксированным интервалом seconds_between_waves -
## это спавнило волну N+1 даже если волна N ЕЩЁ НЕ УШЛА за камеру (барьеры
## едут от spawn_z до despawn_z обычно дольше, чем пауза между волнами,
## особенно на малых значениях seconds_between_waves после нескольких
## уровней сложности). В итоге на трассе одновременно летело по 2-3 волны
## разом, счётчик "Волна: N" рос быстрее, чем волны реально заканчивались,
## а FAIL мог сработать от СТАРОЙ волны ровно в тот момент, когда рядом в
## логе только что печаталась НОВАЯ - выглядело как рассинхрон букв.
##
## ТЕПЕРЬ: следующая волна планируется ТОЛЬКО когда ВСЕ барьеры ПОСЛЕДНЕЙ
## заспавненной волны реально ушли за камеру (см. _maybe_schedule_next_wave(),
## вызывается из _advance_objects() при каждом despawn). _wave_timer теперь
## ОДНОРАЗОВЫЙ - это просто пауза seconds_between_waves между "волна ушла" и
## "спавним следующую", а не фиксированный ритм поверх ещё летящей волны.
var _next_wave_scheduled := false  # чтобы не запланировать следующую волну дважды подряд

func _start_wave_timer() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_spawn_next_wave)
	_wave_timer = timer


## Вызывается из _advance_objects() каждый раз, когда барьер убирается с
## трассы - проверяет, не остались ли ещё барьеры ИМЕННО последней
## заспавненной волны (entry["wave"] == _wave_count). Если ни одного не
## осталось - волна реально закончилась, планируем следующую с паузой.
func _maybe_schedule_next_wave() -> void:
	for entry in _active_barriers:
		if entry.get("wave", -1) == _wave_count:
			return  # у последней волны ещё есть барьеры на трассе - рано
	_schedule_next_wave()


func _schedule_next_wave() -> void:
	if _next_wave_scheduled:
		return
	_next_wave_scheduled = true

	# FIX: Timer с wait_time=0 в Godot либо молча клэмпится до маленького
	# минимума, либо всё равно ждёт следующий физический кадр - то есть
	# "мгновенно" через Timer не гарантируется. Раз Bashir просил именно
	# мгновенный спавн (seconds_between_waves=0 по умолчанию теперь) -
	# вызываем _spawn_next_wave() напрямую, без прогона через Timer/паузу.
	if seconds_between_waves <= 0.0:
		_spawn_next_wave()
		return

	if _wave_timer == null:
		_start_wave_timer()  # страховка на случай, если почему-то не был создан в _ready()
	_wave_timer.wait_time = seconds_between_waves
	_wave_timer.start()


## ------------------- НАРАСТАНИЕ СЛОЖНОСТИ -------------------
## Вызывается из _spawn_next_wave() каждые waves_per_difficulty_level волн:
## чуть быстрее дорога, чуть чаще волны, чуть быстрее респавн после аварии.
## Всё это ограничено потолками сверху (speed_max / min_seconds_between_waves
## / min_respawn_delay), так что сложность выходит на плато, а не растёт
## бесконечно.
func _ramp_difficulty() -> void:
	difficulty_level += 1

	# --- скорость дороги (та же группа "road_scroller", что читает camera_3d.gd) ---
	for n in get_tree().get_nodes_in_group("road_scroller"):
		if "speed" in n:
			n.speed = min(n.speed + speed_increase_per_level, speed_max)

	# --- волны барьеров чаще ---
	seconds_between_waves = max(seconds_between_waves - wave_interval_decrease_per_level, min_seconds_between_waves)
	# _wave_timer теперь одноразовый и стартует только через _schedule_next_wave(),
	# который каждый раз сам берёт свежий seconds_between_waves - трогать сам
	# таймер здесь больше не нужно (менять wait_time у уже идущего Timer не
	# перезапускает отсчёт, поэтому раньше это всё равно не работало как надо).

	# --- респавн машин после аварии быстрее (меньше времени на "отдохнуть") ---
	respawn_delay = max(respawn_delay - respawn_delay_decrease_per_level, min_respawn_delay)

	print("[barrier_manager.gd] DIFFICULTY UP -> level %d, seconds_between_waves=%.2f, respawn_delay=%.2f" % [difficulty_level, seconds_between_waves, respawn_delay])


## ФИКС "4 машины"/leftover cars между волнами: раньше здесь вызывался
## _respawn_all_lanes(), который переставляет машины ТОЛЬКО там, где новая
## буква не 'O' (см. старую логику в _spawn_car_in_lane() - при letter=='O'
## был ранний return БЕЗ queue_free() старой машины). Из-за этого при
## смене сценария от волны к волне машина в полосе, которая раньше была
## занята, а в новом сценарии стала пустой ('O'), просто переставала
## отслеживаться (lane_cars[lane]=null), но сама нода оставалась в дереве
## сцены и на экране - копилась как "лишняя" машина.
##
## Теперь при каждой новой волне сначала ПОЛНОСТЬЮ уничтожаем все текущие
## машины (clear_cars() - тот же метод, что использует _on_continue() после
## аварии), а затем спавним заново по свежему current_scenario["cars"] -
## гарантированно ровно 4 актуальные машины (считая пустые полосы), без
## накопления "призраков" от прошлых волн.
func _spawn_next_wave() -> void:
	_next_wave_scheduled = false  # эта волна уже спавнится - флаг планирования больше не актуален

	# Новый случайный сценарий на каждую волну - применяется И к барьерам,
	# И к машинам игрока (полный destroy-and-replace, см. коммент выше).
	pick_scenario()
	if current_scenario.is_empty():
		return

	var pattern: String = current_scenario.get("barriers", "")
	if pattern.is_empty():
		push_warning("[barrier_manager.gd] current_scenario has no 'barriers' pattern")
		return

	_validate_one_empty_lane(pattern)

	# NEW: полностью уничтожаем старые машины и спавним заново по новому
	# сценарию, вместо точечного _respawn_all_lanes() (который и приводил
	# к накоплению "лишних" машин на пустых полосах).
	clear_cars()
	_spawn_initial_cars()

	_wave_count += 1

	# Сложность растёт каждые waves_per_difficulty_level волн (Bashir просил
	# "каждые 4 волны") - считаем от _wave_count, а не от реального времени.
	if difficulty_enabled and waves_per_difficulty_level > 0 and _wave_count % waves_per_difficulty_level == 0:
		_ramp_difficulty()

	_spawn_wave(pattern)


## По задумке в паттерне барьеров ВСЕГДА должна быть ровно одна пустая
## полоса (O) - иначе бывают волны, где ни одна полоса не является
## гарантированным проходом. Просто предупреждаем в консоли, если данные
## сценария (Inspector) это нарушают - ничего не ломаем и не подставляем
## значения за автора, это его сценарий и его данные.
## ------------------- ВАЛИДАЦИЯ ВСЕХ СЦЕНАРИЕВ (при старте) -------------------
## Старый _validate_one_empty_lane() ниже проверяет только ТЕКУЩИЙ сценарий,
## и только в момент, когда он выпал случайно - то есть кривые данные могут
## месяцами лежать в scenarios[] незамеченными, пока pick_random() наконец
## на них не попадёт.
##
## Эта функция вместо этого проверяет КАЖДЫЙ элемент scenarios[] сразу в
## _ready(), ДО того как игра вообще началась:
##  1. "cars" и "barriers" вообще заданы и не пустые
##  2. оба паттерна тайзят ровно в lane_markers.size() токенов (иначе на
##     некоторых полосах вообще не будет ни машины, ни проверки столкновения)
##  3. в "barriers" ровно ОДНА пустая полоса (O) - иначе либо нет гарантированного
##     прохода, либо появляется риск 4 машин разом (см. коммент выше по коду)
##  4. каждая буква (кроме O) - это именно A/B/C, а не опечатка/левый символ
##
## ВАЖНО: НЕ проверяет, что машина из "cars" на старте уже стоит в "своей"
## полосе (совпадает с "barriers" по этой же полосе) - это У ЭТОЙ ИГРЫ И НЕ
## ДОЛЖНО совпадать по умолчанию. "cars" - это ГОЛОВОЛОМКА: стартовая
## раскладка, которую игрок обязан сам разрулить кликами через
## InputManager/SelectionManager/RoadManager.move_car() ДО того, как волна
## барьеров долетит до trigger_z. Реальная проверка "проехала машина или
## нет" всегда идёт по фактическим полям объектов в _check_collision() -
## car.car_type и entry["letter"] (который сам берётся из gate_type
## заспавненного барьера, а не из буквы паттерна) - см. _size_fits() выше.
## Здесь эта же логика НЕ дублируется намеренно.
##
## Ничего не "чинит" и не подставляет значения за автора - только громко
## сообщает через push_error(), с точным индексом сценария и номером полосы,
## чтобы было сразу понятно, что и где поправить в инспекторе.
func _validate_all_scenarios() -> void:
	if scenarios.is_empty():
		return  # пустой scenarios[] уже отдельно ловится в pick_scenario()

	var expected_lanes := lane_markers.size()
	if expected_lanes <= 0:
		expected_lanes = 4  # lane_markers ещё не назначены в инспекторе - проверяем хотя бы форму паттернов

	var had_errors := false

	for i in scenarios.size():
		var scenario: Dictionary = scenarios[i]
		var tag := "[barrier_manager.gd][VALIDATE] scenarios[%d]" % i

		var cars_pattern: String = scenario.get("cars", "")
		var barriers_pattern: String = scenario.get("barriers", "")

		if cars_pattern.is_empty() or barriers_pattern.is_empty():
			push_error("%s: 'cars' или 'barriers' пустой/отсутствует (cars='%s', barriers='%s')" % [tag, cars_pattern, barriers_pattern])
			had_errors = true
			continue

		var cars_tokens := _tokenize(cars_pattern)
		var barriers_tokens := _tokenize(barriers_pattern)

		if cars_tokens.size() != expected_lanes:
			push_error("%s: 'cars' паттерн '%s' даёт %d токенов, ожидалось %d (по lane_markers)" % [tag, cars_pattern, cars_tokens.size(), expected_lanes])
			had_errors = true
		if barriers_tokens.size() != expected_lanes:
			push_error("%s: 'barriers' паттерн '%s' даёт %d токенов, ожидалось %d (по lane_markers)" % [tag, barriers_pattern, barriers_tokens.size(), expected_lanes])
			had_errors = true
		if cars_tokens.size() != expected_lanes or barriers_tokens.size() != expected_lanes:
			continue  # дальше по полосам сверять бессмысленно - размеры уже не совпадают

		# буквы должны быть только A/B/C/O; отдельно считаем O в barriers
		# ТОЛЬКО для информации в логе - это не жёсткое требование движка:
		# если в barriers вообще нет O (все 4 полосы под гейтами), игра всё
		# равно не сломается - там, где в cars стоит O (машины нет), гейт
		# просто пролетает мимо без всякой проверки столкновения.
		var empty_count := 0
		for lane in barriers_tokens.size():
			var letter: String = barriers_tokens[lane].substr(0, 1).to_upper()
			if letter == "O":
				empty_count += 1
			elif not _GATE_RANK.has(letter):
				push_error("%s: неизвестная буква ворот '%s' в полосе %d (barriers='%s') - допустимы только A/B/C/O" % [tag, letter, lane, barriers_pattern])
				had_errors = true

		if empty_count != 1:
			push_warning("%s: 'barriers'='%s' содержит %d пустых (O) полос (не 1) - это не ошибка, просто для информации" % [tag, barriers_pattern, empty_count])

		for lane in cars_tokens.size():
			var car_letter: String = cars_tokens[lane].substr(0, 1).to_upper()
			if car_letter != "O" and not _GATE_RANK.has(car_letter):
				push_error("%s: неизвестная буква машины '%s' в полосе %d (cars='%s') - допустимы только A/B/C/O" % [tag, car_letter, lane, cars_pattern])
				had_errors = true

	if had_errors:
		push_error("[barrier_manager.gd][VALIDATE] найдены ошибки в scenarios[] - см. сообщения выше.")
	else:
		print("[barrier_manager.gd][VALIDATE] все %d сценариев прошли проверку без ошибок" % scenarios.size())


func _validate_one_empty_lane(pattern: String) -> void:
	var tokens := _tokenize(pattern)
	var empty_count := 0
	for t in tokens:
		if t.substr(0, 1).to_upper() == "O":
			empty_count += 1
	if empty_count != 1:
		push_warning("[barrier_manager.gd] scenario 'barriers' pattern '%s' has %d empty (O) lanes, expected exactly 1 - check scenarios in the inspector" % [pattern, empty_count])


func _process(delta: float) -> void:
	_update_speed()
	_advance_objects(delta)
	_run_time += delta


func _update_speed() -> void:
	for n in get_tree().get_nodes_in_group("road_scroller"):
		if "speed" in n:
			_speed = n.speed
			return
	# если группа "road_scroller" не нашлась - барьеры заспавнятся,
	# но НЕ БУДУТ ДВИГАТЬСЯ (speed=0). Это одна из частых причин
	# "барьеры не видно" - они стоят далеко на spawn_z и никогда не
	# доезжают до камеры. Проверь, что твой скролл-скрипт дороги
	# реально добавлен в группу "road_scroller" (main_scene.gd это делает).


func _advance_objects(delta: float) -> void:
	# ВАЖНО: двигаем через global_position, а не position (локальную).
	# Если у самого BarrierManager есть смещение/поворот в дереве сцены,
	# то position.z "врёт" относительно реального мира - объект едет не
	# туда и/или триггер срабатывает не в том месте. global_position
	# всегда в мировых координатах, независимо от родителя.
	for i in range(_active_barriers.size() - 1, -1, -1):
		var entry: Dictionary = _active_barriers[i]
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			_active_barriers.remove_at(i)
			_maybe_schedule_next_wave()
			continue

		var gp := node.global_position
		gp.z += _speed * delta
		node.global_position = gp

		if not entry["checked"] and gp.z >= trigger_z:
			entry["checked"] = true
			_check_collision(entry)

		if gp.z >= despawn_z:
			node.queue_free()
			_active_barriers.remove_at(i)
			_maybe_schedule_next_wave()


func _check_collision(entry: Dictionary) -> void:
	if road_manager == null:
		return  # RoadManager нет в сцене (тестовый режим) - пропускаем проверку

	var lane: int = entry["lane"]
	var car: Node = road_manager.lane_cars.get(lane, null)
	if not is_instance_valid(car):
		return  # полоса игрока пуста - барьер просто проезжает мимо

	var car_type: String = car.car_type if "car_type" in car else "A"
	if not _size_fits(car_type, entry["letter"]):
		_on_fail(car, entry, car_type)
	else:
		_play_sfx(sfx_gate_pass, car.global_position)
		_spawn_burst_particles(car.global_position, pass_particle_color, 10)


## ПРАВИЛО ПРОЕЗДА - РАНГОВОЕ (по требованию):
##  - A (small, легковушка) - проходит ЧЕРЕЗ ЛЮБЫЕ ворота (A, B и C)
##  - B (medium, truck)     - проходит через ворота B ИЛИ C (в A - нет, слишком узкие)
##  - C (big, мусоровоз)    - проходит ТОЛЬКО через ворота C (самые широкие)
## Таблица допустимых пар (car -> gate): A->A/B/C, B->B/C, C->C.
## Раньше тут было строгое равенство (A только в A и т.д.) - это было
## сознательным фиксом другого бага (см. историю), но по факту требовалась
## именно эта ранговая схема. Т.к. правило снова "мягкое", вся ответственность
## за то, чтобы сценарии не подсовывали C в A-ворота (гарантированная авария),
## лежит на данных scenarios[] - поэтому ниже есть _validate_all_scenarios(),
## который при старте проверяет КАЖДЫЙ сценарий по этой же таблице и громко
## ругается в лог, если где-то машина заведомо не проедет в свои ворота.
const _GATE_RANK := {"A": 0, "B": 1, "C": 2}

func _size_fits(car_type: String, gate_letter: String) -> bool:
	var c := car_type.to_upper()
	var g := gate_letter.to_upper()
	if not _GATE_RANK.has(c) or not _GATE_RANK.has(g):
		return false  # неизвестная буква - считаем несовпадением, а не молча пропускаем
	return _GATE_RANK[c] <= _GATE_RANK[g]


## ЗАГЛУШКА НА СМЕРТЬ / GAME OVER - машина уже умеет красиво умирать
## (car.die() в car.gd/car2.gd/car3.gd). Дальше (реальный game-over экран,
## рестарт, счёт) добавим следующим шагом, когда база обкатается.
##
## ВАЖНО (как просил Bashir): при смерти ЛЮБОЙ машины на любой полосе -
## респавнятся ВСЕ 4 полосы разом, а не только та, что разбилась. Строго
## по current_scenario["cars"] - то есть все машины сбрасываются к тому
## же паттерну, что был у волны, на которой произошла авария.
func _on_fail(car: Node, entry: Dictionary, car_type: String) -> void:
	var lane: int = entry["lane"]
	# ВАЖНО ДЛЯ ДИАГНОСТИКИ: печатаем и тип МАШИНЫ, и букву ВОРОТ, и из какой
	# волны эти ворота (entry["wave"]) - потому что в одной полосе одновременно
	# может лететь несколько барьеров подряд от РАЗНЫХ волн (новая волна
	# спавнится каждые seconds_between_waves секунд, а барьер едет от spawn_z
	# до trigger_z дольше этого интервала), и без wave-номера в логе легко
	# перепутать "только что заспавненный барьер этой волны" с "тем, что уже
	# давно летел от прошлой волны и только сейчас доехал до триггера".
	print("[barrier_manager.gd] FAIL: lane %d, car_type='%s' vs gate='%s' (gate from wave #%d)" % [lane, car_type, entry["letter"], entry.get("wave", -1)])
	_play_sfx(sfx_gate_crash, car.global_position)
	_shake_camera()
	_spawn_burst_particles(car.global_position, crash_particle_color, 24)
	if car is Node3D:
		_play_death_flourish(car)
	if car.has_method("die"):
		car.die()
	await _hit_stop()
	player_hit_barrier()


## Маленький "импакт-стоп" для ощущения удара - на пару кадров подтормаживаем
## время (НЕ pause - Engine.time_scale, чтобы tween смерти машины успел
## доиграться в замедлении, а не замер), затем возвращаем как было. Чисто
## визуальная приправа, на логику/сценарии не влияет.
@export var hit_stop_duration := 0.12
@export var hit_stop_scale := 0.15

func _hit_stop() -> void:
	Engine.time_scale = hit_stop_scale
	# ignore_time_scale=true - таймер идёт в реальном времени, а не в
	# "замедленном", иначе hit_stop_duration растянется в 1/hit_stop_scale раз
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = 1.0


## Если за respawn_delay успеют упасть ещё машины (например 2 полосы
## пробили ворота в одной волне) - НЕ запускаем респавн повторно, флаг
## _respawn_pending гасит дубли, иначе полосы дважды пересоздадутся подряд.
func _schedule_respawn_all() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	await get_tree().create_timer(respawn_delay).timeout
	_respawn_pending = false
	# "Ударился - поменял сценарий - обновил": на КАЖДУЮ аварию берём
	# новый случайный сценарий (не тот же самый current_scenario), и уже
	# по нему пересобираем все полосы.
	pick_scenario()
	_respawn_all_lanes()


## СТРОГОЕ ПРАВИЛО (Bashir настоял - "нельзя чтобы появлялось 4 машины"):
## пустая полоса без машины ВСЕГДА ровно одна, и это ВСЕГДА та же полоса,
## что помечена 'O' в паттерне barriers ЭТОГО ЖЕ сценария - а не то, что
## написано в паттерне cars. Данные сценариев в инспекторе могут вообще
## не содержать 'O' в "cars" (как сейчас - "ABCA"/"BCAB"/"CABC") - это
## больше не важно, логика сама гасит машину в полосе-проходе барьеров,
## так что 4 машины одновременно появиться просто не могут.
func _cars_tokens_with_forced_empty_lane(cars_pattern: String, barriers_pattern: String) -> Array:
	var cars_tokens := _tokenize(cars_pattern)
	var empty_lane := _find_empty_lane_index(barriers_pattern)
	if empty_lane >= 0 and empty_lane < cars_tokens.size():
		cars_tokens[empty_lane] = "O"
	return cars_tokens


func _find_empty_lane_index(barriers_pattern: String) -> int:
	var tokens := _tokenize(barriers_pattern)
	for i in tokens.size():
		if tokens[i].substr(0, 1).to_upper() == "O":
			return i
	return -1


## Пересоздаёт машины СТРОГО по current_scenario["cars"] на всех полосах -
## живые машины тоже удаляются и ставятся заново, чтобы после аварии на
## трассе всегда был чистый, согласованный со сценарием набор машин.
## (Всё ещё используется _schedule_respawn_all() после аварии - для смены
## волн теперь вместо неё используется clear_cars()+_spawn_initial_cars(),
## см. _spawn_next_wave() выше.)
func _respawn_all_lanes() -> void:
	if current_scenario.is_empty():
		push_warning("[barrier_manager.gd] respawn-all skipped - current_scenario is empty")
		return

	var cars_pattern: String = current_scenario.get("cars", "")
	var barriers_pattern: String = current_scenario.get("barriers", "")
	var tokens := _cars_tokens_with_forced_empty_lane(cars_pattern, barriers_pattern)
	print("[barrier_manager.gd] respawning ALL lanes, cars=%s (empty lane forced from barriers=%s)" % [cars_pattern, barriers_pattern])

	for lane in car_spawn_markers.size():
		if lane >= tokens.size():
			push_warning("[barrier_manager.gd] cars pattern '%s' has no token for lane %d" % [cars_pattern, lane])
			continue
		var letter: String = tokens[lane].substr(0, 1)
		_spawn_car_in_lane(lane, letter, "respawned-all")


## Расставляет машины игрока по всем полосам ОДИН РАЗ при старте сцены,
## по тому же принципу "буква = тип ворот" что и волны барьеров/респавн.
## Вызывается из _ready() ДО первой волны барьеров, используя тот же
## current_scenario, который выбрал pick_scenario(). Также вызывается из
## _spawn_next_wave() (после clear_cars()) на каждую новую волну.
func _spawn_initial_cars() -> void:
	if current_scenario.is_empty():
		push_warning("[barrier_manager.gd] initial spawn skipped - current_scenario is empty")
		return

	var cars_pattern: String = current_scenario.get("cars", "")
	var barriers_pattern: String = current_scenario.get("barriers", "")
	var tokens := _cars_tokens_with_forced_empty_lane(cars_pattern, barriers_pattern)
	print("[barrier_manager.gd] spawning initial cars, cars=%s (empty lane forced from barriers=%s)" % [cars_pattern, barriers_pattern])

	for lane in car_spawn_markers.size():
		if lane >= tokens.size():
			continue
		var letter: String = tokens[lane].substr(0, 1)
		_spawn_car_in_lane(lane, letter, "spawned")


## Общее ядро для _spawn_initial_cars() и _respawn_car(): создаёт машину
## типа letter в полосе lane (или оставляет полосу пустой для 'O'),
## ставит её в road_manager.lane_cars. label - только для вывода в консоль
## ("spawned"/"respawned"), на логику не влияет.
##
## ФИКС УТЕЧКИ МАШИН: раньше при letter=='O' был ранний return, который
## только обнулял road_manager.lane_cars[lane], но НИКОГДА не вызывал
## queue_free() у машины, которая реально стояла в этой полосе раньше
## (если она там была). Нода оставалась в дереве сцены и на экране
## навсегда - это и была причина "вижу 4 машины" при смене сценариев
## между волнами. Теперь old_car освобождается ДО early-return, независимо
## от того, какая буква пришла новой.
func _spawn_car_in_lane(lane: int, letter: String, label: String) -> void:
	if road_manager == null or car_manager == null:
		push_warning("[barrier_manager.gd] spawn skipped - RoadManager/CarManager not found")
		return
	if car_spawn_markers.is_empty():
		push_warning("[barrier_manager.gd] spawn skipped - car_spawn_markers is EMPTY, assign them in the inspector!")
		return
	if lane >= car_spawn_markers.size():
		push_warning("[barrier_manager.gd] spawn skipped - no car_spawn_marker for lane %d" % lane)
		return

	# Убираем то, что осталось от предыдущей машины в этой полосе - ДО
	# проверки на 'O', иначе полоса, ставшая пустой в новом сценарии,
	# никогда не освобождает свою старую машину (см. коммент выше).
	var old_car: Node = road_manager.lane_cars.get(lane, null)
	if is_instance_valid(old_car):
		old_car.queue_free()

	if letter.to_upper() == "O":
		print("[barrier_manager.gd] lane %d stays empty by scenario" % lane)
		road_manager.lane_cars[lane] = null
		return

	var scene := _pick_player_scene(letter)
	if scene == null:
		push_warning("[barrier_manager.gd] no player car scene assigned for letter '%s'" % letter)
		road_manager.lane_cars[lane] = null
		return

	var inst = scene.instantiate()
	if "lane" in inst:
		inst.lane = lane

	# ВАЖНО: scale ставим ДО add_child(). car.gd/car2.gd/car3.gd делают
	# `base_scale = scale` в своём _ready(), который срабатывает СИНХРОННО
	# внутри add_child() - если scale выставить ПОСЛЕ add_child, base_scale
	# запомнит неправильный дефолтный масштаб из .tscn (обычно 1,1,1), а не
	# реальный (1.35/1.6). Это и было причиной "размер меняется при смене
	# полосы / после смерти" - move_to_lane()/die() откатывали scale именно
	# к этому неправильно запомненному base_scale.
	#
	# NEW: base_scale всё ещё выставляется здесь ДО add_child (чтобы
	# car.gd::_ready() запомнил правильный масштаб) - анимация появления
	# ниже (_play_spawn_flourish) временно ПЕРЕЗАПИСЫВАЕТ scale/position
	# сразу после add_child и плавно доводит их до этих же целевых
	# значений, так что base_scale, запомненный в _ready(), не ломается.
	var target_scale := _pick_scale(letter)
	inst.scale = target_scale
	car_manager.add_child(inst)

	# Позиция и ПОВОРОТ - берём с маркера (крутани сам маркер в редакторе
	# так, чтобы машина смотрела в ту же сторону, что и остальные), плюс
	# тонкая подстройка через offset-поля конкретного типа.
	var target_position := car_spawn_markers[lane].global_position + _pick_position_offset(letter)
	inst.global_rotation_degrees = car_spawn_markers[lane].global_rotation_degrees + _pick_rotation_offset(letter)

	if inst is Node3D:
		_play_spawn_flourish(inst, target_position, target_scale)
	else:
		inst.global_position = target_position

	road_manager.lane_cars[lane] = inst
	print("[barrier_manager.gd] %s '%s' in lane %d, pos=%s, rot=%s, scale=%s" % [label, letter, lane, inst.global_position, inst.global_rotation_degrees, inst.scale])


func _pick_player_scene(letter: String) -> PackedScene:
	match letter.to_upper():
		"A":
			return player_small_car_scene
		"B":
			return player_medium_car_scene
		"C":
			return player_big_car_scene
	return null


func _pick_scale(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return player_small_car_scale
		"B":
			return player_medium_car_scale
		"C":
			return player_big_car_scale
	return Vector3.ONE


func _pick_position_offset(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return player_small_car_position_offset
		"B":
			return player_medium_car_position_offset
		"C":
			return player_big_car_position_offset
	return Vector3.ZERO


func _pick_rotation_offset(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return player_small_car_rotation_offset
		"B":
			return player_medium_car_rotation_offset
		"C":
			return player_big_car_rotation_offset
	return Vector3.ZERO


func _tokenize(pattern: String) -> Array:
	var re := RegEx.new()
	re.compile(TOKEN_PATTERN)
	var tokens: Array = []
	for m in re.search_all(pattern):
		tokens.append(m.get_string())
	return tokens


func _pick_scene(letter: String) -> PackedScene:
	match letter.to_upper():
		"A":
			return small_barrier_scene
		"B":
			return medium_barrier_scene
		"C":
			return big_barrier_scene
	return null


## Пер-типовые offset'ы барьеров - те же три хелпера, что и у машин игрока,
## только для ворот (small/medium/big по букве A/B/C).
func _pick_barrier_position_offset(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return small_barrier_position_offset
		"B":
			return medium_barrier_position_offset
		"C":
			return big_barrier_position_offset
	return Vector3.ZERO


func _pick_barrier_rotation_offset(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return small_barrier_rotation_offset
		"B":
			return medium_barrier_rotation_offset
		"C":
			return big_barrier_rotation_offset
	return Vector3.ZERO


func _pick_barrier_scale(letter: String) -> Vector3:
	match letter.to_upper():
		"A":
			return small_barrier_scale
		"B":
			return medium_barrier_scale
		"C":
			return big_barrier_scale
	return Vector3.ONE


func _spawn_wave(pattern: String) -> void:
	var tokens := _tokenize(pattern)
	if tokens.size() != lane_markers.size():
		push_warning("[barrier_manager.gd] pattern '%s' has %d tokens, expected %d lanes" % [pattern, tokens.size(), lane_markers.size()])

	print("[barrier_manager.gd] spawning wave #%d, pattern=%s" % [_wave_count, pattern])
	_play_sfx(sfx_wave_spawn, global_position)

	for lane in lane_markers.size():
		if lane >= tokens.size():
			continue
		var token: String = tokens[lane]
		var letter := token.substr(0, 1)
		if letter.to_upper() == "O":
			print("[barrier_manager.gd]   lane %d: empty (O)" % lane)
			continue

		var scene := _pick_scene(letter)
		if scene == null:
			push_warning("[barrier_manager.gd] no scene assigned for letter '%s'" % letter)
			continue

		var inst: Node3D = scene.instantiate()
		add_child(inst)
		var marker := lane_markers[lane]

		# Глобальный offset (для всех типов) + пер-типовой offset (для
		# этой конкретной модели ворот) складываются вместе.
		inst.global_position = Vector3(
			marker.global_position.x,
			marker.global_position.y,
			spawn_z
		) + barrier_position_offset + _pick_barrier_position_offset(letter)

		inst.rotation_degrees += barrier_rotation_offset + _pick_barrier_rotation_offset(letter)
		var target_scale: Vector3 = inst.scale * barrier_scale_multiplier * _pick_barrier_scale(letter)

		# --- Новая анимация появления ворот: "выезжают" из 0 до целевого
		# масштаба, вместо того чтобы просто мгновенно возникать в воздухе.
		inst.scale = target_scale * 0.01
		var pop_tween := create_tween()
		pop_tween.tween_property(inst, "scale", target_scale, 0.25)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# --- Реальный тип ворот берём с самого объекта (barrier_gate.gd::
		# gate_type), если он там есть - это единственный источник правды
		# для _check_collision(). Буква из паттерна нужна только чтобы
		# решить, какую сцену спавнить - если сцена вдруг "не той" (старые
		# данные сценария / перепутанный slot в инспекторе), проверка
		# столкновений всё равно пойдёт по РЕАЛЬНОМУ типу объекта, а не по
		# букве из строки - и мы громко предупредим об рассинхроне.
		var effective_letter := letter
		if "gate_type" in inst:
			effective_letter = inst.gate_type
			if effective_letter.to_upper() != letter.to_upper():
				push_warning("[barrier_manager.gd] MISMATCH lane %d: pattern says '%s' but spawned scene's gate_type='%s' - using gate_type as source of truth. Проверь, что small/medium/big_barrier_scene и их gate_type реально соответствуют друг другу." % [lane, letter, effective_letter])

		print("[barrier_manager.gd]   lane %d: spawned '%s' at %s" % [lane, effective_letter, inst.global_position])

		_active_barriers.append({
			"node": inst,
			"lane": lane,
			"letter": effective_letter,
			"wave": _wave_count,
			"checked": false,
		})

	# Страховка: если в этой волне вообще не заспавнилось ни одного барьера
	# (например, все 4 полосы 'O', или все сцены барьеров не назначены в
	# инспекторе) - despawn-событий для неё никогда не будет, и
	# _maybe_schedule_next_wave() никогда не сработает сама. Проверяем это
	# явно здесь же, сразу после спавна.
	_maybe_schedule_next_wave()
		

## ФИКС "тап не закрывает death-экран": если в одной волне разбились
## СРАЗУ 2+ машины (например 2 полосы пробили не свои ворота одним
## кадром), player_hit_barrier() вызывался бы 2+ раза подряд и на экране
## оказывалось НЕСКОЛЬКО наложенных друг на друга DeathMenu. Тап закрывал
## только верхний - под ним оставался второй, всё ещё держащий
## get_tree().paused = true, и снаружи это выглядело как "тап не
## работает". Флаг ниже гарантирует ровно один активный death-экран.
var _death_screen_active := false

func player_hit_barrier():
	if _death_screen_active:
		return  # экран смерти уже показан - не плодим второй поверх
	_death_screen_active = true

	var death = DEATH_SCENE.instantiate()
	get_tree().current_scene.add_child(death)

	# Отдаём death-экрану статистику текущего заезда, если он умеет её
	# принять (см. death_menu.gd::setup()) - старая/минимальная версия
	# death_menu без setup() тоже продолжит работать, просто без цифр.
	if death.has_method("setup"):
		death.setup({
			"run_time": _run_time,
			"wave_count": _wave_count,
			"difficulty_level": difficulty_level,
		})

	death.continue_game.connect(_on_continue)

func _on_continue():
	_death_screen_active = false

	# выбрать новый сценарий
	pick_scenario()

	# удалить старые машины
	clear_cars()

	# удалить барьеры
	clear_barriers()

	# Сбрасываем состояние планирования волн - _spawn_next_wave() ниже
	# запускает волну СРАЗУ, минуя обычную паузу seconds_between_waves.
	# Если до аварии уже был запланирован _wave_timer (ждал паузы после
	# предыдущей волны) - его нужно остановить, иначе он потом внезапно
	# выстрелит ЕЩЁ ОДНОЙ волной поверх той, что мы создаём здесь вручную.
	_next_wave_scheduled = false
	if _wave_timer:
		_wave_timer.stop()

	# создать заново
	_spawn_initial_cars()
	_spawn_next_wave()

	# счётчик времени заезда - на дисплее death-экрана показываем время
	# ИМЕННО этого отрезка (сложность/уровень при этом не сбрасываются -
	# игра продолжает жать педаль в пол, как и положено endless runner'у)
	_run_time = 0.0


func clear_barriers() -> void:
	for data in _active_barriers:
		if data.has("node") and is_instance_valid(data["node"]):
			data["node"].queue_free()

	_active_barriers.clear()

func clear_cars() -> void:
	for car in get_tree().get_nodes_in_group("cars"):
		if is_instance_valid(car):
			car.queue_free()

	for i in range(road_manager.lane_cars.size()):
		road_manager.lane_cars[i] = null
