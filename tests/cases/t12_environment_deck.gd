extends RefCounted


func run(t: TestContext) -> void:
	t.begin("地图构筑卡模式")
	var run_state := RunState.new_run(4321)
	t.eq(String(run_state.options.get("card_mode", "")), "position", "默认使用 v2 站位卡")
	run_state.options["card_mode"] = "environment"
	t.eq(run_state.effects().is_empty(), true, "地图构筑模式不叠加站位卡效果")
	var options := MapCardDB.offer([], 12345)
	t.eq(options.size(), 3, "战后提供三张不同卡")
	t.eq(options, MapCardDB.offer([], 12345), "固定种子给出可复现选项")
	run_state.environment_reward_pending = true
	var offered := run_state.environment_choices()
	t.eq(run_state.choose_environment_card(String(offered[0])), true, "可选择一张地图构筑卡")
	t.eq(run_state.environment_deck.size(), 1, "所选卡持续保存在本局卡组")
	t.eq(run_state.choose_environment_card(String(offered[1])), false, "一场只能领取一张")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.environment_deck, run_state.environment_deck, "读档保留地图构筑卡")
	t.eq(String(restored.options.get("card_mode", "")), "environment", "读档保留卡模式")
	var water_deck := ["water", "electric"]
	var weights := MapCardDB.weights(water_deck)
	t.check(int(weights["water"]) > int(MapCardDB.weights(["water"])["water"]), "水电组合增加水域倾向")
	var water_gain := 0
	for seed_value in range(20, 40):
		var plain := MapGenerator.generate(seed_value, 0)
		var water := MapGenerator.generate(seed_value, 0, 0, water_deck)
		t.eq(water["terrain"], MapGenerator.generate(seed_value, 0, 0, water_deck)["terrain"], "同种子和卡组地图可复现")
		water_gain += _count(water["terrain"], TerrainDB.WATER) - _count(plain["terrain"], TerrainDB.WATER)
	t.check(water_gain > 0, "水电卡组在样本地图中总体提高浅水数量")
	_test_ui_flow(t)
	t.finish()


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
	var selector: OptionButton = app.current_screen.find_child("CardModeOption", true, false)
	t.check(selector != null, "整备页能找到环境卡模式选择")
	if selector == null:
		app.queue_free()
		return
	selector.select(1)
	selector.item_selected.emit(1)
	t.eq(String(app.run.options.get("card_mode", "")), "environment", "整备页切换为地图构筑模式")
	var prep = app.current_screen
	for uid in [1, 2, 3]:
		var deploy: CheckBox = prep.find_child("Deploy_%d" % uid, true, false)
		deploy.button_pressed = true
	var preview: Button = prep.find_child("PreviewButton", true, false)
	preview.pressed.emit()
	t.eq(app.current_screen.name, "PreviewScreen", "进入地图构筑预览")
	t.check(app.current_screen.find_child("CardToggle_stream", true, false) == null, "地图构筑模式不要求站位卡五选二")
	var start: Button = app.current_screen.find_child("StartBattleButton", true, false)
	start.pressed.emit()
	t.eq(app.current_screen.name, "BattleScreen", "地图构筑模式无卡也可开始战斗")
	var battle = app.current_screen
	for enemy in battle.state.alive_units("enemy"):
		battle.state.kill_unit(enemy, "测试清场", "player")
	battle.state.check_battle_end()
	battle.report_end_now()
	t.eq(app.current_screen.name, "SettlementScreen", "进入结算领取环境卡")
	var choices: Array = app.run.environment_choices()
	var choice: Button = app.current_screen.find_child("EnvironmentChoice_%s" % String(choices[0]), true, false)
	t.check(choice != null, "结算页出现环境卡三选一按钮")
	if choice != null:
		choice.pressed.emit()
		t.eq(app.run.environment_deck.size(), 1, "所选卡加入本局卡组")
		t.eq(app.run.environment_reward_pending, false, "领取后本场不再重复出现卡奖励")
	app.queue_free()


func _count(terrain: Array, kind: int) -> int:
	var total := 0
	for cell in terrain:
		if int(cell) == kind:
			total += 1
	return total
