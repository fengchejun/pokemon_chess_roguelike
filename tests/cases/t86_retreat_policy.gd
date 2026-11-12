extends RefCounted

func make_state(role: String, kind: String) -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.exploration_v2 = true; state.exploration_role = role; state.node_kind = kind
	state.stop_nests()
	return state

func run(t: TestContext) -> void:
	t.begin("按节点分类撤退、旧存档兼容与结算")
	for role in ["capture", "treasure"]:
		var state := make_state(role, "battle" if role != "treasure" else "event")
		state.retreat_disabled = true # 旧快照遗留字段不能继续封锁新规则。
		state.trainer().cell = Vector2i(3, 3)
		state.unit_by_uid(1).cell = Vector2i(4, 3)
		var hp := state.unit_by_uid(1).hp
		t.check(state.can_leave_node() and not state.can_escape(), "非普通战斗节点可直接离开")
		t.check(state.leave_node() and state.end_reason == "explored", "直接离开不计作清场胜利")
		t.eq(state.unit_by_uid(1).hp, hp, "直接离开不扣区外伙伴血量")
	var ordinary := make_state("starter", "battle")
	ordinary.trainer().cell = Vector2i(3, 3)
	t.check(not ordinary.can_leave_node() and not ordinary.can_escape() and not ordinary.leave_node(true), "普通战斗训练师未到撤离点不能撤退")
	ordinary.trainer().cell = Vector2i(0,3)
	t.check(not ordinary.can_escape() and not ordinary.leave_node(true), "站在旧撤退格也不能退出战斗")

	var app = load("res://scripts/main.gd").new(); app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region(); region.nodes["battle_2"]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node("battle_2"); app.show_preview([1, 2, 3]); app.current_screen._on_start()
	var capture: BattleState = app.current_screen.state
	app.current_screen.playback.finish_all(); app.current_screen.battle_notice.finish_all()
	t.check(not app.current_screen.leave_node_button.disabled and app.current_screen.leave_node_button.text == "返回区域", "捕捉开战即可直接返回")
	capture.debug_capture_percent = 100
	var target: CombatUnit = capture.alive_units("enemy")[0]
	capture.trainer().cell = target.cell + Vector2i.LEFT
	t.check(capture.capture_attempt(capture.trainer(), target).get("success", false), "真实捕获成功")
	var caught_species := target.species_id
	var old_caught_count: int = app.run.carried.filter(func(r): return r["species_id"] == caught_species).size()
	var trainer_hp := capture.trainer().hp
	t.check(capture.leave_node(), "有剩余野生单位也能直接返回")
	app.finish_battle(capture)
	t.check(app.run.carried.filter(func(r): return r["species_id"] == caught_species).size() > old_caught_count or not app.run.pending_captures.is_empty(), "提前离开保留已捕获成员")
	t.eq(app.run.trainer_hp, trainer_hp, "捕捉直接离开不产生撤退损耗")
	t.check(not app.run.get_region().nodes["battle_2"].get("challenge_reward_claimed", false), "捕捉离开不冒领奖励")
	# 事件战斗未清场可直接离开，仍可回访处理。
	region = app.run.get_region(); region.active_node = "event_1"
	app.run.region_data = region.to_dict()
	app.run.pending_captures.clear()
	var event_state := make_state("group", "battle")
	t.check(not event_state.leave_node(), "主动选择事件战斗后也不能撤退")
	app.battle_settled = false; app.finish_battle(event_state)
	t.check(not app.run.get_region().nodes["event_1"].get("done", false), "未胜利事件保持未完成")
	t.check(not app.run.get_region().nodes["event_1"].get("challenge_reward_claimed", false), "未胜利事件不发挑战遗物")
	app.free()
	t.finish()
