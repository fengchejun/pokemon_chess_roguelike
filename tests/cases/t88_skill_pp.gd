extends RefCounted

## PP 是每个技能独立的本局使用次数；只有成功施法消耗，可由营地和道具恢复。


func run(t: TestContext) -> void:
	t.begin("技能 PP 上限、消耗与恢复")
	_definitions(t)
	_player_consumption(t)
	_channel_consumption(t)
	_run_persistence(t)
	_enemy_and_ui(t)
	t.finish()


func _definitions(t: TestContext) -> void:
	for skill_id in SkillDB.DEFS:
		var id := String(skill_id)
		var def := SkillDB.get_def(id)
		t.check(def.has("pp"), "%s配置 PP" % id)
		t.check(
			int(def.get("pp", 0)) in [5, 10, 15, 20, 25] or SkillDB.is_battle_only(id) or id == "mage_key",
			"%s的 PP 上限位于本局五档或属于遗物魔法" % id
		)
		t.eq(SkillDB.pp_of(id), int(def.get("pp", 0)), "%s的 PP 查询与定义一致" % id)
	_assert_pp_group(t, ["burn_out", "mirror_water_moon"], 5, "特殊或高危技能")
	_assert_pp_group(t, [
		"double_cast", "earth_shake", "electric_resonance", "fire_burst", "flame_rush",
		"ice_breath", "ice_glide", "imprint", "lightning", "mountain_form", "rock_blast",
		"rock_slide", "skyfire", "surf", "tree_man", "tsunami", "water_magic_burst",
		"windfire_breath",
	], 10, "强范围、跨回合或多目标技能")
	_assert_pp_group(t, [
		"antidote", "electric_spark", "fire_amplify", "first_aid", "freeze_ray",
		"frozen_ground", "glare", "guard_rock", "herbal_heal", "leech_seed", "magnet_pull",
		"mountain_chain", "rain_call", "rain_dance", "rock_create", "rooted_grass",
		"seed_sow", "tailwind", "volt_replace", "volt_step", "water_drop_stone", "wild_vines",
	], 15, "战术控制、地形或条件收益技能")
	_assert_pp_group(t, [
		"combustion", "drain", "electromagnetic_laser", "fire_seed", "flame_charge", "furnace_fist",
	], 20, "进阶单体技能")
	_assert_pp_group(t, [
		"discharge", "electric_arc", "flame_jet", "ice_shard", "leaf_wind", "push",
		"rock_break", "rock_push", "rock_smash", "tree_wrath", "water_flow",
	], 25, "稳定基础技能")
	_assert_same_pp(t, ["electric_arc", "discharge"], "同效果放电")
	_assert_same_pp(t, ["rain_call", "rain_dance"], "同效果造雨术")
	_assert_same_pp(t, ["rock_break", "rock_smash"], "同效果碎岩")
	_assert_same_pp(t, ["rock_push", "push"], "同效果推击")
	t.eq(SkillDB.pp_of("mirror_water_moon"), 5, "镜花水月使用特殊技能 PP 档")


func _assert_pp_group(t: TestContext, skill_ids: Array, expected: int, role: String) -> void:
	for skill_id in skill_ids:
		t.eq(SkillDB.pp_of(String(skill_id)), expected, "%s的 PP 为 %d 档（%s）" % [skill_id, expected, role])


func _assert_same_pp(t: TestContext, skill_ids: Array, role: String) -> void:
	var expected := SkillDB.pp_of(String(skill_ids[0]))
	for skill_id in skill_ids.slice(1):
		t.eq(SkillDB.pp_of(String(skill_id)), expected, "%s使用一致的 PP" % role)


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


func _run_persistence(t: TestContext) -> void:
	var run := RunState.new_run(8803)
	var record := run.record_by_uid(5)
	record["known_skills"] = ["rock_push", "rock_break"]
	record["equipped_skills"] = ["rock_push", "rock_break"]
	record["skill_pp_uses"] = {"rock_push": 7, "rock_break": 20}
	var units := run.build_deploy_units([5])
	var caster := units[1] as CombatUnit
	t.eq(caster.pp_remaining("rock_push"), SkillDB.pp_of("rock_push") - 7, "战前部署继承本局已消耗 PP")
	t.eq(caster.pp_remaining("rock_break"), SkillDB.pp_of("rock_break") - 20, "不同技能分别保留本局 PP")
	var state := BattleState.new()
	state.setup(TestScenario.make_map(TestScenario.plain_terrain()), {"enemies": [["fire_wild1", Vector2i(7, 7)]]}, 8803, 0, units, {}, {}, [])
	t.eq(state.unit_by_uid(5).pp_remaining("rock_push"), SkillDB.pp_of("rock_push") - 7, "进入新战斗不自动回满我方 PP")
	var consumed := state.unit_by_uid(5).consume_skill_pp("rock_push")
	t.check(consumed, "本局 PP 剩余时可继续施法")
	run.sync_from_battle(state)
	t.eq(run.record_pp_used(record, "rock_push"), 8, "战斗消耗即时写回本局记录")
	run.advance_battle()
	t.eq((run.build_deploy_units([5])[1] as CombatUnit).pp_remaining("rock_push"), SkillDB.pp_of("rock_push") - 8, "推进到下一场战斗不会恢复 PP")
	var loaded := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
	t.eq(loaded.record_pp_used(loaded.record_by_uid(5), "rock_push"), 8, "本局 PP 消耗随存档保留")
	var legacy_data := run.to_dict()
	legacy_data["version"] = 18
	(legacy_data["carried"][4] as Dictionary).erase("skill_pp_uses")
	var legacy := RunState.from_dict(legacy_data)
	t.eq(legacy.record_pp_remaining(legacy.record_by_uid(5), "rock_push"), SkillDB.pp_of("rock_push"), "旧存档缺少 PP 记录时按满 PP 迁入")
	var legacy_path := "res://.test_pp_v18_migration.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy_data))
		legacy_file.close()
	var loaded_legacy := SaveSystem.load_run(legacy_path)
	t.check(loaded_legacy != null and loaded_legacy.record_pp_remaining(loaded_legacy.record_by_uid(5), "rock_push") == SkillDB.pp_of("rock_push"), "存档入口继续接受并迁移 v18 本局记录")
	SaveSystem.delete_save(legacy_path)

	var snapshot_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], [], {}, {}, [], 8803)
	var snapshot_caster := snapshot_state.unit_by_uid(1)
	snapshot_caster.skills = ["water_flow"]
	snapshot_caster.battle_skill_uses["water_flow"] = 2
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	var restored_caster := restored.unit_by_uid(caster.uid) if restored != null else null
	t.check(restored_caster != null, "PP 状态可写入并读取战斗快照")
	if restored_caster != null:
		t.eq(restored_caster.pp_remaining("rock_push"), SkillDB.pp_of("rock_push") - 8, "快照读档保留本局 PP")
	var clone_caster := state.clone().unit_by_uid(caster.uid)
	t.eq(clone_caster.pp_remaining("rock_push"), SkillDB.pp_of("rock_push") - 8, "状态克隆保留本局 PP")
	var migrated_state := BattleSnapshot.load_state(RunState.migrate_legacy_pp_snapshot(BattleSnapshot.save_state(snapshot_state)))
	t.eq(migrated_state.unit_by_uid(snapshot_caster.uid).pp_used("water_flow"), 10, "旧快照已消耗 PP 按五倍比例迁移")


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
