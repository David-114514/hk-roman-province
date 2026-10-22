extends Node2D

## 單棟建築的外觀與產出。沒連回倉庫時暫停計時，避免恢復連接後一次補產。
## 原料不夠就跳過這一輪，不把進度存下來一次補產。
## 居民人數記在住宅上。拆除時由 Main 通知 GameManager 把人帶走。

var building_id: String = ""
var anchor_cell := Vector2i.ZERO
var residents: int = 0
var _def: Dictionary = {}
var _elapsed: float = 0.0
var _output_enabled := false
var _grid = null
var _cells: Array[Vector2i] = []


func setup(id: String, anchor: Vector2i, grid) -> void:
	building_id = id
	anchor_cell = anchor
	_grid = grid
	_def = GameManager.get_building_def(id)
	_cells = grid.footprint_cells(anchor, _def)
	_elapsed = 0.0
	_output_enabled = false
	residents = 0
	queue_redraw()


func occupied_cells() -> Array[Vector2i]:
	return _cells.duplicate()


func notify_registered() -> void:
	_set_output_enabled(true)


func shutdown() -> void:
	_set_output_enabled(false)


## 手動升級。呼叫前要已扣過升級成本。原居民轉為市民，格子不變。
func upgrade_to(new_id: String) -> void:
	shutdown()
	GameManager.unregister_building(building_id)
	var moved := residents
	building_id = new_id
	_def = GameManager.get_building_def(new_id)
	_elapsed = 0.0
	if _grid != null:
		for cell in _cells:
			_grid.relabel(cell, building_id)
	GameManager.register_building(building_id)
	GameManager.convert_plebs_to_citizens(moved)
	notify_registered()
	queue_redraw()


func info_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(_def.get("display_name", building_id)))
	var input_name := str(_def.get("input_resource", ""))
	var input_amount := int(_def.get("input_amount", 0))
	if input_name != "" and input_amount > 0:
		lines.append("消耗    %d %s" % [input_amount, GameManager.good_name(input_name)])
	var output_name := str(_def.get("output_resource", ""))
	var output_amount := int(_def.get("output_amount", 0))
	var capacity := int(_def.get("capacity", 0))
	if output_name == "population" or output_name == "citizens":
		lines.append("居民    %d / %d" % [residents, capacity])
	elif output_name != "" and output_amount > 0:
		var every := int(float(_def.get("interval", 0.0)))
		lines.append("產出    每 %d 秒 %d %s" % [every, output_amount, GameManager.good_name(output_name)])
	var linked: bool = _grid != null and _grid.is_building_linked(anchor_cell, _def)
	if str(_def.get("kind", "")) == "warehouse":
		lines.append("倉庫    路網起點")
		lines.append("狀態    啟用")
	else:
		lines.append("倉庫    " + ("已連接" if linked else "未連接"))
		if not _def.has("interval"):
			if str(building_id) == "market":
				lines.append("範圍    %d 格" % int(_def.get("radius", 5)))
				lines.append("狀態    " + ("供應中" if linked else "停工"))
			else:
				lines.append("狀態    " + ("啟用" if linked else "停工"))
		elif not linked:
			lines.append("狀態    停工")
		elif input_name != "" and not GameManager.has_stock(input_name, input_amount):
			lines.append("狀態    原料不足")
		else:
			lines.append("狀態    運作中")
	if capacity > 0:
		var covered: bool = _grid != null and _grid.market_covers(anchor_cell)
		if output_name == "citizens":
			lines.append("市場    " + ("已覆蓋" if covered else "未覆蓋，市民不增加"))
		else:
			lines.append("市場    " + ("已覆蓋" if covered else "未覆蓋，平民仍可成長"))
		lines.append("需求    " + GameManager.need_summary())
	return "\n".join(lines)


func _set_output_enabled(enabled: bool) -> void:
	if enabled == _output_enabled:
		return
	_output_enabled = enabled
	if _def.is_empty() or not _def.has("output_resource"):
		return
	GameManager.set_producer_active(building_id, enabled)


func _process(delta: float) -> void:
	if _def.is_empty():
		return
	var linked: bool = _grid != null and _grid.is_building_linked(anchor_cell, _def)
	_set_output_enabled(linked)
	if not _def.has("interval") or not linked:
		return
	_elapsed += delta
	var interval := float(_def["interval"])
	while _elapsed >= interval:
		_elapsed -= interval
		_produce()
	queue_redraw()


func _produce() -> void:
	var resource := str(_def.get("output_resource", ""))
	var amount := int(_def.get("output_amount", 0))
	if resource == "population":
		if GameManager.try_add_population(amount):
			residents += amount
		return
	if resource == "citizens":
		if _grid == null or not _grid.market_covers(anchor_cell):
			return
		if GameManager.try_add_citizen(amount):
			residents += amount
		return
	var input_name := str(_def.get("input_resource", ""))
	var input_amount := int(_def.get("input_amount", 0))
	if input_name != "" and input_amount > 0:
		if not GameManager.try_consume(input_name, input_amount):
			return
	if resource != "" and amount > 0:
		GameManager.add_good(resource, amount)


func _draw() -> void:
	if _def.is_empty() or _grid == null:
		return
	var size: Vector2 = _grid.visual_size(_def)
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect.grow(3.0), Color(0, 0, 0, 0.28))
	draw_rect(rect, _def["color"])
	draw_rect(rect, Color(1, 1, 1, 0.4), false, 2.0)
	if _def.has("interval"):
		var interval := float(_def["interval"])
		var progress := 0.0 if interval <= 0.0 else clampf(_elapsed / interval, 0.0, 1.0)
		var track := Rect2(rect.position.x + 6.0, rect.end.y - 12.0, rect.size.x - 12.0, 5.0)
		draw_rect(track, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(track.position, Vector2(track.size.x * progress, track.size.y)), Color(1, 1, 1, 0.92))
	var font := GameManager.get_ui_font()
	var text := str(_def["display_name"])
	var font_size := 15
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		Vector2(-text_size.x * 0.5, text_size.y * 0.15),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(1, 1, 1, 0.96)
	)
