extends RefCounted

## 八邻格捕获；低血量保证与原地转阵营分别由设置控制。


func run(t: TestContext) -> void:
	t.begin("捕获（概率制）")
	_t_chance_curve(t)
	_t_range(t)
	_t_flow(t)
	_t_low_hp_option(t)
	_t_field_join_option(t)
	t.finish()


func _t_chance_curve(t: TestContext) -> void:
	var wild := CombatUnit.make("rock_wild1", "enemy", 100)
	wild.hp = wild.max_hp
	t.eq(CaptureSystem.chance_percent(wild), 30, "满血：基础 30%")
	var full_chance := CaptureSystem.capture_chance(wild)
	wild.hp = 3
	var half_chance := CaptureSystem.capture_chance(wild)
	wild.hp = 1
	var low_chance := CaptureSystem.capture_chance(wild)
	t.check(half_chance > full_chance, "半血成功率高于满血")
	t.check(low_chance > half_chance, "残血成功率高于半血")
	t.check(CaptureSystem.chance_percent(wild) >= 70, "残血成功率明显更高（%d%%）" % CaptureSystem.chance_percent(wild))
	t.check(full_chance >= Balance.CAPTURE_CHANCE_MIN and low_chance <= Balance.CAPTURE_CHANCE_MAX, "概率夹在上下限内")


func _t_range(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var trainer := state.trainer()
	trainer.cell = Vector2i(1, 3)
	var wild := state.unit_by_uid(100)
	wild.cell = Vector2i(2, 3)
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), true, "正交相邻可尝试")
	wild.cell = Vector2i(2, 4)
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), true, "斜角相邻可尝试")
	wild.cell = Vector2i(3, 3)
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), false, "直线两格不可尝试")


func _t_flow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var trainer := state.trainer()
	trainer.cell = Vector2i(1, 3)
	var wild := state.unit_by_uid(100)
	wild.cell = Vector2i(2, 3)
	wild.hp = 1
	var result := state.capture_attempt(trainer, wild, 0.01)
	t.eq(bool(result["success"]), true, "低骰值判定成功")
	t.eq(wild.hp, 0, "成功后立即离场")
	t.eq(state.captured.size(), 1, "记录捕获")
	t.eq(int(state.captured[0]["hp"]), 1, "保留剩余生命")
	t.eq(state.end_reason, "victory", "捕获计为已解决，推进胜利")
	t.eq(state.battle_exp(), 2, "捕获经验与击败持平 2 点")
	var state2 := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var trainer2 := state2.trainer()
	trainer2.cell = Vector2i(1, 3)
	var wild2 := state2.unit_by_uid(100)
	wild2.cell = Vector2i(2, 3)
	wild2.hp = 1
	var fail := state2.capture_attempt(trainer2, wild2, 0.99)
	t.eq(bool(fail["success"]), false, "高骰值判定失败")
	t.eq(wild2.is_alive(), true, "失败后目标留场")
	t.eq(CaptureSystem.can_attempt(state2, trainer2, wild2), false, "每回合仅 1 次尝试")
	state2.start_round()
	var auto := state2.capture_attempt(trainer2, wild2)
	t.eq(bool(auto.get("ok", false)), true, "未注入骰值时走战斗内种子随机数")


func _t_low_hp_option(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	state.capture_options["capture_low_hp"] = true
	var trainer := state.trainer()
	trainer.cell = Vector2i(1, 3)
	var wild := state.unit_by_uid(100)
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), false, "开启低血量规则后满血不可尝试")
	wild.hp = 2
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), true, "半血可尝试")
	t.check(CaptureSystem.capture_chance(wild, true) < 1.0, "2 HP 无减益仍为概率捕获")
	wild.slow_ticks = 1
	t.eq(CaptureSystem.chance_percent(wild, true), 100, "带减益的 2 HP 必成")
	var rng_before := state.capture_rng.state
	var result := state.capture_attempt(trainer, wild)
	t.eq(bool(result.get("success", false)), true, "必成不依赖随机值")
	t.eq(state.capture_rng.state, rng_before, "必成不消耗捕获随机数")
	var state2 := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	state2.capture_options["capture_low_hp"] = true
	state2.trainer().cell = Vector2i(1, 3)
	var wild2 := state2.unit_by_uid(100)
	wild2.hp = 1
	t.eq(CaptureSystem.chance_percent(wild2, true), 100, "1 HP 必成")
	t.eq(bool(state2.capture_attempt(state2.trainer(), wild2, 0.99).get("success", false)), true, "1 HP 高骰值仍必成")


func _t_field_join_option(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)], ["fire_wild1", Vector2i(6, 3)]])
	state.capture_options["capture_field_join"] = true
	var trainer := state.trainer()
	trainer.cell = Vector2i(1, 3)
	var wild := state.unit_by_uid(100)
	wild.hp = 2
	wild.moved = true
	wild.skill_used = true
	t.eq(bool(state.capture_attempt(trainer, wild, 0.01).get("success", false)), true, "开启原地转阵营后捕获成功")
	t.eq(wild.side, "player", "目标留在原格转为我方")
	t.eq(wild.cell, Vector2i(2, 3), "保留捕获位置")
	t.eq(wild.hp, 2, "保留捕获生命")
	t.eq(wild.moved, false, "捕获本轮获得一次移动")
	t.eq(wild.skill_used, false, "捕获本轮获得一次技能")
	t.eq(state.alive_enemy_count(), 1, "其他敌人仍可行动")
	t.eq(state.move_unit(wild, Vector2i(3, 3)), true, "捕获当轮可以实际移动")
	var rock_entries := state.skill_targets(wild, "rock_create")
	t.check(not rock_entries.is_empty(), "捕获当轮存在合法技能目标")
	if not rock_entries.is_empty():
		t.eq(bool(state.cast_skill(wild, "rock_create", rock_entries[0]).get("ok", false)), true, "捕获当轮可以实际施法")
	var run := RunState.new_run(77)
	run.sync_from_battle(state)
	t.eq(run.pending_captures.size(), 0, "战斗未结束时不提前收入队伍")
	state.kill_unit(wild, "捕获后阵亡", "enemy")
	state.end_battle("victory")
	run.sync_from_battle(state)
	t.eq(run.pending_captures.size(), 0, "捕获单位战中阵亡不入队")
	var survivor_state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	survivor_state.capture_options["capture_field_join"] = true
	survivor_state.trainer().cell = Vector2i(1, 3)
	var survivor := survivor_state.unit_by_uid(100)
	survivor.hp = 2
	survivor_state.capture_attempt(survivor_state.trainer(), survivor, 0.01)
	var survivor_run := RunState.new_run(78)
	survivor_run.sync_from_battle(survivor_state)
	t.eq(survivor_run.pending_captures.size(), 1, "战斗结束时存活的捕获单位进入待处理队列")
	t.eq(int(survivor_run.pending_captures[0]["hp"]), 2, "战后保留存活单位的剩余生命")
	var old_data := RunState.new_run(79).to_dict()
	old_data["options"] = {"threat_preview": true}
	var old_run := RunState.from_dict(old_data)
	t.eq(bool(old_run.options.get("capture_low_hp", true)), false, "旧存档新增低血量开关默认关闭")
	t.eq(bool(old_run.options.get("capture_field_join", true)), false, "旧存档新增原地转阵营开关默认关闭")
