extends RefCounted

func run(t: TestContext) -> void:
	t.begin("合并成长：无楼层上限、即时分配、旧档与商人刻印")
	_curve(t)
	_experience(t)
	_learning(t)
	_migration(t)
	_merchant(t)
	t.finish()

func _battle(run: RunState) -> BattleState:
	run.region_mode = true
	run.mark_deployed([1, 2, 3])
	var state := BattleState.new()
	state.node_kind = "battle"
	state.setup(TestScenario.make_map(TestScenario.plain_terrain()), {"enemies": [["rock_wild1", Vector2i(5, 3)], ["grass_wild1", Vector2i(5, 4)]]}, run.seed, 0, run.build_deploy_units([1, 2, 3]), {}, {}, [])
	return state

func _curve(t: TestContext) -> void:
	var xp := [0, 6, 16, 30, 48, 70, 96, 126, 160, 198]
	var hp := [0, 6, 14, 24, 36, 50, 66, 84, 104, 126]
	for i in range(10):
		t.eq(MonsterProgression.threshold_for_level(i + 1), xp[i], "新经验门槛")
		t.eq(MonsterProgression.max_hp("rock_starter", i + 1), SpeciesDB.hp_of("rock_starter") + hp[i], "保留主线递增血量")
	var run := RunState.new_run(7101)
	var state := _battle(run)
	var first := state.unit_by_uid(1)
	first.hp = 2
	first.moved = true
	first.skill_used = true
	first.paralyzed_ticks = 1
	state.award_battle_experience("multi", 198)
	t.eq(first.combat_level, 10, "首层也能跨多级到十级")
	t.eq(first.hp, 128, "只补增加的生命上限")
	t.check(first.moved and first.skill_used and first.paralyzed_ticks == 1, "升级不刷新行动或控制")
	t.eq(state.trainer().combat_level, 10, "训练家共用新曲线即时成长")
	run.sync_from_battle(state)
	t.eq(RunState.from_dict(run.to_dict()).trainer_max_hp(), SpeciesDB.hp_of("trainer") + 126, "训练家等级血量读档")
	for floor in range(3):
		t.eq(run.level_cap_for_floor(floor), 10, "所有楼层只保留全局十级上限")

func _experience(t: TestContext) -> void:
	var run := RunState.new_run(7102)
	run.trainer_xp = 1
	var state := _battle(run)
	var first := state.unit_by_uid(1)
	first.hp = 5
	state.unit_by_uid(100).enemy_level = 9
	state.kill_unit(state.unit_by_uid(100), "测试", "player", 1)
	t.eq(first.combat_xp, 6, "九级敌人即时给击杀者六经验")
	t.eq(first.hp, 11, "升级即时加六生命")
	t.eq(state.unit_by_uid(2).combat_xp, 3, "其他存活原出战者得正常奖励的一半")
	state.kill_unit(state.unit_by_uid(2), "濒死", "enemy")
	state.on_captured(state.unit_by_uid(101), "grass_wild1", 5)
	t.eq(first.combat_xp, 8, "捕获共享固定二经验")
	t.eq(state.unit_by_uid(2).combat_xp, 3, "濒死前已得经验保留，之后不再获得")
	t.eq(state.trainer().combat_level, 2, "训练家获得参与和捕获经验后即时升级")
	var sig := state._signature()
	state.award_battle_experience("capture:101", 99)
	t.eq(state._signature(), sig, "事件幂等")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state)).clone()
	t.eq(restored.unit_by_uid(1).combat_xp, 8, "克隆与快照保留绝对经验")
	restored.end_battle("escape")
	var outcome := run.settle_battle(restored)
	t.eq(run.record_by_uid(1)["xp"], 9, "战后只新增一点参战经验")
	t.eq(run.record_by_uid(2)["xp"], 4, "濒死成员只追加非失败参战经验")
	t.eq(run.record_by_uid(2)["hp"], 0, "结算不复活濒死成员")
	t.eq(outcome["trainer_exp"]["gained"], 6, "训练家摘要包含本场即时与参战经验")
	run.settle_battle(restored)
	t.eq(run.record_by_uid(1)["xp"], 9, "重复结算不发经验")
	var late := _battle(RunState.new_run(7103))
	late.unit_by_uid(100).spawned_from_nest = true
	late.unit_by_uid(100).spawn_round = 9
	late.kill_unit(late.unit_by_uid(100), "测试", "player", 1)
	t.eq(late.unit_by_uid(1).combat_xp, 0, "后期增援不发击杀经验")
	late.unit_by_uid(101).set_corrupted(true)
	late.kill_unit(late.unit_by_uid(101), "测试", "player", 1)
	t.eq(late.unit_by_uid(1).combat_xp, 0, "黑化敌人不给击杀经验")
	var failed_run := RunState.new_run(7104)
	var failed := _battle(failed_run)
	failed.kill_unit(failed.unit_by_uid(100), "测试", "player", 1)
	failed.end_battle("forced_retreat")
	failed_run.settle_battle(failed)
	t.eq(failed_run.record_by_uid(1)["xp"], 2, "失败也保留此前即时经验")
	var joined := _battle(RunState.new_run(7110))
	joined.capture_options["capture_field_join"] = true
	joined.on_captured(joined.unit_by_uid(101), "grass_wild1", 5)
	joined.kill_unit(joined.unit_by_uid(100), "测试", "player", 1)
	t.eq(joined.unit_by_uid(101).combat_xp, 0, "本场新捕获不参与共享经验")

func _learning(t: TestContext) -> void:
	var run := RunState.new_run(7105)
	var record := run.record_by_uid(1)
	MonsterProgression.award_xp(record, 198)
	t.eq(run.pending_monster_levels().map(func(p): return p["level"]), [2, 4, 6, 8, 10], "偶数级四次学招和十级特性入口")
	for level in [2, 4, 6, 8]:
		var candidates := run.monster_level_choices(1, level)
		t.eq(candidates.size(), 3, "每次三招候选")
		var replaced: String = record["equipped_skills"][0] if record["equipped_skills"].size() == 3 else ""
		t.check(run.learn_monster_skill(1, level, candidates[0], replaced), "从候选中学习并维持三招装备")
	t.check(run.claim_monster_trait_upgrade(1, 10), "十级入口只领取一次")
	t.check(run.pending_monster_levels().is_empty(), "不重复领取")
	t.eq(run.monster_engraving_slots(record), 4, "最终四个刻印槽")

func _migration(t: TestContext) -> void:
	var run := RunState.new_run(7107)
	var data := run.to_dict()
	data.erase("progression_schema")
	data["version"] = 17
	data["carried"][0].merge({"level": 3, "xp": 28, "hp": 20, "claimed_even_levels": [2]}, true)
	var migrated := RunState.from_dict(data)
	t.eq(migrated.record_by_uid(1)["xp"], 23, "主线旧三级一半进度转为新三级一半")
	t.eq(migrated.record_by_uid(1)["hp"], 20, "主线生命成长不变，不重新缩放生命")
	t.eq(migrated.record_by_uid(1)["claimed_even_levels"], [2], "领取次数保留")
	t.eq(RunState.from_dict(migrated.to_dict()).record_by_uid(1)["xp"], 23, "迁移只发生一次")
	data.erase("trainer_xp")
	data.erase("trainer_level")
	data["version"] = 12
	data["carried"][0].merge({"level": 3, "xp": 14, "hp": 18}, true)
	var collab := RunState.from_dict(data)
	t.eq(collab.record_by_uid(1)["xp"], 23, "协作者旧108曲线等比例转换")
	t.eq(collab.record_by_uid(1)["hp"], 22, "协作者36上限半血迁为44上限半血")
	var old_state := _battle(run)
	old_state.unit_by_uid(1).combat_level = 3
	old_state.unit_by_uid(1).combat_xp = 14
	old_state.unit_by_uid(1).max_hp = 36
	old_state.unit_by_uid(1).hp = 18
	old_state.unit_by_uid(2).hp = 0
	old_state.enemy_kills.append({"uid": 100, "killer_side": "player", "killer_uid": 1, "level": 1})
	data["battle_snapshot"] = BattleSnapshot.save_state(old_state)
	data["in_battle"] = true
	var active := RunState.from_dict(data)
	t.eq(active.record_by_uid(1)["xp"], 25, "协作者未结算进行中战斗补记一次击杀经验")
	t.eq(active.record_by_uid(2)["hp"], 0, "旧战斗补经验不复活")
	t.eq(RunState.from_dict(active.to_dict()).record_by_uid(1)["xp"], 25, "补记幂等")

	data["carried"][0].merge({"level": 5, "xp": 108, "hp": 44}, true)
	old_state.unit_by_uid(1).combat_level = 5
	old_state.unit_by_uid(1).combat_xp = 0
	old_state.unit_by_uid(1).max_hp = 44
	old_state.unit_by_uid(1).hp = 22
	old_state.enemy_kills.clear()
	data["battle_snapshot"] = BattleSnapshot.save_state(old_state)
	var banked := RunState.from_dict(data)
	var banked_battle := BattleSnapshot.load_state(banked.battle_snapshot)
	t.eq(banked_battle.unit_by_uid(1).combat_level, 10, "移除旧楼层上限后积存经验立即升级")
	t.eq(banked_battle.unit_by_uid(1).max_hp, 156, "积存经验升级同步增加战场生命上限")
	t.eq(banked_battle.unit_by_uid(1).hp, 78, "旧上限下半血按新上限比例迁移")
	var peaceful := _battle(RunState.new_run(7111))
	peaceful.node_kind = "event"
	peaceful.end_battle("explored")
	var peaceful_run := RunState.new_run(7111)
	peaceful_run.region_mode = true
	peaceful_run.mark_deployed([1, 2, 3])
	peaceful_run.settle_battle(peaceful)
	t.eq(peaceful_run.record_by_uid(1)["xp"], 0, "反复进入和平收集区不会刷参战经验")

func _merchant(t: TestContext) -> void:
	var run := RunState.new_run(7108)
	var state := _battle(run)
	state.node_kind = "event"
	state.merchant = {"cell": Vector2i(2, 3), "stock": {}}
	state.trainer().cell = Vector2i(1, 3)
	state.award_battle_experience("level", 6)
	run.sync_from_battle(state)
	run.essence = 100
	var skill := String(RunState.upgrade_info(run.available_monster_upgrades(1)[0])["requires_skill"])
	var round_before := state.round
	t.check(Merchant.upgrade_skill(run, state, 1, skill)["ok"], "商人升级消耗空刻印槽")
	t.eq(run.essence, 88, "原质只在成功强化后扣除")
	t.eq(state.round, round_before, "强化不推进回合")
	t.check(not Merchant.upgrade_skill(run, state, 1, skill)["ok"], "同招不能重复强化")
	t.eq(run.essence, 88, "失败不扣钱")
	var loaded := RunState.from_dict(run.to_dict())
	t.eq(loaded.monster_empty_engraving_slots(loaded.record_by_uid(1)), 0, "已用刻印槽读档后保留")
	t.check(not loaded.get_region().nodes.values().any(func(node): return node.has("mentor")), "不再生成旧导师旁路")
