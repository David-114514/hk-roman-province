extends Node

## 佔用與路網。斜角不相鄰，也不做 45 度建築。
## 倉庫是路網的起點。道路可以任意鋪，建築必須貼到一條能走回倉庫的路。

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var _occupied: Dictionary = {}
var _network_version := 0
var _cached_version := -1
var _connected_roads: Dictionary = {}


func world_to_cell(world: Vector2) -> Vector2i:
	var size := float(GameManager.CELL_SIZE)
	return Vector2i(floori(world.x / size), floori(world.y / size))


func cell_center(cell: Vector2i) -> Vector2:
	var size := float(GameManager.CELL_SIZE)
	return (Vector2(cell) + Vector2(0.5, 0.5)) * size


func footprint_cells(anchor: Vector2i, def: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size := GameManager.footprint_size(def)
	for x in size.x:
		for y in size.y:
			cells.append(anchor + Vector2i(x, y))
	return cells


func footprint_center(anchor: Vector2i, def: Dictionary) -> Vector2:
	var size := GameManager.footprint_size(def)
	return cell_center(anchor) + Vector2(float(size.x - 1), float(size.y - 1)) * float(GameManager.CELL_SIZE) * 0.5


func visual_size(def: Dictionary) -> Vector2:
	var fp := GameManager.footprint_size(def)
	var cell := float(GameManager.CELL_SIZE)
	return Vector2(fp.x * cell - 8.0, fp.y * cell - 8.0)


func visual_origin(anchor: Vector2i, def: Dictionary) -> Vector2:
	return footprint_center(anchor, def) - visual_size(def) * 0.5


## 現在只檢查邊界。高度圖、海域之後在這裡返回 false。
func is_land(cell: Vector2i) -> bool:
	var half: Vector2i = GameManager.MAP_HALF
	return absi(cell.x) < half.x and absi(cell.y) < half.y


func occupant(cell: Vector2i) -> String:
	return str(_occupied.get(cell, ""))


func rejection_reason(anchor: Vector2i, def: Dictionary) -> String:
	var cells := footprint_cells(anchor, def)
	for cell in cells:
		if not is_land(cell):
			return "超出地圖範圍"
		if _occupied.has(cell):
			return "這裡已經有東西"
	var kind := str(def.get("kind", ""))
	if kind == "road" or kind == "warehouse":
		return ""
	if not _touches_road(cells):
		return "建築必須貼著道路"
	if not _touches_connected_road(cells):
		return "必須連到倉庫"
	return ""


func mark(cell: Vector2i, id: String) -> void:
	_occupied[cell] = id
	if id == "road" or id == "warehouse":
		_network_version += 1


func clear(cell: Vector2i) -> void:
	var previous := occupant(cell)
	_occupied.erase(cell)
	if previous == "road" or previous == "warehouse":
		_network_version += 1


func is_building_linked(anchor: Vector2i, def: Dictionary) -> bool:
	if str(def.get("kind", "")) == "warehouse":
		return true
	return _touches_connected_road(footprint_cells(anchor, def))


func relabel(cell: Vector2i, id: String) -> void:
	if not _occupied.has(cell):
		return
	_occupied[cell] = id


func road_connected(cell: Vector2i) -> bool:
	_ensure_network()
	return _connected_roads.has(cell)


## 市場範圍用切比雪夫距離，斜角也算覆蓋。這是服務範圍，不是道路連接。
## 市場自己斷路時不提供覆蓋。平民成長不看市場，市民成長和升級要看。
func market_covers(cell: Vector2i) -> bool:
	var def := GameManager.get_building_def("market")
	var radius := int(def.get("radius", 5))
	for key in _occupied.keys():
		var origin: Vector2i = key
		if occupant(origin) != "market":
			continue
		if not is_building_linked(origin, def):
			continue
		if absi(cell.x - origin.x) <= radius and absi(cell.y - origin.y) <= radius:
			return true
	return false


func _touches_road(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		for step in NEIGHBORS:
			if occupant(cell + step) == "road":
				return true
	return false


func _touches_connected_road(cells: Array[Vector2i]) -> bool:
	_ensure_network()
	for cell in cells:
		for step in NEIGHBORS:
			if _connected_roads.has(cell + step):
				return true
	return false


func _ensure_network() -> void:
	if _cached_version == _network_version:
		return
	_cached_version = _network_version
	_connected_roads.clear()
	var queue: Array[Vector2i] = []
	for key in _occupied.keys():
		var cell: Vector2i = key
		if occupant(cell) != "warehouse":
			continue
		for step in NEIGHBORS:
			var road_cell: Vector2i = cell + step
			if occupant(road_cell) == "road" and not _connected_roads.has(road_cell):
				_connected_roads[road_cell] = true
				queue.append(road_cell)
	var index := 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		for step in NEIGHBORS:
			var nxt: Vector2i = current + step
			if occupant(nxt) != "road" or _connected_roads.has(nxt):
				continue
			_connected_roads[nxt] = true
			queue.append(nxt)
