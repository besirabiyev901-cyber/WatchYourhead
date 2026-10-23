extends Resource
class_name Scenario

# 3 символа = 3 lane (индексы 0,1,2)
# Cars:  'A'/'B'/'C' = тип машины в лейне, '0' = пусто
# Gates: 'S'/'M'/'B' = размер барьера, '0' = пустой лейн (без барьера)

@export var car_layout: String = "ABC"

@export var gate_sequence: Array[String] = [
	"SMB",
	"S0M",
	"BMS",
]

@export var gate_spacing := 20.0  # расстояние по Z между рядами барьеров
