extends RefCounted

func run(t: TestContext) -> void:
	t.begin("敌方守点拾取、多点携带与夺回")
	_timing(t)
	_interrupt(t)
	_drops(t)
	_persistence(t)
	_ui(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(5, 3)], ["grass_wild1", Vector2i(6, 5)]])
	state.node_kind = "battle"
	state.nest["alive"] = false
	state.reward = {"state": "absent", "cell": Vector2i(-1, -1), "owner_uid": -1, "guard_uid": -1}
	state.add_reward_point(Vector2i(5, 3), "chest:enemy-test")
	return state

func _waiting() -> BattleState:
	var state := _state()
	state.begin_enemy_phase()
	state.end_enemy_phase()
	return state

func _carried() -> BattleState:
	var state := _waiting()
	state.begin_enemy_phase()
	return state

func _timing(t: TestContext) -> void:
	var state := _state()
	state.begin_enemy_phase()
	t.eq(state.reward["state"], "map", "站上去尚未经过敌方回合末不能领取")
	state.end_enemy_phase()
	t.eq(state.reward["state"], "guarding", "敌方回合末开始占点")
	t.eq(state.reward["guard_side"], "enemy", "占点记录所属方")
	t.eq(state.reward_count_held("enemy"), 0, "占点阶段尚未携带")
	state.damage_unit(state.unit_by_uid(1), state.unit_by_uid(100), 1, {"no_element": true})
	state.begin_enemy_phase()
	t.eq(state.reward["state"], "carried", "守过我方阶段后正式携带")
	t.eq(state.reward["owner_uid"], 100, "奖励点属于实际占点敌人")
	t.eq(state.reward_count_held("enemy"), 1, "被击伤但存活不打断占点")
	state.unit_by_uid(100).cell = Vector2i(4, 3)
	state.apply_vine_on_landing(state.unit_by_uid(100))
	t.eq(state.reward["state"], "carried", "拾取后可以离开奖励格")
	state.end_battle("escape")
	t.check(state.earned_reward_points().is_empty(), "敌方持有不能兑换我方奖励")
	var run := RunState.new_run(7201)
	run.mark_deployed([1, 2])
	t.eq(run.settle_battle(state)["pending_reward_choices"], 0, "敌方持有不增加结算选择")

func _interrupt(t: TestContext) -> void:
	var pushed := _waiting()
	var enemy := pushed.unit_by_uid(100)
	PushResolver.push(pushed, enemy, Vector2i.LEFT, 1, 0, "中断占点", "player", 1)
	t.eq(pushed.reward["state"], "map", "推离当场中断敌方占点")
	PushResolver.push(pushed, enemy, Vector2i.RIGHT, 1, 0, "推回", "player", 1)
	pushed.begin_enemy_phase()
	t.eq(pushed.reward["state"], "map", "中途离开再回来仍不能立即领取")
	pushed.end_enemy_phase()
	t.eq(pushed.reward["state"], "guarding", "下一次敌方回合末重新占点")
	var dead := _waiting()
	dead.kill_unit(dead.unit_by_uid(100), "占点时击杀", "player", 1)
	t.eq(dead.reward["state"], "map", "占点中死亡只解除占领")
	var captured := _waiting()
	captured.on_captured(captured.unit_by_uid(100), "rock_wild1", 2)
	t.eq(captured.reward["state"], "map", "占点中被捕获后地面点仍存在")
	var ice := _waiting()
	ice.set_terrain(ice.unit_by_uid(100).cell, TerrainDB.ICE)
	ice.unit_by_uid(100).last_move_direction = Vector2i.LEFT
	ice._settle_ice_slides()
	t.eq(ice.reward["state"], "map", "环境冰面滑离也中断占点")

func _drops(t: TestContext) -> void:
	var state := _carried()
	var enemy := state.unit_by_uid(100)
	var source: String = state.reward["id"]
	enemy.cell = Vector2i(4, 3)
	state.kill_unit(enemy, "夺回", "player", 1)
	t.eq(state.reward["state"], "map", "正常击杀掉落拾取的奖励点")
	t.eq(state.reward["cell"], Vector2i(4, 3), "按实际死亡位置掉落")
	t.eq(state.reward["id"], source, "夺回不改变原始来源")
	state.kill_unit(enemy, "重复击杀", "player", 1)
	t.eq(state.all_rewards().size(), 1, "重复击杀不重复生成")
	state.unit_by_uid(1).cell = Vector2i(4, 3)
	state._begin_reward_guard()
	state._finish_reward_guard()
	state.end_battle("escape")
	t.eq(state.earned_reward_points().size(), 1, "掉落后可由我方拾取并兑换")
	for kind in [TerrainDB.DEEP, TerrainDB.LAVA, TerrainDB.PIT]:
		var fatal := _carried()
		fatal.set_terrain(Vector2i(6, 3), kind)
		PushResolver.push(fatal, fatal.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "推入危险格", "player", 1)
		t.eq(fatal.reward["state"], "lost", "危险格死亡不掉落拾取点")
	var captured := _carried()
	captured.capture_options["capture_field_join"] = true
	captured.on_captured(captured.unit_by_uid(100), "rock_wild1", 2)
	t.eq(captured.reward["state"], "lost", "捕获沿用不掉落规则")
	t.eq(captured.reward_count_held("player"), 0, "捕获转我方不能偷偷带入奖励")
	var multi := _state()
	multi.unit_by_uid(100).reward_carrier = true
	multi.add_reward_point(Vector2i(5, 3), "nest:another")
	multi._begin_reward_guard("enemy")
	multi._finish_reward_guard("enemy")
	t.eq(multi.reward_count_held("enemy"), 3, "可同时携带两拾取点与一个初始点")
	multi.kill_unit(multi.unit_by_uid(100), "多点掉落", "player", 1)
	t.eq(multi.all_rewards().filter(func(p): return p.get("state") == "map").size(), 3, "全部原点和初始点各掉一次")

func _persistence(t: TestContext) -> void:
	var waiting := BattleSnapshot.load_state(BattleSnapshot.save_state(_waiting())).clone()
	waiting.begin_enemy_phase()
	t.eq(waiting.reward["state"], "carried", "等待期间克隆读档不会提前或漏领")
	var carried := BattleSnapshot.load_state(BattleSnapshot.save_state(waiting)).clone()
	t.eq(carried.reward_count_held("enemy"), 1, "携带状态克隆读档保留")
	carried.end_battle("escape")
	var region := RegionState.create_floor(0, "rock")
	region.active_node = "battle_1"
	region.store_battle("battle_1", carried)
	var run := RunState.new_run(7202)
	var resumed := region.resume_node("battle_1", run.build_deploy_units([1, 2]), {"enemies": [], "reinforce": ["rock_wild1"]})
	t.check(resumed != null, "撤离后可重访")
	if resumed != null:
		t.eq(resumed.reward_count_held("enemy"), 1, "敌人重置位置时保留携带点归属")
		var cell: Vector2i = resumed.unit_by_uid(100).cell
		resumed.kill_unit(resumed.unit_by_uid(100), "重访夺回", "player", 1)
		t.eq(resumed.reward["cell"], cell, "重访死亡在当前格掉落")
	var old := _state()
	old.unit_by_uid(1).cell = old.reward["cell"]
	old._begin_reward_guard()
	old.reward.erase("guard_side")
	old._finish_reward_guard()
	t.eq(old.reward["owner_uid"], 1, "旧档缺少所属方字段仍按我方占点")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(7203)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _carried()
	app._switch(screen)
	screen.playback.finish_all()
	screen.refresh_all()
	t.check(screen.objective_label.text.contains("我持 0 · 敌持 1"), "界面区分敌我持有数")
	screen.select_unit(100)
	t.check(screen.unit_body.text.contains("抢走的奖励点"), "敌人详情说明拾取携带和掉落规则")
	t.eq(screen.board.reward["owner_uid"], 100, "棋盘收到敌人携带标记")
	app.free()
