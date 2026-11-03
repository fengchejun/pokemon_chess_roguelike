extends RefCounted


func run(t: TestContext) -> void:
	t.begin("电系技能池扩充与感电麻痹互斥")
	_definition_and_learning(t)
	_shock_paralysis_exclusion(t)
	_magnet_pull(t)
	_glare(t)
	_electromagnetic_laser(t)
	_electric_resonance(t)
	_electric_spark(t)
	_ui_display(t)
	t.finish()


func _definition_and_learning(t: TestContext) -> void:
	var expected_upgrades := {
		"magnet_pull": "magnet_pull_reach",
		"glare": "glare_radius",
		"electromagnetic_laser": "electromagnetic_laser_damage",
		"electric_resonance": "electric_resonance_power",
		"electric_spark": "electric_spark_damage",
	}
	for skill_id in expected_upgrades:
		t.check(not SkillDB.get_def(skill_id).is_empty(), "%s 有技能定义" % skill_id)
		t.check(SkillDB.learnable_ids_for("electric").has(skill_id), "%s 进入电系普通学习池" % skill_id)
		t.check(not SkillDB.is_special(skill_id), "%s 是普通技能" % skill_id)
		t.eq(RunState.upgrade_id_for_skill(skill_id), expected_upgrades[skill_id], "%s 有专属强化" % skill_id)
		t.check(not SpeciesDB.skills_of("electric_starter").has(skill_id), "%s 不自动进入初始技能表" % skill_id)


func _shock_paralysis_exclusion(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var target := state.unit_by_uid(100)
	state.apply_paralysis(target)
	t.check(not state.apply_shock(target, 1), "麻痹期间不能施加感电")
	t.eq(target.shock_ticks, 0, "麻痹期间的感电施加失败")
	t.check(target.paralyzed_ticks > 0, "原麻痹状态保留")
	target.paralyzed_ticks = 0
	t.check(state.apply_shock(target, 1), "麻痹消除后可以施加感电")
	t.eq(target.shock_ticks, 1, "首次感电为一层")
	t.check(state.apply_shock(target, 1), "已有感电可以继续叠层")
	t.check(target.paralyzed_ticks > 0 and target.shock_ticks == 0, "第二层感电转为麻痹并清空感电")
	var immune := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var immune_target := immune.unit_by_uid(100)
	immune_target.battle_buffs["status_immune"] = true
	t.check(not immune.apply_shock(immune_target, 1), "净化免疫感电")


func _magnet_pull(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(5, 3)],
		["rock_wild1", Vector2i(2, 1)],
	])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	caster.skills.append("magnet_pull")
	t.check(SkillResolver.magnet_pull_target(state, caster).uid == 101, "磁吸在多个射线目标中选择最近敌人")
	var result := state.cast_skill(caster, "magnet_pull", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "磁吸成功施放")
	t.eq(state.unit_by_uid(101).cell, Vector2i(2, 2), "无带电状态时向施法者拉近一格")
	t.eq(state.unit_by_uid(100).cell, Vector2i(5, 3), "较远敌人不被移动")
	var boosted := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(6, 3)]])
	var boosted_caster := boosted.unit_by_uid(1)
	var boosted_target := boosted.unit_by_uid(100)
	boosted_caster.cell = Vector2i(2, 3)
	boosted_caster.skills.append("magnet_pull")
	boosted.apply_shock(boosted_target, 1)
	boosted.cast_skill(boosted_caster, "magnet_pull", {"type": "cell", "cell": boosted_caster.cell})
	t.eq(boosted_target.cell, Vector2i(4, 3), "感电目标额外拉近一格")
	var blocked_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.OBSTACLE]])
	var blocked := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(6, 3)]], blocked_terrain)
	var blocked_caster := blocked.unit_by_uid(1)
	blocked_caster.cell = Vector2i(2, 3)
	t.check(SkillResolver.magnet_pull_target(blocked, blocked_caster) == null, "障碍阻挡磁吸射线")
	var upgraded := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(7, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.cell = Vector2i(1, 3)
	t.check(SkillResolver.magnet_pull_target(upgraded, upgraded_caster) == null, "磁吸基础射程外没有目标")
	upgraded_caster.upgrades["magnet_pull_reach"] = 1
	t.check(SkillResolver.magnet_pull_target(upgraded, upgraded_caster).uid == 100, "强化后磁吸射程扩大到六格")


func _glare(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(2, 2)],
		["rock_wild1", Vector2i(4, 4)],
		["rock_wild1", Vector2i(6, 6)],
		["rock_wild1", Vector2i(2, 4)],
	])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills.append("glare")
	var near := state.unit_by_uid(100)
	var shocked_near := state.unit_by_uid(101)
	var far := state.unit_by_uid(102)
	var paralyzed_near := state.unit_by_uid(103)
	state.apply_shock(shocked_near, 1)
	state.apply_paralysis(paralyzed_near)
	var result := state.cast_skill(caster, "glare", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "眩光成功施放")
	t.eq((result.get("area_cells", []) as Array).size(), 9, "眩光覆盖自身周围九格")
	t.eq(near.shock_ticks, 1, "范围内普通敌人获得一层感电")
	t.check(shocked_near.paralyzed_ticks > 0 and shocked_near.shock_ticks == 0, "已有感电的敌人被眩光转为麻痹")
	t.eq(far.shock_ticks + far.paralyzed_ticks, 0, "三乘三范围外敌人不受影响")
	t.check(paralyzed_near.paralyzed_ticks > 0 and paralyzed_near.shock_ticks == 0, "麻痹中的敌人不会获得感电")
	var upgraded := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(5, 5)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.cell = Vector2i(3, 3)
	upgraded_caster.upgrades["glare_radius"] = 1
	t.eq(SkillResolver.glare_area(upgraded_caster).size(), 25, "眩光强化后覆盖五乘五")
	upgraded_caster.skills.append("glare")
	upgraded.cast_skill(upgraded_caster, "glare", {"type": "cell", "cell": upgraded_caster.cell})
	t.eq(upgraded.unit_by_uid(100).shock_ticks, 1, "强化眩光可命中原三乘三范围外敌人")


func _electromagnetic_laser(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 3)]], terrain)
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("electromagnetic_laser")
	var base_entries := SkillResolver.targets(state, caster, "electromagnetic_laser")
	t.check(not base_entries.any(func(entry): return int(entry.get("unit", -1)) == target.uid), "障碍后的普通目标不可被电磁镭射选中")
	state.apply_shock(target, 1)
	var piercing_entries := SkillResolver.targets(state, caster, "electromagnetic_laser")
	t.check(piercing_entries.any(func(entry): return int(entry.get("unit", -1)) == target.uid), "感电目标可被越障选中")
	var target_hp := target.hp
	var obstacle_hp := int(state.obstacle_durability.get(Vector2i(2, 3), 0))
	var result := state.cast_skill(caster, "electromagnetic_laser", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "电磁镭射成功施放")
	t.eq(target.hp, target_hp - Elements.direct_damage(12, "electric", target.element), "电磁镭射造成十二点基础直伤")
	t.eq(int(state.obstacle_durability.get(Vector2i(2, 3), -1)), obstacle_hp, "镭射穿障不额外损伤障碍")
	var blocked_by_unit := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(4, 3)],
	])
	var unit_blocker := blocked_by_unit.unit_by_uid(1)
	unit_blocker.cell = Vector2i(1, 3)
	blocked_by_unit.apply_shock(blocked_by_unit.unit_by_uid(101), 1)
	t.check(not SkillResolver.targets(blocked_by_unit, unit_blocker, "electromagnetic_laser").any(func(entry): return int(entry.get("unit", -1)) == 101), "带电目标仍不能穿过中间单位")
	var upgraded := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_target := upgraded.unit_by_uid(100)
	upgraded_caster.cell = Vector2i(1, 3)
	upgraded_caster.skills.append("electromagnetic_laser")
	upgraded_caster.upgrades["electromagnetic_laser_damage"] = 5
	var upgraded_hp := upgraded_target.hp
	upgraded.cast_skill(upgraded_caster, "electromagnetic_laser", {"type": "unit", "unit": upgraded_target.uid, "cell": upgraded_target.cell})
	t.eq(upgraded_target.hp, upgraded_hp - Elements.direct_damage(17, "electric", upgraded_target.element), "电磁镭射强化后造成十七点基础直伤")


func _electric_resonance(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter", "rock_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(3, 3)
	ally.cell = Vector2i(2, 3)
	enemy.cell = Vector2i(4, 3)
	ally.shock_ticks = 2
	enemy.paralyzed_ticks = 2
	caster.skills.append("electric_resonance")
	caster.skills.append("electric_arc")
	var result := state.cast_skill(caster, "electric_resonance", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "电共鸣成功施放")
	t.eq(caster.electric_resonance_bonus, 8, "一层感电与一层麻痹共蓄积八点伤害")
	t.eq(ally.shock_ticks, 1, "友军感电被消耗一层")
	t.eq(enemy.paralyzed_ticks, 1, "敌人麻痹被消耗一层")
	t.eq(BattleSnapshot.load_state(BattleSnapshot.save_state(state)).unit_by_uid(1).electric_resonance_bonus, 8, "电共鸣蓄伤随战场存档保存")
	caster.skill_used = false
	caster.moved = false
	var enemy_hp := enemy.hp
	state.cast_skill(caster, "electric_arc", {"type": "cell", "cell": enemy.cell})
	t.eq(enemy.hp, enemy_hp - Elements.direct_damage(18, "electric", enemy.element), "电共鸣为下一次技能增加八点伤害")
	t.eq(caster.electric_resonance_bonus, 0, "实际伤害命中后消耗电共鸣蓄伤")
	var upgraded := TestScenario.make_state(["electric_starter", "rock_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.cell = Vector2i(3, 3)
	upgraded.unit_by_uid(2).cell = Vector2i(2, 3)
	upgraded.unit_by_uid(2).shock_ticks = 1
	upgraded_caster.upgrades["electric_resonance_power"] = 2
	upgraded_caster.skills.append("electric_resonance")
	upgraded.cast_skill(upgraded_caster, "electric_resonance", {"type": "cell", "cell": upgraded_caster.cell})
	t.eq(upgraded_caster.electric_resonance_bonus, 5, "强化后每层感电蓄积五点伤害")


func _electric_spark(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(5, 3), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(2, 3)],
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(4, 3)],
		["rock_wild1", Vector2i(6, 3)],
	], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("electric_spark")
	var shocked := state.unit_by_uid(100)
	var normal := state.unit_by_uid(101)
	var paralyzed := state.unit_by_uid(102)
	var blocked := state.unit_by_uid(103)
	state.apply_shock(shocked, 1)
	state.apply_paralysis(paralyzed)
	var hp_before := [shocked.hp, normal.hp, paralyzed.hp, blocked.hp]
	var spark_damage := Elements.direct_damage(8, "electric", normal.element)
	var result := state.cast_skill(caster, "electric_spark", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)})
	t.check(bool(result.get("ok", false)), "电极火花成功施放")
	t.eq(shocked.hp, int(hp_before[0]) - spark_damage, "电极火花命中一格内带电敌人")
	t.eq(normal.hp, int(hp_before[1]) - spark_damage, "电极火花继续命中第二格普通敌人")
	t.eq(paralyzed.hp, int(hp_before[2]) - spark_damage, "电极火花继续命中第三格麻痹敌人")
	t.eq(blocked.hp, int(hp_before[3]), "障碍后敌人不受电极火花影响")
	t.check(shocked.burn_ticks > 0 and paralyzed.burn_ticks > 0, "带电目标被附加烧伤")
	t.eq(normal.burn_ticks, 0, "无感电麻痹的目标不附加烧伤")
	var upgraded := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_target := upgraded.unit_by_uid(100)
	upgraded_caster.cell = Vector2i(1, 3)
	upgraded_caster.skills.append("electric_spark")
	upgraded_caster.upgrades["electric_spark_damage"] = 5
	var upgraded_hp := upgraded_target.hp
	upgraded.cast_skill(upgraded_caster, "electric_spark", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)})
	t.eq(upgraded_target.hp, upgraded_hp - Elements.direct_damage(13, "electric", upgraded_target.element), "电极火花强化后造成十三点基础直伤")


func _ui_display(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(6401)
	var state := TestScenario.make_state(["electric_starter"], [
		["rock_wild1", Vector2i(4, 2)],
		["rock_wild1", Vector2i(5, 3)],
	])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills.append_array(["magnet_pull", "glare", "electromagnetic_laser", "electric_resonance", "electric_spark"])
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	screen.action_mode = "skills"
	t.check(screen._skill_tag("glare", caster).contains("3×3"), "技能栏显示眩光三乘三范围")
	t.check(screen._skill_tag("electric_resonance", caster).contains("感电 +3"), "技能栏显示电共鸣基础蓄伤")
	screen._on_skill_pressed("glare")
	t.eq(screen.board.area_cells.size(), 9, "眩光瞄准时高亮九格")
	screen._clear_aim()
	var magnet_entry := {"type": "cell", "cell": caster.cell}
	var magnet_preview := state.preview_skill(caster, "magnet_pull", magnet_entry)
	t.check(bool(magnet_preview.get("ok", false)) and magnet_preview.get("pull") != null, "磁吸预览包含拉拽结果")
	screen._preview_overlays(magnet_preview)
	t.check(not screen.board.arrows.is_empty(), "磁吸预览绘制拉拽箭头")
	app.queue_free()
