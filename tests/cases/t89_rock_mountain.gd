extends RefCounted
const ROCK := Vector2i(4, 3)
const DEST := Vector2i(5, 3)

func run(t: TestContext) -> void:
	t.begin("岩山无限耐久、推移及限定生成")
	var map := TestScenario.make_map(TestScenario.with_cells(TestScenario.plain_terrain(), [
		[ROCK, TerrainDB.ROCK_MOUNTAIN], [DEST, TerrainDB.DEEP],
	]))
	var actor := CombatUnit.make("rock_wild1", "player", 1)
	var state := BattleState.new()
	state.setup(map, {"enemies": []}, 51, 0, [actor], {}, {}, [])
	actor.cell = Vector2i(3, 3)
	actor.skills = ["rock_push", "rock_break", "rock_smash"]
	t.check(state.terrain_blocks_move(ROCK) and state.is_blocking_ray(ROCK), "岩山阻挡移动和射线")
	var entry := {"type": "cell", "cell": ROCK}
	t.check(SkillResolver.apply(state, actor, "rock_smash", entry, false).get("ok", false), "旧碎石招式可以命中")
	t.check(not state.damage_obstacle(ROCK, 999, "player", "earth_shake") and state.terrain_at(ROCK) == TerrainDB.ROCK_MOUNTAIN, "旧碎石和超高耐久伤害均不能破坏岩山")
	state.set_terrain(ROCK, TerrainDB.WATER)
	t.eq(state.terrain_at(ROCK), TerrainDB.ROCK_MOUNTAIN, "地形改写不能绕过岩山耐久")
	t.check(not MapGenerator.apply_modification(map, ROCK, "clear"), "整备开垦不能移除岩山")
	var preview := state.preview_skill(actor, "rock_push", entry)
	t.check(preview.get("obstacle_push", {}).get("moved", false), "推击预览显示岩山可移动")
	t.eq(state.terrain_at(ROCK), TerrainDB.ROCK_MOUNTAIN, "预览不移动实际岩山")
	var result := SkillResolver.apply(state, actor, "rock_push", entry, false)
	t.check(result.get("obstacle_push", {}).get("moved", false), "实际推击移动岩山")
	t.eq(state.terrain_at(ROCK), TerrainDB.PLAIN, "岩山离开后恢复原地形")
	t.eq(state.terrain_at(DEST), TerrainDB.ROCK_MOUNTAIN, "推入深水也不会消耗岩山")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.obstacle_origin[DEST], TerrainDB.DEEP, "岩山位置与覆盖的深水随快照保留")
	var breaker := restored.unit_by_uid(1)
	var break_result := SkillResolver.apply(restored, breaker, "rock_break", {"type": "cell", "cell": DEST}, false)
	t.check(break_result.get("ok", false), "碎岩可选中岩山")
	t.eq(restored.terrain_at(DEST), TerrainDB.DEEP, "碎岩破坏岩山后露出深水")
	t.check(not restored.obstacle_durability.has(DEST), "碎岩后清除岩山障碍")

	var central := 0
	var total := 0
	for seed_value in range(1, 61):
		var rock_map := MapGenerator.generate(seed_value, 0, 0, [], "rock")
		var fire_map := MapGenerator.generate(seed_value, 0, 0, [], "fire")
		t.check(not fire_map["terrain"].has(TerrainDB.ROCK_MOUNTAIN), "非岩系常规地图不生成岩山")
		var mountains: int = rock_map["terrain"].count(TerrainDB.ROCK_MOUNTAIN)
		t.check(mountains <= 1, "岩系地图最多一座岩山")
		total += mountains
		for cell in MapGenerator.CENTER_CELLS:
			if rock_map["terrain"][GridSpec.index(cell)] == TerrainDB.ROCK_MOUNTAIN:
				central += 1
		for cell in rock_map["obstacle_cells"]:
			if rock_map["terrain"][GridSpec.index(cell)] == TerrainDB.ROCK_MOUNTAIN:
				t.check(GridSpec.neighbors4(cell).all(func(near): return not TerrainDB.blocks_move(rock_map["terrain"][GridSpec.index(near)]) and not rock_map["electric_flowers"].has(near)), "岩山独立于其他障碍")
	t.check(total >= 50 and central > total / 2, "岩山在岩系地图常见且多数位于中心四格（%d/%d）" % [central, total])
	t.finish()
