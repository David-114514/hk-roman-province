extends Node2D

var _size := Vector2.ZERO
var _color := Color.WHITE
var _valid := true


func set_ghost(origin: Vector2, size: Vector2, color: Color, valid: bool) -> void:
	position = origin
	_size = size
	_color = color
	_valid = valid
	visible = true
	queue_redraw()


func hide_ghost() -> void:
	visible = false


func _draw() -> void:
	if _size == Vector2.ZERO:
		return
	var fill := _color
	fill.a = 0.45
	if not _valid:
		fill = Color(0.86, 0.22, 0.16, 0.42)
	var rect := Rect2(Vector2.ZERO, _size)
	draw_rect(rect, fill)
	var outline := Color(1, 1, 1, 0.8) if _valid else Color(1, 0.85, 0.8, 0.55)
	draw_rect(rect, outline, false, 2.0)
