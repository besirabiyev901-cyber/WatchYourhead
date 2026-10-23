extends Node

# Attach this as a child of Camera3D (or anywhere in MainScene).
# It replaces per-Area3D input_event picking, which is flaky when
# multiple Area3D shapes overlap in space (car standing on a lane zone) -
# Godot's physics picking can then randomly hit either one.
# A single manual raycast per click removes that ambiguity.

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var selection: Node = get_node("/root/MainScene/SelectionManager")
@onready var road: Node3D = get_node("/root/MainScene/RoadManager")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var space_state := get_viewport().get_world_3d().direct_space_state
	var from := camera.project_ray_origin(event.position)
	var to := from + camera.project_ray_normal(event.position) * 1000.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		print("[input_manager] click hit nothing")
		return

	var collider = result.collider
	print("[input_manager] hit: ", collider.name)

	# Priority 1: clicking a car selects it.
	if collider.is_in_group("car_hitbox"):
		var car = collider.get_parent()
		if not car.moving:
			selection.select(car)
		return

	# Priority 2: clicking a lane zone moves the selected car there.
	if collider.is_in_group("lane_hitbox"):
		var lane_id: int = collider.lane_id
		if selection.selected_car == null:
			print("[input_manager] -> no car selected, ignoring")
			return
		if not road.lane_free(lane_id):
			print("[input_manager] -> lane %d occupied, ignoring" % lane_id)
			return
		road.move_car(selection.selected_car, lane_id)
		selection.clear()
