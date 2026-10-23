extends Node3D

@export var speed := 10.0

# Точное расстояние между дорогами (совпадает с длиной одного куска дороги)
@export var tile_spacing := 50.0

@onready var road1: Node3D = $RoadManager/Road
@onready var road2: Node3D = $RoadManager/Road2
@onready var road3: Node3D = $RoadManager/Road3
@onready var road_end: Node3D = $RoadManager/RoadEnd

var roads: Array[Node3D] = []
var total_length: float

func _ready():
	add_to_group("road_scroller")

	roads = [road1, road2, road3, road_end]
	total_length = tile_spacing * roads.size()  # 50 * 4 = 200

	# Расставляем ровно так, как у тебя было: 0, -50, -100, -150
	road1.position.z = 0.0
	road2.position.z = -tile_spacing
	road3.position.z = -tile_spacing * 2.0
	road_end.position.z = -tile_spacing * 3.0

	print("tile_spacing = ", tile_spacing, " total_length = ", total_length)

func _process(delta):
	for road in roads:
		road.position.z += speed * delta

		if road.position.z >= tile_spacing:
			road.position.z -= total_length
