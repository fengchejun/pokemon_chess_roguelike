extends Control
const FoodDB = preload("res://scripts/data/food_db.gd")

var app = null
var result_label: Label
var inventory_label: Label
var fire_overlay: ColorRect


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
	var manage := UIKit.button("营地宝可梦（%d）" % app.run.storage.size())
	manage.name = "CampStorage"
	manage.pressed.connect(_open_storage)
	top.add_child(manage)
	inventory_label = UIKit.label("", 17, UIKit.ACCENT)
	column.add_child(inventory_label)
	column.add_child(UIKit.wrapped("点击篝火选择食物并休息。点击携带的宝可梦可查看状态、抚摸或交谈；互动不改变养成数值。", 15))
	var stage := UIKit.panel(Color("202a29"))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(center)
	var party := UIKit.hbox(28)
	center.add_child(party)
	var left := UIKit.vbox(16)
	var right := UIKit.vbox(16)
	party.add_child(left)
	var fire := UIKit.button("🔥\n篝火\n选择食物与休息", 26)
	fire.name = "Campfire"
	fire.custom_minimum_size = Vector2(250, 205)
	fire.pressed.connect(_open_fire)
	party.add_child(fire)
	party.add_child(right)
	var index := 0
	for record in app.run.carried:
		var uid := int(record["uid"])
		var button := UIKit.button("%s\nHP %d/%d" % [SpeciesDB.name_of(String(record["species_id"])), int(record["hp"]), app.run.monster_max_hp(record)], 16)
		button.name = "CampMonster_%d" % uid
		button.custom_minimum_size = Vector2(170, 66)
		button.pressed.connect(func() -> void: _show_monster(uid))
		(left if index < 3 else right).add_child(button)
		index += 1
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
	dialog.title = "营地宝可梦 · 与背包交换"
	dialog.size = Vector2i(600, 480)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	dialog.add_child(scroll)
	var column := UIKit.vbox(8)
	scroll.add_child(column)
	column.add_child(UIKit.wrapped("选择营地成员与背包成员交换。仓库成员会随本局跨层保留，但本局结束时默认被抛弃；想稳定保留下局使用，请在结束对局前换入携带名单。最终结局页仅提供一次勾选例外保留。", 15))
	for stored in app.run.storage:
		column.add_child(UIKit.label("营地：%s HP %d/%d" % [SpeciesDB.name_of(String(stored["species_id"])), int(stored["hp"]), app.run.monster_max_hp(stored)], 16, UIKit.ACCENT))
		for member in app.run.carried:
			var stored_uid := int(stored["uid"])
			var member_uid := int(member["uid"])
			var button := UIKit.small_button("交换背包中的 %s" % SpeciesDB.name_of(String(member["species_id"])))
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
	dialog.popup_hide.connect(func() -> void: dialog.queue_free())
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
		for record in app.run.carried:
			var button := find_child("CampMonster_%d" % int(record["uid"]), true, false)
			if button != null:
				button.text = "%s\nHP %d/%d" % [SpeciesDB.name_of(String(record["species_id"])), int(record["hp"]), app.run.monster_max_hp(record)]
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
