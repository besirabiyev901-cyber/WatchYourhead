extends CanvasLayer

@onready var fade: ColorRect = $ColorRect

func _ready() -> void:
	layer = 100
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 0.0


func fade_in(duration := 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, duration)
	await tween.finished


func fade_out(duration := 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, duration)
	await tween.finished
