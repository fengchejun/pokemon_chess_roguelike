extends RefCounted

## 技能次数只在真实施法成功后增加；结算去重，跨开局收藏存档保留。

const PROFILE_PATH := "res://.test_skill_usage_profile.json"


func run(t: TestContext) -> void:
	t.begin("跨局技能使用次数")
	_test_cast_entries(t)
	_test_enemy_and_profile(t)
	_test_menu_view(t)
	t.finish()


func _test_cast_entries(t: TestContext) -> void:
	var battle := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8123)
	var caster := battle.unit_by_uid(1)
	var target := battle.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	t.check(bool(battle.preview_skill(caster, "rock_break", entry).get("ok", false)), "技能预览成功")
	t.eq(int((battle.skill_use_counts["player"] as Dictionary).get("rock_break", 0)), 0, "预览不计数")
	t.eq(bool(battle.cast_skill(caster, "rock_break", {}).get("ok", false)), false, "无效目标施法失败")
	t.eq(int((battle.skill_use_counts["player"] as Dictionary).get("rock_break", 0)), 0, "失败施法不计数")
	t.check(bool(battle.cast_skill(caster, "rock_break", entry).get("ok", false)), "有效施法成功")
	t.eq(int((battle.skill_use_counts["player"] as Dictionary).get("rock_break", 0)), 1, "真实我方施法计一次")
	t.eq(int((battle.clone().skill_use_counts["player"] as Dictionary).get("rock_break", 0)), 1, "状态克隆保留统计")

	var channel := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8124)
	var fire := channel.unit_by_uid(1)
	fire.cell = Vector2i(2, 2)
	var center := {"type": "cell", "cell": Vector2i(4, 2)}
	t.check(bool(channel.cast_skill(fire, "fire_burst", center).get("ok", false)), "蓄力开始成功")
	t.eq(int((channel.skill_use_counts["player"] as Dictionary).get("fire_burst", 0)), 1, "蓄力开始计一次")
	channel.round = 2
	channel._resolve_due_channels("player")
	t.eq(int((channel.skill_use_counts["player"] as Dictionary).get("fire_burst", 0)), 1, "蓄力落下不重复计数")


func _test_enemy_and_profile(t: TestContext) -> void:
	var battle := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8125)
	var ally := battle.unit_by_uid(1)
	ally.cell = Vector2i(2, 2)
	EnemyAI.plan(battle)
	t.eq((battle.skill_use_counts["enemy"] as Dictionary).size(), 0, "敌方 AI 模拟不计数")
	battle.phase = BattleState.PHASE_ENEMY
	battle._pending_actions = [{"uid": 100, "move_path": [], "skill": {"id": "rock_break",
		"target": {"type": "unit", "unit": ally.uid, "cell": ally.cell}}}]
	battle._pending_index = 0
	battle.step_enemy_phase()
	t.eq(int((battle.skill_use_counts["enemy"] as Dictionary).get("rock_break", 0)), 1, "敌方真实施法计一次")
	var profile := CollectionState.defaults()
	t.eq(profile.record_battle_skill_usage(battle), false, "未结束战斗不进入永久统计")
	battle.end_battle("escape")
	t.eq(profile.record_battle_skill_usage(battle), true, "已结束战斗首次入账")
	t.eq(profile.record_battle_skill_usage(battle), false, "同一场战斗重复结算不计数")
	t.eq(profile.skill_use_total("enemy"), 1, "敌方总次数正确")
	t.eq(profile.skill_use_total("player"), 0, "双方次数独立")
	t.eq(profile.recorded_skill_battles.size(), 1, "已统计场数正确")
	t.check(profile.save(PROFILE_PATH), "永久收藏统计可保存")
	var loaded := CollectionState.load_profile(PROFILE_PATH)
	t.eq(loaded.skill_use_total("enemy"), 1, "重新读取永久统计保留敌方次数")
	t.eq(loaded.record_battle_skill_usage(battle), false, "读档后仍防止重复入账")
	SaveSystem.delete_save(PROFILE_PATH)


func _test_menu_view(t: TestContext) -> void:
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8126, [{"species_id": "rock_starter", "id": 1, "affinity": 0}])
	app.run.mark_deployed([1])
	var battle := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8126)
	var caster := battle.unit_by_uid(1)
	caster.cell = Vector2i(2, 2)
	var target := battle.unit_by_uid(100)
	battle.cast_skill(caster, "rock_break", {"type": "unit", "unit": target.uid, "cell": target.cell})
	battle.end_battle("escape")
	app.finish_battle(battle)
	t.eq(app.collection.skill_use_total("player"), 1, "主流程结算写入永久我方次数")
	t.eq(app.collection.recorded_skill_battles.size(), 1, "主流程结算登记一场战斗")
	app.show_menu()
	var stats_button: Button = app.current_screen.find_child("SkillStatsButton", true, false)
	t.check(stats_button != null, "主菜单有技能使用统计入口")
	if stats_button != null:
		stats_button.pressed.emit()
		t.eq(app.current_screen.name, "SkillStatsScreen", "进入技能统计页")
		var summary: Label = app.current_screen.find_child("SkillStatsSummary", true, false)
		t.check(summary != null and summary.text.contains("我方施放 1 次"), "统计页展示已结算的我方次数")
		var back: Button = app.current_screen.find_child("SkillStatsBackButton", true, false)
		t.check(back != null, "统计页可返回主菜单")
		if back != null:
			back.pressed.emit()
			t.eq(app.current_screen.name, "MenuScreen", "从统计页返回主菜单")
	t.tree.root.remove_child(app)
	app.queue_free()
