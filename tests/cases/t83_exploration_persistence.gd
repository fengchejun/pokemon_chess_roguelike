extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")

func app_for(t: TestContext):
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.region_data = Flow.create(0, app.run.current_theme()).to_dict()
	app.show_region()
	return app

func open_for_test(app, id: String) -> void:
	var region = app.run.get_region()
	region.visit_pending = false
	region.nodes[id]["unlocked"] = true
	region.nodes[id]["revealed"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)

func run(t: TestContext) -> void:
	t.begin("新开局入口、文字节点存档、宝箱进度与捕获换人")
	var app = app_for(t)
	var run: RunState = app.run
	t.check(run.options.get("exploration_v2", false), "正常收藏开局启用新版第一层")
	# 图连通但并非格点四通八达。
	var region = run.get_region()
	var reached := {"camp": true}
	var frontier: Array = ["camp"]
	while not frontier.is_empty():
		var id: String = frontier.pop_front()
		for other in region.nodes[id]["links"]:
			if not reached.has(other): reached[other] = true; frontier.append(other)
	t.eq(reached.size(), 16, "十六个节点全部可达")
	t.eq(Flow.POSITIONS["boss"], Vector2i(2, 1), "Boss居中")
	t.eq(Flow.POSITIONS["camp"].x, 0, "营地在边缘")
	open_for_test(app, "camp")
	t.eq(app.current_screen.name, "NodeScreen", "营地是文字按钮界面")
	t.check(app.current_screen.find_child("BoardView", true, false) == null, "营地不创建实际地图")
	run.trainer_hp = 1
	var food := run.total_food()
	app.current_screen.refresh()
	app.current_screen.find_child("CampRestButton", true, false).pressed.emit()
	t.eq(run.trainer_hp, run.trainer_max_hp(), "文字营地休息生效")
	t.eq(run.total_food(), food - 3, "休息确实扣食物")
	open_for_test(app, "event_1")
	var before := run.essence
	app.current_screen.find_child("PlayGroup", true, false).pressed.emit()
	var saved_actions: int = run.get_region().visits
	var legacy_path := "res://.test_exploration_legacy.json"
	var legacy := RunState.new_run(1)
	SaveSystem.save_run(legacy, legacy_path)
	t.check(SaveSystem.clear_obsolete_run(legacy_path) and not FileAccess.file_exists(legacy_path), "旧局内存档清除")
	var path := "res://.test_exploration_flow.json"
	SaveSystem.save_run(run, path)
	t.check(not SaveSystem.clear_obsolete_run(path), "当前4x4新流程存档保留")
	app.continue_run(path)
	run = app.run
	t.eq(app.current_screen.name, "NodeScreen", "在文字事件中保存后继续仍回该事件")
	t.eq(run.get_region().visits, saved_actions, "重载不退还已发生的行动")
	t.eq(run.essence, before + 4, "事件收益读档保留但不重复")
	t.check(app.current_screen.find_child("PlayGroup", true, false) == null, "重载后已完成选项不再出现")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	open_for_test(app, "battle_4")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var state: BattleState = app.current_screen.state
	t.check(state.preserve_node_terrain and state.chests.has(Vector2i(6, 3)), "宝箱在特殊实际地图")
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.DEEP, "宝箱隔着深水河")
	state.set_terrain(Vector2i(3, 3), TerrainDB.ICE)
	state.damage_obstacle(Vector2i(5, 3), 1, "player")
	app.sync_and_save(state)
	state.leave_node()
	app.finish_battle(state)
	app.continue_after_settlement()
	open_for_test(app, "battle_4")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	state = app.current_screen.state
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.ICE, "离开回访保留冰面改造")
	t.eq(state.terrain_at(Vector2i(5, 3)), TerrainDB.ROCK_MOUNTAIN, "回访保留未被普通攻击破坏的岩山")
	var water := state.unit_by_uid(2)
	water.cell = Vector2i(4, 3)
	water.skills = ["water_flow"]
	var breaker := state.unit_by_uid(1)
	breaker.cell = Vector2i(4, 2)
	breaker.skills = ["rock_break"]
	t.check(state.cast_skill(breaker, "rock_break", {"type": "cell", "cell": Vector2i(5, 3)}).get("ok", false), "碎岩打开宝箱外围的岩山")
	var entry := {"type": "cell", "cell": Vector2i(6, 3)}
	t.check(state.cast_skill(water, "water_flow", entry).get("ok", false), "实际技能打开宝箱")
	t.check(state.chests.is_empty() and not state.all_rewards().is_empty(), "开箱产生实际宝藏奖励点")
	# 用真实拾取获得奖励，再验证领取过的宝箱不能重复生成。
	water.cell = Vector2i(6, 3)
	state._pickups()
	state.leave_node()
	app.finish_battle(state)
	while run.pending_reward_choices > 0: run.choose_reward(run.reward_choices()[0])
	for record in run.carried: record["claimed_even_levels"] = [2, 4, 6, 8, 10]
	app.continue_after_settlement()
	var relic_count := 0
	for rank in run.relic_stacks.values(): relic_count += int(rank)
	t.check(relic_count >= 1, "宝箱奖励实际兑换为遗物")
	# 捕获满员替换，不损失旧伙伴培养。
	while run.carried.size() < Balance.CARRIED_LIMIT: run.carried.append(run._make_record("fire_wild1", 10))
	var outgoing: Dictionary = run.carried[0].duplicate(true)
	var incoming := run._make_record("water_wild1", 9)
	run.pending_captures.append(incoming)
	var settle = load("res://scripts/ui/settlement_screen.gd").new()
	app._switch(settle)
	settle.find_child("CaptureSwap_%d" % int(outgoing["uid"]), true, false).pressed.emit()
	t.check(run.carried.any(func(r): return int(r["uid"]) == int(incoming["uid"])), "新捕获立即进入随身队伍")
	t.check(run.storage.has(outgoing), "换下成员完整保留培养")
	app.free()
	t.finish()
