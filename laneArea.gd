extends Area3D

@export var lane_id := 0

func _ready() -> void:
	# Clicking is now handled centrally by input_manager.gd via manual
	# raycast (avoids flaky picking when Area3D shapes overlap).
	# We just tag ourselves so input_manager can find/identify us.
	add_to_group("lane_hitbox")
	print("[lane_area.gd] %s ready, lane_id=%d" % [name, lane_id])
