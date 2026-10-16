extends RefCounted


func run(t: TestContext) -> void:
	t.begin("五招学习、持续效果与海啸")
	_learning(t)
	_parasite(t)
	_fire_amplify(t)
	_terrain_travel(t)
	_tsunami(t)
	t.finish()


func _learning(t: TestContext) -> void:
	var expectations := {
		"fire": ["fire_amplify"],
		"water": ["surf", "tsunami"],
		"grass": ["leech_seed"],
		"ice": ["ice_glide"],
	}
	for element in expectations:
		var choices := SkillDB.learnable_ids_for(element)
		for skill_id in expectations[element]:
			t.check(choices.has(skill_id), "%s 可在升级时学习 %s" % [element, skill_id])
	var starter := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [["ice_wild1", Vector2i(6, 6)]])
	t.check(not starter.unit_by_uid(1).skills.has("fire_amplify"), "新技能不会默认加入火系初始技能栏")
	t.check(not starter.unit_by_uid(2).skills.has("surf"), "新技能不会默认加入水系初始技能栏")
	t.check(not starter.unit_by_uid(3).skills.has("leech_seed"), "新技能不会默认加入草系初始技能栏")
	var run_state := RunState.new_run(2501, [{"id": 1, "species_id": "grass_starter", "affinity": 0}])
	var record := run_state.record_by_uid(1)
	MonsterProgression.award_xp(record, 4)
	t.check(run_state.available_new_skills(1).has("leech_seed"), "Lv2 成长列表含寄生种子")
	t.check(run_state.learn_monster_skill(1, 2, "leech_seed"), "Lv2 可真正学习寄生种子")
	t.check((run_state.record_by_uid(1).get("known_skills", []) as Array).has("leech_seed"), "已学技能写入本局怪物记录")


func _parasite(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 2)
	caster.hp = caster.max_hp - 2
	caster.skills.append("leech_seed")
	var result := state.cast_skill(caster, "leech_seed", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "相邻敌人可寄生")
	t.eq(target.parasite_source_uid, caster.uid, "寄生记录来源")
	var old_hp := target.hp
	state.settle_round()
	t.eq(target.hp, old_hp - 1, "整轮结算寄生扣一血")
	t.eq(caster.hp, caster.max_hp - 1, "仍存活的施法者回复一血")
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
	t.eq(caster.fire_amp_stacks, 2, "只吸收曼哈顿两格内的两处火焰")
	t.check(state.burning_cells.has(Vector2i(5, 2)), "范围外火焰保持燃烧")
	t.check(not state.burning_cells.has(Vector2i(2, 3)), "被吸收的火焰立即熄灭")
	caster.skill_used = false
	SkillResolver.apply(state, caster, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 2)}, false)
	t.eq(target.hp, target.max_hp - 3, "下次技能直伤附加全部两点增幅")
	t.eq(caster.fire_amp_stacks, 0, "实际造成直伤后消耗增幅")
	var no_hit := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var fire := no_hit.unit_by_uid(1)
	fire.cell = Vector2i(2, 2)
	fire.fire_amp_stacks = 3
	SkillResolver.apply(no_hit, fire, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 2)}, false)
	t.eq(fire.fire_amp_stacks, 3, "未造成直伤的技能不消耗增幅")


func _terrain_travel(t: TestContext) -> void:
	var ice_cells := [[Vector2i(2, 2), TerrainDB.ICE], [Vector2i(3, 2), TerrainDB.ICE],
		[Vector2i(4, 2), TerrainDB.ICE], [Vector2i(5, 2), TerrainDB.ICE], [Vector2i(6, 2), TerrainDB.ICE]]
	var ice_state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), ice_cells))
	var skater := ice_state.unit_by_uid(1)
	skater.cell = Vector2i(2, 2)
	skater.skills.append("ice_glide")
	t.check(bool(ice_state.cast_skill(skater, "ice_glide", {"type": "cell", "cell": skater.cell}).get("ok", false)), "溜冰施放成功")
	t.check(not skater.can_move_now(), "施放当阶段不能立刻移动")
	ice_state.start_round()
	t.check(ice_state.move_options(skater).has(Vector2i(6, 2)), "下一本方阶段可越过基础移动范围滑到连通冰面")
	t.check(ice_state.move_unit(skater, Vector2i(6, 2)), "长距离冰面移动实际成功")
	ice_state.start_round()
	t.check(ice_state.move_options(skater).has(Vector2i(2, 2)), "第二本方阶段仍可长距离溜冰")
	ice_state.start_round()
	t.check(not ice_state.move_options(skater).has(Vector2i(2, 2)), "第三阶段冰面无限距离能力到期")
	var water_cells := [[Vector2i(2, 2), TerrainDB.WATER], [Vector2i(3, 2), TerrainDB.DEEP],
		[Vector2i(4, 2), TerrainDB.WATER], [Vector2i(5, 2), TerrainDB.WATER], [Vector2i(6, 2), TerrainDB.WATER]]
	var water_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), water_cells))
	var surfer := water_state.unit_by_uid(1)
	surfer.cell = Vector2i(2, 2)
	surfer.skills.append("surf")
	water_state.cast_skill(surfer, "surf", {"type": "cell", "cell": surfer.cell})
	water_state.start_round()
	t.check(water_state.move_options(surfer).has(Vector2i(6, 2)), "冲浪连通浅水与深水")
	water_state.unit_by_uid(100).cell = Vector2i(4, 2)
	t.check(not water_state.move_options(surfer).has(Vector2i(6, 2)), "冲浪不能穿过单位占据的水格")


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
	t.eq((state.pending_casts[0]["cells"] as Array).size(), 20, "完整宽五长四区域全部标记")
	t.eq(wet_enemy.hp, wet_enemy.max_hp, "宣告时不造成提前伤害")
	state.start_round()
	t.eq(wet_enemy.hp, wet_enemy.max_hp - 4, "结算时水格中的敌人受四点直伤")
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
