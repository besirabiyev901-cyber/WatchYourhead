extends Node3D

@export var speed: float = 10.0
@export var length: float = 50.0

func _process(delta: float) -> void:
	position.z += speed * delta

	if position.z >= length:
		position.z -= length * 2.0
