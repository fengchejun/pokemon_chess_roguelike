extends RefCounted


func run(t: TestContext) -> void:
	t.begin("镜花水月：限次状态、水格跃迁与一次免伤")
	_definition(t)
	_activation_and_movement(t)
	_damage_bonus(t)
	_damage_immunity(t)
	_duration_and_limit(t)
	t.finish()


func _definition(t: TestContext) -> void:
	var def := SkillDB.get_def("mirror_water_moon")
	t.eq(String(def.get("name", "")), "镜花水月", "技能名称")
	t.eq(int(def.get("battle_limit", 0)), 1, "镜花水月每场限用一次")
	t.check(SkillDB.learnable_ids_for("water").has("mirror_water_moon"), "镜花水月进入水系学习池")
	t.check(SpeciesDB.skills_of("water_starter").has("mirror_water_moon"), "镜花水月进入杰尼龟基础技能池")
	var opening_run := RunState.new_run(5601, [{
		"id": 1,
		"species_id": "water_starter",
		"affinity": 0,
		"starting_skill_id": "mirror_water_moon",
	}])
	var opening_record := opening_run.record_by_uid(1)
	t.eq(opening_record.get("known_skills", []), ["mirror_water_moon"], "开局可选择镜花水月作为起始技能")
	t.eq(opening_record.get("equipped_skills", []), ["mirror_water_moon"], "开局选择后立即装备镜花水月")
	t.eq(RunState.upgrade_id_for_skill("mirror_water_moon"), "mirror_water_moon_duration", "镜花水月拥有专属强化")


func _activation_and_movement(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 2), TerrainDB.WATER],
		[Vector2i(4, 2), TerrainDB.WATER],
		[Vector2i(6, 2), TerrainDB.DEEP],
	])
	var state := TestScenario.make_state(["water_starter"], [
		["fire_wild1", Vector2i(4, 2)],
		["water_wild1", Vector2i(5, 6)],
	], terrain)
	var caster := state.unit_by_uid(1)
	caster.skills.append("mirror_water_moon")
	var fire_enemy := state.unit_by_uid(100)
	var water_enemy := state.unit_by_uid(101)
	var result := state.cast_skill(caster, "mirror_water_moon", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "镜花水月可对自身施放")
	t.eq(caster.mirror_until_round, state.round + Balance.MIRROR_WATER_MOON_ROUNDS - 1, "状态持续三个完整回合")
	t.check(not caster.moved, "施放时保留本回合普通移动机会")
	t.eq(fire_enemy.slow_ticks, 1, "非水系敌人获得一回合浸湿")
	t.eq(water_enemy.slow_ticks, 0, "水系敌人沿用浸湿免疫")
	t.check((result.get("area_cells", []) as Array).has(fire_enemy.cell), "施放反馈标记全场敌人")
	t.eq(state.clone().unit_by_uid(1).mirror_until_round, caster.mirror_until_round, "战场克隆保留状态截止回合")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.unit_by_uid(1).mirror_until_round, caster.mirror_until_round, "战斗存档保留状态截止回合")
	var options := state.move_options(caster)
	t.check(options.has(Vector2i(2, 2)), "可从陆地跃迁至浅水")
	t.check(options.has(Vector2i(6, 2)), "可跃迁至不连通的深水")
	t.check(not options.has(fire_enemy.cell), "被单位占据的水格不能作为落点")
	t.eq(int(options[Vector2i(6, 2)].get("cost", -1)), 0, "镜花水月水格跃迁不消耗移动力")
	t.check(bool(options[Vector2i(6, 2)].get("mirror_travel", false)), "跃迁使用独立移动标记")
	t.check(state.move_unit(caster, Vector2i(2, 2)), "实际跃迁至浅水")
	t.check(not caster.moved, "浅水跃迁不消耗普通移动机会")
	t.check(state.move_unit(caster, Vector2i(6, 2)), "同一阶段可再次跃迁至离散深水")
	t.check(not caster.moved, "连续跃迁仍不消耗普通移动机会")
	state.settle_round()
	t.eq(fire_enemy.slow_ticks, 0, "浸湿只覆盖敌方下一次行动")


func _damage_bonus(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("mirror_water_moon")
	state.cast_skill(caster, "mirror_water_moon", {"type": "cell", "cell": caster.cell})
	var water_result := SkillResolver.apply(state, caster, "water_flow", {"type": "cell", "cell": target.cell}, false)
	var boosted := SkillDB.damage_of("water_flow") + Balance.MIRROR_WATER_DAMAGE_BONUS
	t.eq(int(water_result["hits"][0]["damage"]), Elements.direct_damage(boosted, "water", target.element), "状态期间水系技能基础直伤加五")
	target.cell = Vector2i(3, 3)
	var ice_result := SkillResolver.apply(state, caster, "ice_shard", {"type": "unit", "unit": target.uid, "cell": target.cell}, false)
	var boosted_ice := SkillDB.damage_of("ice_shard") + Balance.MIRROR_WATER_DAMAGE_BONUS
	t.eq(int(ice_result["hits"][0]["damage"]), Elements.direct_damage(boosted_ice, "water", target.element), "冰系招式按水系技能获得同一加成")
	caster.mirror_until_round = 0
	target.hp = target.max_hp
	var normal_result := SkillResolver.apply(state, caster, "water_flow", {"type": "cell", "cell": target.cell}, false)
	t.eq(int(normal_result["hits"][0]["damage"]), Elements.direct_damage(SkillDB.damage_of("water_flow"), "water", target.element), "状态结束后恢复基础水伤")


func _damage_immunity(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	caster.skills.append("mirror_water_moon")
	state.cast_skill(caster, "mirror_water_moon", {"type": "cell", "cell": caster.cell})
	var hp_before := caster.hp
	var immune := state.damage_unit(enemy, caster, 12, {"skill_direct": true, "element": "electric", "cause": "测试直伤"})
	t.eq(int(immune.get("amount", -1)), 0, "首次实际伤害被完全免疫")
	t.check(bool(immune.get("mirror_immune", false)), "返回免伤标记")
	t.eq(caster.hp, hp_before, "免伤不扣除生命")
	t.eq(caster.mirror_until_round, 0, "免伤后状态提前结束")
	var following := state.damage_unit(enemy, caster, 12, {"skill_direct": true, "element": "electric", "cause": "后续直伤"})
	t.check(int(following.get("amount", 0)) > 0, "状态结束后后续伤害正常结算")
	t.check(caster.hp < hp_before, "后续伤害扣除生命")
	var guarded := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var guarded_caster := guarded.unit_by_uid(1)
	guarded_caster.skills.append("mirror_water_moon")
	guarded.cast_skill(guarded_caster, "mirror_water_moon", {"type": "cell", "cell": guarded_caster.cell})
	guarded_caster.battle_buffs["direct_guard"] = true
	var zero := guarded.damage_unit(guarded.unit_by_uid(100), guarded_caster, 1, {"skill_direct": true, "element": "electric", "cause": "被完全减伤"})
	t.eq(int(zero.get("amount", -1)), 0, "既有减伤可把伤害降为零")
	t.check(guarded_caster.mirror_until_round > 0, "没有实际伤害时不会消耗镜花水月")


func _duration_and_limit(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.skills.append("mirror_water_moon")
	var entry := {"type": "cell", "cell": caster.cell}
	t.check(bool(state.cast_skill(caster, "mirror_water_moon", entry).get("ok", false)), "首次发动成功")
	caster.skill_used = false
	caster.moved = false
	t.check(not bool(state.cast_skill(caster, "mirror_water_moon", entry).get("ok", false)), "同一场不能再次发动")
	t.eq(caster.mirror_until_round, state.round + 2, "重复施放失败不会刷新状态")
	state.start_round()
	t.check(caster.mirror_until_round > 0, "第二回合状态持续")
	state.start_round()
	t.check(caster.mirror_until_round > 0, "第三回合状态持续")
	state.start_round()
	t.eq(caster.mirror_until_round, 0, "第四回合开始时状态到期")
	var upgraded := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.skills.append("mirror_water_moon")
	upgraded_caster.upgrades["mirror_water_moon_duration"] = 1
	upgraded.cast_skill(upgraded_caster, "mirror_water_moon", {"type": "cell", "cell": upgraded_caster.cell})
	t.eq(upgraded_caster.mirror_until_round, upgraded.round + 3, "专属强化延长一回合")
