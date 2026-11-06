extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")

func run(t: TestContext) -> void:
	t.begin("捕捉支援、禁止撤退与未知节点显示")
	var state := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter", "rock_starter"], [["rock_wild1", Vector2i(5, 5)]])
	state.units.append(CombatUnit.make("rock_starter", "player", 4))
	var target := state.unit_by_uid(100)
	target.hp = target.max_hp
	state.trainer().cell = Vector2i(4, 5)
	for ally in state.alive_units("player"):
		if not ally.is_trainer: ally.cell = Vector2i(0, 0)
	t.eq(CaptureSystem.support_count(state, target), 0, "训练师不提供支援，5格外不提供支援")
	t.eq(CaptureSystem.chance_percent_for(state, target), 1, "满血无支援1%")
	state.unit_by_uid(1).cell = Vector2i(1, 1)
	t.eq(CaptureSystem.chance_percent_for(state, target), 11, "四格斜向边界计入，单只+10个百分点")
	for id in [2, 3, 4]: state.unit_by_uid(id).cell = Vector2i(2 + id, 4)
	t.eq(CaptureSystem.chance_percent_for(state, target), 31, "四只最多加30个百分点")
	state.unit_by_uid(4).hp = 0
	state.unit_by_uid(3).summon_owner_uid = 1
	t.eq(CaptureSystem.support_count(state, target), 2, "濒死及召唤物不计入")
	state.capture_aid = true
	t.eq(CaptureSystem.chance_percent_for(state, target), 41, "支援与20点辅助叠加")
	var expected := CaptureSystem.chance_for(state, target)
	var result := CaptureSystem.attempt(state, state.trainer(), target, 0.999)
	t.eq(result["chance"], expected, "实际投骰与显示同源")
	t.check(not state.capture_aid, "投骰后消耗捕获辅助")
	state.debug_capture_percent = 0
	t.eq(CaptureSystem.chance_percent_for(state, target), 0, "调试概率仍精确覆盖")
	state.debug_capture_percent = -1
	target.hp = 1
	state.capture_aid = true
	t.check(CaptureSystem.chance_for(state, target) <= 1.0, "总概率不超过100%")
	# 新开局未知节点只显示连线/可达性，通知与确认框不泄露类型。
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8401)
	app.run.region_mode = true
	app.run.options["exploration_v2"] = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_region()
	var region = app.run.get_region()
	t.check(region.nodes["battle_5"]["unlocked"] and not region.nodes["battle_5"]["revealed"], "邻接委托已点亮但未知类型")
	var node_button: Button = app.current_screen.find_child("Node_battle_5", true, false)
	t.check(node_button.text.contains("未知地点") and not node_button.text.contains("委托"), "地图不提前泄露委托")
	app.current_screen._confirm_entry("battle_5")
	var dialogs: Array = app.current_screen.get_children().filter(func(child): return child is ConfirmationDialog)
	t.check(dialogs.back().title.contains("未知地点") and not dialogs.back().dialog_text.contains("可达鸭"), "确认框不泄露未知事件")
	app.enter_region_node("empty_2")
	var region2 = app.run.get_region()
	t.check(region2.nodes["event_1"]["unlocked"], "到达空地可探索相邻普通事件")
	region2.complete_visit(); app.run.region_data = region2.to_dict()
	app.enter_region_node("event_1")
	region2 = app.run.get_region()
	t.check(region2.nodes["battle_5"]["unlocked"], "普通事件进入后点亮邻接节点")
	t.check(not region2.nodes["battle_5"]["revealed"], "点亮不等于揭示类型")
	region2.complete_visit(); app.run.region_data = region2.to_dict(); app.show_region()
	t.check(app.current_screen.find_child("Node_event_1", true, false).text.contains("嬉戏"), "去过的事件显示实际类型")
	# 底层不能通过按钮之外的接口提前撤退；解谜例外。
	var capture := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	capture.exploration_v2 = true; capture.exploration_role = "capture"; capture.retreat_disabled = true
	capture.stop_nests()
	t.check(not capture.can_escape() and not capture.can_leave_node() and not capture.leave_node(true), "捕捉未完成不能主动撤离")
	capture.exploration_role = "starter"
	t.check(not capture.can_escape() and not capture.leave_node(true), "普通实战也不能紧急撤退")
	capture.exploration_role = "treasure"; capture.node_kind = "event"
	t.check(capture.can_leave_node() and capture.leave_node(), "解谜仍可暂离")
	# 各种地形跨种子可出现，部署格和对岸解法不被随机装饰封死。
	var found := {}
	for seed_value in range(1, 41):
		app.run.seed = seed_value
		var ledger = app.run.get_region(); ledger.active_node = "battle_4"; app.run.region_data = ledger.to_dict()
		var map := MapGenerator.generate(seed_value, 0)
		Flow.prepare_map(app.run, map)
		for value in map["terrain"]: found[value] = true
		t.eq(map["terrain"][GridSpec.index(Vector2i(3, 3))], TerrainDB.DEEP, "保护解谜深水主障碍")
		for cell in Balance.DEPLOY_AREA:
			t.check(TerrainDB.can_stand(map["terrain"][GridSpec.index(cell)], "fire"), "部署区始终可站立")
	t.eq(found.size(), TerrainDB.ALL.size(), "全部地形类型均可由完整池出现")
	# 横幅结束后刷新按钮，不会把正常离开永远锁成灰色。
	var board_state := TestScenario.make_state(["fire_starter"], [])
	board_state.node_kind = "event"
	var screen = load("res://scripts/ui/battle_screen.gd").new(); screen.state = board_state
	app._switch(screen)
	screen.playback.finish_all(); screen.battle_notice.finish_all()
	t.check(not screen.leave_node_button.disabled, "无横幅时解谜/事件正常离开可用")
	screen.battle_notice.push("我方回合", "player")
	t.check(screen.leave_node_button.disabled, "横幅期间暂时禁用")
	screen.battle_notice.advance(2.0)
	t.check(not screen.leave_node_button.disabled, "横幅结束后离开按钮自动恢复")
	# 老版当前流程快照缺少新字段时，继续冒险也强制应用新规则。
	capture.ended = false; capture.exploration_role = "capture"; capture.node_kind = "battle"
	app.run.battle_snapshot = BattleSnapshot.save_state(capture)
	app.run.battle_snapshot["fields"].erase("retreat_disabled")
	var path := "res://.test_feedback_retreat.json"
	SaveSystem.save_run(app.run, path)
	app.continue_run(path)
	t.check(app.current_screen.state.retreat_disabled and not app.current_screen.state.can_escape(), "旧快照读档后也禁止提前撤退")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	app.free()
	t.finish()
