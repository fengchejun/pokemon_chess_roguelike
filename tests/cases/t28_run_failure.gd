extends RefCounted


func run(t: TestContext) -> void:
	t.begin("训练家死亡终止整局")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(2801)
	app.run.mark_deployed([1])
	app.run.pending_captures.append({"species_id": "water_wild1", "hp": 1})
	var battle := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(5, 3)]])
	battle.damage_unit(battle.unit_by_uid(100), battle.trainer(), 99, {"no_element": true, "cause": "测试"})
	t.eq(battle.trainer().hp, 0, "训练家死亡时生命为零")
	t.eq(battle.end_reason, "forced_retreat", "旧结局 ID 保持存档兼容")
	app.finish_battle(battle)
	t.check(app.run.run_failed and app.run.run_lost(), "本局状态标记失败")
	t.eq(app.current_screen.name, "RunEndScreen", "直接进入本局结束页")
	t.check(not app.run.settlement_pending, "不会停留在战后结算选择")
	t.eq(app.run.pending_captures.size(), 0, "本场未收容捕获在失败时丢弃")
	t.check(not app.run.run_finished(), "未通关不能显示为通关")
	var legacy := RunState.new_run(2802).to_dict()
	legacy["settlement_pending"] = true
	legacy["last_settlement"] = {"reason": "forced_retreat"}
	legacy.erase("run_failed")
	var migrated := RunState.from_dict(legacy)
	t.check(migrated.run_failed and not migrated.settlement_pending and migrated.trainer_hp == 0, "旧失败结算存档读取后直接终止本局")
	var summary: Label = app.current_screen.find_child("RunEndSummary", true, false)
	t.check(summary != null and summary.text.contains("训练家倒下"), "结束页说明失败原因")
	app.end_run_to_menu()
	t.eq(app.current_screen.name, "MenuScreen", "结束页可返回主菜单重新开始")
	t.eq(app.run, null, "退出失败局后本局数据清空")
	app.queue_free()
	t.finish()
