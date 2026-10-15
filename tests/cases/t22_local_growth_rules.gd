extends RefCounted


func run(t: TestContext) -> void:
	t.begin("局内强化与真实击杀链路")
	_test_push_kill_attribution(t)
	_test_local_guards(t)
	_test_new_skill_upgrades(t)
	_test_all_species_choice_depth(t)
	_test_choice_save_roundtrip(t)
	_test_old_run_migration(t)
	t.finish()


func _test_push_kill_attribution(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 2), TerrainDB.DEEP]])
	var battle := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(3, 2)]], terrain)
	var caster := battle.unit_by_uid(1)
	caster.cell = Vector2i(2, 2)
	var enemy := battle.unit_by_uid(100)
	enemy.hp = 3
	var result := battle.cast_skill(caster, "rock_push", {"type": "unit", "unit": 100, "cell": enemy.cell})
	t.check(bool(result.get("ok", false)), "推击技能成功施放")
	t.eq(enemy.hp, 0, "推击后进入深水会立即击败非水系怪物")
	t.eq(int(battle.enemy_kills[0].get("killer_uid", -1)), caster.uid, "推击入深水沿用施法者归属")
	var run_state := RunState.new_run(2201, [{"id": 7, "species_id": "rock_starter", "affinity": 0}])
	run_state.mark_deployed([1])
	run_state.settle_battle(battle)
	t.eq(int(run_state.record_by_uid(1)["xp"]), Balance.EXP_PER_KILL, "真实推杀给岩怪两点击杀经验")


func _test_local_guards(t: TestContext) -> void:
	var battle := TestScenario.make_state(["rock_starter", "water_starter"], [["fire_wild1", Vector2i(6, 6)]])
	var guarded := battle.unit_by_uid(1)
	var plain := battle.unit_by_uid(2)
	var attacker := battle.unit_by_uid(100)
	guarded.upgrades = {"direct_guard": 1, "collision_guard": 1}
	var direct_guarded := battle.damage_unit(attacker, guarded, 1, {"element": "fire", "cause": "测试技能"})
	var direct_plain := battle.damage_unit(attacker, plain, 1, {"element": "fire", "cause": "测试技能"})
	t.eq(int(direct_guarded["amount"]), 1, "旧通用直伤减免已失效")
	t.eq(int(direct_plain["amount"]), 1, "队友不会继承技能减伤")
	var collision_guarded := battle.damage_unit(null, guarded, 1, {"no_element": true, "collision": true, "cause": "碰撞"})
	var collision_plain := battle.damage_unit(null, plain, 1, {"no_element": true, "collision": true, "cause": "碰撞"})
	t.eq(int(collision_guarded["amount"]), 1, "旧通用碰撞减免已失效")
	t.eq(int(collision_plain["amount"]), 1, "队友不会继承碰撞减伤")


func _test_all_species_choice_depth(t: TestContext) -> void:
	var index := 0
	for species_id in SpeciesDB.SPECIES:
		if SpeciesDB.is_trainer(String(species_id)):
			continue
		index += 1
		var run_state := RunState.new_run(2200 + index, [{"id": index, "species_id": species_id, "affinity": 0}])
		var record := run_state.record_by_uid(1)
		MonsterProgression.award_xp(record, 108)
		for level in [2, 4, 6, 8, 10]:
			var enhancements := run_state.available_monster_upgrades(1)
			var learnable := run_state.available_new_skills(1)
			t.check(not enhancements.is_empty() or not learnable.is_empty(), "%s Lv%d 至少有一种合法成长" % [species_id, level])
			var chosen := false
			if not enhancements.is_empty():
				chosen = run_state.take_monster_level_choice(1, level, String(enhancements[0]))
			elif not learnable.is_empty():
				var equipped: Array = record.get("equipped_skills", [])
				var replace_id := String(equipped[0]) if equipped.size() >= RunState.MAX_EQUIPPED_SKILLS else ""
				chosen = run_state.learn_monster_skill(1, level, String(learnable[0]), replace_id)
			t.check(chosen, "%s Lv%d 可领取独立成长" % [species_id, level])
		t.check(run_state.pending_monster_levels().is_empty(), "%s 五次成长已处理完毕" % species_id)


func _test_new_skill_upgrades(t: TestContext) -> void:
	var electric := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := electric.unit_by_uid(1)
	caster.cell = Vector2i(2, 2)
	var target := electric.unit_by_uid(100)
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	t.eq(SkillResolver.targets(electric, caster, "volt_replace").has(entry), false, "普通伏特替换仍要求相距两格")
	caster.upgrades = {"volt_replace_flex": 1}
	t.check(SkillResolver.targets(electric, caster, "volt_replace").has(entry), "灵活换位使相邻单位成为合法目标")
	var swap := SkillResolver.apply(electric, caster, "volt_replace", entry, false)
	t.check(bool(swap.get("ok", false)), "灵活换位可实际交换相邻单位")
	var wind := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var wind_caster := wind.unit_by_uid(1)
	wind_caster.cell = Vector2i(1, 2)
	wind.unit_by_uid(2).cell = Vector2i(4, 2)
	wind_caster.upgrades = {"tailwind_reach": 1}
	var gust := SkillResolver.apply(wind, wind_caster, "tailwind", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(2, 2)}, false)
	t.check(bool(gust.get("ok", false)), "远风可实际施放")
	t.check(wind.unit_by_uid(2).haste_ticks > 0, "远风影响正前方第三排友军")


func _test_old_run_migration(t: TestContext) -> void:
	var old := RunState.new_run(2288)
	old.battle_index = 3
	old.reward_inventory = ["map:water"]
	old.settlement_pending = true
	old.last_settlement = {"reason": "victory", "exp": 40, "monster_exp": [{"uid": 1, "level_after": 6}]}
	old.carried[0]["level"] = 6
	old.carried[0]["xp"] = 40
	old.carried[0]["hp"] = 20
	var data := old.to_dict()
	data["version"] = 1
	data["trainer_hp"] = 20
	data["exp"] = 40
	data["upgrades"] = {"team_move": 1}
	data["upgrades_taken"] = ["team_move"]
	var path := "res://.test_growth_v1_save.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var migrated := SaveSystem.load_run(path)
	t.check(migrated != null, "SaveSystem 可以读取并迁移 v1 本局存档")
	if migrated == null:
		SaveSystem.delete_save(path)
		return
	t.eq(migrated.battle_index, 3, "旧本局迁移保留关卡进度")
	t.eq(migrated.reward_inventory, ["map:water"], "旧本局迁移保留消耗卡背包")
	t.eq(int(migrated.record_by_uid(1)["level"]), 1, "旧本局等级重置")
	t.eq(int(migrated.record_by_uid(1)["xp"]), 0, "旧本局经验重置")
	t.eq(int(migrated.record_by_uid(1)["hp"]), SpeciesDB.hp_of("fire_starter"), "旧本局生命被校正到新基础上限")
	t.eq(migrated.trainer_hp, SpeciesDB.hp_of("trainer"), "旧训练家全局生命强化迁移后被校正")
	t.check(migrated.upgrades.is_empty() and migrated.upgrades_taken.is_empty(), "旧全队强化全部清除")
	t.eq(int(migrated.last_settlement.get("exp", -1)), 0, "旧待处理结算不再展示已清除的经验")
	t.check(bool(migrated.last_settlement.get("growth_migrated", false)), "旧结算页会提示成长迁移")
	SaveSystem.delete_save(path)


func _test_choice_save_roundtrip(t: TestContext) -> void:
	var run_state := RunState.new_run(2287)
	MonsterProgression.award_xp(run_state.record_by_uid(1), 4)
	var before := run_state.monster_level_choices(1, 2)
	var path := "res://.test_growth_v2_save.json"
	t.check(SaveSystem.save_run(run_state, path), "本局待选强化可以写入存档")
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "本局待选强化可以从存档恢复")
	if loaded != null:
		t.eq(loaded.monster_level_choices(1, 2), before, "JSON 读档后候选保持不变")
		if not before.is_empty():
			t.check(loaded.take_monster_level_choice(1, 2, String(before[0])), "读档后仍可领取该怪物强化")
	SaveSystem.delete_save(path)
