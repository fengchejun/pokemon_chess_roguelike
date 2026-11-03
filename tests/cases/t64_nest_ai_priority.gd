extends RefCounted

func run(t: TestContext) -> void:
	t.begin("巢穴守护权衡与增援下一轮实际行动")
	var healthy := _state()
	var action := _action(healthy, 100)
	t.check(not action.has("guard") and not action.get("skill", {}).is_empty(), "满耐久巢穴附近优先攻击可命中的玩家")
	var moderate := _state()
	moderate.nest["hp"] = 2
	t.check(not _action(moderate, 100).has("guard"), "剩余两点耐久时仍更倾向有效攻击")
	var hurt := _state()
	hurt.nest["hp"] = 1
	t.check(_action(hurt, 100).has("guard"), "残血巢穴受附近攻击者威胁时主动守护")
	var lethal := _state()
	lethal.nest["hp"] = 1
	lethal.unit_by_uid(1).hp = 1
	t.check(not _action(lethal, 100).has("guard"), "可击杀玩家时不机械地放弃进攻守巢")
	var far := _state()
	far.nest["hp"] = 1
	far.unit_by_uid(1).cell = Vector2i(0, 7)
	var distant := _action(far, 100)
	t.check(not distant.has("guard") and not distant.get("move_path", []).is_empty(), "巢穴残血但没有近处威胁时主动接敌")
	var shared := _state()
	shared.nest["hp"] = 1
	var guard := CombatUnit.make("rock_wild1", "enemy", 101)
	guard.cell = Vector2i(4, 4)
	shared.units.append(guard)
	shared.begin_nest_guard(guard, shared.nest["cell"])
	t.check(not _action(shared, 100).has("guard"), "已有足够拦截时其他敌人继续攻击")
	_spawn(t, Vector2i(2, 2), false)
	_spawn(t, Vector2i(0, 2), true)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 2)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(4, 3)
	state.unit_by_uid(1).cell = Vector2i(2, 2)
	state.unit_by_uid(1).skills = ["rock_break"]
	state.unit_by_uid(100).skills = ["rock_break"]
	state.unit_by_uid(100).max_hp = 100
	state.unit_by_uid(100).hp = 100
	return state

func _action(state: BattleState, uid: int) -> Dictionary:
	for action in EnemyAI.plan(state):
		if int(action["uid"]) == uid:
			return action
	return {}

func _cycle(state: BattleState) -> Array:
	var plan := state.begin_enemy_phase()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
	state.end_enemy_phase()
	return plan

func _spawn(t: TestContext, player_cell: Vector2i, require_move: bool) -> void:
	var state := _state()
	state.unit_by_uid(100).cell = Vector2i(7, 7)
	state.unit_by_uid(100).skills = []
	state.unit_by_uid(100).move_points = 0
	state.unit_by_uid(1).cell = player_cell
	state.unit_by_uid(1).max_hp = 200
	state.unit_by_uid(1).hp = 200
	state.start_round()
	var spawned: CombatUnit = state.units.back()
	spawned.skills = ["rock_break"]
	var born_cell := spawned.cell
	t.check(spawned.fresh_spawn, "第2轮生成增援")
	var birth_plan := _cycle(state)
	t.check(not birth_plan.any(func(a): return int(a["uid"]) == spawned.uid), "出生轮不执行移动或施法")
	t.eq(spawned.cell, born_cell, "出生轮保持原格")
	t.check(state.round == 3 and not spawned.fresh_spawn, "第3轮已解除出生待机")
	var saved := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.check(not saved.unit_by_uid(spawned.uid).fresh_spawn, "读档不会额外增加出生待机")
	var hp := state.unit_by_uid(1).hp
	var next_plan := _cycle(state)
	var own_actions := next_plan.filter(func(a): return int(a["uid"]) == spawned.uid)
	t.check(not own_actions.is_empty(), "出生后的下一轮真实进入AI计划")
	t.check(state.unit_by_uid(1).hp < hp, "下一轮真实执行攻击并造成伤害")
	t.check(spawned.guard_nest.x < 0, "健康巢穴不会让刚恢复行动的增援原地守护")
	if require_move:
		t.check(spawned.cell != born_cell, "下一轮能实际移动接近并攻击玩家")
