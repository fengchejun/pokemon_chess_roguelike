extends RefCounted

func run(t: TestContext) -> void:
	t.begin("辅助先行、后续重规划与额外施法兑现")
	_haste(t)
	_unused(t)
	_engine(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(5, 3)], ["wind_wild1", Vector2i(5, 4)]])
	state.node_kind = "battle"
	state.nest["alive"] = false
	state.trainer().cell = Vector2i(0, 3)
	state.trainer().hp = 300
	state.trainer().max_hp = 300
	state.unit_by_uid(100).skills = ["rock_push"]
	state.unit_by_uid(100).move_points = 2
	state.unit_by_uid(101).skills = ["tailwind"]
	state.unit_by_uid(101).move_points = 0
	return state

func _haste(t: TestContext) -> void:
	var state := _state()
	var before := BattleSnapshot.save_state(state)
	var plan := EnemyAI.plan(state)
	t.eq(BattleSnapshot.save_state(state), before, "规划不修改真实状态")
	t.check(not plan.is_empty() and plan[0].get("skill", {}).get("id") == "tailwind", "登记较晚的磁场加速先施放")
	var attackers := plan.filter(func(a): return int(a["uid"]) == 100)
	t.check(not attackers.is_empty(), "受益队员仍有行动")
	if not attackers.is_empty():
		t.eq(attackers[0]["move_path"].size(), 4, "按加速后的移动力重新规划四格路线")
		t.eq(attackers[0]["skill"].get("id"), "rock_push", "加速让原本够不到的近战实际出手")
	t.eq(EnemyAI.plan(state), plan, "辅助重排保持确定性")
	var actual := state.begin_enemy_phase()
	t.eq(actual, plan, "预告与实际执行使用同一顺序")
	var replay := _state()
	for action in plan:
		EnemyAI._execute_on(replay, action)
	while not state.enemy_phase_finished():
		state.step_enemy_phase()
	for unit in state.units:
		var other := replay.unit_by_uid(unit.uid)
		t.eq([unit.cell, unit.hp, unit.moved, unit.skill_used, unit.extra_casts], [other.cell, other.hp, other.moved, other.skill_used, other.extra_casts], "辅助规划与逐次执行一致")

func _unused(t: TestContext) -> void:
	for kind in ["moved", "frozen", "rooted", "adjacent"]:
		var state := _state()
		var target := state.unit_by_uid(100)
		if kind == "moved": target.moved = true
		if kind == "frozen": target.frozen = true
		if kind == "rooted": target.move_cancelled = true
		if kind == "adjacent":
			target.cell = Vector2i(1, 3)
			state.unit_by_uid(101).cell = Vector2i(1, 4)
		var plan := EnemyAI.plan(state)
		t.check(not plan.any(func(a): return a.get("skill", {}).get("id") == "tailwind"), "没有可用移动收益就不空放磁场加速：" + kind)

func _engine(t: TestContext) -> void:
	var state := _state()
	state.unit_by_uid(100).cell = Vector2i(2, 3)
	state.unit_by_uid(100).skills = ["rock_break"]
	state.unit_by_uid(100).moved = true
	state.unit_by_uid(101).cell = Vector2i(3, 3)
	state.unit_by_uid(101).skills = ["double_cast"]
	var plan := EnemyAI.plan(state)
	t.check(plan[0].get("skill", {}).get("id") == "double_cast", "电力引擎先于受益攻击者")
	t.eq(plan.filter(func(a): return a["uid"] == 100 and a.get("skill", {}).get("id") == "rock_break").size(), 2, "额外施法在本阶段实际兑现")
	var used := state.clone()
	used.unit_by_uid(100).skill_used = true
	var late := EnemyAI.plan(used)
	t.eq(late.filter(func(a): return a["uid"] == 100 and a.get("skill", {}).get("id") == "rock_break").size(), 1, "已经施法的友军收到引擎后仍能补一次")
	var lethal := state.clone()
	lethal.trainer().hp = 1
	var kill := EnemyAI.plan(lethal)
	t.eq(kill[0]["uid"], 100, "可直接击倒训练家时保留进攻优先")
	t.check(not kill.any(func(a): return a.get("skill", {}).get("id") == "double_cast"), "已能结束战斗时不多放辅助")
	var extra_engine := state.clone()
	extra_engine.units.append(CombatUnit.make("wind_wild1", "enemy", 102))
	extra_engine.unit_by_uid(102).cell = Vector2i(2, 4)
	extra_engine.unit_by_uid(102).skills = ["double_cast"]
	extra_engine.unit_by_uid(102).moved = true
	extra_engine.unit_by_uid(102).reg_index = 3
	var bounded := EnemyAI.plan(extra_engine)
	t.eq(bounded.filter(func(a): return a.get("skill", {}).get("id") == "double_cast").size(), 1, "已可完成两次施法时第二个引擎不重复浪费")
	var guarding := state.clone()
	guarding.nest["cell"] = Vector2i(2, 2)
	guarding.nest["alive"] = true
	guarding.begin_nest_guard(guarding.unit_by_uid(100), guarding.nest["cell"])
	t.check(not EnemyAI.plan(guarding).any(func(a): return a.get("skill", {}).get("id") == "double_cast"), "守护巢穴者不能用引擎绕过施法承诺")
