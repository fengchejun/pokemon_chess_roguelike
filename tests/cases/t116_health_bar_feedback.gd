extends RefCounted
const Feedback = preload("res://scripts/ui/health_bar_feedback.gd")

func run(t: TestContext) -> void:
	t.begin("血条扣血残影、连击、治疗与死亡收尾")
	var actor := CombatUnit.make("fire_wild1", "enemy", 1)
	actor.max_hp = 100
	actor.hp = 100
	var feedback := Feedback.new()
	feedback.sync([actor])
	t.check(feedback.trails.is_empty(), "初次显示不制造伤害")
	actor.hp = 70
	feedback.sync([actor])
	t.approx(feedback.displayed_ratio(1, 0.7), 1.0, "受击立即显示扣掉的生命段")
	feedback.advance(0.18)
	feedback.sync([actor])
	t.approx(feedback.trails[1]["age"], 0.18, "重复刷新不重置残影")
	feedback.advance(0.275)
	t.approx(feedback.displayed_ratio(1, 0.7), 0.85, "残影平滑收缩")
	actor.hp = 50
	feedback.sync([actor])
	t.approx(feedback.displayed_ratio(1, 0.5), 0.85, "连续受击保留尚未收缩完的残影")
	actor.hp = 80
	feedback.sync([actor])
	t.check(feedback.trails.is_empty(), "治疗后清除旧伤害残影")
	actor.hp = 0
	feedback.sync([actor])
	t.approx(feedback.displayed_ratio(1, 0), 0.8, "致死伤害也有血条反馈")
	feedback.advance(1.0)
	t.check(feedback.trails.is_empty(), "残影结束后停止动画")
	feedback.sync([])
	t.check(feedback.previous.is_empty(), "单位移除后清理缓存")
	var board := BoardView.new()
	var state := BattleState.new()
	state.units = [actor]
	state.terrain = TestScenario.plain_terrain()
	actor.hp = 100
	board.set_from_state(state)
	actor.hp = 40
	board.set_from_state(state)
	t.approx(board.health_feedback.displayed_ratio(1, 0.4), 1.0, "真实棋盘刷新接入血条动画")
	board.free()
	t.finish()
