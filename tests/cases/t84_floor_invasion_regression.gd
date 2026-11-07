extends RefCounted

func run(t: TestContext) -> void:
	t.begin("楼层进入与早期入侵回归")
	_early_timed_pressure(t)
	_late_timed_pressure(t)
	_legacy_early_repair(t)
	_boss_to_third_floor(t)
	t.finish()


func _run_with_region(seed: int, floor: int) -> RunState:
	var run := RunState.new_run(seed)
	run.region_mode = true
	var region := RegionState.create_floor(floor, "fire")
	for node in region.nodes.values():
		node["unlocked"] = true
	region.active_node = "battle_1"
	run.region_data = region.to_dict()
	run.mark_deployed([1])
	return run


func _battle(run: RunState, seed: int) -> BattleState:
	var state := BattleState.new()
	state.node_kind = "battle"
	state.setup(TestScenario.make_map(TestScenario.plain_terrain(), Vector2i(7, 7)), {"enemies": [["rock_wild1", Vector2i(4, 3)]]}, seed, 0, run.build_deploy_units([1]), {}, {}, [])
	state.round = 8
	state.settle_round()
	return state


func _early_timed_pressure(t: TestContext) -> void:
	var run := _run_with_region(8401, 1)
	var battle := _battle(run, 8401)
	run.sync_from_battle(battle)
	var region: RegionState = run.get_region()
	t.check(not region.support_triggered and not region.camp_invaded, "第二层第8轮不触发全面占领")
	t.check(bool(region.nodes["battle_1"].get("corrupted", false)), "当前战斗节点仍记录黑化")
	t.eq(String(region.nodes["event_1"].get("mode", "")), "event", "第二层探索节点未被错误占领")


func _late_timed_pressure(t: TestContext) -> void:
	var run := _run_with_region(8402, 2)
	var battle := _battle(run, 8402)
	run.sync_from_battle(battle)
	var region: RegionState = run.get_region()
	t.check(region.support_triggered and region.camp_invaded, "第三层第8轮保留全面占领")


func _legacy_early_repair(t: TestContext) -> void:
	var run := _run_with_region(8403, 1)
	var region: RegionState = run.get_region()
	region.support_triggered = true
	region.camp_invaded = true
	region.nodes["event_1"]["mode"] = "battle"
	region.nodes["event_1"]["cleared"] = false
	run.region_data = region.to_dict()
	var data := run.to_dict()
	var restored := RunState.from_dict(data)
	var repaired: RegionState = restored.get_region()
	t.check(not repaired.support_triggered and not repaired.camp_invaded, "旧二层全面占领标记被修复")
	t.eq(String(repaired.nodes["event_1"].get("mode", "")), "event", "旧二层探索节点恢复")


func _boss_to_third_floor(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8404)
	app.run.region_mode = true
	var region := RegionState.create_floor(1, "fire")
	region.active_node = "boss"
	region.nodes["boss"]["unlocked"] = true
	region.nodes["boss"]["cleared"] = true
	app.run.region_data = region.to_dict()
	app.run.battle_index = 11
	var stored: Dictionary = app.run._make_record("rock_starter")
	stored["level"] = 1
	stored["xp"] = 0
	app.run.storage.append(stored)
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 0, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var continue_button: Button = app.current_screen.find_child("ContinueButton", true, false)
	t.check(continue_button != null and not continue_button.disabled, "首领结算可继续")
	continue_button.pressed.emit()
	var confirm: Button = app.current_screen.find_child("ConfirmNextFloorButton", true, false)
	t.check(confirm != null, "场景内显示下一层确认")
	if confirm != null:
		confirm.pressed.emit()
	t.eq(app.current_screen.name, "FloorThemeScreen", "确认后进入第三层主题选择")
	t.eq(app.run.floor_index(), 2, "确认后楼层索引为第三层")
	app.queue_free()
