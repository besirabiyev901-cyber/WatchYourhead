extends Camera3D

# Attach directly to your Camera3D.
# Reads speed from the road_scroller group (same one decor_scroller.gd uses),
# so shake/FOV automatically scale with how fast the road is moving.

@export var base_fov := 75.0
@export var fov_pulse_amount := 5.0    # extra FOV degrees added at max speed

@export var shake_intensity := 0.014   # max positional jitter (world units) at max speed
@export var shake_frequency := 1.6     # how fast the shake wobbles (было 3.0 - слишком резко/дёргано)
@export var max_speed_ref := 20.0      # speed value that maps to "100% effect" - tune to your road's speed

@export var position_smoothing := 10.0  # выше = резче отклик, ниже = мягче/плавнее

var road_scroller: Node3D
var base_position: Vector3
var current_offset := Vector3.ZERO
var noise := FastNoiseLite.new()
var t_accum := 0.0

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	base_position = position
	fov = base_fov
	noise.seed = randi()
	noise.frequency = shake_frequency
	for n in get_tree().get_nodes_in_group("road_scroller"):
		if n is Node3D:
			road_scroller = n
			break
	if road_scroller == null:
		push_warning("[camera_3d.gd] no node in group 'road_scroller' found - shake/FOV pulse disabled")

func _process(delta: float) -> void:
	var speed: float = road_scroller.speed if road_scroller else 0.0
	var t: float = clamp(speed / max_speed_ref, 0.0, 1.0)

	fov = base_fov + fov_pulse_amount * t


	t_accum += delta * 10.0
	var shake_amount := shake_intensity * t
	var offset_x := noise.get_noise_2d(t_accum, 0.0) * shake_amount
	var offset_y := noise.get_noise_2d(0.0, t_accum) * shake_amount
	var target_offset := Vector3(offset_x, offset_y, 0.0)

	current_offset = current_offset.lerp(target_offset, clamp(delta * position_smoothing, 0.0, 1.0))
	position = base_position + current_offset
