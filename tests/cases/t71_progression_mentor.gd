extends RefCounted

func run(t: TestContext) -> void:
	t.begin("递增血量、即时经验与导师付费强化")
	_curve(t)
	_experience(t)
	_learning(t)
	_migration(t)
	_mentor(t)
	t.finish()

func _battle(run: RunState) -> BattleState:
	run.region_mode = true
	run.mark_deployed([1, 2, 3])
	var state := BattleState.new()
	state.node_kind = "battle"
	state.setup(TestScenario.make_map(TestScenario.plain_terrain()), {"enemies": [["rock_wild1", Vector2i(5, 3)], ["grass_wild1", Vector2i(5, 4)]]}, run.seed, 0, run.build_deploy_units([1, 2, 3]), {}, {}, [])
	for enemy in state.alive_units("enemy"):
		enemy.enemy_level = 2
	return state

func _curve(t: TestContext) -> void:
	var base := SpeciesDB.hp_of("rock_starter")
	var expected := [0, 6, 14, 24, 36, 50, 66, 84, 104, 126]
	for index in range(10):
		t.eq(MonsterProgression.max_hp("rock_starter", index + 1), base + expected[index], "每级递增生命")
	var run := RunState.new_run(7101)
	run.trainer_xp = 400
	run.trainer_level = 10
	t.eq(run.trainer_max_hp(), SpeciesDB.hp_of("trainer") + 126, "训练家同用生命曲线")
	t.eq(RunState.from_dict(run.to_dict()).trainer_max_hp(), run.trainer_max_hp(), "训练家等级读档不丢失")

func _experience(t: TestContext) -> void:
	var run := RunState.new_run(7102)
	var state := _battle(run)
	var first := state.unit_by_uid(1)
	first.hp = 5
	first.moved = true
	first.skill_used = true
	first.paralyzed_ticks = 1
	state.kill_unit(state.unit_by_uid(100), "测试", "player", 1)
	t.eq(first.combat_xp, 3, "击杀当场入账共享经验")
	state.kill_unit(state.unit_by_uid(2), "濒死", "enemy")
	state.on_captured(state.unit_by_uid(101), "grass_wild1", 5)
	t.eq(first.combat_xp, 6, "捕获也即时入账")
	t.eq(first.combat_level, 2, "达到门槛立即升级")
	t.eq(first.hp, 11, "升级立即补上增加的6点生命")
	t.check(first.moved and first.skill_used and first.paralyzed_ticks == 1, "升级不重置动作或控制")
	t.eq(state.unit_by_uid(2).combat_xp, 3, "濒死前所得经验保留，之后经验不再增加")
	t.eq(state.unit_by_uid(2).hp, 0, "经验不能复活")
	t.eq(state.trainer().combat_level, 2, "训练家也立即升级")
	var signature := state._signature()
	state.award_battle_experience("capture:101", 3)
	t.eq(state._signature(), signature, "同一事件不重复结算")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.clone().unit_by_uid(1).combat_xp, 6, "克隆读档保留经验")
	run.sync_from_battle(restored)
	t.eq(run.record_by_uid(2)["xp"], 3, "濒死经验写回角色记录")
	restored.end_battle("escape")
	var summary := run.settle_battle(restored)
	t.eq(run.record_by_uid(1)["xp"], 6, "战后不再重复追加击杀捕获经验")
	t.eq(summary["monster_exp"][0]["gained"], 6, "结算报告包含当场已经获得的经验")
	t.eq(summary["trainer_exp"]["gained"], 6, "结算报告包含训练家即时经验")
	run.settle_battle(restored)
	t.eq(run.record_by_uid(1)["xp"], 6, "重复结算也不重复增加经验")
	var late := _battle(RunState.new_run(7103))
	late.unit_by_uid(100).spawned_from_nest = true
	late.unit_by_uid(100).spawn_round = 9
	late.kill_unit(late.unit_by_uid(100), "测试", "player", 1)
	t.eq(late.unit_by_uid(1).combat_xp, 0, "后期增援仍为0击杀经验")
	var joined := _battle(RunState.new_run(7110))
	joined.capture_options["capture_field_join"] = true
	joined.on_captured(joined.unit_by_uid(101), "grass_wild1", 5)
	var summon := CombatUnit.make("grass_starter", "player", 300)
	summon.summon_owner_uid = 1
	joined.units.append(summon)
	joined.kill_unit(joined.unit_by_uid(100), "共享名单测试", "player", 1)
	t.eq(joined.unit_by_uid(101).combat_xp, 0, "本场新捕获成员不进入经验共享")
	t.eq(summon.combat_xp, 0, "召唤物不进入经验共享")
	t.eq(joined.unit_by_uid(1).combat_xp, 6, "原出战者仍取得两个事件的完整经验")
	var sim := _battle(RunState.new_run(7104))
	sim.unit_by_uid(1).cell = Vector2i(4, 3)
	sim.unit_by_uid(1).skills = ["rock_break"]
	sim.unit_by_uid(1).combat_xp = 3
	sim.unit_by_uid(100).hp = 1
	var preview := sim.clone()
	var entry := {"type": "unit", "unit": 100, "cell": Vector2i(5, 3)}
	SkillResolver.apply(preview, preview.unit_by_uid(1), "rock_break", entry, false)
	SkillResolver.apply(sim, sim.unit_by_uid(1), "rock_break", entry, false)
	t.eq(sim.unit_by_uid(1).hp, preview.unit_by_uid(1).hp, "模拟与实际升级加血一致")
	sim.award_battle_experience("multi-level", 400)
	t.eq(sim.unit_by_uid(1).combat_level, 10, "单次经验可跨多级到封顶")
	t.eq(sim.unit_by_uid(1).max_hp, SpeciesDB.hp_of(sim.unit_by_uid(1).species_id) + 126, "跨多级累计所有生命增量")
	t.eq(sim.unit_by_uid(1).hp, preview.unit_by_uid(1).hp + 120, "跨多级立即补足增量当前生命")

func _learning(t: TestContext) -> void:
	var run := RunState.new_run(7105)
	var record := run.record_by_uid(1)
	MonsterProgression.award_xp(record, MonsterProgression.threshold_for_level(7))
	t.eq(run.pending_monster_levels().map(func(p): return p["level"]), [2, 5, 7], "学习机会只有2、5、7级")
	t.check(not run.enhance_monster_skill(1, 2, record["known_skills"][0]), "等级不能强化技能")
	for level in [2, 5, 7]:
		var skill: String = run.available_new_skills(1)[0]
		var replaced: String = record["equipped_skills"][0] if record["equipped_skills"].size() == 3 else ""
		t.check(run.learn_monster_skill(1, level, skill, replaced), "可用学习机会学招")
		t.check(record["equipped_skills"].size() <= 3, "装备不超过三招")
	t.check(run.pending_monster_levels().is_empty(), "已领取机会不重复出现")
	var empty := RunState.new_run(7106)
	var all_known := empty.record_by_uid(1)
	MonsterProgression.award_xp(all_known, 6)
	all_known["known_skills"].append_array(empty.available_new_skills(1))
	t.check(not empty.pending_upgrades(), "无可学招式不阻塞结算")
	t.check(not all_known["claimed_even_levels"].has(2), "无可学招式时保留学习机会")

func _migration(t: TestContext) -> void:
	var run := RunState.new_run(7107)
	var record := run.record_by_uid(1)
	MonsterProgression.award_xp(record, 18)
	record["hp"] = 20
	record["claimed_even_levels"] = [2]
	var data := run.to_dict()
	data["version"] = 12
	var migrated := RunState.from_dict(data)
	t.eq(migrated.record_by_uid(1)["xp"], 18, "旧角色保留经验")
	t.eq(migrated.record_by_uid(1)["hp"], 22, "旧40上限下20生命迁移为44上限下22生命")
	t.eq(migrated.record_by_uid(1)["claimed_even_levels"], [2], "已领取等级奖励抵扣新机会")
	var battle := _battle(run)
	battle.unit_by_uid(1).max_hp = 40
	battle.unit_by_uid(1).hp = 20
	battle.unit_by_uid(2).hp = 0
	battle.enemy_kills.append({"uid": 100, "killer_side": "player", "xp_reward": 3})
	data["battle_snapshot"] = BattleSnapshot.save_state(battle)
	data["in_battle"] = true
	var active := RunState.from_dict(data)
	var restored := BattleSnapshot.load_state(active.battle_snapshot)
	t.eq(active.record_by_uid(1)["xp"], 21, "旧进行中战斗补记未结算经验")
	t.eq(restored.unit_by_uid(2).hp, 0, "旧战斗补记经验不复活")
	var again := RunState.from_dict(active.to_dict())
	t.eq(again.record_by_uid(1)["xp"], 21, "旧战斗补记仅发生一次")
	var legacy_path := "user://test_t71_legacy.json"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var disk := SaveSystem.load_run(legacy_path)
	t.check(disk != null, "存档入口接受真实v12旧文件")
	if disk != null:
		t.eq(disk.record_by_uid(1)["xp"], 21, "真实文件读取后仅补记一次")
	SaveSystem.delete_save(legacy_path)

func _mentor(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(7108)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var mentor_id := ""
	for id in ["event_1", "event_2"]:
		if region.nodes[id].has("mentor"):
			mentor_id = id
			t.check(not region.nodes[id].has("merchant"), "导师与商人分开节点")
	t.check(mentor_id != "", "每层存在导师")
	region.active_node = mentor_id
	app.run.region_data = region.to_dict()
	var state := _battle(app.run)
	state.node_kind = "event"
	state.mentor = {"cell": Vector2i(2, 3), "services": 0}
	state.trainer().cell = Vector2i(1, 3)
	app.run.essence = 100
	var skill := String(RunState.upgrade_info(app.run.available_monster_upgrades(1)[0])["requires_skill"])
	var before_round := state.round
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.playback.finish_all()
	screen._show_mentor()
	t.check(screen.find_child("MentorTrain_1_%s" % skill, true, false) != null, "导师界面显示具体可强化招式")
	var result: Dictionary = app.mentor_train(state, 1, skill)
	t.check(result["ok"], "导师强化成功")
	t.eq(app.run.essence, 88, "首次消耗12原质")
	t.eq(SkillMentor.cost(state.mentor), 20, "下次费用20原质")
	t.eq(state.round, before_round, "导师服务不推进回合")
	t.check(not app.mentor_train(state, 1, skill)["ok"], "同一招不能再次强化")
	t.eq(app.run.essence, 88, "失败不扣钱")
	var saved := RunState.from_dict(app.run.to_dict())
	t.eq(SkillMentor.cost(saved.get_region().nodes[mentor_id]["mentor"]), 20, "导师费用读档不重置")
	state.node_kind = "battle"
	t.eq(state.move_cost_for(state.trainer(), state.mentor["cell"]), -1, "占领时导师设施仍不可站立")
	t.check(not state.can_interact_at(state.mentor["cell"]), "占领时不开放导师交互")
	var next_skill := String(RunState.upgrade_info(app.run.available_monster_upgrades(2)[0])["requires_skill"])
	t.check(not app.mentor_train(state, 2, next_skill)["ok"], "占领期间暂停导师服务")
	state.node_kind = "event"
	app.autosave_enabled = true
	var rollback: Dictionary = app.mentor_train(state, 2, next_skill, "user://missing_mentor_dir/save.json")
	t.check(not rollback["ok"], "存档失败撤回导师交易")
	t.eq(app.run.essence, 88, "存档失败退回原质")
	t.eq(SkillMentor.cost(state.mentor), 20, "存档失败不增加服务次数")
	app.autosave_enabled = false
	app.run.essence = 19
	t.check(not app.mentor_train(state, 2, next_skill)["ok"], "余额不足不能强化")
	t.eq(app.run.essence, 19, "余额不足不扣费")
	app.run.essence = 100
	app.run.record_by_uid(2)["equipped_skills"].clear()
	t.check(app.mentor_train(state, 2, next_skill)["ok"], "已学但未装备的技能仍可强化")
	t.eq(app.run.essence, 80, "第二次成功按20原质扣费")
	t.eq(SkillMentor.cost(state.mentor), 28, "第三次费用为28原质")
	app.run.battle_index = 6
	app.run.region_data.clear()
	var next_floor = app.run.get_region()
	for node in next_floor.nodes.values():
		if node.has("mentor"):
			t.eq(SkillMentor.cost(node["mentor"]), 12, "下一层导师重新从12原质开始")
	app.autosave_enabled = false
	app.free()
