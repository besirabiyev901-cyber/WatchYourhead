extends Node
class_name InputManager

# =====================================================================
# InputManager
# ---------------------------------------------------------------------
# Централизованная обработка кликов мышкой: один raycast от камеры,
# и по результату решаем - кликнули по машине (выбрать) или по полосе
# (переместить выбранную машину туда).
#
# ВАЖНО: НЕ кэширует список машин/хитбоксов при старте. Каждый клик -
# это свежий raycast по текущей физике сцены, поэтому машины, которые
# заспавнились/респавнились уже ПОСЛЕ старта игры (BarrierManager),
# кликаются точно так же, как и те, что были в сцене изначально.
# Это тот же принцип, что уже применён в road_manager.gd (там в своё
# время была похожая проблема с "залипшим" кэшем машин).
#
# Полагается на то, что уже есть в проекте:
#  - car.gd/car2.gd/car3.gd добавляют свои Area3D в группу "car_hitbox"
#  - laneArea.gd добавляет себя в группу "lane_hitbox" и хранит lane_id
#  - selection_manager.gd (select/selected_car)
#  - road_manager.gd (move_car(car, new_lane))
# =====================================================================

## Разместить как Node на том же уровне, что и SelectionManager/RoadManager
## (обычно прямо под MainScene, рядом с CarManager/BarrierManager).
@onready var selection: Node = $"../SelectionManager"
@onready var road: Node = $"../RoadManager"

## Максимальная дальность луча от камеры
@export var ray_length := 1000.0


func _ready() -> void:
	if selection == null:
		push_error("[input_manager.gd] SelectionManager not found at ../SelectionManager - fix the node path/parent")
	if road == null:
		push_error("[input_manager.gd] RoadManager not found at ../RoadManager - fix the node path/parent")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)


func _handle_click(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		push_warning("[input_manager.gd] no active Camera3D in current viewport")
		return

	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var to := from + dir * ray_length

	var space_state := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0xFFFFFFFF

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		print("[input_manager] hit: none")
		return

	var collider: Object = result.get("collider")
	print("[input_manager] hit: %s" % collider)

	if collider == null:
		return

	if collider.is_in_group("car_hitbox"):
		var car := _find_car_root(collider as Node)
		if car:
			print("[input_manager] -> select car %s" % car.name)
			selection.select(car)
		return

	if collider.is_in_group("lane_hitbox"):
		var lane_id: int = collider.lane_id if "lane_id" in collider else -1
		if lane_id == -1:
			push_warning("[input_manager.gd] lane hitbox has no lane_id property")
			return
		print("[input_manager] -> lane %d clicked" % lane_id)
		if selection.selected_car:
			road.move_car(selection.selected_car, lane_id)
		return


## Хитбокс лежит где-то внутри модели машины (см. _find_all_area3d в
## car.gd/car2.gd/car3.gd) - поднимаемся по дереву, пока не найдём сам
## CharacterBody3D (корень сцены машины).
func _find_car_root(node: Node) -> Node:
	var n := node
	while n != null:
		if n is CharacterBody3D:
			return n
		n = n.get_parent()
	return null
