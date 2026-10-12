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
	t.check(bool(SkillResolver.apply(state, caster, "lightning", entry, false).get("ok", false)), "闪电命中全场单位")
	t.check(target.shock_ticks > 0, "闪电施加感电")
	SkillResolver.apply(state, caster, "lightning", entry, false)
	t.check(target.paralyzed_ticks > 0, "重复感电触发麻痹")
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
