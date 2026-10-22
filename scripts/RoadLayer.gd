extends Node2D

var _cells: Dictionary = {}


func add_cell(cell: Vector2i) -> void:
	_cells[cell] = true
	queue_redraw()


func remove_cell(cell: Vector2i) -> void:
	_cells.erase(cell)
	queue_redraw()


func _has(cell: Vector2i) -> bool:
	return _cells.has(cell)


func _draw() -> void:
	var cell_size := float(GameManager.CELL_SIZE)
	for key in _cells.keys():
		_draw_cell(key, cell_size)


func _draw_cell(cell: Vector2i, cell_size: float) -> void:
	var origin := Vector2(cell) * cell_size
	var full := Rect2(origin, Vector2(cell_size, cell_size))
	draw_rect(full, Color(0.28, 0.24, 0.19))
	var inset := 8.0
	var inner := full.grow(-inset)
	if _has(cell + Vector2i(0, -1)):
		inner.position.y -= inset
		inner.size.y += inset
	if _has(cell + Vector2i(0, 1)):
		inner.size.y += inset
	if _has(cell + Vector2i(-1, 0)):
		inner.position.x -= inset
		inner.size.x += inset
	if _has(cell + Vector2i(1, 0)):
		inner.size.x += inset
	draw_rect(inner, Color(0.66, 0.57, 0.42))
