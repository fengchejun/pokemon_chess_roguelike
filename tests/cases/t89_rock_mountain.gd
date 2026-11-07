extends RefCounted
const ROCK := Vector2i(4, 3)
const DEST := Vector2i(5, 3)

func run(t: TestContext) -> void:
	t.begin("岩山不可推动、两次碎岩破坏及限定生成")
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
	t.eq(state.obstacle_durability[ROCK], 2, "岩山初始需要两次碎岩")
	var push := SkillResolver.apply(state, actor, "rock_push", entry, false)
	t.check(not push.get("obstacle_push", {}).get("moved", false), "岩系推击无法移动岩山")
	t.check(not PushResolver.push_obstacle(state, actor, ROCK).get("moved", false), "直接推障入口也不能搬动岩山")
	t.eq(state.terrain_at(ROCK), TerrainDB.ROCK_MOUNTAIN, "岩山留在原地")
	t.eq(state.terrain_at(DEST), TerrainDB.DEEP, "相邻深水保持原样")
	t.eq(state.obstacle_durability[ROCK], 2, "推击不扣岩山耐久")
	state.obstacle_origin[ROCK] = TerrainDB.DEEP
	var preview := state.preview_skill(actor, "rock_break", entry)
	t.eq(preview["obstacles_damaged"][0]["damage"], 1, "碎岩预览显示只扣一点耐久")
	t.eq(state.obstacle_durability[ROCK], 2, "预览不改变实际耐久")
	t.check(SkillResolver.apply(state, actor, "rock_break", entry, false).get("ok", false), "第一次碎岩可选中岩山")
	t.eq(state.terrain_at(ROCK), TerrainDB.ROCK_MOUNTAIN, "第一次碎岩后仍有岩山")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.obstacle_durability[ROCK], 1, "第一次碎岩后的耐久随快照保留")
	var breaker := restored.unit_by_uid(1)
	t.check(SkillResolver.apply(restored, breaker, "rock_break", entry, false).get("ok", false), "第二次碎岩可选中岩山")
	t.eq(restored.terrain_at(ROCK), TerrainDB.DEEP, "第二次碎岩破坏岩山后露出原底层")
	t.check(not restored.obstacle_durability.has(ROCK), "第二次碎岩后清除岩山障碍")

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
