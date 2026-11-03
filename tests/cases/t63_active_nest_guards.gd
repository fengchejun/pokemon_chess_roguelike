extends RefCounted

func run(t: TestContext) -> void:
	t.begin("主动守巢、均分拦截与后期增援经验")
	_guard(t)
	_interrupt(t)
	_ai(t)
	_spawn_and_xp(t)
	_save(t)
	_capture_and_area(t)
	_ui(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 2)], ["rock_wild1", Vector2i(4, 4)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(4, 3)
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	state.unit_by_uid(1).skills = ["rock_break"]
	for enemy in state.alive_units("enemy"):
		enemy.max_hp = 100
		enemy.hp = 100
	return state

func _attack(state: BattleState) -> Dictionary:
	return SkillResolver.apply(state, state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": state.nest["cell"]}, false)

func _guard(t: TestContext) -> void:
	var state := _state()
	var first := state.unit_by_uid(100)
	var second := state.unit_by_uid(101)
	t.check(state.begin_nest_guard(first, state.nest["cell"]), "相邻守军可主动守护")
	t.check(state.begin_nest_guard(second, state.nest["cell"]), "第二名守军可同时守护")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 2, "两名守军提供两次拦截")
	first.extra_casts = 1
	t.check(not first.can_act_skill(), "守护后额外施法也不能绕过动作承诺")
	t.check(not state.begin_nest_guard(first, state.nest["cell"]), "不能重复守护刷新次数")
	var preview := state.preview_skill(state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": state.nest["cell"]})
	t.check(preview.get("guard_intercepted", false), "预览显示守军拦截")
	t.eq(preview["hits"].size(), 2, "预览显示所有分伤守军")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 2, "预览不消耗实战拦截")
	_attack(state)
	t.eq([first.hp, second.hp], [95, 95], "10伤害由两守军各承受5点")
	t.eq(state.nest["hp"], 3, "第一次拦截巢穴不掉耐久")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 1, "一次攻击只消耗一次拦截")
	_attack(state)
	t.eq([first.hp, second.hp], [90, 90], "第二次拦截仍由所有守军均分")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 0, "两次用完")
	_attack(state)
	t.eq(state.nest["hp"], 2, "次数用尽后直接伤巢")
	t.eq([first.hp, second.hp], [90, 90], "守军不会无限自动挡伤")
	var odd := _state()
	odd.begin_nest_guard(odd.unit_by_uid(100), odd.nest["cell"])
	odd.begin_nest_guard(odd.unit_by_uid(101), odd.nest["cell"])
	var summary := {"skill_id": "rock_break", "hits": []}
	SkillResolver._hit_nest(odd, odd.unit_by_uid(1), odd.nest["cell"], summary, 1, 11)
	t.eq([odd.unit_by_uid(100).hp, odd.unit_by_uid(101).hp], [94, 95], "奇数分伤6加5，不凭空增加总伤害")

func _interrupt(t: TestContext) -> void:
	var state := _state()
	var first := state.unit_by_uid(100)
	var second := state.unit_by_uid(101)
	first.fresh_spawn = true
	t.check(not state.begin_nest_guard(first, state.nest["cell"]), "出生待机单位不能立刻守护")
	first.fresh_spawn = false
	state.begin_nest_guard(first, state.nest["cell"])
	state.begin_nest_guard(second, state.nest["cell"])
	PushResolver.push(state, first, Vector2i.UP, 1, 0, "测试")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 1, "推离四邻后失去拦截")
	second.frozen = true
	t.eq(state.nest_guard_charges(state.nest["cell"]), 0, "冻结失去守护资格")
	_attack(state)
	t.eq(state.nest["hp"], 2, "控制守军可直接攻击巢穴")
	second.frozen = false
	state.begin_enemy_phase()
	t.check(first.guard_nest.x < 0 and second.guard_nest.x < 0, "下一敌方阶段开始清除旧守护")

func _ai(t: TestContext) -> void:
	var state := _state()
	state.unit_by_uid(100).skills = []
	state.unit_by_uid(101).skills = []
	state.unit_by_uid(100).moved = true
	state.unit_by_uid(101).moved = true
	var plan := state.begin_enemy_phase()
	t.eq(plan.filter(func(a): return a.has("guard")).size(), 2, "AI会规划多人守护")
	while not state.enemy_phase_finished():
		state.step_enemy_phase()
	t.eq(state.nest_guard_charges(state.nest["cell"]), 2, "真实执行与规划守护一致")
	t.check(not state.unit_by_uid(100).can_act_skill(), "真实守护消耗施法机会")

func _spawn_and_xp(t: TestContext) -> void:
	var state := _state()
	state.round = 10
	state.nest["pending_waves"] = 1
	state._try_spawn_wave()
	var late: CombatUnit = state.units.back()
	t.check(late.spawned_from_nest and late.spawn_round == 10, "记录真实出生轮次")
	t.eq(GridSpec.manhattan(late.cell, state.nest["cell"]), 1, "只在上下左右空格生成")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	var saved_late := restored.unit_by_uid(late.uid)
	t.check(saved_late.spawned_from_nest and saved_late.spawn_round == 10, "读档保留增援分类")
	restored.kill_unit(saved_late, "测试", "player", 1)
	t.eq(restored.enemy_kills.back()["xp_reward"], 0, "后期出生增援击杀经验为0")
	state.kill_unit(state.unit_by_uid(100), "测试", "player", 1)
	t.check(int(state.enemy_kills.back()["xp_reward"]) > 0, "第10轮击杀初始敌人仍有经验")
	var early := _state()
	early.round = 8
	early.nest["pending_waves"] = 1
	early._try_spawn_wave()
	var early_spawn: CombatUnit = early.units.back()
	early.round = 20
	early.kill_unit(early_spawn, "测试", "player", 1)
	t.check(int(early.enemy_kills.back()["xp_reward"]) > 0, "第8轮出生增援即使晚杀仍有经验")
	var run := RunState.new_run(4242)
	run.region_mode = true
	run.mark_deployed([1])
	t.eq(run.battle_kill_xp_for(restored, 1), 0, "即时经验不会补发后期增援经验")
	restored.nest["alive"] = false
	restored.end_battle("victory")
	run.settle_battle(restored)
	t.eq(run.record_by_uid(1)["xp"], 0, "战后也不补发后期增援击杀经验")

func _save(t: TestContext) -> void:
	var state := _state()
	state.begin_nest_guard(state.unit_by_uid(100), state.nest["cell"])
	state.begin_nest_guard(state.unit_by_uid(101), state.nest["cell"])
	_attack(state)
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.nest_guard_charges(restored.nest["cell"]), 1, "读档保留已经消耗的次数")
	t.eq(restored.clone().nest_guard_charges(restored.nest["cell"]), 1, "克隆保留守护状态")
	var before := restored.unit_by_uid(100).hp
	_attack(restored)
	t.eq(restored.unit_by_uid(100).hp, before - 5, "读档后剩余一次拦截正确分伤")
	t.eq(restored.nest_guard_charges(restored.nest["cell"]), 0, "读档不刷新已消耗拦截")

func _capture_and_area(t: TestContext) -> void:
	var state := _state()
	state.begin_nest_guard(state.unit_by_uid(100), state.nest["cell"])
	state.begin_nest_guard(state.unit_by_uid(101), state.nest["cell"])
	SkillResolver.resolve_channel(state, state.unit_by_uid(1), "fire_burst", [state.nest["cell"]])
	t.eq(state.nest_guard_charges(state.nest["cell"]), 1, "一次范围攻击对同一巢穴只消耗一次拦截")
	t.eq(state.nest["hp"], 3, "范围攻击拦截后巢穴不掉耐久")
	var captured := _state()
	var guard := captured.unit_by_uid(100)
	captured.begin_nest_guard(guard, captured.nest["cell"])
	captured.capture_options["capture_field_join"] = true
	captured.on_captured(guard, guard.species_id, guard.hp)
	t.check(guard.side == "player" and guard.guard_nest.x < 0, "捕获转阵营解除敌方守护")
	t.check(guard.can_act_skill(), "捕获后立即行动不被旧守护标记锁死")
	var late := _state()
	late.round = 10
	late.nest["pending_waves"] = 1
	late._try_spawn_wave()
	var target: CombatUnit = late.units.back()
	late.on_captured(target, target.species_id, target.hp)
	t.check(int(late.captured.back()["xp_reward"]) > 0, "只限制击杀经验，捕获奖励沿用原规则")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state()
	var state: BattleState = screen.state
	state.begin_nest_guard(state.unit_by_uid(100), state.nest["cell"])
	state.begin_nest_guard(state.unit_by_uid(101), state.nest["cell"])
	app._switch(screen)
	screen.refresh_all()
	screen._show_terrain(state.nest["cell"])
	t.check(screen.terrain_label.text.contains("巢穴（不可站立）"), "巢穴详情不再误标平地")
	t.check(screen.terrain_label.text.contains("移动消耗：不可进入"), "巢穴详情明确不能作为移动终点")
	t.eq(screen.board.nest_guard_counts[state.nest["cell"]], 2, "棋盘显示实际拦截次数")
	state.unit_by_uid(100).spawned_from_nest = true
	state.unit_by_uid(100).spawn_round = 10
	screen.viewed_enemy_uid = 100
	screen.refresh_all()
	t.check(screen.unit_title.text.contains("击杀无经验"), "后期增援有明确经验提示")
	app.free()
