extends RefCounted

const PROFILE_PATH := "res://.test_monster_progression_profile.json"


func run(t: TestContext) -> void:
	t.begin("局内等级、永久亲密度与旧收藏迁移")
	_test_thresholds(t)
	_test_legacy_profile(t)
	_test_collection_sync(t)
	t.finish()


func _test_thresholds(t: TestContext) -> void:
	t.eq(MonsterProgression.threshold_for_level(2), 6, "二级阈值是六点累计经验")
	t.eq(MonsterProgression.threshold_for_level(3), 16, "三级阈值是十八点累计经验")
	t.eq(MonsterProgression.threshold_for_level(4), 30, "四级阈值按递增步长配置")
	t.eq(MonsterProgression.threshold_for_level(10), 198, "十级阈值为198")
	t.eq(MonsterProgression.threshold_for_level(11), 198, "超过十级的阈值不继续增长")
	var record := {"species_id": "fire_starter", "hp": 0}
	var earned := MonsterProgression.award_xp(record, MonsterProgression.threshold_for_level(3))
	t.eq(earned["level_after"], 3, "一次可跨多级")
	t.eq(record["hp"], 0, "濒死单位升级不被直接救活")
	for level in range(1, 11):
		t.eq(MonsterProgression.max_hp("fire_starter", level), [30, 36, 44, 54, 66, 80, 96, 114, 134, 156][level - 1], "小火龙 Lv%d 生命增量逐级提高" % level)
	t.eq(MonsterProgression.max_hp_for_record(record), 44, "记录中的三级生命上限为44")
	MonsterProgression.award_xp(record, -5)
	t.eq(record["xp"], 16, "负经验不会降低等级")
	MonsterProgression.award_xp(record, 100000)
	t.eq(record["level"], 10, "局内等级最高十级")
	t.eq(record["xp"], 198, "累计经验到十级阈值封顶")
	t.eq(MonsterProgression.award_xp(record, 5)["gained"], 0, "满级后不再增加经验")
	var uncapped := {"species_id": "fire_starter", "level": 1, "xp": 0, "hp": 30}
	MonsterProgression.award_xp(uncapped, 126, 5)
	t.eq(uncapped["level"], 8, "旧楼层上限参数不再限制升级")
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
	MonsterProgression.award_xp(fire, MonsterProgression.threshold_for_level(3))
	MonsterProgression.award_affinity(fire, 2)
	run._add_capture("ice_wild1", 0)
	var ice: Dictionary = run.carried.back()
	MonsterProgression.award_xp(ice, MonsterProgression.threshold_for_level(2))
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
