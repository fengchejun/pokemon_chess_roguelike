extends RefCounted


func run(t: TestContext) -> void:
	t.begin("招式库、占位技能与旧局升级迁移")
	_test_placeholder_effect(t)
	_test_missing_skill_upgrades(t)
	_test_save_and_equipment(t)
	_test_v2_migration(t)
	_test_growth_and_prep_ui(t)
	t.finish()


func _test_placeholder_effect(t: TestContext) -> void:
	for element in ["fire", "water", "grass", "electric", "rock", "ice", "wind"]:
		var ids := SkillDB.placeholder_ids_for(element)
		t.eq(ids.size(), 2, "%s 有两招占位技能" % element)
		t.check(ids[0] != ids[1] and SkillDB.element_of(ids[0]) == element, "%s 占位招式 ID 与属性正确" % element)
		t.eq(SkillDB.get_def(ids[0]).get("range", 0), 2, "%s 占位招式基础射程 2" % element)
	var battle := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := battle.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("trial_fire_1")
	var target := battle.unit_by_uid(100)
	var hp := target.hp
	var terrain_before := battle.terrain.duplicate()
	var result := battle.cast_skill(caster, "trial_fire_1", {"type": "unit", "unit": 100, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "占位技能可作为正常技能施放")
	t.eq(target.hp, hp - 1, "占位技能只造成 1 点直接伤害")
	t.eq(battle.terrain, terrain_before, "占位技能不改变地形")
	t.eq(target.burn_ticks + target.slow_ticks + target.shock_ticks, 0, "占位技能不附加状态")
	t.check(not caster.can_act_skill(), "占位技能耗用普通一次施法机会")
	var ranged := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var ranged_caster := ranged.unit_by_uid(1)
	ranged_caster.cell = Vector2i(1, 3)
	ranged_caster.skills.append("trial_fire_1")
	t.check(ranged.skill_targets(ranged_caster, "trial_fire_1").is_empty(), "未强化试招无法攻击三格目标")
	ranged_caster.upgrades["trial_fire_1_range"] = 1
	t.check(not ranged.skill_targets(ranged_caster, "trial_fire_1").is_empty(), "强化后试招射程增加至三格")


func _test_missing_skill_upgrades(t: TestContext) -> void:
	var charge := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var fire := charge.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	fire.upgrades["flame_charge_damage"] = 1
	var crossed := charge.unit_by_uid(100)
	var charge_hp := crossed.hp
	SkillResolver.apply(charge, fire, "flame_charge", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.eq(crossed.hp, charge_hp - 1, "冲锋强化对沿途单位追加一点直伤")
	var vines := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var grass := vines.unit_by_uid(1)
	grass.cell = Vector2i(1, 3)
	grass.upgrades["wild_vines_reach"] = 1
	SkillResolver.apply(vines, grass, "wild_vines", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)}, false)
	t.eq(vines.terrain_at(Vector2i(4, 3)), TerrainDB.VINES, "藤蔓强化向前延长一格")
	var electric := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(2, 3)], ["rock_wild1", Vector2i(3, 3)], ["rock_wild1", Vector2i(4, 3)]
	])
	var bolt := electric.unit_by_uid(1)
	bolt.cell = Vector2i(1, 3)
	bolt.upgrades["lightning_first_shock"] = 1
	for enemy in electric.alive_units("enemy"):
		enemy.hp = 8
		enemy.max_hp = 8
	SkillResolver.resolve_channel(electric, bolt, "lightning", [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)])
	t.check(electric.unit_by_uid(100).paralyzed_ticks > 0, "闪电强化仅第一落点双重感电致麻痹")
	t.eq(electric.unit_by_uid(101).paralyzed_ticks, 0, "第二落点不获得额外感电")
	t.eq(electric.unit_by_uid(102).paralyzed_ticks, 0, "第三落点不获得额外感电")
	var rock := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var rock_caster := rock.unit_by_uid(1)
	rock_caster.cell = Vector2i(1, 3)
	t.check(rock.skill_targets(rock_caster, "rock_break").is_empty(), "碎岩原射程不足三格")
	rock_caster.upgrades["rock_break_range"] = 1
	t.check(not rock.skill_targets(rock_caster, "rock_break").is_empty(), "碎岩强化射程达到三格")
	var ice := TestScenario.make_state(["ice_starter"], [["fire_wild1", Vector2i(6, 3)]])
	var ice_caster := ice.unit_by_uid(1)
	ice_caster.cell = Vector2i(1, 3)
	t.check(not ice.skill_targets(ice_caster, "freeze_ray").has({"type": "cell", "cell": Vector2i(6, 3)}), "急冻原射程不足五格")
	ice_caster.upgrades["freeze_ray_range"] = 1
	t.check(ice.skill_targets(ice_caster, "freeze_ray").has({"type": "cell", "cell": Vector2i(6, 3)}), "急冻强化射程达到五格")
	var wind := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var wind_caster := wind.unit_by_uid(1)
	wind_caster.cell = Vector2i(1, 3)
	wind.unit_by_uid(2).cell = Vector2i(3, 3)
	var ally_entry := {"type": "unit", "unit": 2, "cell": Vector2i(3, 3)}
	t.check(not wind.skill_targets(wind_caster, "double_cast").has(ally_entry), "加速2原施放距离为一格")
	wind_caster.upgrades["double_cast_range"] = 1
	t.check(wind.skill_targets(wind_caster, "double_cast").has(ally_entry), "加速2强化后可施放至两格")


func _test_save_and_equipment(t: TestContext) -> void:
	var run_state := RunState.new_run(2301)
	var fire := run_state.record_by_uid(1)
	MonsterProgression.award_xp(fire, 18)
	t.check(run_state.learn_monster_skill(1, 2, "trial_fire_1"), "先学招领取 Lv2")
	t.check(run_state.enhance_monster_skill(1, 4, "trial_fire_1"), "再强化领取 Lv4")
	t.eq((fire.get("claimed_even_levels", []) as Array), [2, 4], "学习与强化都记录各自的等级")
	var saved := RunState.from_dict(run_state.to_dict())
	var restored := saved.record_by_uid(1)
	t.eq(restored.get("claimed_even_levels", []), [2, 4], "v3 读档保留学招与强化两个已领取等级")
	t.eq(restored.get("upgrades_taken", []), ["trial_fire_1_range"], "v3 读档保留占位招式强化")
	t.eq((restored.get("equipped_skills", []) as Array).size(), 4, "v3 读档保留四招装备")
	t.check(not saved.pending_upgrades(), "v3 读档不会重复发放已领取等级")
	t.check(saved.equip_monster_skill(1, 3, ""), "整备换装可以卸下第四招")
	t.check((restored.get("known_skills", []) as Array).has("trial_fire_1"), "卸下后依然已学")
	var deployed: Array = saved.build_deploy_units([1])
	t.check(not (deployed[1] as CombatUnit).skills.has("trial_fire_1"), "下场战斗仅使用装备招式")
	t.check(saved.equip_monster_skill(1, 3, "trial_fire_1"), "整备换装可重新装备保留的试招")
	deployed = saved.build_deploy_units([1])
	t.eq(int((deployed[1] as CombatUnit).upgrades.get("trial_fire_1_range", 0)), 1, "重新装备后强化继续生效")
	var path := "res://.test_skill_library_save.json"
	t.check(SaveSystem.save_run(saved, path), "新招式库可写入 JSON 存档")
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "新招式库可从 JSON 存档读取")
	if loaded != null:
		t.eq(loaded.record_by_uid(1).get("claimed_even_levels", []), [2, 4], "JSON 往返仍保留学招和强化等级")
		t.check((loaded.record_by_uid(1).get("equipped_skills", []) as Array).has("trial_fire_1"), "JSON 往返仍装备已学试招")
	SaveSystem.delete_save(path)


func _test_v2_migration(t: TestContext) -> void:
	var old := RunState.new_run(2302)
	var fire := old.record_by_uid(1)
	MonsterProgression.award_xp(fire, 40)
	fire["upgrades_taken"] = ["fireball_damage", "direct_guard", "max_hp_plus"]
	fire["claimed_even_levels"] = [2, 4, 6]
	fire["upgrades"] = {"fireball_damage": 1, "direct_guard": 1, "max_hp_plus": 2}
	fire["hp"] = 99
	fire["level_choices"] = {"8": ["direct_guard", "move_plus", "max_hp_plus"]}
	var data := old.to_dict()
	data["version"] = 2
	var migrated := RunState.from_dict(data)
	var record := migrated.record_by_uid(1)
	t.eq(int(record["level"]), 6, "v2 迁移保留局内等级")
	t.eq(int(record["xp"]), 40, "v2 迁移保留经验")
	t.eq(record["upgrades_taken"], ["fireball_damage"], "v2 仅保留技能专属强化")
	t.eq(record["claimed_even_levels"], [2], "v2 通用强化占用的 Lv4 与 Lv6 已退还")
	t.eq(migrated.pending_monster_levels().size(), 2, "v2 退还等级成为两次待选")
	t.eq(record["level_choices"], {}, "v2 旧三选一候选清空")
	t.eq(int(record["hp"]), migrated.monster_max_hp(record), "移除生命强化后裁剪当前 HP")
	t.eq(record["known_skills"], SpeciesDB.skills_of("fire_starter"), "旧局招式库由物种基础技能初始化")
	t.eq((record["equipped_skills"] as Array).size(), 3, "旧局基础技能正常装备")


func _test_growth_and_prep_ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(2303)
	MonsterProgression.award_xp(app.run.record_by_uid(1), 18)
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 0, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var learn_type: Button = app.current_screen.find_child("MonsterGrowth_learn_1_2", true, false)
	t.check(learn_type != null, "升级页提供学习类别")
	if learn_type == null:
		app.queue_free()
		return
	learn_type.pressed.emit()
	var first: Button = app.current_screen.find_child("MonsterLearn_1_2_trial_fire_1", true, false)
	t.check(first != null, "学招页列出第一招占位技能")
	first.pressed.emit()
	learn_type = app.current_screen.find_child("MonsterGrowth_learn_1_4", true, false)
	t.check(learn_type != null, "下一等级仍可选择学习另一招")
	learn_type.pressed.emit()
	var second: Button = app.current_screen.find_child("MonsterLearn_1_4_trial_fire_2", true, false)
	t.check(second != null, "学招页列出第二招占位技能")
	second.pressed.emit()
	var replace: Button = app.current_screen.find_child("MonsterReplace_1_4_trial_fire_2_flame_jet", true, false)
	t.check(replace != null, "四招满栏时出现卸招选择")
	replace.pressed.emit()
	t.eq(app.run.record_by_uid(1).get("equipped_skills", []), ["fire_burst", "trial_fire_2", "flame_charge", "trial_fire_1"], "UI 满栏换装仅替换指定装备位")
	app.show_prep()
	var selector: OptionButton = app.current_screen.find_child("SkillSlot_1_1", true, false)
	t.check(selector != null, "整备页显示四个技能装备位")
	if selector != null:
		for index in range(selector.item_count):
			if String(selector.get_item_metadata(index)) == "flame_jet":
				selector.item_selected.emit(index)
				break
	t.check((app.run.record_by_uid(1).get("equipped_skills", []) as Array).has("flame_jet"), "整备页可换回招式库里的卸下技能")
	t.check(not (app.run.record_by_uid(1).get("equipped_skills", []) as Array).has("trial_fire_2"), "换装后原招式留在库中但不装备")
	app.queue_free()
