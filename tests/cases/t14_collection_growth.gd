extends RefCounted

const PROFILE_PATH := "res://.test_collection_profile.json"


func run(t: TestContext) -> void:
	t.begin("永久收藏、进攻补齐与升级池")
	_test_collection(t)
	_test_new_skills(t)
	_test_matchup_preview(t)
	_test_upgrades(t)
	t.finish()


func _test_collection(t: TestContext) -> void:
	var profile := CollectionState.defaults()
	t.eq(profile.owned.size(), 5, "初始收藏为五只基础怪物")
	var chosen := profile.select_records([1, 2, 3])
	var run := RunState.new_run(777, chosen)
	t.eq(run.carried.size(), 3, "从永久收藏三只开局")
	t.eq(int(run.carried[0]["collection_id"]), 1, "开局成员关联永久记录")
	run._add_capture("ice_wild1", 1)
	run.carried[3]["hp"] = 0
	run._add_capture("wind_wild1", 2)
	var added := profile.absorb_run(run)
	t.eq(added, 2, "濒死和存活的捕获均进入永久收藏")
	t.eq(profile.absorb_run(run), 0, "同一局重复结算不会复制收藏")
	t.check(profile.save(PROFILE_PATH), "永久收藏独立存档可写入")
	var loaded := CollectionState.load_profile(PROFILE_PATH)
	t.eq(loaded.owned.size(), 7, "重新读取仍保留捕获")
	var next_run := RunState.new_run(778, loaded.select_records([6, 7, 1]))
	t.eq(next_run.carried.size(), 3, "下局可选择刚捕获的怪物")
	t.eq(String(next_run.carried[0]["species_id"]), "ice_wild1", "冰系捕获可开局使用")
	t.eq(int(next_run.carried[0]["hp"]), SpeciesDB.hp_of("ice_wild1"), "濒死成员跨局恢复满血")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _test_new_skills(t: TestContext) -> void:
	for species_id in ["grass_starter", "grass_wild1", "ice_starter", "ice_wild1", "wind_starter", "wind_wild1"]:
		var skills := SpeciesDB.skills_of(species_id)
		var expected := "drain" if SpeciesDB.element_of(species_id) == "grass" else ("ice_shard" if SpeciesDB.element_of(species_id) == "ice" else "wind_gust")
		t.check(skills.has(expected), "%s 有基础进攻技" % species_id)
	var ice := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var ice_unit := ice.unit_by_uid(1)
	ice_unit.cell = Vector2i(0, 2)
	var ice_target := ice.unit_by_uid(100)
	var ice_hp := ice_target.hp
	var ice_hit := SkillResolver.apply(ice, ice_unit, "ice_shard", {"type": "unit", "unit": 100, "cell": ice_target.cell}, false)
	t.check(bool(ice_hit.get("ok", false)), "冰锥可命中目标")
	t.eq(ice_target.hp, ice_hp - 1, "冰锥造成 1 点直伤")
	var wind := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var wind_unit := wind.unit_by_uid(1)
	wind_unit.cell = Vector2i(0, 2)
	var pushed := wind.unit_by_uid(100)
	var gust := SkillResolver.apply(wind, wind_unit, "wind_gust", {"type": "unit", "unit": 100, "cell": pushed.cell}, false)
	t.check(bool(gust.get("ok", false)), "推风可命中两格内目标")
	t.eq(pushed.cell, Vector2i(3, 2), "推风使目标位移一格")
	var grass := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var grass_unit := grass.unit_by_uid(1)
	grass_unit.cell = Vector2i(0, 2)
	grass_unit.hp = 3
	var drain := SkillResolver.apply(grass, grass_unit, "drain", {"type": "unit", "unit": 100, "cell": Vector2i(2, 2)}, false)
	t.check(bool(drain.get("ok", false)), "吸取进入现行草系技能表")
	t.eq(grass_unit.hp, 4, "吸取后回复一格生命")


func _test_upgrades(t: TestContext) -> void:
	t.check(RunState.UPGRADES.size() >= 12, "升级池扩充到至少十二项")
	var run := RunState.new_run(880)
	t.check(not run.available_upgrades().has("volt_step"), "电光步死项不再进入奖励池")
	var chosen := CollectionState.defaults().select_records([1, 2, 3])
	var focused := RunState.new_run(881, chosen)
	t.check(not focused.available_upgrades().has("push_distance"), "没有岩怪时不抽推击强化")
	t.check(focused.available_upgrades().has("fireball_damage"), "有火怪时可抽火球强化")
	var before := focused.trainer_hp
	focused.take_upgrade("trainer_hp")
	t.eq(focused.trainer_hp, before + 2, "训练家防护立即增加当前生命")
	t.eq(focused.build_deploy_units([1])[0].max_hp, SpeciesDB.hp_of("trainer") + 2, "训练家防护增加出战生命上限")
	focused.take_upgrade("trainer_hp")
	t.eq(focused.trainer_hp, before + 2, "同项强化不能重复领取")
	focused.take_upgrade("team_move")
	t.eq(focused.build_deploy_units([1])[1].move_points, SpeciesDB.move_of("fire_starter") + 1, "机动训练改变实际出战移动力")
	t.eq(Elements.counter_hint("ice").contains("火"), true, "单位界面可显示冰被火克制")
	var fire := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 2)]], [], {}, {"fireball_damage": 1})
	fire.unit_by_uid(1).cell = Vector2i(0, 2)
	var fire_hit := SkillResolver.apply(fire, fire.unit_by_uid(1), "fire_burst", {"type": "cell", "cell": Vector2i(3, 2)}, false)
	t.eq(int(fire_hit["hits"][0]["damage"]), 3, "炽烈火球中心直伤 +1 生效")
	var water := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(2, 2)]], [], {}, {"water_flow_push": 1})
	water.unit_by_uid(1).cell = Vector2i(0, 2)
	SkillResolver.apply(water, water.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(2, 2)}, false)
	t.eq(water.unit_by_uid(100).cell, Vector2i(4, 2), "急流使水流击退两格")
	var gust := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(2, 2)]], [], {}, {"wind_gust_distance": 1})
	gust.unit_by_uid(1).cell = Vector2i(0, 2)
	SkillResolver.apply(gust, gust.unit_by_uid(1), "wind_gust", {"type": "unit", "unit": 100, "cell": Vector2i(2, 2)}, false)
	t.eq(gust.unit_by_uid(100).cell, Vector2i(4, 2), "强劲推风击退两格")


func _test_matchup_preview(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(3, 2)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 2)
	var preview := state.preview_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(3, 2)})
	t.check(bool(preview.get("ok", false)), "火球预览可执行")
	t.eq(int(preview["hits"][0].get("modifier", 0)), 1, "预览命中数据含克制 +1")
	t.eq(state.unit_by_uid(100).hp, SpeciesDB.hp_of("ice_wild1"), "预览不修改真实战斗生命")
