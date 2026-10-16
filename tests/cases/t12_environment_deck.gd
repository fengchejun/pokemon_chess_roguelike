extends RefCounted


func run(t: TestContext) -> void:
	t.begin("地貌消耗卡与改造工具")
	_test_consumable_rules(t)
	_test_map_generation(t)
	_test_ui_flow(t)
	_test_modification_ui(t)
	t.finish()


func _test_consumable_rules(t: TestContext) -> void:
	var run_state := RunState.new_run(4321)
	t.eq(run_state.map_deck(), [], "新局没有常驻地图构筑卡")
	t.eq(run_state.mod_points(), 0, "新局没有免费地形改造")
	t.eq(run_state.use_reward_item_in_preview("map:water"), false, "未拥有的地貌卡不能使用")
	run_state.reward_inventory = ["map:water", RewardDB.MOD_ITEM]
	t.eq(run_state.use_reward_item_in_preview("map:water"), true, "预览页从背包使用一张地貌卡")
	t.eq(run_state.map_deck(), ["water"], "已使用地貌卡只作用于本场地图")
	t.eq(run_state.effects().is_empty(), true, "地貌卡不叠加站位卡战斗增益")
	t.eq(run_state.mod_points(), 0, "选择地貌卡时不能同时使用改造工具")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.reward_inventory, run_state.reward_inventory, "背包随本局存档恢复")
	t.eq(restored.preview_used_reward_item, "map:water", "读档保留预览页已使用的卡")
	t.eq(run_state.use_reward_item_in_preview(RewardDB.MOD_ITEM), false, "本场不允许叠用改造工具")
	run_state.advance_battle()
	t.eq(run_state.map_deck(), [], "下一场地貌卡不再影响地图")
	t.eq(run_state.use_reward_item_in_preview(RewardDB.MOD_ITEM), true, "下一场可以使用改造工具")
	t.eq(run_state.mod_points(), Balance.MOD_POINTS, "工具提供可配置的改造次数")
	t.eq(run_state.reward_inventory, [], "工具在预览页立即消耗")


func _test_map_generation(t: TestContext) -> void:
	var water_gain := 0
	var steam_gain := 0
	for seed_value in range(20, 40):
		var plain := MapGenerator.generate(seed_value, 0)
		var water := MapGenerator.generate(seed_value, 0, 0, ["water"])
		var fog := MapGenerator.generate(seed_value, 0, 0, ["steam_focus"])
		t.eq(water["terrain"], MapGenerator.generate(seed_value, 0, 0, ["water"])["terrain"], "同种子与单张地貌卡的地图可复现")
		water_gain += _count(water["terrain"], TerrainDB.WATER) - _count(plain["terrain"], TerrainDB.WATER)
		steam_gain += (fog["steam_cells"] as Dictionary).size() - (plain["steam_cells"] as Dictionary).size()
	t.check(water_gain > 0, "水地貌卡在样本地图中总体增加浅水")
	t.check(steam_gain > 0, "雾泉单卡在样本地图中提高蒸汽生成")
	for card_id in MapCardDB.ALL_IDS:
		for seed_value in range(6):
			var baseline := MapGenerator.generate(seed_value, 0)
			var result := MapGenerator.generate_card_preview(seed_value, 0, String(card_id), baseline)
			var before: Dictionary = result["before"]
			var after: Dictionary = result["after"]
			for key in MapGenerator.card_targets(String(card_id)):
				t.check(int(after[key]) > int(before[key]), "%s 地貌卡使 %s 严格增加（种子 %d）" % [card_id, key, seed_value])
			t.check(bool(result["guaranteed"]), "%s 地貌卡满足地形增加保证" % card_id)


func _test_ui_flow(t: TestContext) -> void:
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.start_new_run()
	for id in [1, 2, 3]:
		var choice: CheckBox = app.current_screen.find_child("Collection_%d" % id, true, false)
		choice.button_pressed = true
	var collection_start: Button = app.current_screen.find_child("StartFromCollectionButton", true, false)
	collection_start.pressed.emit()
	app.run.reward_inventory = ["map:water", RewardDB.MOD_ITEM]
	app.show_prep()
	t.check(app.current_screen.find_child("RewardItemOption", true, false) == null, "整备页没有消耗品入口")
	app.show_preview([1, 2, 3])
	var selector: OptionButton = app.current_screen.find_child("RewardItemOption", true, false)
	t.check(selector != null and selector.item_count == 3, "预览页提供两张背包消耗卡")
	if selector == null:
		app.queue_free()
		return
	selector.select(1)
	var before_counts := MapGenerator.terrain_counts(app.current_screen.map)
	var use_button: Button = app.current_screen.find_child("UseRewardItemButton", true, false)
	use_button.pressed.emit()
	t.eq(app.run.preview_used_reward_item, "map:water", "预览页使用地貌卡")
	t.eq(app.run.reward_inventory, [RewardDB.MOD_ITEM], "使用后立即消耗所选地貌卡")
	t.check(app.current_screen.find_child("CardToggle_stream", true, false) == null, "预览页不再免费选五选二")
	t.check(int(MapGenerator.terrain_counts(app.current_screen.map)["water"]) > int(before_counts["water"]), "刷新地图后浅水数量严格增加")
	var saved_terrain: Array = app.current_screen.map["terrain"].duplicate()
	var restored_run := RunState.from_dict(app.run.to_dict())
	t.eq(restored_run.preview_used_reward_item, "map:water", "存档恢复后仍记得本场已用卡")
	var restored_map := MapGenerator.generate_card_preview(restored_run.seed, restored_run.battle_index, "water", MapGenerator.generate(restored_run.seed, restored_run.battle_index))
	t.eq((restored_map["map"] as Dictionary)["terrain"], saved_terrain, "读档后可复原同一张地貌卡地图")
	var back: Button = app.current_screen.find_child("BackButton", true, false)
	back.pressed.emit()
	app.show_preview([1, 2, 3])
	t.eq(app.current_screen.map["terrain"], saved_terrain, "返回整备后再进预览保留已用卡地图")
	var start: Button = app.current_screen.find_child("StartBattleButton", true, false)
	start.pressed.emit()
	t.eq(app.current_screen.name, "BattleScreen", "只选一张消耗卡即可开战")
	t.eq(app.run.reward_inventory, [RewardDB.MOD_ITEM], "开战不重复消耗地貌卡")
	t.eq(app.run.selected_reward_item, "", "开战后清空卡牌选择")
	app.queue_free()


func _test_modification_ui(t: TestContext) -> void:
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.start_new_run()
	for id in [1, 2, 3]:
		var choice: CheckBox = app.current_screen.find_child("Collection_%d" % id, true, false)
		choice.button_pressed = true
	var collection_start: Button = app.current_screen.find_child("StartFromCollectionButton", true, false)
	collection_start.pressed.emit()
	app.run.reward_inventory = [RewardDB.MOD_ITEM]
	app.show_prep()
	app.show_preview([1, 2, 3])
	var preview = app.current_screen
	var selector: OptionButton = preview.find_child("RewardItemOption", true, false)
	selector.select(1)
	var use_button: Button = preview.find_child("UseRewardItemButton", true, false)
	use_button.pressed.emit()
	t.eq(preview.mod_count_label.text, "剩余改造次数：%d / %d" % [Balance.MOD_POINTS, Balance.MOD_POINTS], "使用工具后预览页显示改造次数")
	var valid_cell := Vector2i(-1, -1)
	for y in range(GridSpec.H):
		for x in range(GridSpec.W):
			var cell := Vector2i(x, y)
			if not MapGenerator.mod_protected(preview.map, cell) and int(preview.map["terrain"][GridSpec.index(cell)]) == TerrainDB.PLAIN:
				valid_cell = cell
				break
		if valid_cell != Vector2i(-1, -1):
			break
	t.check(valid_cell != Vector2i(-1, -1), "预览地图有可用于测试的普通地面")
	if valid_cell != Vector2i(-1, -1):
		preview._on_cell_clicked(valid_cell)
		t.eq(int(preview.map["terrain"][GridSpec.index(valid_cell)]), TerrainDB.WATER, "改造工具在预览页真正改变所选地形")
		t.eq(preview.mod_used, 1, "改造成功消耗一次工具使用额度")
		t.eq((RunState.from_dict(app.run.to_dict()).preview_modifications as Array).size(), 1, "改造记录可随本局存档恢复")
		var back: Button = preview.find_child("BackButton", true, false)
		back.pressed.emit()
		app.show_preview([1, 2, 3])
		preview = app.current_screen
		t.eq(int(preview.map["terrain"][GridSpec.index(valid_cell)]), TerrainDB.WATER, "返回整备后改造地形仍保留")
	var start: Button = preview.find_child("StartBattleButton", true, false)
	start.pressed.emit()
	t.eq(app.current_screen.name, "BattleScreen", "改造后可带修改后的地图开战")
	t.eq(app.run.reward_inventory, [], "地形改造工具使用时已从背包消耗")
	app.queue_free()


func _count(terrain: Array, kind: int) -> int:
	var total := 0
	for cell in terrain:
		if int(cell) == kind:
			total += 1
	return total
