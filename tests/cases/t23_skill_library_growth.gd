extends RefCounted


func run(t: TestContext) -> void:
	t.begin("招式库与旧局升级迁移")
	_test_missing_skill_upgrades(t)
	_test_save_and_equipment(t)
	_test_v2_migration(t)
	_test_growth_and_prep_ui(t)
	t.finish()


func _test_missing_skill_upgrades(t: TestContext) -> void:
	var charge := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var fire := charge.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	fire.upgrades["flame_charge_damage"] = 1
	var crossed := charge.unit_by_uid(100)
	var charge_hp := crossed.hp
	SkillResolver.apply(charge, fire, "flame_charge", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.eq(crossed.hp, charge_hp - SkillDB.damage_of("flame_charge") - 5, "冲锋强化增加五点直伤")
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
		enemy.hp = 100
		enemy.max_hp = 100
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
	var ice := TestScenario.make_state(["ice_starter"], [["fire_wild1", Vector2i(7, 3)]])
	var ice_caster := ice.unit_by_uid(1)
	ice_caster.cell = Vector2i(0, 3)
	t.check(not ice.skill_targets(ice_caster, "freeze_ray").has({"type": "cell", "cell": Vector2i(7, 3)}), "急冻原射程不足七格")
	ice_caster.upgrades["freeze_ray_range"] = 1
	t.check(ice.skill_targets(ice_caster, "freeze_ray").has({"type": "cell", "cell": Vector2i(6, 3)}), "急冻强化射程达到七格")
	var wind := TestScenario.make_state(["wind_starter", "fire_starter", "grass_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var wind_caster := wind.unit_by_uid(1)
	wind_caster.cell = Vector2i(1, 3)
	wind.unit_by_uid(2).cell = Vector2i(2, 3)
	wind.unit_by_uid(3).cell = Vector2i(1, 4)
	var far_entry := {"type": "unit", "unit": 2, "cell": Vector2i(3, 3)}
	t.check(wind.skill_targets(wind_caster, "double_cast").has({"type": "unit", "unit": 2, "cell": Vector2i(2, 3)}), "风力引擎未强化时选一名相邻友军")
	wind_caster.upgrades["double_cast_range"] = 1
	t.check(wind.skill_targets(wind_caster, "double_cast").has({"type": "unit_pair", "units": [2, 3], "cell": Vector2i(1, 4)}), "保留旧强化存档标识并改为相邻双目标")
	wind.unit_by_uid(2).cell = Vector2i(3, 3)
	t.check(not wind.skill_targets(wind_caster, "double_cast").has(far_entry), "升级后施法距离仍为一格")


func _test_save_and_equipment(t: TestContext) -> void:
	var run_state := RunState.new_run(2301)
	var fire := run_state.record_by_uid(1)
	MonsterProgression.award_xp(fire, MonsterProgression.threshold_for_level(5))
	var level_two_skill := String(run_state.monster_level_choices(1, 2)[0])
	t.check(run_state.learn_monster_skill(1, 2, level_two_skill), "Lv2 从三招候选中领取一招")
	var level_four_skill := String(run_state.monster_level_choices(1, 4)[0])
	t.check(run_state.learn_monster_skill(1, 4, level_four_skill), "Lv4 再领取一次三选一")
	t.check(run_state.apply_merchant_skill_upgrade(1, level_two_skill), "技能强化消耗独立刻印槽")
	t.eq((fire.get("claimed_even_levels", []) as Array), [2, 4], "两次学招各自记录已领取等级")
	var saved := RunState.from_dict(run_state.to_dict())
	var restored := saved.record_by_uid(1)
	t.eq(restored.get("claimed_even_levels", []), [2, 4], "读档保留两次学招等级")
	t.eq(restored.get("upgrades_taken", []), [RunState.upgrade_id_for_skill(level_two_skill)], "读档保留商人技能强化")
	t.eq((restored.get("equipped_skills", []) as Array).size(), 3, "读档保留两招学习和三格装备上限")
	t.check(not saved.pending_upgrades(), "读档不会重复发放已领取等级")
	t.check(saved.equip_monster_skill(1, 1, ""), "整备换装可以卸下已学招式")
	t.check((restored.get("known_skills", []) as Array).has(level_two_skill), "卸下后依然已学")
	var deployed: Array = saved.build_deploy_units([1])
	t.check(not (deployed[1] as CombatUnit).skills.has(level_two_skill), "下场战斗仅使用装备招式")
	t.check(saved.equip_monster_skill(1, 1, level_two_skill), "整备换装可重新装备保留的招式")
	deployed = saved.build_deploy_units([1])
	var upgrade_id := RunState.upgrade_id_for_skill(level_two_skill)
	var upgrade_key := String(RunState.upgrade_info(upgrade_id).get("key", ""))
	t.eq(int((deployed[1] as CombatUnit).upgrades.get(upgrade_key, 0)), int(RunState.upgrade_info(upgrade_id).get("value", 0)), "重新装备后商人强化继续生效")
	var path := "res://.test_skill_library_save.json"
	t.check(SaveSystem.save_run(saved, path), "新招式库可写入 JSON 存档")
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "新招式库可从 JSON 存档读取")
	if loaded != null:
		t.eq(loaded.record_by_uid(1).get("claimed_even_levels", []), [2, 4], "JSON 往返仍保留两次学招等级")
		t.check((loaded.record_by_uid(1).get("equipped_skills", []) as Array).has(level_two_skill), "JSON 往返仍装备已学招式")
	SaveSystem.delete_save(path)


func _test_v2_migration(t: TestContext) -> void:
	var old := RunState.new_run(2302)
	var fire := old.record_by_uid(1)
	MonsterProgression.award_xp(fire, MonsterProgression.threshold_for_level(6))
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
	t.eq(int(record["xp"]), 70, "v2 迁移保留经验")
	t.eq(record["upgrades_taken"], ["fireball_damage"], "v2 仅保留技能专属强化")
	t.eq(record["claimed_even_levels"], [2], "v2 通用强化占用的 Lv4 与 Lv6 已退还")
	t.eq(migrated.pending_monster_levels().size(), 2, "v2 退还等级成为两次待选")
	t.eq(record["level_choices"], {}, "v2 旧三选一候选不会原样保留")
	var candidates := migrated.monster_level_choices(1, 4)
	t.eq(candidates.size(), 3, "v2 退还的首个待选等级重新生成三招候选")
	for skill_id in candidates:
		t.check(migrated.available_new_skills(1).has(String(skill_id)), "迁移候选来自当前普通可学池")
	t.eq(int(record["hp"]), migrated.monster_max_hp(record), "移除生命强化后裁剪当前 HP")
	t.eq(record["known_skills"], SpeciesDB.skills_of("fire_starter"), "旧局招式库由物种基础技能初始化")
	t.eq((record["equipped_skills"] as Array).size(), 3, "旧局基础技能正常装备")


func _test_growth_and_prep_ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(2303)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	MonsterProgression.award_xp(app.run.record_by_uid(1), MonsterProgression.threshold_for_level(6))
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 0, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var first_skill := String(app.run.monster_level_choices(1, 2)[0])
	var first: Button = app.current_screen.find_child("MonsterLearn_1_2_%s" % first_skill, true, false)
	t.check(first != null, "Lv2 升级页直接列出三招候选")
	first.pressed.emit()
	var second_skill := String(app.run.monster_level_choices(1, 4)[0])
	var second: Button = app.current_screen.find_child("MonsterLearn_1_4_%s" % second_skill, true, false)
	t.check(second != null, "Lv4 升级页继续提供三招候选")
	second.pressed.emit()
	var fire_record: Dictionary = app.run.record_by_uid(1)
	var replaced_skill := String((fire_record.get("equipped_skills", []) as Array)[2])
	var third_skill := String(app.run.monster_level_choices(1, 6)[0])
	var third: Button = app.current_screen.find_child("MonsterLearn_1_6_%s" % third_skill, true, false)
	t.check(third != null, "Lv6 可继续从三招候选中学习")
	if third == null:
		app.queue_free()
		return
	third.pressed.emit()
	var replace: Button = app.current_screen.find_child("MonsterReplace_1_6_%s_%s" % [third_skill, replaced_skill], true, false)
	t.check(replace != null, "三招满栏时出现卸招选择")
	if replace != null:
		replace.pressed.emit()
	t.check((app.run.record_by_uid(1).get("known_skills", []) as Array).has(third_skill), "UI 满栏学习后新招进入招式库")
	t.check((app.run.record_by_uid(1).get("known_skills", []) as Array).has(replaced_skill), "被替换的招式仍留在招式库")
	t.check(not (app.run.record_by_uid(1).get("equipped_skills", []) as Array).has(replaced_skill), "满栏替换后旧招不再装备（新 %s，旧 %s，当前 %s）" % [third_skill, replaced_skill, app.run.record_by_uid(1).get("equipped_skills", [])])
	app.show_prep()
	var selector: OptionButton = app.current_screen.find_child("SkillSlot_1_0", true, false)
	t.check(selector != null, "整备页显示三个技能装备位")
	if selector != null:
		var old_slot_one := String(app.run.record_by_uid(1).get("equipped_skills", [])[0])
		var selected_index := -1
		for index in range(selector.item_count):
			if String(selector.get_item_metadata(index)) == replaced_skill:
				selected_index = index
				break
		t.check(selected_index >= 0, "整备页列表包含已卸下的招式")
		if selected_index >= 0:
			selector.select(selected_index)
			selector.item_selected.emit(selected_index)
		t.check((app.run.record_by_uid(1).get("equipped_skills", []) as Array).has(replaced_skill), "整备页可换回招式库里的卸下技能")
		t.check(not (app.run.record_by_uid(1).get("equipped_skills", []) as Array).has(old_slot_one), "换装后原装备招式留在库中但不装备（原装备 %s，换入 %s，当前 %s）" % [old_slot_one, replaced_skill, app.run.record_by_uid(1).get("equipped_skills", [])])
	app.queue_free()
