extends RefCounted


func run(t: TestContext) -> void:
	t.begin("合并后技能")
	for species_id in SpeciesDB.SPECIES:
		for skill_id in SpeciesDB.skills_of(String(species_id)):
			t.check(not SkillDB.get_def(String(skill_id)).is_empty(), "%s 的 %s 有技能定义" % [species_id, skill_id])
	_fire(t)
	_water(t)
	_electric(t)
	_grass_ice_wind(t)
	_matchup_damage(t)
	_ice_slide(t)
	t.finish()


func _fire(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE], [Vector2i(4, 2), TerrainDB.GRASS], [Vector2i(4, 4), TerrainDB.FRAGILE]])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	var entry := {"type": "cell", "cell": Vector2i(4, 3)}
	t.check(state.skill_targets(fire, "fire_burst").has(entry), "火球能跨越障碍选中中心")
	var preview := state.preview_skill(fire, "fire_burst", entry)
	t.check(bool(preview.get("ok", false)), "火球预览可用")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.FRAGILE, "预览不修改真实地形")
	var result := state.cast_skill(fire, "fire_burst", entry)
	t.check(bool(result.get("ok", false)) and state.pending_casts.size() == 1, "火球成功宣告并等待下一阶段")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.FRAGILE, "吟唱宣告不立即改变地面")
	state.round = 2
	state._resolve_due_channels("player")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.PIT, "火球击碎易碎地面")
	t.check(state.burning_cells.has(Vector2i(4, 2)), "火球点燃草丛")
	t.check(fire.can_use_in_battle("fire_burst"), "火球不再限制每场次数")
	var jet_state := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(2, 3)]])
	var jet_fire := jet_state.unit_by_uid(1)
	jet_fire.cell = Vector2i(0, 3)
	var jet := SkillResolver.apply(jet_state, jet_fire, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(1, 3)}, false)
	t.check(bool(jet.get("ok", false)), "喷射火焰按方向施放")
	t.check(jet_state.unit_by_uid(100).burn_ticks > 0, "喷射火焰附加灼烧")
	var close_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(1, 3)], ["water_wild1", Vector2i(3, 3)]])
	var close_fire := close_state.unit_by_uid(1)
	close_fire.cell = Vector2i(0, 3)
	var close_preview := close_state.preview_skill(close_fire, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(1, 3)})
	t.eq(close_preview["hits"][0]["damage"], 2, "近身喷射预览显示 2 点直伤")
	t.eq(close_state.unit_by_uid(100).hp, close_state.unit_by_uid(100).max_hp, "喷射预览不修改生命")
	SkillResolver.apply(close_state, close_fire, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(1, 3)}, false)
	t.eq(close_state.unit_by_uid(100).hp, close_state.unit_by_uid(100).max_hp - 2, "紧邻单位额外受到 1 点直伤")
	t.eq(close_state.unit_by_uid(101).hp, close_state.unit_by_uid(101).max_hp - 1, "三格处单位仍只受到 1 点直伤")


func _water(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var water := state.unit_by_uid(1)
	water.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, water, "water_flow", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.check(bool(result.get("ok", false)), "水流可施放")
	t.check(state.unit_by_uid(100).slow_ticks > 0, "水流命中单位施加浸湿")
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.PLAIN, "水流命中单位不造水")
	var rain := SkillResolver.apply(state, water, "rain_call", {"type": "cell", "cell": Vector2i(2, 4)}, false)
	t.check(bool(rain.get("ok", false)), "造雨术可施放")
	t.eq(state.terrain_at(Vector2i(3, 5)), TerrainDB.WATER, "造雨术覆盖九宫格角落")


func _electric(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	var target := state.unit_by_uid(100)
	var entry := {"type": "cell", "cell": caster.cell}
	var preview := state.preview_skill(caster, "lightning", entry)
	t.check(bool(preview.get("ok", false)), "打雷预览可用")
	t.eq(state.pending_casts.size(), 0, "预览不会开始真实吟唱")
	t.check(bool(state.cast_skill(caster, "lightning", entry).get("ok", false)), "打雷锁定当前所有敌方落点")
	t.eq(state.pending_casts[0]["cells"], [target.cell], "只有敌方所在格被锁定")
	t.eq(target.hp, target.max_hp, "闪电宣告后目标暂不受伤")
	state.round = 2
	state._resolve_due_channels("player")
	t.check(target.shock_ticks > 0, "闪电施加感电")
	t.eq(int(caster.battle_skill_uses.get("lightning", 0)), 0, "闪电不再消耗每场次数")
	t.check(caster.can_use_in_battle("lightning"), "下一回合仍可再次吟唱闪电")
	t.check(caster.can_use_in_battle("electric_arc"), "放电不受闪电次数限制")
	var second := CombatUnit.make("electric_starter", "player", 51)
	second.cell = Vector2i(1, 3)
	state.units.append(second)
	target.hp = 10
	var second_entry := {"type": "cell", "cell": second.cell}
	t.check(bool(SkillResolver.apply(state, second, "lightning", second_entry, false).get("ok", false)), "另一只电怪可同时吟唱")
	state.round = 3
	state._resolve_due_channels("player")
	t.check(target.paralyzed_ticks > 0, "不同单位再次感电仍触发麻痹")
	var fresh_battle := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)]])
	t.check(fresh_battle.unit_by_uid(1).can_use_in_battle("lightning"), "下一场战斗重新获得闪电次数")
	var water_state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.WATER], [Vector2i(3, 3), TerrainDB.WATER]]))
	var electric := water_state.unit_by_uid(1)
	electric.cell = Vector2i(1, 3)
	var arc_entry := {"type": "cell", "cell": Vector2i(2, 3)}
	t.check(water_state.skill_targets(electric, "electric_arc").has(arc_entry), "放电可以选相邻水格")
	var before_hp := water_state.unit_by_uid(100).hp
	SkillResolver.apply(water_state, electric, "electric_arc", arc_entry, false)
	t.check(water_state.unit_by_uid(100).hp < before_hp, "放电沿相连水格击中单位")


func _grass_ice_wind(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter", "ice_starter", "wind_starter"], [])
	var grass := state.unit_by_uid(1)
	grass.cell = Vector2i(2, 2)
	var dir_entry := {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 2)}
	t.check(bool(SkillResolver.apply(state, grass, "wild_vines", dir_entry, false).get("ok", false)), "疯狂藤蔓可施放")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.VINES, "藤蔓生成在前方")
	var ice := state.unit_by_uid(2)
	ice.cell = Vector2i(2, 5)
	var ice_entry := {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 5)}
	t.check(bool(SkillResolver.apply(state, ice, "frozen_ground", ice_entry, false).get("ok", false)), "冰封大地可施放")
	t.eq(state.terrain_at(Vector2i(4, 5)), TerrainDB.ICE, "冰封大地生成冰面")
	var wind := state.unit_by_uid(3)
	wind.cell = Vector2i(1, 2)
	t.eq(wind.move_points, 4, "风怪基础移动力为 4")
	t.check(bool(SkillResolver.apply(state, wind, "tailwind", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(2, 2)}, false).get("ok", false)), "风怪加速可施放")
	t.check(grass.haste_ticks > 0, "风怪给前方友军加速")
	grass.hp = grass.max_hp - 1
	t.check(bool(SkillResolver.apply(state, grass, "herbal_heal", {"type": "cell", "cell": grass.cell}, false).get("ok", false)), "药草治疗以自身为中心施放")
	t.eq(grass.hp, grass.max_hp, "药草治疗恢复友军")


func _ice_slide(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.ICE], [Vector2i(3, 3), TerrainDB.PIT]])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	t.check(state.move_unit(fire, Vector2i(2, 3)), "单位主动走上冰面")
	t.eq(fire.last_move_direction, Vector2i(1, 0), "记录最后位移方向")
	var slide := state.ice_slide_outcome(fire)
	t.eq(slide.get("to", Vector2i(-1, -1)), Vector2i(3, 3), "冰面箭头指向实际滑行落点")
	t.check(bool(slide.get("lethal", false)) and not bool(slide.get("blocked", true)), "致死落点在滑行前标为危险")
	state.settle_round()
	t.eq(fire.hp, 0, "冰面结算滑入深坑立即倒下")
	t.check(state.ice_slide_outcome(fire).is_empty(), "结算后清除滑行箭头")
	var blocked_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.ICE], [Vector2i(3, 3), TerrainDB.OBSTACLE]])
	var blocked_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], blocked_terrain)
	var blocked_unit := blocked_state.unit_by_uid(1)
	blocked_unit.cell = Vector2i(2, 3)
	blocked_unit.last_move_direction = Vector2i(1, 0)
	t.check(bool(blocked_state.ice_slide_outcome(blocked_unit).get("blocked", false)), "障碍前显示止步标记")
	blocked_state.settle_round()
	t.eq(blocked_unit.cell, Vector2i(2, 3), "标为受阻的滑行实际停在原地")
	blocked_unit.last_move_direction = Vector2i.ZERO
	t.check(blocked_state.ice_slide_outcome(blocked_unit).is_empty(), "本轮无位移时没有方向箭头")
	blocked_unit.last_move_direction = Vector2i(1, 0)
	blocked_unit.battle_buffs["flight"] = true
	t.check(blocked_state.ice_slide_outcome(blocked_unit).is_empty(), "飞行单位没有冰面滑行箭头")


func _matchup_damage(t: TestContext) -> void:
	var grass := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]])
	grass.unit_by_uid(1).cell = Vector2i(0, 3)
	var grass_entry := {"type": "cell", "cell": Vector2i(4, 3)}
	var grass_preview := grass.preview_skill(grass.unit_by_uid(1), "fire_burst", grass_entry)
	t.eq((grass_preview["hits"] as Array).size(), 0, "火球宣告预览不提前造成伤害")
	var grass_result := SkillResolver.resolve_channel(grass, grass.unit_by_uid(1), "fire_burst", [Vector2i(4, 3)])
	t.eq(int(grass_result["hits"][0]["damage"]), 4, "火球术命中草系为基础 4 伤")
	t.eq(int(grass_result["hits"][0]["modifier"]), 0, "火克草修正已停用")
	var fire := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(4, 3)]])
	fire.unit_by_uid(1).cell = Vector2i(0, 3)
	var fire_result := SkillResolver.resolve_channel(fire, fire.unit_by_uid(1), "fire_burst", [Vector2i(4, 3)])
	t.eq(int(fire_result["hits"][0]["damage"]), 4, "火球术打冰系只有基础伤害")
	t.eq(int(fire_result["hits"][0]["modifier"]), 0, "火球命中数据不标注克制")
	t.check(not fire.events.any(func(line: String) -> bool: return line.contains("属性克制")), "战斗日志不再写出克制修正")
	var water := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	water.unit_by_uid(1).cell = Vector2i(0, 3)
	var water_result := SkillResolver.apply(water, water.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(int(water_result["hits"][0]["damage"]), 1, "水流打火系：基础 1")
	var rock := TestScenario.make_state(["rock_starter"], [["electric_wild1", Vector2i(5, 4)]])
	rock.unit_by_uid(1).cell = Vector2i(4, 4)
	var push_result := SkillResolver.apply(rock, rock.unit_by_uid(1), "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(5, 4)}, false)
	t.eq(int(push_result["hits"][0]["damage"]), 2, "推击打电系：基础 2")
	var inverse := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(4, 3)]])
	inverse.unit_by_uid(1).cell = Vector2i(0, 3)
	var inverse_result := SkillResolver.resolve_channel(inverse, inverse.unit_by_uid(1), "fire_burst", [Vector2i(4, 3)])
	t.eq(int(inverse_result["hits"][0]["damage"]), 4, "火球术打水系：基础 4")
	t.eq(int(inverse_result["hits"][0]["modifier"]), 0, "逆克制标记已停用")
	var enemy := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	enemy.unit_by_uid(1).cell = Vector2i(2, 3)
	var enemy_result := SkillResolver.resolve_channel(enemy, enemy.unit_by_uid(100), "fire_burst", [Vector2i(2, 3)])
	t.eq(int(enemy_result["hits"][0]["damage"]), 4, "敌方火球也只有基础伤害")
