extends RefCounted


func run(t: TestContext) -> void:
	t.begin("区域物资与重访存档")
	var state := TestScenario.make_state(["fire_starter"], [])
	state.node_kind = "event"
	var picker := state.unit_by_uid(1)
	state.food_cells.append(picker.cell)
	state._pickups()
	var origin := picker.cell
	var options := state.move_options(picker)
	var destination: Vector2i = options.keys()[0]
	t.check(state.move_unit(picker, destination), "自由收集可以移动")
	t.check(not state.food_wait.has(origin), "离开食物格打断停留计时")
	t.check(state.undo_last_move(), "自由收集可以撤回移动")
	t.eq(state.food_wait.get(origin, -1), picker.uid, "撤回恢复原有停留计时")
	state._pickups()
	t.eq(state.food_collected, 1, "恢复的计时仅领取一次食物")
	var cell := Vector2i(4, 4)
	state.set_terrain(cell, TerrainDB.TREE)
	state.obstacle_durability[cell] = Balance.TREE_DURABILITY
	state.obstacle_origin[cell] = TerrainDB.PLAIN
	var rng := RandomNumberGenerator.new()
	for trial_seed in range(1, 100):
		rng.seed = trial_seed
		if rng.randf() < 0.25:
			state.terrain_rng.seed = trial_seed
			break
	var preview := state.clone()
	preview.damage_obstacle(cell, 100)
	t.check(not state.food_cells.has(cell), "预览不提前生成真实掉落")
	t.check(state.damage_obstacle(cell, 100), "破坏树木")
	t.check(state.food_cells.has(cell), "树木按随机数结果掉落食物")
	t.eq(preview.food_cells, state.food_cells, "预览与实际随机掉落一致")
	state.damage_obstacle(cell, 100)
	t.eq(state.food_cells.count(cell), 1, "已破坏树木不能重复掉落")
	var run_state := RunState.new_run(42)
	run_state.region_mode = true
	run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
	var region = run_state.get_region()
	region.record_entry("camp")
	region.record_entry("battle_1")
	region.store_battle("battle_1", state)
	run_state.region_data = region.to_dict()
	var path := "res://.test_region_resources.json"
	t.check(SaveSystem.save_run(run_state, path), "跨节点存档写盘")
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "跨节点存档读回")
	if loaded != null:
		var restored = loaded.get_region().load_battle("battle_1")
		t.check(restored.food_cells.has(cell), "重读保留尚未拾取的树木食物")
		t.check(not restored.obstacle_durability.has(cell), "重读不会复活已破坏的树木")
		t.eq(restored.terrain_rng.state, state.terrain_rng.state, "节点掉落随机数进度持久化")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var fight := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var attacker: CombatUnit = fight.alive_units("enemy")[0]
	var defender := fight.unit_by_uid(1)
	defender.max_hp = 500
	defender.hp = 500
	fight.boss_uid = attacker.uid
	var baseline := fight.damage_unit(attacker, defender, 10, {"skill_direct": true, "no_element": true})
	fight.boss_power_percent = 20
	var boosted := fight.damage_unit(attacker, defender, 10, {"skill_direct": true, "no_element": true})
	t.eq(boosted["amount"], ceili(int(baseline["amount"]) * 1.2), "首领强化实际增加技能直伤")
	var quota := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	quota.node_kind = "battle"
	quota.reinforcement_pool = []
	quota.nest["scheduled_waves"] = [2]
	quota.nest["pending_waves"] = 0
	quota.round = 1
	quota.start_round()
	t.eq(quota.nest["pending_waves"], 0, "重访第二回合不会重发已使用产敌名额")
	quota.round = 3
	quota.start_round()
	t.eq(quota.nest["pending_waves"], 1, "尚未使用的第四回合名额仍能发放")
	t.finish()
