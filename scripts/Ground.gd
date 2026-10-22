extends Node2D


func _draw() -> void:
	var cell := float(GameManager.CELL_SIZE)
	var half: Vector2i = GameManager.MAP_HALF
	var origin := Vector2(-half.x * cell, -half.y * cell)
	var extent := Vector2(float(half.x * 2) * cell, float(half.y * 2) * cell)
	var rect := Rect2(origin, extent)
	draw_rect(rect, Color(0.27, 0.42, 0.24))
	var grid := Color(1, 1, 1, 0.08)
	for x in range(-half.x, half.x + 1):
		var px := float(x) * cell
		draw_line(Vector2(px, origin.y), Vector2(px, origin.y + extent.y), grid, 1.0)
	for y in range(-half.y, half.y + 1):
		var py := float(y) * cell
		draw_line(Vector2(origin.x, py), Vector2(origin.x + extent.x, py), grid, 1.0)
	draw_rect(rect, Color(0.9, 0.85, 0.55, 0.35), false, 4.0)
