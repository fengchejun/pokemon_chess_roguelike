extends RefCounted

const PROFILE_PATH := "res://.test_monster_progression_profile.json"


func run(t: TestContext) -> void:
	t.begin("局内等级、永久亲密度与旧收藏迁移")
	_test_thresholds(t)
	_test_legacy_profile(t)
	_test_collection_sync(t)
	t.finish()


func _test_thresholds(t: TestContext) -> void:
	t.eq(MonsterProgression.threshold_for_level(2), 4, "二级阈值是四点累计经验")
	t.eq(MonsterProgression.threshold_for_level(3), 10, "三级阈值是十点累计经验")
	t.eq(MonsterProgression.threshold_for_level(4), 18, "四级阈值按递增步长配置")
	t.eq(MonsterProgression.threshold_for_level(10), 108, "十级阈值为 108")
	t.eq(MonsterProgression.threshold_for_level(11), 108, "超过十级的阈值不继续增长")
	var record := {"species_id": "fire_starter", "hp": 0}
	var earned := MonsterProgression.award_xp(record, 10)
	t.eq(earned["level_after"], 3, "一次可跨多级")
	t.eq(record["hp"], 0, "濒死单位升级不被直接救活")
	for level in range(1, 11):
		t.eq(MonsterProgression.max_hp("fire_starter", level), 30 + int(MonsterProgression.PLAYER_HP_CURVE[level - 1]), "小火龙 Lv%d 使用平滑生命曲线" % level)
	t.eq(MonsterProgression.max_hp_for_record(record), 36, "记录中的三级生命上限为 36")
	t.eq(MonsterProgression.enemy_max_hp("fire_starter", 5), 50, "敌方继续使用独立生命曲线")
	t.eq(MonsterProgression.enemy_xp_reward(1), 2, "一级敌人提供两点击杀经验")
	t.eq(MonsterProgression.enemy_xp_reward(5), 4, "五级敌人提供四点击杀经验")
	t.eq(MonsterProgression.enemy_xp_reward(5, true), 6, "首领击杀额外增加两点经验")
	t.eq(MonsterProgression.enemy_participation_xp(5), 2, "高等级敌人的参与经验同步提高")
	t.check(MonsterProgression.enemy_xp_reward(11) > MonsterProgression.enemy_xp_reward(10), "入侵造成的高等级敌人继续提高击杀经验")
	for level in range(1, MonsterProgression.MAX_LEVEL):
		t.check(MonsterProgression.enemy_xp_reward(level + 1) >= MonsterProgression.enemy_xp_reward(level), "击杀经验随敌人等级单调提高")
		t.check(MonsterProgression.enemy_participation_xp(level + 1) >= MonsterProgression.enemy_participation_xp(level), "参与经验随敌人等级单调提高")
	var run := RunState.new_run(1901)
	run.mark_deployed([1, 2])
	var battle := TestScenario.make_state(["fire_starter", "water_starter"], [
		["rock_wild1", Vector2i(4, 2)],
		["water_wild1", Vector2i(5, 3)],
	])
	battle.unit_by_uid(100).enemy_level = 5
	battle.unit_by_uid(101).enemy_level = 5
	battle.unit_by_uid(101).is_boss = true
	battle.kill_unit(battle.unit_by_uid(100), "等级梯度验收", "player", 1)
	battle.kill_unit(battle.unit_by_uid(101), "首领梯度验收", "player", 2)
	t.eq(run.battle_kill_xp_for(battle, 1), MonsterProgression.enemy_xp_reward(5) + MonsterProgression.enemy_participation_xp(5), "首领击杀者获得完整经验，并在另一场按普通参与规则结算")
	t.eq(run.battle_kill_xp_for(battle, 2), MonsterProgression.enemy_participation_xp(5) + MonsterProgression.enemy_xp_reward(5, true), "不同击杀者按各自贡献获得等级梯度经验")
	t.eq(battle.battle_exp(), MonsterProgression.enemy_xp_reward(5) + MonsterProgression.enemy_xp_reward(5, true), "战场经验汇总也按敌人等级与首领标记计算")
	var living := {"species_id": "fire_starter", "level": 1, "xp": 0, "hp": 30}
	MonsterProgression.award_xp(living, 4)
	t.eq(living["level"], 2, "存活单位升到二级")
	t.eq(living["hp"], 33, "升级增加的生命同步补到当前生命")
	MonsterProgression.award_xp(record, -5)
	t.eq(record["xp"], 10, "负经验不会降低等级")
	MonsterProgression.award_xp(record, 100000)
	t.eq(record["level"], 10, "局内等级最高十级")
	t.eq(record["xp"], 108, "累计经验到十级阈值封顶")
	t.eq(MonsterProgression.award_xp(record, 5)["gained"], 0, "满级后不再增加经验")
	var capped := {"species_id": "fire_starter", "level": 1, "xp": 0, "hp": 30}
	MonsterProgression.award_xp(capped, 40, 5)
	t.eq(capped["level"], 5, "经验超过等级上限时只升到当前楼层上限")
	t.eq(capped["xp"], 40, "超出楼层上限的经验继续保留")
	MonsterProgression.unlock_for_level_cap(capped, 8)
	t.eq(capped["level"], 6, "进入下一层后按保留经验突破")
	var affinity_gain := MonsterProgression.award_affinity(record, 1)
	t.eq(affinity_gain["after"], 1, "亲密度从零开始并可加一")
	t.eq(MonsterProgression.award_affinity(record, -10)["gained"], 0, "负数不会扣除亲密度")


func _test_legacy_profile(t: TestContext) -> void:
	var legacy := {"version": 1, "next_id": 13, "owned": [
		{"id": 7, "species_id": "fire_starter", "source": "starter:fire_starter", "level": 8, "xp": 70},
		{"id": 10, "species_id": "water_starter", "source": "starter:water_starter", "level": 3, "xp": 10},
		{"id": 12, "species_id": "grass_starter", "source": "run:55:2", "level": 4, "xp": 18},
	]}
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var loaded := CollectionState.load_profile(PROFILE_PATH)
	t.eq(loaded.owned.size(), 3, "旧版收藏档仍可读取")
	t.eq(loaded.next_id, 13, "迁移保留下一实例 ID")
	t.eq(String(loaded.record_by_id(7).get("species_id")), "fire_starter", "迁移保留实例与物种")
	t.eq(String(loaded.record_by_id(12).get("source")), "run:55:2", "迁移保留捕获来源")
	t.eq(loaded.record_by_id(7).get("affinity"), 0, "旧永久经验转制后亲密度从零开始")
	t.check(not loaded.record_by_id(7).has("level") and not loaded.record_by_id(7).has("xp"), "迁移后收藏不保存等级经验")
	t.check(loaded.save(PROFILE_PATH), "迁移后的收藏可保存")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	t.eq(int(parsed.get("version", 0)), CollectionState.VERSION, "同路径保存为当前收藏格式")
	t.check(not parsed["owned"][0].has("level") and not parsed["owned"][0].has("xp"), "v2 文件不含旧永久等级经验")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _test_collection_sync(t: TestContext) -> void:
	var profile := CollectionState.defaults()
	var run := RunState.new_run(442, profile.select_records([1, 2, 3]))
	var fire: Dictionary = run.carried[0]
	MonsterProgression.award_xp(fire, 10)
	MonsterProgression.award_affinity(fire, 2)
	run._add_capture("ice_wild1", 0)
	var ice: Dictionary = run.carried.back()
	MonsterProgression.award_xp(ice, 4)
	MonsterProgression.award_affinity(ice, 1)
	t.eq(profile.absorb_run(run), 1, "只新增捕获的怪物")
	t.eq(profile.record_by_id(1)["affinity"], 2, "已收藏实例同步永久亲密度")
	t.check(not profile.record_by_id(1).has("level") and not profile.record_by_id(1).has("xp"), "收藏不吸收局内等级经验")
	var ice_id := int(ice["collection_id"])
	t.eq(profile.record_by_id(ice_id)["affinity"], 1, "新捕获实例登记亲密度")
	t.eq(profile.absorb_run(run), 0, "再次吸收不重复新增")
	MonsterProgression.award_affinity(profile.record_by_id(1), 3)
	profile.absorb_run(run)
	t.eq(profile.record_by_id(1)["affinity"], 5, "旧局再次吸收不覆盖更高亲密度")
	t.check(profile.save(PROFILE_PATH), "亲密度收藏可写入")
	var loaded := CollectionState.load_profile(PROFILE_PATH)
	t.eq(loaded.record_by_id(1)["affinity"], 5, "重新读取保留亲密度")
	t.eq(loaded.record_by_id(ice_id)["affinity"], 1, "重新读取保留新捕获亲密度")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
