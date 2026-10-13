extends RefCounted

## 威胁预告：确定性、行动顺序、携带者优先级、计划与执行一致


func run(t: TestContext) -> void:
	t.begin("AI 与威胁预告")
	_t_determinism(t)
	_t_order(t)
	_t_reward_approach(t)
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
	if plan.size() >= 1:
		var action: Dictionary = plan[0]
		var skill: Dictionary = action.get("skill", {})
		var path: Array = action.get("move_path", [])
		t.check(not path.is_empty(), "可一步抢点时敌人移动")
		if not path.is_empty():
			t.eq(path.back(), Vector2i(0, 3), "敌人优先到达奖励格")


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
