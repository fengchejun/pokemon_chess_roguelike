extends RefCounted


func run(t: TestContext) -> void:
	t.begin("五招学习、持续效果与海啸")
	_learning(t)
	_parasite(t)
	_fire_amplify(t)
	_terrain_travel(t)
	_tsunami(t)
	_range_changes(t)
	_multi_gust(t)
	t.finish()


func _learning(t: TestContext) -> void:
	var expectations := {
		"fire": ["fire_amplify"],
		"grass": ["leech_seed"],
		"water": ["surf", "tsunami", "ice_glide"],
		"electric": ["tailwind", "double_cast"],
	}
	for element in expectations:
		var choices := SkillDB.learnable_ids_for(element)
		for skill_id in expectations[element]:
			t.check(choices.has(skill_id), "%s 可在升级时学习 %s" % [element, skill_id])
	for element in Elements.LIST:
		for skill_id in SkillDB.learnable_ids_for(element):
			t.check(RunState.upgrade_id_for_skill(String(skill_id)) != "", "%s 学会后有专属强化" % skill_id)
	var starter := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [["ice_wild1", Vector2i(6, 6)]])
	t.check(not starter.unit_by_uid(1).skills.has("fire_amplify"), "新技能不会默认加入火系初始技能栏")
	t.check(not starter.unit_by_uid(2).skills.has("surf"), "新技能不会默认加入水系初始技能栏")
	t.check(not starter.unit_by_uid(3).skills.has("leech_seed"), "新技能不会默认加入草系初始技能栏")
	var run_state := RunState.new_run(2501, [{"id": 1, "species_id": "grass_starter", "affinity": 0}])
	var record := run_state.record_by_uid(1)
	MonsterProgression.award_xp(record, 4)
	t.check(run_state.available_new_skills(1).has("leech_seed"), "Lv2 成长列表含寄生种子")
	var candidates := run_state.monster_level_choices(1, 2)
	t.eq(candidates.size(), 3, "Lv2 从三招候选中选择一招")
	var chosen := String(candidates[0])
	t.check(run_state.learn_monster_skill(1, 2, chosen), "Lv2 可真正学习候选技能")
	t.check((run_state.record_by_uid(1).get("known_skills", []) as Array).has(chosen), "已学技能写入本局怪物记录")


func _parasite(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	caster.hp = caster.max_hp - 20
	caster.skills.append("leech_seed")
	var result := state.cast_skill(caster, "leech_seed", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "相邻敌人可寄生")
	t.eq(target.parasite_source_uid, caster.uid, "寄生记录来源")
	var old_hp := target.hp
	state.settle_round()
	t.eq(target.hp, old_hp - Balance.PARASITE_DAMAGE, "整轮结算寄生扣除配置的生命")
	t.eq(caster.hp, caster.max_hp - 20 + Balance.PARASITE_HEAL, "仍存活的施法者回复生命")
	state.damage_unit(caster, target, 1, {"element": "grass", "cause": "其他技能"})
	t.eq(target.parasite_source_uid, -1, "受到其他实际伤害后寄生解除")
	old_hp = target.hp
	state.settle_round()
	t.eq(target.hp, old_hp, "解除后不再寄生扣血")
	var guarded := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 2)]])
	guarded.unit_by_uid(1).cell = Vector2i(2, 2)
	guarded.unit_by_uid(1).skills.append("leech_seed")
	guarded.cast_skill(guarded.unit_by_uid(1), "leech_seed", {"type": "unit", "unit": 100, "cell": Vector2i(3, 2)})
	guarded.unit_by_uid(100).battle_buffs["direct_guard"] = true
	guarded.damage_unit(guarded.unit_by_uid(1), guarded.unit_by_uid(100), 1, {"element": "grass", "cause": "被抵消的直伤"})
	t.eq(guarded.unit_by_uid(100).parasite_source_uid, 1, "未造成实际伤害不会解除寄生")
	var deeper := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var deep_caster := deeper.unit_by_uid(1)
	deep_caster.cell = Vector2i(2, 2)
	deep_caster.hp -= 10
	deep_caster.skills.append("leech_seed")
	deep_caster.upgrades["leech_seed_tick_bonus"] = 2
	var deep_target := deeper.unit_by_uid(100)
	deeper.cast_skill(deep_caster, "leech_seed", {"type": "unit", "unit": deep_target.uid, "cell": deep_target.cell})
	var deep_hp := deep_target.hp
	var caster_hp := deep_caster.hp
	deeper.settle_round()
	t.eq(deep_hp - deep_target.hp, 6, "强化寄生每轮伤害为六点")
	t.eq(deep_caster.hp - caster_hp, 6, "强化寄生同时提高回复上限")


func _fire_amplify(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	caster.skills.append("fire_amplify")
	state.set_terrain(Vector2i(2, 3), TerrainDB.GRASS)
	state.set_terrain(Vector2i(3, 2), TerrainDB.GRASS)
	state.set_terrain(Vector2i(5, 2), TerrainDB.GRASS)
	state.ignite(Vector2i(2, 3))
	state.ignite(Vector2i(3, 2))
	state.ignite(Vector2i(5, 2))
	var result := state.cast_skill(caster, "fire_amplify", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "火焰增幅可施放")
	t.eq(caster.fire_amp_stacks, Balance.SKILL_DAMAGE_UPGRADE * 2, "只吸收曼哈顿两格内的两处火焰")
	t.check(state.burning_cells.has(Vector2i(5, 2)), "范围外火焰保持燃烧")
	t.check(not state.burning_cells.has(Vector2i(2, 3)), "被吸收的火焰立即熄灭")
	caster.skill_used = false
	SkillResolver.apply(state, caster, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 2)}, false)
	t.eq(target.hp, target.max_hp - SkillDB.damage_of("flame_jet") - Balance.SKILL_DAMAGE_UPGRADE * 2, "下次技能直伤附加全部增幅")
	t.eq(caster.fire_amp_stacks, 0, "实际造成直伤后消耗增幅")
	var no_hit := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var fire := no_hit.unit_by_uid(1)
	fire.cell = Vector2i(2, 2)
	fire.fire_amp_stacks = 3
	SkillResolver.apply(no_hit, fire, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 2)}, false)
	t.eq(fire.fire_amp_stacks, 3, "未造成直伤的技能不消耗增幅")
	var stronger := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var strong_caster := stronger.unit_by_uid(1)
	strong_caster.cell = Vector2i(2, 2)
	strong_caster.skills.append("fire_amplify")
	strong_caster.upgrades["fire_amplify_power"] = 8
	stronger.set_terrain(Vector2i(2, 3), TerrainDB.GRASS)
	stronger.ignite(Vector2i(2, 3))
	stronger.cast_skill(strong_caster, "fire_amplify", {"type": "cell", "cell": strong_caster.cell})
	t.eq(strong_caster.fire_amp_stacks, 8, "强化火焰增幅每格蓄积八点")


func _terrain_travel(t: TestContext) -> void:
	var ice_cells := [[Vector2i(2, 2), TerrainDB.ICE], [Vector2i(3, 2), TerrainDB.ICE],
		[Vector2i(4, 2), TerrainDB.ICE], [Vector2i(5, 2), TerrainDB.ICE], [Vector2i(6, 2), TerrainDB.ICE]]
	var ice_state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), ice_cells))
	var skater := ice_state.unit_by_uid(1)
	skater.cell = Vector2i(2, 2)
	skater.skills.append("ice_glide")
	skater.upgrades["ice_glide_duration"] = 1
	t.check(bool(ice_state.cast_skill(skater, "ice_glide", {"type": "cell", "cell": skater.cell}).get("ok", false)), "溜冰施放成功")
	t.eq(skater.ice_glide_until_round, ice_state.round + 3, "强化溜冰延长一个回合")
	t.check(skater.can_move_now(), "溜冰施放当阶段保留未用的移动机会")
	ice_state.unit_by_uid(100).cell = Vector2i(4, 2)
	t.check(ice_state.move_options(skater).has(Vector2i(6, 2)), "溜冰可穿过敌方占据的冰面")
	t.check(not ice_state.move_options(skater).has(Vector2i(4, 2)), "溜冰终点不可被敌人占据")
	t.check(ice_state.move_options(skater).has(Vector2i(6, 2)), "施放当阶段即可越过基础移动范围")
	t.check(ice_state.move_unit(skater, Vector2i(6, 2)), "当阶段长距离冰面移动实际成功")
	t.check(not skater.moved, "溜冰沿冰面移动不消耗普通移动机会")
	t.check(ice_state.move_unit(skater, Vector2i(2, 2)), "溜冰同阶段可再次沿冰面移动")
	t.check(ice_state.move_unit(skater, Vector2i(6, 2)), "溜冰同阶段可多次免费移动")
	ice_state.start_round()
	t.check(ice_state.move_options(skater).has(Vector2i(2, 2)), "第二回合仍可长距离溜冰")
	ice_state.start_round()
	t.check(ice_state.move_options(skater).has(Vector2i(2, 2)), "第三回合仍可长距离溜冰")
	ice_state.start_round()
	t.check(ice_state.move_options(skater).has(Vector2i(2, 2)), "强化后第四回合仍可免费溜冰")
	ice_state.start_round()
	t.check(not ice_state.move_options(skater).has(Vector2i(2, 2)), "强化后第五回合冰面免费移动到期")
	var water_cells := [[Vector2i(2, 2), TerrainDB.WATER], [Vector2i(3, 2), TerrainDB.DEEP],
		[Vector2i(4, 2), TerrainDB.WATER], [Vector2i(5, 2), TerrainDB.WATER], [Vector2i(6, 2), TerrainDB.WATER]]
	var water_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), water_cells))
	var surfer := water_state.unit_by_uid(1)
	surfer.cell = Vector2i(2, 2)
	surfer.skills.append("surf")
	surfer.upgrades["surf_duration"] = 1
	water_state.cast_skill(surfer, "surf", {"type": "cell", "cell": surfer.cell})
	t.eq(surfer.surf_until_round, water_state.round + 3, "强化冲浪延长一个回合")
	t.check(water_state.move_options(surfer).has(Vector2i(6, 2)), "冲浪当阶段连通浅水与深水")
	water_state.unit_by_uid(100).cell = Vector2i(4, 2)
	t.check(water_state.move_options(surfer).has(Vector2i(6, 2)), "冲浪可越过敌方占据的水格")
	t.check(not water_state.move_options(surfer).has(Vector2i(4, 2)), "冲浪终点不可被敌人占据")
	t.check(water_state.move_unit(surfer, Vector2i(6, 2)), "越过敌方单位的冲浪路线可实际执行")
	t.check(not surfer.moved, "冲浪沿水域移动不消耗普通移动机会")
	t.check(water_state.move_options(surfer).has(Vector2i(6, 3)), "免费冲浪后仍可向陆地普通移动")
	t.check(water_state.move_unit(surfer, Vector2i(6, 3)) and surfer.moved, "离开水域消耗普通移动机会")
	var spent_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), water_cells))
	var spent_surfer := spent_state.unit_by_uid(1)
	spent_surfer.cell = Vector2i(1, 2)
	spent_surfer.skills.append("surf")
	t.check(spent_state.move_unit(spent_surfer, Vector2i(2, 2)) and spent_surfer.moved, "先用普通移动进入水域")
	t.check(bool(spent_state.cast_skill(spent_surfer, "surf", {"type": "cell", "cell": spent_surfer.cell}).get("ok", false)), "已经移动后仍可施放冲浪")
	t.check(spent_state.move_options(spent_surfer).has(Vector2i(6, 2)), "已移动后施放冲浪仍可当回合免费移动")
	t.check(spent_state.move_unit(spent_surfer, Vector2i(6, 2)), "已用普通移动后可实际冲浪")
	t.check(spent_surfer.moved, "免费冲浪不返还已用的普通移动机会")
	t.check(spent_state.undo_last_move() and spent_surfer.moved, "撤回免费冲浪不会返还之前已用的普通移动机会")
	t.check(spent_state.move_unit(spent_surfer, Vector2i(6, 2)), "撤回后仍可继续免费冲浪")
	t.check(not spent_state.move_options(spent_surfer).has(Vector2i(6, 3)), "普通移动已用时不可借冲浪再走上陆地")


func _tsunami(t: TestContext) -> void:
	var water_cells := [[Vector2i(3, 2), TerrainDB.WATER], [Vector2i(3, 3), TerrainDB.WATER], [Vector2i(4, 3), TerrainDB.WATER]]
	var state := TestScenario.make_state(["water_starter", "rock_starter"], [["rock_wild1", Vector2i(3, 2)], ["fire_wild1", Vector2i(5, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), water_cells))
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("tsunami")
	var ally := state.unit_by_uid(2)
	ally.cell = Vector2i(3, 3)
	var wet_enemy := state.unit_by_uid(100)
	var dry_enemy := state.unit_by_uid(101)
	var result := state.cast_skill(caster, "tsunami", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(2, 3)})
	t.check(bool(result.get("ok", false)), "海啸可锁定前方方向")
	t.eq(state.pending_casts.size(), 1, "海啸进入跨回合吟唱")
	t.eq((state.pending_casts[0]["cells"] as Array).size(), 25, "完整宽五长五区域全部标记")
	t.eq(wet_enemy.hp, wet_enemy.max_hp, "宣告时不造成提前伤害")
	state.start_round()
	t.eq(wet_enemy.hp, wet_enemy.max_hp - SkillDB.damage_of("tsunami"), "结算时水格中的敌人受到海啸直伤")
	t.eq(dry_enemy.hp, dry_enemy.max_hp, "结算时陆地上的敌人无伤")
	t.eq(ally.hp, ally.max_hp, "己方单位不受海啸伤害")
	t.check(caster.moved and caster.skill_used, "海啸落下阶段施法者不能行动")
	var edge := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var edge_caster := edge.unit_by_uid(1)
	edge_caster.cell = Vector2i(7, 3)
	edge_caster.skills.append("tsunami")
	var empty_direction := {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(8, 3)}
	t.check(not edge.skill_targets(edge_caster, "tsunami").has(empty_direction), "棋盘边缘不能向完全越界的方向空放海啸")
	t.check(not bool(edge.cast_skill(edge_caster, "tsunami", empty_direction).get("ok", false)), "无效方向不消耗施法机会")
	t.check(not edge_caster.skill_used, "空方向不会开启吟唱")
	var moved := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(3, 2)]], TestScenario.with_cells(TestScenario.plain_terrain(), water_cells))
	var water := moved.unit_by_uid(1)
	water.cell = Vector2i(1, 3)
	water.skills.append("tsunami")
	moved.cast_skill(water, "tsunami", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(2, 3)})
	moved.unit_by_uid(100).cell = Vector2i(6, 2)
	moved.start_round()
	t.eq(moved.unit_by_uid(100).hp, moved.unit_by_uid(100).max_hp, "目标离开固定区域后可躲开")
	var enemy_state := TestScenario.make_state(["water_starter"], [["water_wild1", Vector2i(6, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.WATER]]))
	enemy_state.unit_by_uid(1).cell = Vector2i(4, 3)
	var enemy_caster := enemy_state.unit_by_uid(100)
	enemy_caster.skills = ["tsunami"]
	enemy_caster.moved = true
	var actions := EnemyAI.plan(enemy_state)
	t.check(not actions.is_empty() and String(actions[0].get("skill", {}).get("id", "")) == "tsunami", "敌人持有海啸时能选择有水域目标的吟唱")
	enemy_state.round = Balance.MAX_ROUNDS
	actions = EnemyAI.plan(enemy_state)
	t.check(actions.is_empty() or String(actions[0].get("skill", {}).get("id", "")) != "tsunami", "末轮敌人不会开始来不及落下的海啸")


func _range_changes(t: TestContext) -> void:
	t.check(SkillDB.get_def("wind_gust").is_empty(), "推风定义已删除")
	var tailwind_state := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var tailwind_caster := tailwind_state.unit_by_uid(1)
	tailwind_caster.cell = Vector2i(1, 3)
	tailwind_caster.skills.append("tailwind")
	var ally := tailwind_state.unit_by_uid(2)
	ally.cell = Vector2i(3, 4)
	var tailwind_preview := tailwind_state.preview_skill(tailwind_caster, "tailwind", {"type": "cell", "cell": tailwind_caster.cell})
	t.eq(tailwind_preview.get("area_cells", []), SkillResolver.support_area(tailwind_caster.cell, 2, true), "顺风预览显示实际范围")
	SkillResolver.apply(tailwind_state, tailwind_caster, "tailwind", {"type": "cell", "cell": tailwind_caster.cell}, false)
	t.check(ally.haste_ticks > 0, "磁场两格内侧格也获得加速")


func _multi_gust(t: TestContext) -> void:
	var state := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(2, 3)]])
	t.check(state.skill_targets(state.unit_by_uid(1), "wind_gust").is_empty(), "推风不能进入目标或预览队列")
