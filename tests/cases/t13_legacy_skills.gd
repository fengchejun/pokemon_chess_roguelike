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
	t.check(bool(result.get("ok", false)), "火球实战可施放")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.PIT, "火球击碎易碎地面")
	t.check(state.burning_cells.has(Vector2i(4, 2)), "火球点燃草丛")
	t.eq(state.skill_targets(fire, "fire_burst").size(), 0, "火球一场只能用一次")
	var jet_state := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(2, 3)]])
	var jet_fire := jet_state.unit_by_uid(1)
	jet_fire.cell = Vector2i(0, 3)
	var jet := SkillResolver.apply(jet_state, jet_fire, "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(1, 3)}, false)
	t.check(bool(jet.get("ok", false)), "喷射火焰按方向施放")
	t.check(jet_state.unit_by_uid(100).burn_ticks > 0, "喷射火焰附加灼烧")


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
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	var preview := state.preview_skill(caster, "lightning", entry)
	t.check(bool(preview.get("ok", false)), "闪电预览可用")
	t.eq(int(caster.battle_skill_uses.get("lightning", 0)), 0, "预览不消耗本场闪电次数")
	t.check(bool(SkillResolver.apply(state, caster, "lightning", entry, false).get("ok", false)), "闪电命中全场单位")
	t.check(target.shock_ticks > 0, "闪电施加感电")
	t.eq(int(caster.battle_skill_uses.get("lightning", 0)), 1, "闪电消耗本场唯一使用次数")
	caster.skill_used = false
	t.eq(state.skill_targets(caster, "lightning").size(), 0, "下一回合仍不能再次瞄准闪电")
	t.eq(bool(SkillResolver.apply(state, caster, "lightning", entry, false).get("ok", false)), false, "直接结算入口也拒绝第二次闪电")
	t.check(caster.can_use_in_battle("electric_arc"), "放电不受闪电次数限制")
	var second := CombatUnit.make("electric_starter", "player", 51)
	second.cell = Vector2i(1, 3)
	state.units.append(second)
	target.hp = 10
	t.check(bool(SkillResolver.apply(state, second, "lightning", entry, false).get("ok", false)), "另一只电怪仍可用自己的闪电")
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
	state.settle_round()
	t.eq(fire.hp, 0, "冰面结算滑入深坑立即倒下")


func _matchup_damage(t: TestContext) -> void:
	var grass := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]])
	grass.unit_by_uid(1).cell = Vector2i(0, 3)
	var grass_entry := {"type": "cell", "cell": Vector2i(4, 3)}
	var grass_preview := grass.preview_skill(grass.unit_by_uid(1), "fire_burst", grass_entry)
	t.eq(int(grass_preview["hits"][0]["damage"]), 3, "火球预览草系中心为 3 伤")
	var grass_result := SkillResolver.apply(grass, grass.unit_by_uid(1), "fire_burst", grass_entry, false)
	t.eq(int(grass_result["hits"][0]["damage"]), 3, "旧版火球术命中草系：基础 2 + 火克草 1")
	t.eq(int(grass_result["hits"][0]["modifier"]), 1, "火克草修正进入命中数据")
	var fire := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(4, 3)]])
	fire.unit_by_uid(1).cell = Vector2i(0, 3)
	var fire_result := SkillResolver.apply(fire, fire.unit_by_uid(1), "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(int(fire_result["hits"][0]["damage"]), 3, "火球术打冰系：基础 2 + 克制 1")
	t.eq(int(fire_result["hits"][0]["modifier"]), 1, "火球命中数据标注克制 +1")
	t.check(fire.events.any(func(line: String) -> bool: return line.contains("属性克制 +1")), "战斗日志明确写出克制修正")
	var water := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	water.unit_by_uid(1).cell = Vector2i(0, 3)
	var water_result := SkillResolver.apply(water, water.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(int(water_result["hits"][0]["damage"]), 2, "水流打火系：基础 1 + 克制 1")
	var rock := TestScenario.make_state(["rock_starter"], [["electric_wild1", Vector2i(5, 4)]])
	rock.unit_by_uid(1).cell = Vector2i(4, 4)
	var push_result := SkillResolver.apply(rock, rock.unit_by_uid(1), "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(5, 4)}, false)
	t.eq(int(push_result["hits"][0]["damage"]), 3, "推击打电系：基础 2 + 克制 1")
	var inverse := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(4, 3)]])
	inverse.unit_by_uid(1).cell = Vector2i(0, 3)
	var inverse_result := SkillResolver.apply(inverse, inverse.unit_by_uid(1), "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(int(inverse_result["hits"][0]["damage"]), 1, "火球术打水系：基础 2 - 逆克制 1")
	t.eq(int(inverse_result["hits"][0]["modifier"]), -1, "逆克制标记进入预览数据")
	var enemy := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]])
	enemy.unit_by_uid(1).cell = Vector2i(2, 3)
	var enemy_result := SkillResolver.apply(enemy, enemy.unit_by_uid(100), "fire_burst", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.eq(int(enemy_result["hits"][0]["damage"]), 1, "敌方旧版火球也遵守火打水 -1")
