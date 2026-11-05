extends Control
const FoodDB = preload("res://scripts/data/food_db.gd")

var app = null
var result_label: Label
var inventory_label: Label
var fire_overlay: ColorRect
var board: BoardView
var camp_units: Array = []
var selected_uid: int = Balance.TRAINER_UID
const FIRE_CELL := Vector2i(3, 3)
const STORAGE_CELL := Vector2i(6, 3)



func _ready() -> void:
	name = "CampScreen"
	UIKit.fill_background(self)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 28)
	add_child(outer)
	var column := UIKit.vbox(14)
	outer.add_child(column)
	var top := UIKit.hbox(12)
	column.add_child(top)
	top.add_child(UIKit.title("营地 · 第 %d 层" % (app.run.floor_index() + 1), 28))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var route := UIKit.button("返回区域路线")
	route.name = "ReturnToRegion"
	route.pressed.connect(func() -> void: app.leave_camp())
	top.add_child(route)
	inventory_label = UIKit.label("", 17, UIKit.ACCENT)
	column.add_child(inventory_label)
	column.add_child(UIKit.wrapped("点击单位选择，再点击空格移动；点击篝火休息，点击仓库交换成员。双击宝可梦查看状态或互动；营地内移动不计区域移动次数。", 15))
	var stage := UIKit.panel(Color("202a29"))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	board = BoardView.new()
	board.name = "CampBoard"
	var map_frame := Control.new()
	center.add_child(map_frame)
	map_frame.add_child(board)
	board.show_movement_costs = false
	var fit_map := func() -> void:
		var base := Vector2(GridSpec.W, GridSpec.H) * BoardView.TILE
		var zoom := clampf(minf((scroll.size.x - 16) / base.x, (scroll.size.y - 16) / base.y), 0.35, 1.0)
		board.scale = Vector2.ONE * zoom
		map_frame.custom_minimum_size = base * zoom
	scroll.resized.connect(fit_map)
	fit_map.call_deferred()
	_build_map()
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_double_clicked.connect(func(cell: Vector2i) -> void:
		var unit = _unit_at(cell)
		if unit != null and not unit.is_trainer:
			_show_monster(unit.uid)
	)
	for facility in [[FIRE_CELL, "Campfire", "篝火", _open_fire], [STORAGE_CELL, "CampStorage", "仓库\n%d名" % app.run.storage.size(), _open_storage]]:
		var button := UIKit.button(facility[2], 15)
		button.name = facility[1]
		button.position = Vector2(facility[0]) * BoardView.TILE + Vector2(2, 2)
		button.size = Vector2.ONE * (BoardView.TILE - 4)
		button.pressed.connect(facility[3])
		board.add_child(button)
	var recovered: bool = bool(app.run.get_region().nodes["camp"].get("cleared", false))
	result_label = UIKit.wrapped("营地已夺回，食物回复服务恢复。" if recovered else "营地安全。初始在此，不计区域移动。", 15, UIKit.TEXT_DIM)
	result_label.name = "CampFeedback"
	column.add_child(result_label)
	_refresh_inventory()


func _refresh_inventory() -> void:
	var parts: Array = []
	for id in FoodDB.FOODS:
		parts.append("%s %d" % [FoodDB.definition(String(id))["name"], int(app.run.food_inventory.get(id, 0))])
	inventory_label.text = "食物库存：%s" % " · ".join(parts)


func _open_storage() -> void:
	var dialog := AcceptDialog.new()
	dialog.name = "CampStorageDialog"
	dialog.title = "营地宝可梦 · 与背包交换"
	dialog.size = Vector2i(600, 480)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	dialog.add_child(scroll)
	var column := UIKit.vbox(8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(UIKit.wrapped("选择营地成员与背包成员交换。进入下一层时，留在营地的成员将被抛弃，无法进入永久收藏。", 15))
	for stored in app.run.storage:
		column.add_child(UIKit.label("营地：%s HP %d/%d" % [SpeciesDB.name_of(String(stored["species_id"])), int(stored["hp"]), app.run.monster_max_hp(stored)], 16, UIKit.ACCENT))
		for member in app.run.carried:
			var stored_uid := int(stored["uid"])
			var member_uid := int(member["uid"])
			var button := UIKit.small_button("交换背包中的 %s" % SpeciesDB.name_of(String(member["species_id"])))
			button.name = "CampSwap_%d_%d" % [member_uid, stored_uid]
			button.pressed.connect(func() -> void:
				if app.run.camp_swap(member_uid, stored_uid):
					app.autosave()
					dialog.queue_free()
					app.show_camp()
			)
			column.add_child(button)
	if app.run.storage.is_empty():
		column.add_child(UIKit.label("营地暂无留守成员。", 15))
	add_child(dialog)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _open_fire() -> void:
	if fire_overlay != null and is_instance_valid(fire_overlay):
		fire_overlay.queue_free()
	fire_overlay = ColorRect.new()
	fire_overlay.name = "CampfireOverlay"
	fire_overlay.color = Color(0.02, 0.03, 0.06, 0.78)
	fire_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fire_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fire_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fire_overlay.add_child(center)
	var card := UIKit.panel(UIKit.PANEL)
	card.custom_minimum_size = Vector2(470, 260)
	center.add_child(card)
	var content := UIKit.vbox(12)
	card.add_child(content)
	content.add_child(UIKit.title("篝火 · 选择食物", 24))
	var selector := OptionButton.new()
	selector.name = "CampFoodKind"
	var food_ids: Array = FoodDB.FOODS.keys()
	for food_id in food_ids:
		selector.add_item(String(FoodDB.definition(String(food_id))["name"]))
	content.add_child(selector)
	var description := UIKit.wrapped("", 16)
	content.add_child(description)
	var amount := SpinBox.new()
	amount.name = "BasicFoodAmount"
	amount.min_value = 0
	amount.step = 1
	content.add_child(amount)
	var hint := UIKit.wrapped("", 14, UIKit.BAD)
	hint.name = "CampRestHint"
	content.add_child(hint)
	var rest := UIKit.button("休息", 17)
	rest.name = "CampRestButton"
	var refresh_food := func() -> void:
		var kind := String(food_ids[selector.selected])
		var definition: Dictionary = FoodDB.definition(kind)
		var cost := int(definition["rest_cost"])
		var stock := int(app.run.food_inventory.get(kind, 0))
		description.text = "%s：库存 %d，需选择 %d 份。%s" % [definition["name"], stock, cost, definition["description"]]
		amount.max_value = mini(cost, stock)
		amount.value = amount.max_value
		rest.text = "消耗 %d 份%s并休息" % [cost, definition["name"]]
		rest.disabled = not app.run.needs_camp_rest() or stock < cost
		hint.text = "队伍当前无需恢复。" if not app.run.needs_camp_rest() else "%s不足 %d 份。" % [definition["name"], cost] if stock < cost else ""
	selector.item_selected.connect(func(_index: int) -> void: refresh_food.call())
	refresh_food.call()
	rest.pressed.connect(func() -> void:
		var kind := String(food_ids[selector.selected])
		var outcome: Dictionary = app.run.rest_with_food({kind: int(amount.value)})
		if not bool(outcome.get("ok", false)):
			hint.text = String(outcome.get("reason", "无法休息。"))
			return
		app.autosave()
		fire_overlay.queue_free()
		result_label.text = "消耗%s %d 份。\n" % [FoodDB.definition(kind)["name"], int(outcome["spent"][kind])] + "\n".join(outcome["results"])
		_refresh_inventory()
		_refresh_units()
	)
	content.add_child(rest)
	var close := UIKit.small_button("取消")
	close.pressed.connect(func() -> void: fire_overlay.queue_free())
	content.add_child(close)


func _show_monster(uid: int) -> void:
	var record: Dictionary = app.run.record_by_uid(uid)
	if record.is_empty():
		return
	var monster_name := SpeciesDB.name_of(String(record["species_id"]))
	result_label.text = "%s · Lv.%d · HP %d/%d。可选择互动。" % [monster_name, int(record.get("level", 1)), int(record["hp"]), app.run.monster_max_hp(record)]
	var menu := PopupMenu.new()
	menu.name = "CampInteraction_%d" % uid
	menu.add_item("抚摸", 0)
	menu.add_item("交谈", 1)
	menu.id_pressed.connect(func(id: int) -> void:
		result_label.text = "%s%s：%s回应了你。没有获得经验或亲密度。" % ["抚摸" if id == 0 else "交谈", monster_name, monster_name]
	)
	menu.popup_hide.connect(func() -> void: menu.queue_free())
	add_child(menu)
	menu.position = get_global_mouse_position()
	menu.popup()


func _build_map() -> void:
	var region = app.run.get_region()
	var positions: Dictionary = region.nodes["camp"].get("map_positions", {})
	var trainer := CombatUnit.make("trainer", "player", Balance.TRAINER_UID)
	trainer.hp = app.run.trainer_hp
	trainer.max_hp = app.run.trainer_max_hp()
	camp_units = [trainer]
	for record in app.run.carried:
		var unit := CombatUnit.make(String(record["species_id"]), "player", int(record["uid"]))
		unit.hp = int(record["hp"])
		unit.max_hp = app.run.monster_max_hp(record)
		camp_units.append(unit)
	var free: Array = GridSpec.all_cells().filter(func(cell): return cell != FIRE_CELL and cell != STORAGE_CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("camp:%d:%d" % [app.run.seed, app.run.floor_index()])
	# 先恢复仍在背包中的成员；新增成员再随机找空位，避免交换后挤占原站位。
	var unplaced: Array = []
	for unit in camp_units:
		var saved: Array = positions.get(str(unit.uid), [])
		var cell := Vector2i(int(saved[0]), int(saved[1])) if saved.size() == 2 else Vector2i(-1, -1)
		if free.has(cell):
			unit.cell = cell
			free.erase(cell)
		else:
			unplaced.append(unit)
	for unit in unplaced:
		unit.cell = free.pop_at(rng.randi_range(0, free.size() - 1))
	board.terrain = []
	for cell in GridSpec.all_cells():
		board.terrain.append(TerrainDB.PLAIN)
	board.units = camp_units
	_save_positions()
	_update_movement()


func _unit_at(cell: Vector2i):
	for unit in camp_units:
		if unit.cell == cell:
			return unit
	return null


func _on_cell_clicked(cell: Vector2i) -> void:
	if cell == FIRE_CELL:
		_open_fire()
		return
	if cell == STORAGE_CELL:
		_open_storage()
		return
	var unit = _unit_at(cell)
	if unit != null:
		selected_uid = unit.uid
		result_label.text = "%s · HP %d/%d。点击蓝色空格移动；双击宝可梦互动。" % [unit.display_name, unit.hp, unit.max_hp]
	elif board.movement_cells.has(cell):
		for member in camp_units:
			if member.uid == selected_uid:
				member.cell = cell
		_save_positions()
	_update_movement()


func _update_movement() -> void:
	board.clear_overlays()
	board.selected_uid = selected_uid
	var selected = null
	for unit in camp_units:
		if unit.uid == selected_uid:
			selected = unit
		if unit.hp <= 0:
			board.markers.append({"cell": unit.cell, "text": "%s\n濒死" % unit.display_name, "color": UIKit.BAD})
	if selected != null and selected.hp > 0:
		var frontier: Array = [selected.cell]
		var visited: Dictionary = {selected.cell: true}
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front()
			for direction in GridSpec.DIRS4:
				var next: Vector2i = current + direction
				if not GridSpec.is_inside(next) or visited.has(next) or next in [FIRE_CELL, STORAGE_CELL] or _unit_at(next) != null:
					continue
				visited[next] = true
				board.movement_cells[next] = {"cost": 0}
				frontier.append(next)
	board.queue_redraw()


func _save_positions() -> void:
	var region = app.run.get_region()
	var positions := {}
	for unit in camp_units:
		positions[str(unit.uid)] = [unit.cell.x, unit.cell.y]
	region.nodes["camp"]["map_positions"] = positions
	app.run.region_data = region.to_dict()
	app.autosave()


func _refresh_units() -> void:
	for unit in camp_units:
		if unit.is_trainer:
			unit.hp = app.run.trainer_hp
		else:
			unit.hp = int(app.run.record_by_uid(unit.uid)["hp"])
	_update_movement()
