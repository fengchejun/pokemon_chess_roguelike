extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")
const Encounter = preload("res://scripts/rules/capture_encounter.gd")

func make_state() -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(5, 2)], ["water_wild1", Vector2i(6, 3)], ["rock_wild1", Vector2i(5, 4)]])
	state.stop_nests()
	state.node_kind = "battle"; state.exploration_v2 = true; state.exploration_role = "capture"
	state.retreat_disabled = true; state.capture_deadline = 8
	state.capture_exits = Encounter.EXITS.duplicate()
	return state

func enemy_turn(state: BattleState) -> void:
	state.begin_enemy_phase()
	while not state.enemy_phase_finished(): state.step_enemy_phase()
	state.end_enemy_phase()

func run(t: TestContext) -> void:
	t.begin("八回合捕捉、受惊逃跑与本层常见委托")
	var state := make_state()
	var starts := state.alive_units("enemy").map(func(u): return u.cell)
	for i in 3: enemy_turn(state)
	t.check(not state.ended and not state.capture_alerted, "前三回合未受惊不会结束")
	t.eq(state.alive_units("enemy").map(func(u): return u.cell), starts, "未受惊不主动进攻或逃跑")
	state.trainer().cell = Vector2i(4, 2)
	state.debug_capture_percent = 0
	var failed := state.capture_attempt(state.trainer(), state.unit_by_uid(100), 0.99)
	t.check(failed.get("ok", false) and not failed.get("success", true) and state.capture_alerted, "捕获失败也惊动全场")
	var plan := EnemyAI.plan(state)
	t.eq(plan.size(), 3, "三只均进入逃跑行动")
	t.check(plan.all(func(a): return a.get("capture_flee", false) and a["skill"].is_empty()), "受惊后逃跑而非进攻")
	t.check(plan.any(func(a): return not a["move_path"].is_empty()), "实际规划向撤离点移动")
	var clone := state.clone()
	t.check(clone.capture_alerted and clone.capture_exits == state.capture_exits, "预览克隆保留捕捉规则")
	# 普通攻击也会全场受惊；模拟预览不会改变真实状态。
	state = make_state()
	var foe := state.unit_by_uid(100)
	state.damage_unit(state.unit_by_uid(1), foe, 1, {"no_element": true})
	t.check(state.capture_alerted, "我方攻击惊动全场")
	# 到达不是立即离场，读档后仍等待下一次自己的行动。
	foe.cell = Vector2i(6, 1)
	Encounter.act(state, foe, {"move_path": [Vector2i(7, 1)]})
	t.check(foe.is_alive() and state.capture_exit_wait.has(foe.uid), "到达撤离点保留一轮拦截窗口")
	var saved := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(saved.capture_exit_wait, state.capture_exit_wait, "撤离等待随快照保存")
	var kills := state.enemy_kills.duplicate()
	var essence := state.essence_earned
	state.round += 1
	Encounter.act(state, foe, {"move_path": []})
	t.check(not foe.is_alive(), "下次行动仍在原撤离点则成功逃脱")
	t.eq(state.enemy_kills, kills, "逃脱不算击杀")
	t.eq(state.essence_earned, essence, "逃脱不发击倒原质")
	# 推离原点会打断等待，再次返回也得重新等。
	state = make_state(); state.capture_alerted = true; foe = state.unit_by_uid(100)
	foe.cell = Vector2i(7, 1)
	Encounter.act(state, foe, {"move_path": []})
	state.round += 1
	foe.cell = Vector2i(6, 1); state.apply_vine_on_landing(foe, false)
	t.check(not state.capture_exit_wait.has(foe.uid), "推离撤离点清除等待")
	Encounter.act(state, foe, {"move_path": [Vector2i(7, 1)]})
	t.check(foe.is_alive(), "返回撤离点不能沿用旧等待")
	# 玩家占住撤离点时不能重叠，禁锢仍沿用移动限制。
	state = make_state(); state.capture_alerted = true
	state.trainer().cell = Vector2i(7, 1); state.unit_by_uid(1).cell = Vector2i(7, 6)
	plan = EnemyAI.plan(state)
	t.check(plan.all(func(a): return not a["move_path"].has(Vector2i(7, 1)) and not a["move_path"].has(Vector2i(7, 6))), "不能穿过或占据被玩家封锁的撤离格")
	foe = state.unit_by_uid(100); foe.move_cancelled = true
	plan = EnemyAI.plan(state)
	t.check(plan.filter(func(a): return a["uid"] == foe.uid)[0]["move_path"].is_empty(), "不能移动时不会无视控制逃跑")
	# 八回合总上限，不要求主动惊动。
	state = make_state()
	for i in 7: enemy_turn(state)
	t.check(not state.ended and state.alive_enemy_count() == 3, "第七回合后仍可捕获")
	enemy_turn(state)
	t.check(state.ended and state.end_reason == "explored" and state.alive_enemy_count() == 0, "第八回合结束统一离场")
	# 跨主题、种子与访问检查固定三只、左侧出生、中央障碍与合法路线。
	var central_obstacles := 0
	for theme in BattleDB.THEME_IDS:
		var requested := Flow.request_species(theme)
		t.check(BattleDB.THEMES[theme]["primary"].has(requested), "委托来自本层主物种池")
		t.eq(SpeciesDB.element_of(requested), theme, "委托属性与本层最常见属性一致")
		for seed_value in range(1, 16):
			var run := RunState.new_run(seed_value)
			run.options["exploration_v2"] = true
			var region := Flow.create(0, theme); region.active_node = "battle_2"
			run.region_data = region.to_dict()
			var cfg := Flow.configure(run, {})
			t.eq(cfg["enemies"].size(), 3, "每次固定三只")
			var map := MapGenerator.generate(seed_value, 0)
			Flow.prepare_map(run, map)
			t.eq(map["fixed_deploy_area"], Balance.DEPLOY_AREA, "部署范围使用左侧正常区域")
			var board := make_state(); board.terrain = map["terrain"]
			for cell in [Vector2i(5, 2), Vector2i(6, 3), Vector2i(5, 4)] + Encounter.EXITS:
				t.check(PathFinder.path_distance(board, Vector2i(1, 3), cell, "fire") < 1000, "出生点、野生目标及撤离点之间有陆地通路")
			for cell in GridSpec.all_cells():
				if cell.x in [2, 3, 4] and TerrainDB.blocks_move(map["terrain"][GridSpec.index(cell)]): central_obstacles += 1
	t.check(central_obstacles > 0, "中央区域可以保留障碍")
	# 通过真实整备/部署路径验证，不只检查地图参数。
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region(); region.nodes["battle_2"]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node("battle_2"); app.show_preview([1, 2, 3]); app.current_screen._on_start()
	var live: BattleState = app.current_screen.state
	t.check(live.alive_units("player").all(func(u): return u.cell.x <= 1), "实际开战我方全部从左侧出生")
	t.eq(live.alive_enemy_count(), 3, "实际开战稳定三只野生宝可梦")
	t.eq(app.current_screen.board.capture_exits, Encounter.EXITS, "棋盘显示野生撤离点")
	t.check(app.current_screen.board.extraction_cells.is_empty(), "捕捉区不再误画我方撤离点")
	var hp := live.trainer().hp
	live.damage_unit(live.unit_by_uid(1), live.alive_units("enemy")[0], 1, {"no_element": true})
	while not live.ended and live.round <= 8: enemy_turn(live)
	t.check(live.ended and live.end_reason == "explored", "实际遭遇可由撤离或总时限完成")
	t.eq(live.trainer().hp, hp, "受惊野生单位不会转而攻击训练师")
	t.check(live.enemy_kills.is_empty() and live.essence_earned == 0, "实际逃跑不产生击倒奖励")
	app.free()
	t.finish()
