extends RefCounted

func run(t: TestContext) -> void:
	t.begin("巢穴独占格子与地形覆盖保护")
	var cell := Vector2i(4, 3)
	for value in TerrainDB.ALL:
		var state := _state()
		state.set_terrain(cell, value)
		t.eq(state.terrain_at(cell), TerrainDB.PLAIN, "存活巢穴禁止叠加地形%s" % value)
		state.place_temp_vines(cell)
		state.place_temp_obstacle(cell, TerrainDB.WATER, 10)
		state.ignite(cell, "player")
		state.add_steam(cell)
		t.check(not state.vine_origin.has(cell) and not state.obstacle_durability.has(cell) and not state.burning_cells.has(cell) and not state.steam_cells.has(cell), "被阻止的地形效果不留下状态记录")
	var rain := _state()
	var caster := rain.unit_by_uid(1)
	caster.skills = ["rain_call"]
	var preview := rain.preview_skill(caster, "rain_call", {"type": "cell", "cell": cell})
	var actual := SkillResolver.apply(rain, caster, "rain_call", {"type": "cell", "cell": cell}, false)
	t.eq(rain.terrain_at(cell), TerrainDB.PLAIN, "造雨不能淹没巢穴")
	t.check(not actual["terrain_changes"].any(func(c): return c["cell"] == cell), "预览结算不虚报巢穴变水")
	t.eq(preview["terrain_changes"], actual["terrain_changes"], "造雨预览与实际一致")
	t.eq(rain.terrain_at(Vector2i(4, 2)), TerrainDB.WATER, "巢穴周围仍正常造水")
	for skill in ["frozen_ground", "wild_vines", "rock_create"]:
		var state := _state()
		var result := SkillResolver.apply(state, state.unit_by_uid(1), skill, {"type": "dir", "dir": Vector2i.RIGHT, "cell": cell}, false)
		t.eq(state.terrain_at(cell), TerrainDB.PLAIN, "%s不覆盖巢穴" % skill)
		t.check(not result["terrain_changes"].any(func(c): return c["cell"] == cell), "地形变化列表不含巢穴")
	var seed := _state()
	t.check(not SkillResolver.targets(seed, seed.unit_by_uid(1), "seed_sow").any(func(e): return e["cell"] == cell), "播种不能选择巢穴")
	SkillResolver.apply(seed, seed.unit_by_uid(1), "seed_sow", {"type": "cell", "cell": cell}, false)
	t.eq(seed.terrain_at(cell), TerrainDB.PLAIN, "底层播种也不能覆盖巢穴")
	var old := _state()
	old.terrain[GridSpec.index(cell)] = TerrainDB.ICE
	old.steam_cells[cell] = 2
	old.obstacle_durability[cell] = 2
	old.obstacle_origin[cell] = TerrainDB.WATER
	old.obstacle_expire_round[cell] = 4
	old.vine_origin[cell] = TerrainDB.DEEP
	old.vine_expire_round[cell] = 4
	old.burning_cells[cell] = 2
	old.burning_sources[cell] = "player"
	old.natural_essence_cells.append(cell)
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(old))
	t.eq(restored.terrain_at(cell), TerrainDB.PLAIN, "旧档读入清理叠加地形")
	for records in [restored.obstacle_durability, restored.obstacle_origin, restored.obstacle_expire_round, restored.vine_origin, restored.vine_expire_round, restored.burning_cells, restored.burning_sources, restored.steam_cells]:
		t.check(not records.has(cell), "旧档读入移除巢穴残留效果")
	t.check(not restored.natural_essence_cells.has(cell), "清理旧地形不保留额外原质来源")
	t.eq(restored.nest["hp"], old.nest["hp"], "清理地形不改变巢穴耐久")
	t.eq(restored.essence_earned, 0, "清理旧档不发拆障奖励")
	restored.damage_nest(1, "player", cell)
	t.eq(restored.nest["hp"], 2, "独立巢穴仍承受直接伤害")
	restored.damage_nest(1, "player", cell)
	restored.damage_nest(1, "player", cell)
	restored.set_terrain(cell, TerrainDB.WATER)
	t.eq(restored.terrain_at(cell), TerrainDB.WATER, "巢穴摧毁后原格恢复地形覆盖")
	var map_with_overlap := TestScenario.make_map(TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.WATER], [Vector2i(6, 3), TerrainDB.TREE]]), cell)
	map_with_overlap["nest_cells"] = [cell, Vector2i(6, 3)]
	var initial := BattleState.new()
	initial.load_map(map_with_overlap)
	for current in initial.all_nests():
		t.eq(initial.terrain_at(current["cell"]), TerrainDB.PLAIN, "初次加载时主副巢穴都不保留重叠地形")
		t.check(not initial.obstacle_durability.has(current["cell"]), "初始叠加树木不能留下障碍耐久")
	var destroyed := BattleSnapshot.load_state(BattleSnapshot.save_state(restored))
	t.eq(destroyed.terrain_at(cell), TerrainDB.WATER, "已毁巢穴读档保留后来生成的地形")
	for theme in ["fire", "water", "grass", "electric", "rock"]:
		var map := MapGenerator.generate(666, 0, 0, [], theme, 2)
		for nest_cell in map["nest_cells"]:
			t.eq(map["terrain"][GridSpec.index(nest_cell)], TerrainDB.PLAIN, "生成巢穴不与特殊地形叠加")
			for kind in ["water", "grass", "rock"]:
				t.check(not MapGenerator.apply_modification(map, nest_cell, kind), "战前改造不能覆盖巢穴")
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 7)]])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(4, 3)
	state.unit_by_uid(1).cell = Vector2i(3, 3)
	return state
