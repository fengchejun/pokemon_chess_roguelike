extends Control
const Widgets = preload("res://ui/components/pixel_widgets.gd")
const FoodDB = preload("res://scripts/data/food_db.gd")
var app = null
var result_label: Label
var inventory_label: Label
var fire_overlay: ColorRect

func _refresh_inventory() -> void:
	var parts: Array = []
	for id in FoodDB.FOODS:
		parts.append("%s %d" % [FoodDB.definition(String(id))["name"], int(app.run.food_inventory.get(id, 0))])
	inventory_label.text = "食物库存：%s" % " · ".join(parts)


func _open_storage() -> void:
	if not app.run.camp_service_available("storage"):
		result_label.text = "仓库已被摧毁，本层无法存取宝可梦。"
		return
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
		column.add_child(UIKit.label(SpeciesDB.name_of(String(stored["species_id"])), 16, UIKit.ACCENT))
		column.add_child(Widgets.health(int(stored["hp"]), app.run.monster_max_hp(stored)))
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
	if not app.run.camp_service_available("fire"):
		result_label.text = "篝火已被摧毁，本层无法休息恢复。"
		return
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
	selector.hide()
	var food_grid := Widgets.slot_grid(content, 4)
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
	for index in food_ids.size():
		var id := String(food_ids[index])
		var definition: Dictionary = FoodDB.definition(id)
		var slot := Widgets.slot(String(definition["name"]), int(app.run.food_inventory.get(id, 0)), String(definition["name"]).left(2), String(definition["description"]), UIKit.GOOD)
		slot.name = "CampFoodSlot_" + id
		slot.pressed.connect(func() -> void:
			selector.select(index)
			refresh_food.call())
		food_grid.add_child(slot)
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


func _refresh_units() -> void:
	var screen = app.current_screen
	for unit in screen.state.units:
		if unit.side != "player":
			continue
		if unit.is_trainer:
			unit.hp = app.run.trainer_hp
		else:
			var record: Dictionary = app.run.record_by_uid(unit.uid)
			if not record.is_empty():
				unit.hp = int(record["hp"])
	app.sync_and_save(screen.state)
	screen.refresh_all()
