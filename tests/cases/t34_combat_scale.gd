extends RefCounted

## 数值刻度的玩法结果：跨楼层击倒节奏、预览结算与旧存档比例。


func run(t: TestContext) -> void:
	t.begin("战斗数值刻度")
	_t_ordinary_hits(t)
	_t_enemy_pressure(t)
	_t_no_level_damage(t)
	_t_v4_save_migration(t)
	_t_v5_save_migration(t)
	_t_v6_save_migration(t)
	t.finish()


func _t_ordinary_hits(t: TestContext) -> void:
	for floor_index in 3:
		for species_id in ["ice_wild1", "fire_wild1", "rock_wild1"]:
			var state := TestScenario.make_state(["rock_starter"], [[species_id, Vector2i(3, 2)]])
			var caster := state.unit_by_uid(1)
			var target := state.unit_by_uid(100)
			caster.cell = Vector2i(2, 2)
			caster.combat_level = 1 + floor_index * 2
			BattleDB.configure_enemy(target, 42, floor_index * Balance.BATTLES_PER_FLOOR, 0)
			var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
			var preview := state.preview_skill(caster, "rock_break", entry)
			t.check(bool(preview.get("ok", false)) and not (preview.get("hits", []) as Array).is_empty(), "第 %d 层 %s 碎岩预览可命中" % [floor_index + 1, species_id])
			if not bool(preview.get("ok", false)) or (preview.get("hits", []) as Array).is_empty():
				continue
			var damage := int(preview["hits"][0]["damage"])
			var hits_to_defeat := ceili(float(target.max_hp) / float(damage)) if damage > 0 else 999
			t.check(hits_to_defeat >= 2 and hits_to_defeat <= 7, "第 %d 层 %s 未强化技能 %d 伤击倒 %d HP 需 %d 次" % [floor_index + 1, species_id, damage, target.max_hp, hits_to_defeat])
			var hp_before := target.hp
			var actual := state.cast_skill(caster, "rock_break", entry)
			t.check(bool(actual.get("ok", false)), "碎岩实战施放成功")
			t.eq(hp_before - target.hp, damage, "技能预览与结算伤害一致")
			if floor_index > 0:
				var upgraded := TestScenario.make_state(["rock_starter"], [[species_id, Vector2i(3, 2)]])
				var upgraded_caster := upgraded.unit_by_uid(1)
				var upgraded_target := upgraded.unit_by_uid(100)
				upgraded_caster.cell = Vector2i(2, 2)
				upgraded_caster.combat_level = 1 + floor_index * 2
				upgraded_caster.upgrades["rock_break_range"] = 1
				BattleDB.configure_enemy(upgraded_target, 42, floor_index * Balance.BATTLES_PER_FLOOR, 0)
				var upgraded_entry := {"type": "unit", "unit": upgraded_target.uid, "cell": upgraded_target.cell}
				var upgraded_preview := upgraded.preview_skill(upgraded_caster, "rock_break", upgraded_entry)
				t.check(bool(upgraded_preview.get("ok", false)) and not (upgraded_preview.get("hits", []) as Array).is_empty(), "强化碎岩预览可命中")
				if bool(upgraded_preview.get("ok", false)) and not (upgraded_preview.get("hits", []) as Array).is_empty():
					var upgraded_damage := int(upgraded_preview["hits"][0]["damage"])
					t.check(ceili(float(upgraded_target.max_hp) / float(upgraded_damage)) >= 2 and ceili(float(upgraded_target.max_hp) / float(upgraded_damage)) <= 6, "第 %d 层 %s 强化碎岩需2–6次命中" % [floor_index + 1, species_id])
					var upgraded_hp_before := upgraded_target.hp
					t.check(bool(upgraded.cast_skill(upgraded_caster, "rock_break", upgraded_entry).get("ok", false)), "强化碎岩实战施放成功")
					t.eq(upgraded_hp_before - upgraded_target.hp, upgraded_damage, "强化后预览与实战伤害一致")


func _t_enemy_pressure(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var player := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	player.combat_level = 5
	player.max_hp = MonsterProgression.max_hp(player.species_id, player.combat_level)
	player.hp = player.max_hp
	BattleDB.configure_enemy(enemy, 42, 2 * Balance.BATTLES_PER_FLOOR, 0)
	var player_damage := Balance.skill_damage_for_side(SkillDB.damage_of("rock_break"), player.side)
	var enemy_damage := Balance.skill_damage_for_side(SkillDB.damage_of("rock_break"), enemy.side)
	t.eq(enemy_damage, player_damage, "敌我同技能基础伤害相同")
	t.check(ceili(float(player.max_hp) / float(enemy_damage)) >= 3, "单个普通敌人通常不能两击带走同层坦克")


func _t_no_level_damage(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	var baseline := state.preview_skill(caster, "rock_break", entry)
	t.check(bool(baseline.get("ok", false)) and not (baseline.get("hits", []) as Array).is_empty(), "Lv1 技能预览可命中")
	if not bool(baseline.get("ok", false)) or (baseline.get("hits", []) as Array).is_empty():
		return
	var baseline_damage := int(baseline["hits"][0]["damage"])
	for level in range(2, 11):
		caster.combat_level = level
		var preview := state.preview_skill(caster, "rock_break", entry)
		t.eq(int(preview["hits"][0]["damage"]), baseline_damage, "Lv%d 不自动增加技能直伤" % level)


func _t_v4_save_migration(t: TestContext) -> void:
	var run := RunState.new_run(3405)
	var old := run.to_dict()
	old["version"] = 4
	old["trainer_hp"] = 5
	(old["carried"] as Array)[0]["hp"] = 3
	var save_path := "res://.test_v4_combat_scale_save.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	t.check(file != null, "可写入隔离的旧版测试存档")
	if file == null:
		return
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := SaveSystem.load_run(save_path)
	SaveSystem.delete_save(save_path)
	t.check(loaded != null, "v4 本局存档仍可载入")
	if loaded == null:
		return
	t.eq(loaded.trainer_hp, 25, "v4 训练家按旧 5/7 生命比例迁移")
	t.eq(int(loaded.carried[0]["hp"]), 15, "v4 小火龙按旧 3/6 生命比例迁移")
	t.eq(loaded.monster_max_hp(loaded.carried[0]), SpeciesDB.hp_of(String(loaded.carried[0]["species_id"])), "旧怪物生命上限匹配新刻度")
	var round_trip := RunState.from_dict(loaded.to_dict())
	t.eq(int(round_trip.carried[0]["hp"]), 15, "v7 重读不会重复缩放生命")


func _t_v5_save_migration(t: TestContext) -> void:
	var old := RunState.new_run(3406).to_dict()
	old["version"] = 5
	old["trainer_hp"] = 35
	(old["carried"] as Array)[0]["level"] = 4
	(old["carried"] as Array)[0]["hp"] = 45
	var save_path := "res://.test_v5_combat_scale_save.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	t.check(file != null, "可写入隔离的 v5 测试存档")
	if file == null:
		return
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := SaveSystem.load_run(save_path)
	SaveSystem.delete_save(save_path)
	t.check(loaded != null, "v5 本局存档仍可载入")
	if loaded == null:
		return
	t.eq(loaded.trainer_hp, 18, "v5 训练家半血迁移到新上限")
	t.eq(loaded.monster_max_hp(loaded.carried[0]), 54, "v5 四级怪物迁移到递增生命新上限")
	t.eq(int(loaded.carried[0]["hp"]), 35, "v5 怪物按旧 45/70 生命比例迁移")


func _t_v6_save_migration(t: TestContext) -> void:
	var old := RunState.new_run(3407).to_dict()
	old["version"] = 6
	(old["carried"] as Array)[0]["level"] = 4
	(old["carried"] as Array)[0]["hp"] = 30
	var save_path := "res://.test_v6_combat_scale_save.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	t.check(file != null, "可写入隔离的 v6 测试存档")
	if file == null:
		return
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := SaveSystem.load_run(save_path)
	SaveSystem.delete_save(save_path)
	t.check(loaded != null, "v6 本局存档仍可载入")
	if loaded == null:
		return
	t.eq(loaded.monster_max_hp(loaded.carried[0]), 54, "v6 四级怪物使用递增生命曲线")
	t.eq(int(loaded.carried[0]["hp"]), 27, "v6 的 30/60 生命按比例迁移到 20/40")
