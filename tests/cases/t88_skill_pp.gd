extends RefCounted

## PP 是每个技能独立的每场使用次数；只有成功施法消耗，预览和失败不消耗。


func run(t: TestContext) -> void:
	t.begin("技能 PP 上限、消耗与恢复")
	_definitions(t)
	_player_consumption(t)
	_channel_consumption(t)
	_persistence_and_reset(t)
	_enemy_and_ui(t)
	t.finish()


func _definitions(t: TestContext) -> void:
	for skill_id in SkillDB.DEFS:
		var id := String(skill_id)
		var def := SkillDB.get_def(id)
		t.check(def.has("pp"), "%s配置 PP" % id)
		t.check(int(def.get("pp", 0)) > 0, "%s的 PP 上限为正数" % id)
		t.eq(SkillDB.pp_of(id), int(def.get("pp", 0)), "%s的 PP 查询与定义一致" % id)
	t.eq(SkillDB.pp_of("mirror_water_moon"), 1, "镜花水月保留每场一次限制")


func _player_consumption(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8801)
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	caster.skills = ["rock_break"]
	target.max_hp = 1000
	target.hp = 1000
	var maximum := SkillDB.pp_of("rock_break")
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	t.eq(caster.pp_remaining("rock_break"), maximum, "开战技能 PP 回满")
	t.check(bool(state.preview_skill(caster, "rock_break", entry).get("ok", false)), "有 PP 时可预览")
	t.eq(caster.pp_remaining("rock_break"), maximum, "预览不消耗 PP")
	t.check(not bool(state.cast_skill(caster, "rock_break", {}).get("ok", false)), "无效目标施法失败")
	t.eq(caster.pp_remaining("rock_break"), maximum, "失败施法不消耗 PP")
	for expected_remaining in range(maximum - 1, -1, -1):
		t.check(bool(state.cast_skill(caster, "rock_break", entry).get("ok", false)), "剩余 PP 时施法成功")
		t.eq(caster.pp_remaining("rock_break"), expected_remaining, "成功施法消耗 1 PP")
		caster.skill_used = false
	t.check(not caster.can_use_in_battle("rock_break"), "PP 耗尽后技能不可用")
	t.check(state.skill_targets(caster, "rock_break").is_empty(), "PP 耗尽后不显示技能目标")
	t.check(not bool(state.preview_skill(caster, "rock_break", entry).get("ok", false)), "PP 耗尽后预览失败")
	t.check(not bool(state.cast_skill(caster, "rock_break", entry).get("ok", false)), "PP 耗尽后无法继续施法")


func _channel_consumption(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8802)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 2)
	caster.skills = ["fire_burst"]
	var entry := {"type": "cell", "cell": Vector2i(4, 2)}
	t.check(bool(state.cast_skill(caster, "fire_burst", entry).get("ok", false)), "吟唱成功宣告")
	t.eq(caster.pp_remaining("fire_burst"), SkillDB.pp_of("fire_burst") - 1, "吟唱在宣告时消耗 PP")
	state.round = 2
	state._resolve_due_channels("player")
	t.eq(caster.pp_remaining("fire_burst"), SkillDB.pp_of("fire_burst") - 1, "吟唱落下不会重复消耗 PP")


func _persistence_and_reset(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], [], {}, {}, [], 8803)
	var caster := state.unit_by_uid(1)
	caster.skills = ["water_flow"]
	caster.battle_skill_uses["water_flow"] = 2
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	var restored_caster := restored.unit_by_uid(caster.uid) if restored != null else null
	t.check(restored_caster != null, "PP 状态可写入并读取战斗快照")
	if restored_caster != null:
		t.eq(restored_caster.pp_remaining("water_flow"), SkillDB.pp_of("water_flow") - 2, "读档保留已消耗 PP")
	t.eq(state.clone().unit_by_uid(caster.uid).pp_remaining("water_flow"), SkillDB.pp_of("water_flow") - 2, "状态克隆保留已消耗 PP")
	state.node_kind = "event"
	state.reset_exploration_actions()
	t.eq(caster.pp_remaining("water_flow"), SkillDB.pp_of("water_flow") - 2, "自由探索重置行动不会回满 PP")


func _enemy_and_ui(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]], [], {}, {}, [], 8804)
	var ally := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	ally.cell = Vector2i(2, 2)
	enemy.cell = Vector2i(4, 2)
	enemy.skills = ["rock_break"]
	enemy.battle_skill_uses["rock_break"] = SkillDB.pp_of("rock_break")
	var actions := EnemyAI.plan(state)
	var enemy_action: Dictionary = {}
	for action in actions:
		if int(action.get("uid", -1)) == enemy.uid:
			enemy_action = action
			break
	t.check(enemy_action.is_empty() or String((enemy_action.get("skill", {}) as Dictionary).get("id", "")) != "rock_break", "敌方 AI 不规划 PP 耗尽的技能")
	state.phase = BattleState.PHASE_ENEMY
	state._pending_actions = [{
		"uid": enemy.uid,
		"move_path": [],
		"skill": {"id": "rock_break", "target": {"type": "unit", "unit": ally.uid, "cell": ally.cell}},
	}]
	state._pending_index = 0
	state.step_enemy_phase()
	t.eq(enemy.pp_remaining("rock_break"), 0, "敌方 PP 耗尽时真实施法也被拒绝")
	t.eq(int((state.skill_use_counts["enemy"] as Dictionary).get("rock_break", 0)), 0, "被拒绝的敌方施法不计入统计")

	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	enemy.battle_skill_uses["rock_break"] = 1
	var tag: String = screen._skill_tag("rock_break", enemy)
	t.check(tag.contains("PP %d/%d" % [SkillDB.pp_of("rock_break") - 1, SkillDB.pp_of("rock_break")]), "技能按钮标签显示剩余与最大 PP")
	screen.free()
