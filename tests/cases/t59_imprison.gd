extends RefCounted


func run(t: TestContext) -> void:
	t.begin("禁锢：持续两回合且保留其他行动")
	_blocks_only_normal_movement(t)
	_displacement_does_not_clear(t)
	_after_move_defers_to_next_turn(t)
	t.finish()


func _blocks_only_normal_movement(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(7, 6)]])
	var unit := state.unit_by_uid(1)
	unit.cell = Vector2i(0, 3)
	t.check(state.apply_imprison(unit), "可对存活单位施加禁锢")
	t.eq(unit.imprison_ticks, 2, "当前移动阶段尚未消耗时禁锢持续两回合")
	t.eq(state.clone().unit_by_uid(unit.uid).imprison_ticks, 2, "战场克隆保留禁锢")
	t.eq(BattleSnapshot.load_state(BattleSnapshot.save_state(state)).unit_by_uid(unit.uid).imprison_ticks, 2, "战斗存档保留禁锢")
	t.eq(unit.effective_move(), 0, "禁锢期间移动力显示为零")
	t.check(not state.can_move_unit_now(unit), "禁锢期间不能普通移动")
	t.check(not state.move_unit(unit, Vector2i(1, 3)), "普通移动执行入口拒绝禁锢单位")
	unit.skills.append("volt_step")
	var result := state.cast_skill(unit, "volt_step", {"type": "cell", "cell": Vector2i(1, 2)})
	t.check(bool(result.get("ok", false)), "禁锢不影响其他技能行动")
	t.eq(unit.cell, Vector2i(1, 2), "禁锢单位仍可通过位移技能移动")
	t.eq(unit.imprison_ticks, 2, "位移技能不会提前解除禁锢")
	state._finish_movement_effects("player")
	t.eq(unit.imprison_ticks, 1, "第一个移动阶段结束后仍剩一回合")
	state._finish_movement_effects("player")
	t.eq(unit.imprison_ticks, 0, "第二个移动阶段结束后禁锢解除")


func _displacement_does_not_clear(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(4, 3)]])
	var target := state.unit_by_uid(100)
	state.apply_imprison(target)
	var result := PushResolver.push(state, target, Vector2i.RIGHT, 1, 0, "测试位移")
	t.check(bool(result.get("moved", false)), "禁锢单位会被击退")
	t.eq(target.cell, Vector2i(5, 3), "击退实际改变位置")
	t.eq(target.imprison_ticks, 2, "击退不会清除禁锢")


func _after_move_defers_to_next_turn(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(7, 6)]])
	var unit := state.unit_by_uid(1)
	unit.moved = true
	state.apply_imprison(unit)
	t.eq(unit.imprison_ticks, 3, "已经移动后施加的禁锢覆盖接下来的两次移动机会")
	state._finish_movement_effects("player")
	t.eq(unit.imprison_ticks, 2, "当前阶段只消耗一层计数")
	state._finish_movement_effects("player")
	t.eq(unit.imprison_ticks, 1, "第一个完整移动阶段结束后仍有一层")
	state._finish_movement_effects("player")
	t.eq(unit.imprison_ticks, 0, "连续两个移动阶段结束后解除")
