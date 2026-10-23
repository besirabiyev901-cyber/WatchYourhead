extends Node3D

@export var speed: float = 10.0
@export var road_length: float = 1

@onready var road1: Node3D = $"."
@onready var road2: Node3D = $Road2

func _process(delta: float) -> void:
	road1.position.z += speed * delta
	road2.position.z += speed * delta

	if road1.position.z >= road_length:
		road1.position.z = road2.position.z - road_length

	if road2.position.z >= road_length:
		road2.position.z = road1.position.z - road_length
