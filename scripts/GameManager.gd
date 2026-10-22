extends Node

## 資源、建築目錄、稅收與供需都集中在這裡。
## 平民成長仍只看食物產量，避免開局沒工坊就沒有第一個居民。工具只影響稅收。
## 市民要食物、布料、葡萄酒的庫存和產量都夠才會增加，而且住宅要在市場範圍內（由建築自己檢查）。
## 稅收：沒有居民或食物不夠，這一輪不收。工具不夠，平民稅減半。
## 布料或葡萄酒不夠時，市民改繳平民稅額；若工具也不夠，再減半。不完全停收，避免卡死。
## 升級是手動的。市民住宅不在建造欄，只能由平民住宅升級。

signal resources_changed
signal tax_collected(amount: int)

const START_MONEY := 200
const START_POPULATION := 0
const START_FOOD := 0
const START_WOOD := 24
const START_TOOLS := 0
const START_STONE := 8

## 每 5 個人，每秒 1 份食物或工具。布料和葡萄酒只算市民，每 10 人每秒 1 份。
const POPULATION_PER_FOOD := 5.0
const POPULATION_PER_TOOL := 5.0
const POPULATION_PER_CLOTH := 10.0
const POPULATION_PER_WINE := 10.0

const TAX_INTERVAL := 10.0
const TAX_PER_PERSON := 2
const CITIZEN_TAX_PER_PERSON := 6

const CELL_SIZE := 64
const MAP_HALF := Vector2i(36, 28)

const GOOD_NAMES := {
	"food": "食物",
	"wood": "木材",
	"tools": "工具",
	"stone": "石材",
	"wool": "羊毛",
	"cloth": "布料",
	"grapes": "葡萄",
	"wine": "葡萄酒",
	"population": "平民",
	"citizens": "市民",
}

const BUILDING_ORDER: Array[String] = [
	"road", "warehouse", "market", "housing", "farm", "lumber", "workshop",
	"quarry", "pasture", "weaver", "vineyard", "winery",
]

const BUILDINGS := {
	"road": {
		"id": "road",
		"display_name": "道路",
		"kind": "road",
		"cost": 1,
		"wood_cost": 0,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.64, 0.56, 0.42),
	},
	"warehouse": {
		"id": "warehouse",
		"display_name": "倉庫",
		"kind": "warehouse",
		"cost": 80,
		"wood_cost": 8,
		"stone_cost": 0,
		"width": 2,
		"height": 1,
		"color": Color(0.62, 0.66, 0.7),
	},
	"market": {
		"id": "market",
		"display_name": "市場",
		"kind": "building",
		"cost": 40,
		"wood_cost": 4,
		"stone_cost": 4,
		"width": 1,
		"height": 1,
		"radius": 5,
		"color": Color(0.86, 0.72, 0.28),
	},
	"housing": {
		"id": "housing",
		"display_name": "住宅",
		"kind": "building",
		"cost": 40,
		"wood_cost": 5,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.23, 0.46, 0.9),
		"capacity": 4,
		"output_resource": "population",
		"output_amount": 1,
		"interval": 10.0,
	},
	"citizen": {
		"id": "citizen",
		"display_name": "市民住宅",
		"kind": "building",
		"cost": 60,
		"wood_cost": 4,
		"stone_cost": 6,
		"width": 1,
		"height": 1,
		"color": Color(0.45, 0.32, 0.72),
		"capacity": 6,
		"output_resource": "citizens",
		"output_amount": 1,
		"interval": 10.0,
	},
	"farm": {
		"id": "farm",
		"display_name": "農場",
		"kind": "building",
		"cost": 25,
		"wood_cost": 4,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.48, 0.78, 0.26),
		"output_resource": "food",
		"output_amount": 5,
		"interval": 8.0,
	},
	"lumber": {
		"id": "lumber",
		"display_name": "伐木場",
		"kind": "building",
		"cost": 25,
		"wood_cost": 5,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.52, 0.36, 0.2),
		"output_resource": "wood",
		"output_amount": 2,
		"interval": 6.0,
	},
	"workshop": {
		"id": "workshop",
		"display_name": "工坊",
		"kind": "building",
		"cost": 35,
		"wood_cost": 6,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.72, 0.48, 0.28),
		"output_resource": "tools",
		"output_amount": 4,
		"interval": 4.0,
	},
	"quarry": {
		"id": "quarry",
		"display_name": "採石場",
		"kind": "building",
		"cost": 30,
		"wood_cost": 6,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.55, 0.56, 0.58),
		"output_resource": "stone",
		"output_amount": 2,
		"interval": 8.0,
	},
	"pasture": {
		"id": "pasture",
		"display_name": "牧場",
		"kind": "building",
		"cost": 30,
		"wood_cost": 4,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.62, 0.78, 0.42),
		"output_resource": "wool",
		"output_amount": 3,
		"interval": 5.0,
	},
	"weaver": {
		"id": "weaver",
		"display_name": "紡織工坊",
		"kind": "building",
		"cost": 45,
		"wood_cost": 6,
		"stone_cost": 4,
		"width": 1,
		"height": 1,
		"color": Color(0.62, 0.48, 0.78),
		"input_resource": "wool",
		"input_amount": 2,
		"output_resource": "cloth",
		"output_amount": 2,
		"interval": 4.0,
	},
	"vineyard": {
		"id": "vineyard",
		"display_name": "葡萄園",
		"kind": "building",
		"cost": 35,
		"wood_cost": 4,
		"stone_cost": 0,
		"width": 1,
		"height": 1,
		"color": Color(0.45, 0.62, 0.32),
		"output_resource": "grapes",
		"output_amount": 3,
		"interval": 5.0,
	},
	"winery": {
		"id": "winery",
		"display_name": "釀酒坊",
		"kind": "building",
		"cost": 55,
		"wood_cost": 6,
		"stone_cost": 6,
		"width": 1,
		"height": 1,
		"color": Color(0.62, 0.24, 0.32),
		"input_resource": "grapes",
		"input_amount": 2,
		"output_resource": "wine",
		"output_amount": 2,
		"interval": 5.0,
	},
}

var money: int = START_MONEY
var population: int = START_POPULATION
var pleb_population: int = 0
var citizen_population: int = 0
var food: int = START_FOOD
var wood: int = START_WOOD
var tools: int = START_TOOLS
var stone: int = START_STONE
var wool: int = 0
var cloth: int = 0
var grapes: int = 0
var wine: int = 0
var housing_capacity: int = 0
var citizen_capacity: int = 0
var food_per_second: float = 0.0
var wood_per_second: float = 0.0
var tools_per_second: float = 0.0
var stone_per_second: float = 0.0
var wool_per_second: float = 0.0
var cloth_per_second: float = 0.0
var grapes_per_second: float = 0.0
var wine_per_second: float = 0.0

var _food_fraction: float = 0.0
var _tool_fraction: float = 0.0
var _cloth_fraction: float = 0.0
var _wine_fraction: float = 0.0
var _tax_wait: float = 0.0
var _ui_font: Font


func get_building_ids() -> Array[String]:
	return BUILDING_ORDER.duplicate()


func get_building_def(id: String) -> Dictionary:
	if not BUILDINGS.has(id):
		return {}
	return BUILDINGS[id].duplicate()


func footprint_size(def: Dictionary) -> Vector2i:
	return Vector2i(int(def.get("width", 1)), int(def.get("height", 1)))


func good_name(resource: String) -> String:
	return str(GOOD_NAMES.get(resource, resource))


func get_ui_font() -> Font:
	if _ui_font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray([
			"Microsoft JhengHei UI",
			"Microsoft JhengHei",
			"Microsoft YaHei UI",
			"Microsoft YaHei",
		])
		system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_ui_font = system
	return _ui_font


func try_spend(cost: int) -> bool:
	if cost < 0 or money < cost:
		return false
	money -= cost
	resources_changed.emit()
	return true


## 三種成本都夠才一起扣。
func try_pay(money_cost: int, wood_cost: int, stone_cost: int = 0) -> String:
	if money_cost < 0 or wood_cost < 0 or stone_cost < 0:
		return "成本不正確"
	if money < money_cost:
		return "金錢不足"
	if wood < wood_cost:
		return "木材不足"
	if stone < stone_cost:
		return "石材不足"
	money -= money_cost
	wood -= wood_cost
	stone -= stone_cost
	resources_changed.emit()
	return ""


func register_building(id: String) -> void:
	_adjust_capacity(id, 1)
	resources_changed.emit()


func unregister_building(id: String) -> void:
	_adjust_capacity(id, -1)
	resources_changed.emit()


func set_producer_active(id: String, active: bool) -> void:
	_adjust_output(id, 1 if active else -1)
	resources_changed.emit()


func _adjust_capacity(id: String, sign: int) -> void:
	var def := get_building_def(id)
	if def.is_empty():
		return
	var amount := int(def.get("capacity", 0)) * sign
	if id == "citizen":
		citizen_capacity = maxi(0, citizen_capacity + amount)
	else:
		housing_capacity = maxi(0, housing_capacity + amount)


## 產量只看建築有沒有連著倉庫。原料短暫不夠時這一輪不做，但不把每秒產量改成 0。
func _adjust_output(id: String, sign: int) -> void:
	var def := get_building_def(id)
	if def.is_empty() or not def.has("output_resource"):
		return
	var interval := float(def.get("interval", 0.0))
	if interval <= 0.0:
		return
	var resource := str(def["output_resource"])
	if resource == "population" or resource == "citizens":
		return
	var rate := float(int(def["output_amount"])) / interval * float(sign)
	match resource:
		"food":
			food_per_second = maxf(0.0, food_per_second + rate)
		"wood":
			wood_per_second = maxf(0.0, wood_per_second + rate)
		"tools":
			tools_per_second = maxf(0.0, tools_per_second + rate)
		"stone":
			stone_per_second = maxf(0.0, stone_per_second + rate)
		"wool":
			wool_per_second = maxf(0.0, wool_per_second + rate)
		"cloth":
			cloth_per_second = maxf(0.0, cloth_per_second + rate)
		"grapes":
			grapes_per_second = maxf(0.0, grapes_per_second + rate)
		"wine":
			wine_per_second = maxf(0.0, wine_per_second + rate)
		_:
			pass


func _sync_total() -> void:
	population = pleb_population + citizen_population


## 空房、手上有食物、加人後的吃食不超過農場產量。工具不擋平民。
func try_add_population(amount: int) -> bool:
	if amount <= 0 or food <= 0:
		return false
	if pleb_population + amount > housing_capacity:
		return false
	var demand := float(population + amount) / POPULATION_PER_FOOD
	if demand > food_per_second:
		return false
	pleb_population += amount
	_sync_total()
	resources_changed.emit()
	return true


## 市民要空位、食物、布料、葡萄酒。市場範圍由住宅自己先檢查。
func try_add_citizen(amount: int) -> bool:
	if amount <= 0 or food <= 0 or cloth <= 0 or wine <= 0:
		return false
	if citizen_population + amount > citizen_capacity:
		return false
	if float(population + amount) / POPULATION_PER_FOOD > food_per_second:
		return false
	if float(citizen_population + amount) / POPULATION_PER_CLOTH > cloth_per_second:
		return false
	if float(citizen_population + amount) / POPULATION_PER_WINE > wine_per_second:
		return false
	citizen_population += amount
	_sync_total()
	resources_changed.emit()
	return true


func convert_plebs_to_citizens(count: int) -> void:
	var moved := mini(count, pleb_population)
	if moved <= 0:
		return
	pleb_population -= moved
	citizen_population += moved
	_sync_total()
	resources_changed.emit()


func remove_residents(building_id: String, count: int) -> void:
	if count <= 0:
		return
	if building_id == "citizen":
		citizen_population = maxi(0, citizen_population - count)
	else:
		pleb_population = maxi(0, pleb_population - count)
	_sync_total()
	if population <= 0:
		_food_fraction = 0.0
		_tool_fraction = 0.0
		_cloth_fraction = 0.0
		_wine_fraction = 0.0
	resources_changed.emit()


func add_food(amount: int) -> void:
	add_good("food", amount)


func add_good(resource: String, amount: int) -> void:
	if amount == 0:
		return
	if not _change_stock(resource, amount):
		return
	resources_changed.emit()


func try_consume(resource: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if stock_of(resource) < amount:
		return false
	_change_stock(resource, -amount)
	resources_changed.emit()
	return true


func has_stock(resource: String, amount: int) -> bool:
	return stock_of(resource) >= amount


func stock_of(resource: String) -> int:
	match resource:
		"food":
			return food
		"wood":
			return wood
		"tools":
			return tools
		"stone":
			return stone
		"wool":
			return wool
		"cloth":
			return cloth
		"grapes":
			return grapes
		"wine":
			return wine
		_:
			return 0


func _change_stock(resource: String, amount: int) -> bool:
	match resource:
		"food":
			food = maxi(0, food + amount)
		"wood":
			wood = maxi(0, wood + amount)
		"tools":
			tools = maxi(0, tools + amount)
		"stone":
			stone = maxi(0, stone + amount)
		"wool":
			wool = maxi(0, wool + amount)
		"cloth":
			cloth = maxi(0, cloth + amount)
		"grapes":
			grapes = maxi(0, grapes + amount)
		"wine":
			wine = maxi(0, wine + amount)
		_:
			return false
	return true


func tax_block_reason() -> String:
	if population <= 0:
		return "尚無居民"
	var food_demand := float(population) / POPULATION_PER_FOOD
	if food <= 0 or food_per_second + 0.0001 < food_demand:
		return "食物不足"
	return ""


func tools_are_short() -> bool:
	if population <= 0:
		return false
	var tool_demand := float(population) / POPULATION_PER_TOOL
	return tools <= 0 or tools_per_second + 0.0001 < tool_demand


func cloth_is_short() -> bool:
	if citizen_population <= 0:
		return false
	var demand := float(citizen_population) / POPULATION_PER_CLOTH
	return cloth <= 0 or cloth_per_second + 0.0001 < demand


func wine_is_short() -> bool:
	if citizen_population <= 0:
		return false
	var demand := float(citizen_population) / POPULATION_PER_WINE
	return wine <= 0 or wine_per_second + 0.0001 < demand


func need_summary() -> String:
	if population <= 0:
		return "尚無居民"
	var missing: PackedStringArray = PackedStringArray()
	if tax_block_reason() == "食物不足":
		missing.append("食物")
	if tools_are_short():
		missing.append("工具")
	if cloth_is_short():
		missing.append("布料")
	if wine_is_short():
		missing.append("葡萄酒")
	if missing.is_empty():
		return "需求滿足"
	return "缺少" + "、".join(missing)


func tax_amount_if_due() -> int:
	if tax_block_reason() != "":
		return 0
	var plebs := pleb_population
	var citizens := citizen_population
	# 舊測試會直接改 population。沒有分開計數時，全部當作平民。
	if plebs + citizens <= 0 and population > 0:
		plebs = population
	var pleb_tax := plebs * TAX_PER_PERSON
	if tools_are_short():
		pleb_tax = int(pleb_tax / 2)
	var each := CITIZEN_TAX_PER_PERSON
	if cloth_is_short() or wine_is_short():
		each = TAX_PER_PERSON
	if tools_are_short():
		each = int(each / 2)
	return pleb_tax + citizens * each


func _process(delta: float) -> void:
	_consume_food(delta)
	_consume_tools(delta)
	_consume_cloth(delta)
	_consume_wine(delta)
	if delta <= 0.0:
		return
	_tax_wait += delta
	while _tax_wait >= TAX_INTERVAL:
		_tax_wait -= TAX_INTERVAL
		_collect_tax()


func _collect_tax() -> void:
	var amount := tax_amount_if_due()
	if amount <= 0:
		resources_changed.emit()
		return
	money += amount
	resources_changed.emit()
	tax_collected.emit(amount)


func _consume_food(delta: float) -> void:
	if population <= 0 or food <= 0 or delta <= 0.0:
		return
	_food_fraction = _drain(float(population) / POPULATION_PER_FOOD, delta, _food_fraction, "food")
	if food <= 0:
		_food_fraction = 0.0


func _consume_tools(delta: float) -> void:
	if population <= 0 or tools <= 0 or delta <= 0.0:
		return
	_tool_fraction = _drain(float(population) / POPULATION_PER_TOOL, delta, _tool_fraction, "tools")
	if tools <= 0:
		_tool_fraction = 0.0


func _consume_cloth(delta: float) -> void:
	if citizen_population <= 0 or cloth <= 0 or delta <= 0.0:
		return
	_cloth_fraction = _drain(float(citizen_population) / POPULATION_PER_CLOTH, delta, _cloth_fraction, "cloth")
	if cloth <= 0:
		_cloth_fraction = 0.0


func _consume_wine(delta: float) -> void:
	if citizen_population <= 0 or wine <= 0 or delta <= 0.0:
		return
	_wine_fraction = _drain(float(citizen_population) / POPULATION_PER_WINE, delta, _wine_fraction, "wine")
	if wine <= 0:
		_wine_fraction = 0.0


## 回傳剩下的小數庫存。整數被扣掉時會通知介面。
func _drain(rate: float, delta: float, fraction: float, resource: String) -> float:
	var pool := fraction + rate * delta
	var changed := false
	while pool >= 1.0 and stock_of(resource) > 0:
		pool -= 1.0
		_change_stock(resource, -1)
		changed = true
	if stock_of(resource) <= 0:
		pool = 0.0
		changed = true
	if changed:
		resources_changed.emit()
	return pool
