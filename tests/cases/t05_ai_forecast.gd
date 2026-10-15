extends RefCounted

## 威胁预告：确定性、行动顺序、携带者优先级、计划与执行一致


func run(t: TestContext) -> void:
	t.begin("AI 与威胁预告")
	_t_determinism(t)
	_t_order(t)
	_t_reward_approach(t)
	_t_skill_choice(t)
	_t_double_cast(t)
	_t_execution_matches(t)
	_t_rooted_and_spawn(t)
	t.finish()


func _mix_state() -> BattleState:
	var state := TestScenario.make_state(["fire_starter", "water_starter"], [
		["rock_wild1", Vector2i(6, 3)],
		["fire_wild1", Vector2i(5, 5)],
		["water_wild1", Vector2i(6, 6)],
	])
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	state.unit_by_uid(2).cell = Vector2i(2, 5)
	return state


func _t_determinism(t: TestContext) -> void:
	var state := _mix_state()
	var first := state.forecast()
	var second := state.forecast()
	t.eq(first, second, "同一状态两次计划完全一致")


func _t_order(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(6, 3)],
		["fire_wild1", Vector2i(6, 4)],
		["water_wild1", Vector2i(6, 5)],
	])
	var plan := state.forecast()
	t.check(plan.size() >= 3, "计划包含全部敌人动作")
	if plan.size() >= 3:
		var elements: Array = []
		for action in plan:
			var unit := state.unit_by_uid(int(action["uid"]))
			elements.append(unit.element)
		t.eq(elements, ["rock", "fire", "water"], "行动顺序按初始部署顺序")


func _t_reward_approach(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "water_starter"], [
		["electric_wild1", Vector2i(0, 4)],
	])
	var player := state.unit_by_uid(1)
	state.trainer().cell = Vector2i(0, 0)
	player.cell = Vector2i(2, 3)
	player.hp = 2
	var other := state.unit_by_uid(2)
	other.cell = Vector2i(0, 6)
	state.reward["cell"] = Vector2i(0, 3)
	var plan := state.forecast()
	t.check(plan.size() >= 1, "敌人有行动计划")
	state.reward["state"] = "destroyed"
	state._forecast_signature = ""
	var no_reward_plan := state.forecast()
	t.eq(plan, no_reward_plan, "敌人不再为领取旧 Buff 而改变行动")


func _t_skill_choice(t: TestContext) -> void:
	var heal := TestScenario.make_state(["fire_starter"], [
		["grass_wild1", Vector2i(4, 4)], ["rock_wild1", Vector2i(5, 4)],
	])
	heal.trainer().cell = Vector2i(0, 0)
	heal.unit_by_uid(1).cell = Vector2i(4, 6)
	heal.unit_by_uid(100).moved = true
	heal.unit_by_uid(101).hp = 1
	var heal_plan := EnemyAI.plan(heal)
	t.check(not heal_plan.is_empty(), "草怪可规划行动")
	if not heal_plan.is_empty():
		t.eq(String(heal_plan[0]["skill"].get("id", "")), "herbal_heal", "濒危友军在攻击范围内时，草怪优先治疗")

	var freeze := TestScenario.make_state([], [["ice_wild1", Vector2i(4, 4)]])
	freeze.trainer().cell = Vector2i(4, 2)
	freeze.unit_by_uid(100).moved = true
	var freeze_plan := EnemyAI.plan(freeze)
	t.check(not freeze_plan.is_empty(), "冰怪可规划行动")
	if not freeze_plan.is_empty():
		t.eq(String(freeze_plan[0]["skill"].get("id", "")), "freeze_ray", "冻结高威胁目标比单次 1 点伤害更有价值")

	var rain := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(5, 5)]])
	rain.trainer().cell = Vector2i(0, 0)
	rain.unit_by_uid(1).cell = Vector2i(3, 3)
	rain.unit_by_uid(100).moved = true
	var rain_plan := EnemyAI.plan(rain)
	t.check(not rain_plan.is_empty(), "水怪可规划行动")
	if not rain_plan.is_empty():
		t.eq(String(rain_plan[0]["skill"].get("id", "")), "rain_call", "无直接命中时，水怪在目标附近铺设浅水")

	for cell in GridSpec.all_cells():
		rain.set_terrain(cell, TerrainDB.WATER)
	rain.unit_by_uid(100).moved = false
	var no_change_plan := EnemyAI.plan(rain)
	t.check(not no_change_plan.is_empty(), "已有水域时仍能规划移动")
	if not no_change_plan.is_empty():
		t.check(String(no_change_plan[0]["skill"].get("id", "")) != "rain_call", "不会重复施放无法改变地形的造雨术")


func _t_double_cast(t: TestContext) -> void:
	var state := TestScenario.make_state([], [
		["wind_wild1", Vector2i(5, 3)], ["rock_wild1", Vector2i(4, 3)],
	])
	state.trainer().cell = Vector2i(2, 3)
	state.unit_by_uid(100).moved = true
	state.unit_by_uid(101).moved = true
	var forecast := EnemyAI.plan(state)
	var rock_actions := 0
	for action in forecast:
		if int(action["uid"]) == 101 and not (action["skill"] as Dictionary).is_empty():
			rock_actions += 1
	t.check(not forecast.is_empty(), "风岩组合有行动计划")
	if not forecast.is_empty():
		t.eq(String(forecast[0]["skill"].get("id", "")), "double_cast", "有后续行动机会时风怪选择额外施法")
	t.eq(rock_actions, 2, "受加速2影响的岩怪同阶段最多施放两次")
	var actions := state.begin_enemy_phase()
	t.eq(actions, forecast, "额外施法计划与实际阶段一致")
	while not state.enemy_phase_finished():
		state.step_enemy_phase()
	t.eq(state.unit_by_uid(101).extra_casts, 0, "第二次技能消耗额外施法机会")
	var late_support := TestScenario.make_state([], [
		["rock_wild1", Vector2i(4, 3)], ["wind_wild1", Vector2i(5, 3)],
	])
	late_support.trainer().cell = Vector2i(2, 3)
	late_support.unit_by_uid(100).moved = true
	late_support.unit_by_uid(101).moved = true
	var late_plan := EnemyAI.plan(late_support)
	for action in late_plan:
		if int(action["uid"]) == 101:
			t.check(String(action["skill"].get("id", "")) != "double_cast", "已行动友军无法再兑现额外施法，不选择加速2")

	var finished := TestScenario.make_state([], [
		["wind_wild1", Vector2i(5, 3)], ["rock_wild1", Vector2i(4, 3)],
	])
	finished.trainer().cell = Vector2i(2, 3)
	finished.trainer().hp = 1
	finished.unit_by_uid(100).moved = true
	finished.unit_by_uid(101).moved = true
	var ended_actions := finished.begin_enemy_phase()
	while not finished.enemy_phase_finished():
		finished.step_enemy_phase()
	t.check(finished.ended, "训练家倒下后战斗立即结束")
	t.check(finished.enemy_phase_finished(), "提前结束不会继续执行额外施法队列")
	t.check(ended_actions.size() >= 1, "提前结束场景产生行动计划")


func _t_execution_matches(t: TestContext) -> void:
	var state := _mix_state()
	var forecast := state.forecast()
	var actions := state.begin_enemy_phase()
	t.eq(actions, forecast, "预告与实际计划一致")
	var executed: Array = []
	while not state.enemy_phase_finished():
		var action := state.step_enemy_phase()
		if action.is_empty():
			break
		executed.append(action)
	t.eq(executed, actions, "实际执行的动作序列与计划一致")
	# 手工重放计划：结果状态应与真实执行一致
	var replay := _mix_state()
	for action in actions:
		var unit := replay.unit_by_uid(int(action["uid"]))
		for cell in action.get("move_path", []):
			unit.cell = cell
		var skill: Dictionary = action.get("skill", {})
		if not skill.is_empty():
			SkillResolver.apply(replay, unit, String(skill["id"]), skill["target"], false)
	t.eq(_state_signature(replay), _state_signature(state), "重放结果与真实状态一致")


func _state_signature(state: BattleState) -> String:
	var parts: Array = []
	for unit in state.units:
		parts.append("%d:%d,%d:%d" % [unit.uid, unit.cell.x, unit.cell.y, unit.hp])
	var terrain_text := ""
	for value in state.terrain:
		terrain_text += str(int(value))
	parts.append(terrain_text)
	return "|".join(parts)


func _t_rooted_and_spawn(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(6, 3)],
	], [], {}, {}, ["fire_wild1"])
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	var rock := state.unit_by_uid(100)
	state.apply_root(rock)
	state.start_round()
	t.eq(rock.move_cancelled, true, "被定身的敌人本回合不能移动")
	var plan := state.forecast()
	for action in plan:
		if int(action["uid"]) == rock.uid:
			t.eq((action["move_path"] as Array).size(), 0, "定身单位计划中没有移动")
	# 新生成单位在洞口待机，不进入当轮计划。
	var spawn_plan := state.forecast()
	var spawned_seen := false
	for action in spawn_plan:
		var unit := state.unit_by_uid(int(action["uid"]))
		if unit != null and unit.fresh_spawn:
			spawned_seen = true
			t.eq((action["skill"] as Dictionary).is_empty(), true, "新生成单位不施放技能")
	t.eq(spawned_seen, false, "新生成单位当轮不在行动计划中")
