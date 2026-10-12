extends RefCounted

## 捕获（概率制）：成功率随生命降低而升高、射程 2 格、每回合 1 次、成功即入队


func run(t: TestContext) -> void:
	t.begin("捕获（概率制）")
	_t_chance_curve(t)
	_t_range(t)
	_t_flow(t)
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
	trainer.cell = Vector2i(0, 3)
	var wild := state.unit_by_uid(100)
	wild.cell = Vector2i(2, 3)
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), true, "2 格射程内可尝试")
	trainer.cell = Vector2i(0, 4)
	wild.cell = Vector2i(3, 4)
	t.eq(GridSpec.manhattan(trainer.cell, wild.cell), 3, "构造 3 格距离")
	t.eq(CaptureSystem.can_attempt(state, trainer, wild), false, "3 格外不可尝试")


func _t_flow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var trainer := state.trainer()
	trainer.cell = Vector2i(0, 3)
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
	trainer2.cell = Vector2i(0, 3)
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
