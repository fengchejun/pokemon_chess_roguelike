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
	t.eq(int(run_state.record_by_uid(1)["xp"]), 3, "真实推杀获得两点击杀经验与一点参战经验")


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
		MonsterProgression.award_xp(record, MonsterProgression.threshold_for_level(10))
		for level in [2, 4, 6, 8]:
			var candidates := run_state.monster_level_choices(1, level)
			t.eq(candidates.size(), 3, "%s Lv%d 提供三招候选" % [species_id, level])
			t.check(not candidates.is_empty(), "%s Lv%d 至少有一招可学" % [species_id, level])
			if not candidates.is_empty():
				var equipped: Array = record.get("equipped_skills", [])
				var replace_id := String(equipped[0]) if equipped.size() >= RunState.MAX_EQUIPPED_SKILLS else ""
				t.check(run_state.learn_monster_skill(1, level, String(candidates[0]), replace_id), "%s Lv%d 可在三招中领取一招" % [species_id, level])
		t.check(run_state.claim_monster_trait_upgrade(1, 10), "%s Lv10 可领取特性强化入口" % species_id)
		t.eq(run_state.monster_engraving_slots(record), 4, "%s Lv10 拥有四个刻印槽" % species_id)
		t.check(run_state.pending_monster_levels().is_empty(), "%s 五次成长已处理完毕" % species_id)


func _test_new_skill_upgrades(t: TestContext) -> void:
	var electric := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := electric.unit_by_uid(1)
	caster.cell = Vector2i(2, 2)
	var target := electric.unit_by_uid(100)
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	t.eq(SkillResolver.targets(electric, caster, "volt_replace").has(entry), true, "普通伏特替换已允许相邻单位")
	caster.upgrades = {"volt_replace_flex": 1}
	t.check(SkillResolver.targets(electric, caster, "volt_replace").has(entry), "灵活换位使相邻单位成为合法目标")
	var swap := SkillResolver.apply(electric, caster, "volt_replace", entry, false)
	t.check(bool(swap.get("ok", false)), "灵活换位可实际交换相邻单位")
	var wind := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var wind_caster := wind.unit_by_uid(1)
	wind_caster.cell = Vector2i(1, 2)
	wind.unit_by_uid(2).cell = Vector2i(4, 2)
	wind_caster.upgrades = {"tailwind_reach": 1}
	var gust := SkillResolver.apply(wind, wind_caster, "tailwind", {"type": "cell", "cell": wind_caster.cell}, false)
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
	t.eq(migrated, null, "旧六场本局不能继续，需重新开局")
	t.check(SaveSystem.has_legacy_save(path), "菜单可以识别不兼容的旧本局存档")
	var original_bytes := FileAccess.get_file_as_bytes(path)
	var backup_path := SaveSystem.backup_old_save(path)
	t.check(backup_path != "" and FileAccess.file_exists(backup_path), "不兼容本局存档先生成备份")
	t.eq(FileAccess.get_file_as_bytes(backup_path), original_bytes, "备份与原存档字节一致")
	t.check(not FileAccess.file_exists(path), "备份核对后移走旧本局存档")
	SaveSystem.delete_save(backup_path)
	SaveSystem.delete_save(path)


func _test_choice_save_roundtrip(t: TestContext) -> void:
	var run_state := RunState.new_run(2287)
	MonsterProgression.award_xp(run_state.record_by_uid(1), MonsterProgression.threshold_for_level(2))
	var before := run_state.monster_level_choices(1, 2)
	var path := "res://.test_growth_v2_save.json"
	t.check(SaveSystem.save_run(run_state, path), "本局待选强化可以写入存档")
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "本局待选强化可以从存档恢复")
	if loaded != null:
		t.eq(loaded.monster_level_choices(1, 2), before, "JSON 读档后三招候选保持不变")
		if not before.is_empty():
			t.check(loaded.learn_monster_skill(1, 2, String(before[0])), "读档后仍可从三招中选择学习")
	SaveSystem.delete_save(path)
