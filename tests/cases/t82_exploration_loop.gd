extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")

func make_app(t: TestContext):
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(82001)
	app.run.region_mode = true
	app.run.options["exploration_v2"] = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.region_data = Flow.create(0, app.run.current_theme()).to_dict()
	app.show_region()
	return app

func finish(app) -> void:
	var region = app.run.get_region()
	region.complete_visit()
	app.run.region_data = region.to_dict()
	app.run.pending_region_entry_backup.clear()
	app.show_region()

func resolve_growth(run: RunState) -> void:
	while not run.pending_monster_levels().is_empty():
		var entry: Dictionary = run.pending_monster_levels()[0]
		var uid := int(entry["uid"]); var level := int(entry["level"])
		if level == 10:
			run.claim_monster_trait_upgrade(uid, level)
			continue
		var choices := run.monster_level_choices(uid, level)
		if choices.is_empty(): run.skip_monster_skill_choice(uid, level)
		else:
			var record := run.owned_record_by_uid(uid)
			var equipped: Array = record["equipped_skills"]
			run.learn_monster_skill(uid, level, choices[0], equipped[0] if equipped.size() >= 3 else "")

func run(t: TestContext) -> void:
	t.begin("第一层迷雾、回访、事件、捕捉、入侵与夺回")
	var app = make_app(t)
	var run: RunState = app.run
	var region = run.get_region()
	t.eq(region.flow_version, 2, "启用第一层新流程")
	t.check(region.nodes["boss"]["revealed"] and not region.nodes["boss"]["unlocked"], "Boss位置已知但不能跳过阻挡")
	t.check(not region.nodes["battle_2"]["revealed"], "分支深处内容隐藏")
	t.check(not run.enter_region_node("boss"), "不能直接跳到未到达Boss")
	var pre = run.get_region()
	pre.nodes["event_1"]["unlocked"] = true
	run.region_data = pre.to_dict()
	app.enter_region_node("event_1")
	t.eq(app.current_screen.name, "NodeScreen", "群体事件没有战斗地图")
	app.current_screen.find_child("PlayGroup", true, false).pressed.emit()
	var money := run.essence
	app.current_screen.find_child("ReturnToRegion", true, false).pressed.emit()
	t.eq(run.essence, money, "返回不重复发奖励")
	app.enter_region_node("event_1")
	t.check(app.current_screen.find_child("PlayGroup", true, false) == null, "完成事件无法重复领奖")
	finish(app)
	app.enter_region_node("battle_5")
	t.check(not run.get_region().nodes["battle_4"]["unlocked"], "未交付委托挡住分支")
	run.carried.append(run._make_record(preload("res://scripts/run/exploration_flow.gd").request_species(run.get_region().theme), 10))
	app.current_screen.refresh()
	var uid := int(run.carried.back()["uid"])
	app.current_screen.deliver(uid)
	t.check(run.get_region().nodes["battle_4"]["unlocked"], "交付后打开分支")
	var count := run.carried.size()
	var reward_money := run.essence
	app.current_screen.deliver(uid)
	t.eq(run.carried.size(), count, "交付不能重放")
	t.eq(run.essence, reward_money, "不重复发原质")
	t.check(not run.relic_stacks.is_empty() and run.pending_reward_choices == 0, "委托遗物自动发放")
	finish(app)
	# 首战验证：新流程无巢穴、三名敌人，完成后开启路线。
	var pre_battle = run.get_region()
	pre_battle.nodes["battle_1"]["unlocked"] = true
	run.region_data = pre_battle.to_dict()
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var state: BattleState = app.current_screen.state
	t.check(state.exploration_v2 and not state.has_live_nests(), "首战无巢穴")
	var extra := int(state.alive_units("enemy").any(func(enemy): return enemy.reward_carrier))
	t.eq(state.alive_enemy_count() - extra, 3, "首战有三名基础敌人")
	t.eq(state.chests.size(), 0, "普通战斗取消额外宝箱")
	t.check(state.alive_units("enemy").all(func(u): return u.max_hp == 16 and u.skills.size() == 1), "首战敌人生命与技能压低")
	for enemy in state.alive_units("enemy"):
		state.kill_unit(enemy, "测试", "player", 1)
	state.end_battle("victory")
	app.finish_battle(state)
	# 结算所有奖励，避免测试跳过待处理步骤。
	while run.pending_reward_choices > 0:
		run.choose_reward(run.reward_choices()[0])
	resolve_growth(run)
	for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
	app.continue_after_settlement()
	t.check(run.get_region().nodes["battle_2"]["unlocked"], "首战胜利打通栖息地")
	app.enter_region_node("battle_2")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	state = app.current_screen.state
	t.check(state.alive_enemy_count() == 3 and not state.has_live_nests(), "捕捉固定三只且无巢穴")
	t.check(state.can_leave_node() and not state.can_escape(), "捕捉可直接离开，无需前往撤离点")
	for i in Balance.CAPTURE_ENCOUNTER_ROUNDS:
		state.begin_enemy_phase()
		while not state.enemy_phase_finished(): state.step_enemy_phase()
		state.end_enemy_phase()
	t.check(state.ended and state.end_reason == "explored", "第八回合结束野生目标逃走")
	app.finish_battle(state)
	while run.pending_reward_choices > 0: run.choose_reward(run.reward_choices()[0])
	resolve_growth(run)
	for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
	app.continue_after_settlement()
	# 文字商店：不足原质时可离开，重访不刷新库存。
	app.enter_region_node("event_2")
	t.eq(app.current_screen.name, "NodeScreen", "商店纯文字界面")
	run.essence = 100
	app.current_screen.buy("food")
	var stock := int(run.get_region().nodes["event_2"]["stock"]["food"])
	finish(app)
	app.enter_region_node("event_2")
	t.eq(run.get_region().nodes["event_2"]["stock"]["food"], stock, "回访库存保持")
	# 最后一次行动不打断节点，回地图才入侵。
	region = run.get_region()
	region.visits = 12
	run.region_data = region.to_dict()
	t.eq(app.current_screen.name, "NodeScreen", "行动耗尽不打断当前商店")
	finish(app)
	region = run.get_region()
	t.check(region.invaded and region.active_node == "event_2", "结算商店后在原地图触发入侵")
	t.check(region.nodes["event_2"]["service_lost"] and not region.can_enter_after_invasion("boss"), "失守商店永久关闭且不能跳过前线")
	var paths := {"event_2": ["event_2"]}
	var queue := ["event_2"]
	while not queue.is_empty() and not paths.has("boss"):
		var origin: String = queue.pop_front()
		for adjacent in region.nodes[origin]["links"]:
			if not paths.has(adjacent):
				paths[adjacent] = paths[origin] + [adjacent]
				queue.append(adjacent)
	var path: Array = paths["boss"]
	for id in path.slice(0, -1):
		app.enter_region_node(id)
		app.show_preview([1, 2, 3])
		app.current_screen._on_start()
		state = app.current_screen.state
		t.check(state.exploration_role == "recapture" and state.alive_units("enemy").all(func(u): return u.corrupted), "沿路线挑战开局黑化的驻军")
		t.check(not state.storm_strikes.is_empty() and int(state.storm_strikes[0]["due_round"]) == 1, "夺回战第一轮就预告落雷")
		for enemy in state.alive_units("enemy"):
			state.kill_unit(enemy, "测试", "player", 1)
		t.check(state.experience_gains.get(1, 0) > 0, "击败黑化驻军可获得经验")
		state.check_battle_end()
		t.check(state.ended and state.end_reason == "victory", "夺回清场自动胜利")
		app.finish_battle(state)
		t.eq(run.pending_reward_choices, 0, "没带出宝箱时清场不送遗物")
		for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
		resolve_growth(run)
		for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
		app.continue_after_settlement()
		t.check(run.get_region().nodes[id]["recaptured"], "夺回后重新通行")
	app.enter_region_node("boss")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	state = app.current_screen.state
	t.check(state.exploration_role == "boss" and state.alive_units("enemy").all(func(enemy): return enemy.corrupted), "走通路线后可挑战黑化 Boss")
	var boss := state.unit_by_uid(state.boss_uid)
	state.kill_unit(boss, "测试", "player", 1)
	state.check_battle_end()
	t.check(not state.ended and not GridSpec.is_inside(state.boss_portal_cell) and state.alive_enemy_count() > 0, "击倒Boss不清除其他敌军也不开传送门")
	for enemy in state.alive_units("enemy"): state.kill_unit(enemy, "测试", "player", 1)
	state.stop_nests()
	state.check_battle_end()
	t.check(state.ended and state.end_reason == "victory", "清场后立即胜利")
	var cleared := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.check(cleared.ended and cleared.end_reason == "victory", "存读档保留胜利结果")
	run.storage.append(run._make_record("grass_wild1", 8))
	var stored_uid := int(run.storage.back()["uid"])
	app.finish_battle(state)
	for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
	while run.pending_reward_choices > 0: run.choose_reward(run.reward_choices()[0])
	resolve_growth(run)
	for i in run.pending_battle_loot.size(): run.resolve_battle_loot(i, false)
	app.continue_after_settlement()
	t.eq(run.floor_index(), 1, "入侵后仍可经 Boss 传送门过层")
	t.check(run.storage.any(func(r): return int(r["uid"]) == stored_uid), "仓库成员跨层保留")
	app.free()
	t.finish()
