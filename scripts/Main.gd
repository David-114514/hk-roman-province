extends Node2D

const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")
const MOVE_SPEED := 720.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.4
const ZOOM_STEP := 0.12
const CAMERA_LIMIT := Vector2(2200, 1600)
const MESSAGE_SECONDS := 2.0
const START_WAREHOUSE := Vector2i(-1, 0)

@onready var camera: Camera2D = $Camera2D
@onready var buildings_root: Node2D = $World/Buildings
@onready var city_grid = $World/CityGrid
@onready var roads = $World/Roads
@onready var preview = $World/Preview
@onready var ui_root: Control = $UI/Root
@onready var money_label: Label = $UI/Root/TopLeft/Panel/VBox/MoneyLabel
@onready var population_label: Label = $UI/Root/TopLeft/Panel/VBox/PopulationLabel
@onready var food_label: Label = $UI/Root/TopLeft/Panel/VBox/FoodLabel
@onready var wood_label: Label = $UI/Root/TopLeft/Panel/VBox/WoodLabel
@onready var tools_label: Label = $UI/Root/TopLeft/Panel/VBox/ToolsLabel
@onready var tax_label: Label = $UI/Root/TopLeft/Panel/VBox/TaxLabel
@onready var help_label: Label = $UI/Root/TopLeft/Panel/VBox/HelpLabel
@onready var build_rows: VBoxContainer = $UI/Root/BottomBar/Margin/BuildRows
@onready var message_label: Label = $UI/Root/MessageLabel
@onready var top_panel: PanelContainer = $UI/Root/TopLeft/Panel
@onready var bottom_panel: PanelContainer = $UI/Root/BottomBar

var _selected_id: String = "road"
var _message_left: float = 0.0
var _tax_flash_left: float = 0.0
var _tax_flash_amount: int = 0
var _panning := false
var _road_dragging := false
var _has_drag_cell := false
var _last_drag_cell := Vector2i.ZERO
var _last_notice := ""
var _buttons: Dictionary = {}
var _nodes_by_cell: Dictionary = {}
var _inspected = null
var _info_panel: PanelContainer
var _info_label: Label
var _upgrade_button: Button
var citizen_label: Label
var stone_label: Label
var wool_label: Label
var cloth_label: Label
var grapes_label: Label
var wine_label: Label
var need_label: Label


func _ready() -> void:
	camera.make_current()
	_apply_theme()
	_style_panel(top_panel)
	_style_panel(bottom_panel)
	_create_build_buttons()
	_create_extra_labels()
	_create_info_panel()
	GameManager.resources_changed.connect(_refresh_resources)
	GameManager.tax_collected.connect(_on_tax_collected)
	_place_starting_warehouse()
	_refresh_resources()
	_refresh_build_buttons()
	help_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	help_label.text = "建築須以道路連回倉庫。右鍵取消後，左鍵查看建築。\n市民要布料、葡萄酒和市場。拆除退木材與石材，不退金錢。"
	show_message("中央已有倉庫。先鋪路，再蓋伐木場和農場")


func _process(delta: float) -> void:
	_move_camera(delta)
	_update_preview()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message_label.text = ""
	if _tax_flash_left > 0.0:
		_tax_flash_left -= delta
		if _tax_flash_left <= 0.0:
			_refresh_resources()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		if event.pressed:
			_road_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_road_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_begin_stroke(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_road_dragging = false
			_cancel_build()
	elif event is InputEventMouseMotion and _panning:
		var stretch := get_viewport().get_screen_transform().get_scale()
		camera.position -= event.relative / (camera.zoom * stretch)
		_clamp_camera()
	elif event is InputEventMouseMotion and _road_dragging:
		drag_place_at(get_global_mouse_position())


func select_building(id: String) -> void:
	if id == "demolish":
		_selected_id = id
		_road_dragging = false
		_refresh_build_buttons()
		show_message("拆除模式：點擊建築或道路。不退金錢，退回木材和石材")
		return
	var def := GameManager.get_building_def(id)
	if def.is_empty():
		return
	_selected_id = id
	_road_dragging = false
	_refresh_build_buttons()
	if str(def["kind"]) == "road":
		show_message("目前建造：道路（%s）。按住左鍵可連續鋪設" % _cost_text(def))
	elif str(def["kind"]) == "warehouse":
		show_message("目前建造：倉庫（%s）。新倉庫自己就是路網起點" % _cost_text(def))
	else:
		show_message("目前建造：%s（%s），道路必須連到倉庫" % [def["display_name"], _cost_text(def)])


func try_place_at(world_pos: Vector2) -> bool:
	_last_notice = ""
	return _try_place_cell(city_grid.world_to_cell(world_pos), false)


func try_demolish_at(world_pos: Vector2) -> bool:
	_last_notice = ""
	return _demolish_cell(city_grid.world_to_cell(world_pos), false)


func drag_place_at(world_pos: Vector2) -> void:
	if _selected_kind() != "road" or not _has_drag_cell:
		return
	var cell: Vector2i = city_grid.world_to_cell(world_pos)
	for step in _grid_line(_last_drag_cell, cell):
		_try_place_cell(step, true)
	_last_drag_cell = cell


func _begin_stroke(world_pos: Vector2) -> void:
	_last_notice = ""
	var cell: Vector2i = city_grid.world_to_cell(world_pos)
	if _selected_id == "demolish":
		_demolish_cell(cell, false)
		_road_dragging = false
		_has_drag_cell = false
		return
	if _selected_id == "":
		_inspect_cell(cell)
		_road_dragging = false
		_has_drag_cell = false
		return
	_try_place_cell(cell, false)
	_has_drag_cell = true
	_last_drag_cell = cell
	_road_dragging = _selected_kind() == "road"


func _cancel_build() -> void:
	if _selected_id == "":
		return
	_selected_id = ""
	_road_dragging = false
	_has_drag_cell = false
	_refresh_build_buttons()
	preview.hide_ghost()
	show_message("已取消建造")


func _place_starting_warehouse() -> void:
	_spawn_building(START_WAREHOUSE, GameManager.get_building_def("warehouse"))


func _try_place_cell(cell: Vector2i, quiet_repeat: bool) -> bool:
	var def := GameManager.get_building_def(_selected_id)
	if def.is_empty():
		_notice("請先選擇要建造的東西", quiet_repeat)
		return false
	var reason := str(city_grid.rejection_reason(cell, def))
	if reason != "":
		_notice(reason, quiet_repeat)
		return false
	var pay_reason := GameManager.try_pay(int(def.get("cost", 0)), int(def.get("wood_cost", 0)), int(def.get("stone_cost", 0)))
	if pay_reason != "":
		_notice("%s，無法放置%s" % [pay_reason, def["display_name"]], quiet_repeat)
		return false
	if str(def["kind"]) == "road":
		city_grid.mark(cell, "road")
		roads.add_cell(cell)
	else:
		_spawn_building(cell, def)
	_notice("已放置%s" % def["display_name"], quiet_repeat)
	return true


## 不退金錢。退回木材和石材，避免材料被花光後蓋不出下一階建築。
## 居民記在住宅上，拆除會讓這棟的居民離開。
func _demolish_cell(cell: Vector2i, quiet_repeat: bool) -> bool:
	var id: String = city_grid.occupant(cell)
	if id == "":
		_notice("這裡沒有東西", quiet_repeat)
		return false
	if id == "road":
		city_grid.clear(cell)
		roads.remove_cell(cell)
		if _inspected == null:
			_clear_inspect()
		_notice("已拆除道路", quiet_repeat)
		return true
	var node = _nodes_by_cell.get(cell, null)
	if node == null:
		_notice("這裡沒有東西", quiet_repeat)
		return false
	var building_id := str(node.building_id)
	var display := str(node._def.get("display_name", building_id))
	var wood_back := int(node._def.get("wood_cost", 0))
	var stone_back := int(node._def.get("stone_cost", 0))
	var people := int(node.residents)
	for occupied in node.occupied_cells():
		city_grid.clear(occupied)
		_nodes_by_cell.erase(occupied)
	node.shutdown()
	if people > 0:
		GameManager.remove_residents(building_id, people)
	GameManager.unregister_building(building_id)
	if _inspected == node:
		_clear_inspect()
	node.queue_free()
	if wood_back > 0:
		GameManager.add_good("wood", wood_back)
	if stone_back > 0:
		GameManager.add_good("stone", stone_back)
	var refund := _refund_text(wood_back, stone_back)
	if refund == "":
		_notice("已拆除%s" % display, quiet_repeat)
	else:
		_notice("已拆除%s，退回 %s" % [display, refund], quiet_repeat)
	_refresh_resources()
	return true


func _spawn_building(anchor: Vector2i, def: Dictionary) -> void:
	var id := str(def["id"])
	var node = BUILDING_SCENE.instantiate()
	node.setup(id, anchor, city_grid)
	node.position = city_grid.footprint_center(anchor, def)
	buildings_root.add_child(node)
	for cell in city_grid.footprint_cells(anchor, def):
		city_grid.mark(cell, id)
		_nodes_by_cell[cell] = node
	GameManager.register_building(id)
	node.notify_registered()


func _notice(text: String, quiet_repeat: bool) -> void:
	if quiet_repeat and text == _last_notice:
		return
	_last_notice = text
	show_message(text)


func _selected_kind() -> String:
	var def := GameManager.get_building_def(_selected_id)
	if def.is_empty():
		return ""
	return str(def["kind"])


func _update_preview() -> void:
	if _selected_id == "demolish":
		_update_demolish_preview()
		return
	var def := GameManager.get_building_def(_selected_id)
	if def.is_empty() or _pointer_blocked():
		preview.hide_ghost()
		return
	var cell: Vector2i = city_grid.world_to_cell(get_global_mouse_position())
	var valid: bool = str(city_grid.rejection_reason(cell, def)) == ""
	if valid:
		var pay_reason := ""
		if GameManager.money < int(def.get("cost", 0)):
			pay_reason = "金錢不足"
		elif GameManager.wood < int(def.get("wood_cost", 0)):
			pay_reason = "木材不足"
		elif GameManager.stone < int(def.get("stone_cost", 0)):
			pay_reason = "石材不足"
		valid = pay_reason == ""
	var origin: Vector2 = city_grid.visual_origin(cell, def)
	preview.set_ghost(origin, city_grid.visual_size(def), def["color"] as Color, valid)


func _update_demolish_preview() -> void:
	if _pointer_blocked():
		preview.hide_ghost()
		return
	var cell: Vector2i = city_grid.world_to_cell(get_global_mouse_position())
	if city_grid.occupant(cell) == "":
		preview.hide_ghost()
		return
	var origin := Vector2(cell) * float(GameManager.CELL_SIZE)
	var size := Vector2(GameManager.CELL_SIZE, GameManager.CELL_SIZE)
	preview.set_ghost(origin, size, Color(0.85, 0.25, 0.2), false)


func _pointer_blocked() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _grid_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0 := start.x
	var y0 := start.y
	var x1 := end.x
	var y1 := end.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points


func show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	message_label.text = text
	_message_left = seconds


func _on_tax_collected(amount: int) -> void:
	_tax_flash_amount = amount
	_tax_flash_left = 2.0
	_refresh_resources()


func _move_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return
	camera.position += dir.normalized() * MOVE_SPEED * delta / camera.zoom.x
	_clamp_camera()


func _zoom_by(step: float) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(old_zoom + step, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var viewport_size := get_viewport_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	var world_before := camera.position + (mouse_screen - viewport_size * 0.5) / old_zoom
	camera.zoom = Vector2.ONE * new_zoom
	camera.position = world_before - (mouse_screen - viewport_size * 0.5) / new_zoom
	_clamp_camera()


func _clamp_camera() -> void:
	camera.position = camera.position.clamp(-CAMERA_LIMIT, CAMERA_LIMIT)


func _cost_text(def: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d金" % int(def.get("cost", 0)))
	var wood_cost := int(def.get("wood_cost", 0))
	var stone_cost := int(def.get("stone_cost", 0))
	if wood_cost > 0:
		parts.append("%d木" % wood_cost)
	if stone_cost > 0:
		parts.append("%d石" % stone_cost)
	return " ".join(parts)


func _refund_text(wood_back: int, stone_back: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if wood_back > 0:
		parts.append("%d 木材" % wood_back)
	if stone_back > 0:
		parts.append("%d 石材" % stone_back)
	return "、".join(parts)


func _new_resource_label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	return label


func _create_extra_labels() -> void:
	var box: Node = population_label.get_parent()
	box.add_theme_constant_override("separation", 1)
	var title: Node = box.get_child(0)
	citizen_label = _new_resource_label(Color(0.78, 0.8, 1.0))
	stone_label = _new_resource_label(Color(0.75, 0.78, 0.82))
	wool_label = _new_resource_label(Color(0.9, 0.9, 0.82))
	cloth_label = _new_resource_label(Color(0.78, 0.7, 0.9))
	grapes_label = _new_resource_label(Color(0.7, 0.85, 0.55))
	wine_label = _new_resource_label(Color(0.9, 0.55, 0.62))
	need_label = _new_resource_label(Color(1.0, 0.84, 0.55))
	var extra: Array = [citizen_label, stone_label, wool_label, cloth_label, grapes_label, wine_label, need_label]
	for label in extra:
		box.add_child(label)
	var ordered: Array = [
		title, money_label, population_label, citizen_label,
		food_label, tools_label, wood_label, stone_label,
		wool_label, cloth_label, grapes_label, wine_label,
		need_label, tax_label, help_label,
	]
	for i in ordered.size():
		box.move_child(ordered[i], i)


func _create_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.offset_left = -430.0
	_info_panel.offset_right = -16.0
	_info_panel.offset_top = 16.0
	_info_panel.offset_bottom = 390.0
	_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(_info_panel)
	_style_panel(_info_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_info_panel.add_child(box)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.9))
	box.add_child(_info_label)
	_upgrade_button = Button.new()
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.custom_minimum_size = Vector2(280, 44)
	_upgrade_button.add_theme_font_size_override("font_size", 16)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	box.add_child(_upgrade_button)
	_info_panel.visible = false


func _inspect_cell(cell: Vector2i) -> void:
	var id: String = city_grid.occupant(cell)
	if id == "":
		_clear_inspect()
		return
	if id == "road":
		_inspected = null
		var linked: bool = city_grid.road_connected(cell)
		_show_info("道路\n%s" % ("已連回倉庫" if linked else "尚未連回倉庫"), false)
		return
	var node = _nodes_by_cell.get(cell, null)
	if node == null:
		_clear_inspect()
		return
	_inspected = node
	_show_info(str(node.info_text()), str(node.building_id) == "housing")


func _show_info(text: String, can_upgrade: bool) -> void:
	_info_label.text = text
	_upgrade_button.visible = can_upgrade
	if can_upgrade:
		var def := GameManager.get_building_def("citizen")
		_upgrade_button.text = "升級為市民（%s）" % _cost_text(def)
	_info_panel.visible = true


func _clear_inspect() -> void:
	_inspected = null
	if _info_panel != null:
		_info_panel.visible = false


func _refresh_info() -> void:
	if _info_panel == null or not _info_panel.visible or _inspected == null:
		return
	if not is_instance_valid(_inspected):
		_clear_inspect()
		return
	_info_label.text = str(_inspected.info_text())
	_upgrade_button.visible = str(_inspected.building_id) == "housing"


func _on_upgrade_pressed() -> void:
	if _inspected == null or not is_instance_valid(_inspected):
		return
	if str(_inspected.building_id) != "housing":
		show_message("只有平民住宅可以升級")
		return
	if not city_grid.is_building_linked(_inspected.anchor_cell, _inspected._def):
		show_message("住宅必須連到倉庫才能升級")
		return
	if not city_grid.market_covers(_inspected.anchor_cell):
		show_message("市場要覆蓋這棟住宅才能升級")
		return
	var def := GameManager.get_building_def("citizen")
	var reason := GameManager.try_pay(int(def.get("cost", 0)), int(def.get("wood_cost", 0)), int(def.get("stone_cost", 0)))
	if reason != "":
		show_message("%s，無法升級" % reason)
		return
	_inspected.upgrade_to("citizen")
	show_message("已升級為市民住宅")
	_refresh_info()


func _create_build_buttons() -> void:
	var rows: Array = [
		["road", "warehouse", "market", "demolish"],
		["housing", "farm", "lumber", "workshop"],
		["quarry", "pasture", "weaver"],
		["vineyard", "winery"],
	]
	for row_ids in rows:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		build_rows.add_child(box)
		for id in row_ids:
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(148, 46)
			button.add_theme_font_size_override("font_size", 15)
			button.pressed.connect(select_building.bind(id))
			box.add_child(button)
			_buttons[id] = button


func _refresh_build_buttons() -> void:
	for id in _buttons.keys():
		var button: Button = _buttons[id]
		var active: bool = str(id) == _selected_id
		if str(id) == "demolish":
			button.text = "拆除"
			_style_build_button(button, Color(0.72, 0.32, 0.26), active)
			continue
		var def: Dictionary = GameManager.get_building_def(str(id))
		button.text = "%s\n%s" % [def["display_name"], _cost_text(def)]
		_style_build_button(button, def["color"], active)


func _refresh_resources() -> void:
	money_label.text = "金錢    %d" % GameManager.money
	population_label.text = "平民    %d / %d" % [GameManager.pleb_population, GameManager.housing_capacity]
	if citizen_label != null:
		citizen_label.text = "市民    %d / %d" % [GameManager.citizen_population, GameManager.citizen_capacity]
	food_label.text = "食物    %d" % GameManager.food
	wood_label.text = "木材    %d" % GameManager.wood
	tools_label.text = "工具    %d" % GameManager.tools
	if stone_label != null:
		stone_label.text = "石材    %d" % GameManager.stone
		wool_label.text = "羊毛    %d" % GameManager.wool
		cloth_label.text = "布料    %d" % GameManager.cloth
		grapes_label.text = "葡萄    %d" % GameManager.grapes
		wine_label.text = "葡萄酒  %d" % GameManager.wine
		need_label.text = "需求    %s" % GameManager.need_summary()
	if _tax_flash_left > 0.0:
		tax_label.text = "稅收    +%d" % _tax_flash_amount
	else:
		var reason := GameManager.tax_block_reason()
		if reason == "":
			var amount := GameManager.tax_amount_if_due()
			if GameManager.citizen_population > 0 and (GameManager.cloth_is_short() or GameManager.wine_is_short()):
				tax_label.text = "稅收    奢侈品不足，每10秒 +%d" % amount
			elif GameManager.tools_are_short():
				tax_label.text = "稅收    工具不足，每10秒 +%d" % amount
			else:
				tax_label.text = "稅收    每10秒 +%d" % amount
		elif reason == "尚無居民":
			tax_label.text = "稅收    尚無居民"
		else:
			tax_label.text = "稅收    暫停：%s" % reason
	_refresh_info()


func _apply_theme() -> void:
	var theme := Theme.new()
	theme.default_font = GameManager.get_ui_font()
	theme.default_font_size = 20
	ui_root.theme = theme
	money_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	population_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	food_label.add_theme_color_override("font_color", Color(0.72, 0.95, 0.58))
	wood_label.add_theme_color_override("font_color", Color(0.86, 0.68, 0.42))
	tools_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	tax_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	help_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.75))
	help_label.add_theme_font_size_override("font_size", 14)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	for label in [money_label, population_label, food_label, wood_label, tools_label, tax_label]:
		label.add_theme_font_size_override("font_size", 18)


func _style_panel(panel: PanelContainer) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.08, 0.06, 0.86)
	box.set_corner_radius_all(10)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", box)


func _style_build_button(button: Button, accent: Color, active: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = accent.darkened(0.15 if active else 0.45)
	box.set_corner_radius_all(8)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	if active:
		box.border_width_bottom = 4
		box.border_color = Color(1, 0.9, 0.45)
	button.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(0.98, 0.98, 0.94))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
