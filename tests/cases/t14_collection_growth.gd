extends RefCounted

const PROFILE_PATH := "res://.test_collection_profile.json"


func run(t: TestContext) -> void:
	t.begin("永久收藏、进攻补齐与升级池")
	_test_collection(t)
	_test_new_skills(t)
	_test_matchup_preview(t)
	_test_skill_bound_growth(t)
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
		var expected := "drain" if species_id.begins_with("grass_") else ("ice_shard" if species_id.begins_with("ice_") else "tailwind")
		t.check(skills.has(expected), "%s 有有效初始技" % species_id)
	var ice := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var ice_unit := ice.unit_by_uid(1)
	ice_unit.cell = Vector2i(0, 2)
	var ice_target := ice.unit_by_uid(100)
	var ice_hp := ice_target.hp
	var ice_hit := SkillResolver.apply(ice, ice_unit, "ice_shard", {"type": "unit", "unit": 100, "cell": ice_target.cell}, false)
	t.check(bool(ice_hit.get("ok", false)), "冰锥可命中目标")
	t.eq(ice_target.hp, ice_hp - SkillDB.damage_of("ice_shard"), "冰锥造成配置的直伤")
	var wind := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var wind_unit := wind.unit_by_uid(1)
	wind_unit.cell = Vector2i(0, 2)
	var pushed := wind.unit_by_uid(100)
	var gust := SkillResolver.apply(wind, wind_unit, "wind_gust", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(1, 2)}, false)
	t.check(not bool(gust.get("ok", false)), "已删除推风无法施放")
	t.eq(pushed.cell, Vector2i(2, 2), "删除的技能不改变站位")
	var grass := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(2, 2)]])
	var grass_unit := grass.unit_by_uid(1)
	grass_unit.cell = Vector2i(0, 2)
	grass_unit.hp = 3
	var drain := SkillResolver.apply(grass, grass_unit, "drain", {"type": "unit", "unit": 100, "cell": Vector2i(2, 2)}, false)
	t.check(bool(drain.get("ok", false)), "吸取进入现行草系技能表")
	t.eq(grass_unit.hp, 3 + Balance.DRAIN_HEAL, "吸取后回复配置的生命")


func _test_skill_bound_growth(t: TestContext) -> void:
	var chosen := CollectionState.defaults().select_records([1, 2, 3])
	var run_state := RunState.new_run(881, chosen)
	t.check(run_state.available_monster_upgrades(1).has("fireball_damage"), "火系可强化已学火球术")
	t.check(not run_state.available_monster_upgrades(2).has("fireball_damage"), "水系不会获得火系强化")
	t.check(not run_state.available_monster_upgrades(1).has("direct_guard"), "永久通用减伤不再可选")
	t.eq(run_state.available_new_skills(1), ["flame_jet", "flame_charge", "trial_fire_1", "trial_fire_2", "fire_amplify", "flame_rush", "windfire_breath", "furnace_fist", "skyfire", "combustion", "burn_out"], "未选为开局技能的物种招式与扩充火系招式可学习")
	var fire := run_state.record_by_uid(1)
	MonsterProgression.award_xp(fire, MonsterProgression.threshold_for_level(10))
	var level_two := String(run_state.monster_level_choices(1, 2)[0])
	t.check(run_state.learn_monster_skill(1, 2, level_two), "Lv2 从三招候选中学习一招")
	var level_four := String(run_state.monster_level_choices(1, 4)[0])
	t.check(run_state.learn_monster_skill(1, 4, level_four), "Lv4 继续从三招候选中学习")
	t.eq((fire.get("equipped_skills", []) as Array).size(), 3, "学习两招后装满三个装备位")
	var level_six := String(run_state.monster_level_choices(1, 6)[0])
	var level_six_replacement := String((fire.get("equipped_skills", []) as Array)[2])
	t.check(run_state.learn_monster_skill(1, 6, level_six, level_six_replacement), "Lv6 仍获得一次独立三选一并替换装备")
	t.eq((fire.get("equipped_skills", []) as Array).size(), 3, "技能装备上限为三个")
	var level_eight := String(run_state.monster_level_choices(1, 8)[0])
	var replaced_skill := String((fire.get("equipped_skills", []) as Array)[2])
	t.check(not run_state.learn_monster_skill(1, 8, level_eight), "三格满栏学招需先指定卸下招式")
	t.check(run_state.learn_monster_skill(1, 8, level_eight, replaced_skill), "Lv8 三招满栏时可替换一招后学习")
	t.check((fire.get("known_skills", []) as Array).has(replaced_skill), "卸下的招式保留在本局招式库")
	t.check(run_state.equip_monster_skill(1, 2, replaced_skill), "战前可换回旧招式")
	t.check(not (fire.get("equipped_skills", []) as Array).has(level_eight), "换装后新招保留在招式库")
	t.check(run_state.claim_monster_trait_upgrade(1, 10), "Lv10 领取特性强化入口")
	t.check(bool(fire.get("trait_upgrade_claimed", false)), "特性强化状态写入怪物记录")
	t.eq(run_state.monster_engraving_slots(fire), 4, "Lv10 最终拥有四个刻印槽")
	fire["affinity"] = 0
	t.eq(run_state.merchant_skill_upgrade_cost(fire), 12, "无亲密度时技能强化为 12 原质")
	fire["affinity"] = 5
	t.eq(run_state.merchant_skill_upgrade_cost(fire), 11, "每五级亲密度降低 1 原质")
	fire["affinity"] = 99
	t.eq(run_state.merchant_skill_upgrade_cost(fire), 8, "亲密度折扣最多 4 原质")
	var upgrade_id := String(run_state.available_monster_upgrades(1)[0])
	var upgrade_skill := String(RunState.upgrade_info(upgrade_id).get("requires_skill", ""))
	t.check(run_state.apply_merchant_skill_upgrade(1, upgrade_skill), "技能强化改由带空刻印槽的商人流程执行")
	t.check(not run_state.apply_merchant_skill_upgrade(1, upgrade_skill), "同一招不能重复消耗刻印槽")
	t.check(run_state.pending_monster_levels().is_empty(), "五次偶数级成长均已处理")
	t.check(Elements.counter_hint("fire").contains("草") and Elements.counter_hint("fire").contains("水"), "火系显示克草与被水克")


func _test_matchup_preview(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(3, 2)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 2)
	var preview := state.preview_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(3, 2)})
	t.check(bool(preview.get("ok", false)), "火球预览可执行")
	t.eq(preview["hits"].size(), 0, "吟唱预览不提前造成命中")
	t.check(preview["area_cells"].has(Vector2i(3, 2)), "吟唱预览显示锁定区域")
	t.eq(state.unit_by_uid(100).hp, SpeciesDB.hp_of("ice_wild1"), "预览不修改真实战斗生命")
