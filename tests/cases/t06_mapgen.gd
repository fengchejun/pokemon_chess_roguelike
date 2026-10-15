extends RefCounted

## 地图生成：旧版区域权重、独立树木与蒸汽、保护格与致死预算。


func run(t: TestContext) -> void:
	t.begin("地图生成")
	_t_reproducible(t)
	_t_landscape(t)
	_t_tree_and_steam(t)
	_t_runtime_tree_steam(t)
	_t_budget_and_protection(t)
	_t_modification(t)
	t.finish()


func _t_reproducible(t: TestContext) -> void:
	var first := MapGenerator.generate(12345, 0)
	var second := MapGenerator.generate(12345, 0)
	t.eq(first, second, "同种子生成同一张地图")
	var other := MapGenerator.generate(12345, 0, 1)
	t.check(other["terrain"] != first["terrain"], "重掷使用不同地图")


func _t_landscape(t: TestContext) -> void:
	for battle_index in 6:
		var map := MapGenerator.generate(2468, battle_index)
		var terrain: Array = map["terrain"]
		var special := _special_count(terrain)
		t.check(special >= 20, "旧版逐格权重使特殊地形充分出现（第 %d 场：%d 格）" % [battle_index + 1, special])
		t.check(int(map["attempt"]) < 64, "高密度地图仍通过可玩性检查（第 %d 场）" % (battle_index + 1))
		t.check(_has_adjacent_pair(terrain), "地貌存在成簇 / 成带（第 %d 场）" % (battle_index + 1))
		var lethal := 0
		for cell in GridSpec.all_cells():
			if TerrainDB.is_lethal(int(terrain[GridSpec.index(cell)])):
				lethal += 1
		t.eq(lethal, int(map["lethal_count"]), "致死地形统计一致（第 %d 场）" % (battle_index + 1))


func _t_tree_and_steam(t: TestContext) -> void:
	var tree_maps := 0
	var steam_maps := 0
	for seed_value in range(100, 120):
		var map := MapGenerator.generate(seed_value, 1, 0, ["water", "fire", "steam_focus"])
		t.check(int(map["attempt"]) < 64, "水火卡组地图通过可玩性检查（种子 %d）" % seed_value)
		if not (map.get("tree_cells", []) as Array).is_empty():
			tree_maps += 1
		if not (map.get("steam_cells", {}) as Dictionary).is_empty():
			steam_maps += 1
		for cell in map.get("tree_cells", []):
			t.eq(int(map["terrain"][GridSpec.index(cell)]), TerrainDB.TREE, "独立树木保持自己的地形类别")
		for cell in map.get("steam_cells", {}).keys():
			t.check(TerrainDB.is_water_body(int(map["terrain"][GridSpec.index(cell)])), "初始蒸汽只在水面生成")
	t.check(tree_maps >= 10, "多数地图生成独立树木（%d/20）" % tree_maps)
	t.check(steam_maps >= 10, "水火卡组明显提高蒸汽出现（%d/20）" % steam_maps)


func _t_runtime_tree_steam(t: TestContext) -> void:
	var tree_cell := Vector2i(3, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[tree_cell, TerrainDB.TREE], [Vector2i(4, 3), TerrainDB.GRASS], [Vector2i(2, 4), TerrainDB.WATER],
	])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	t.eq(state.obstacle_durability.get(tree_cell, 0), 1, "独立树木初始耐久为 1")
	t.check(not state.move_options(fire).has(tree_cell), "树木阻挡主动移动")
	var cast := SkillResolver.resolve_channel(state, fire, "fire_burst", [tree_cell])
	t.check(bool(cast.get("ok", false)), "火球术可越障命中独立树木")
	t.eq(state.obstacle_durability.get(tree_cell, 0), 0, "火球对树木造成 1 点物体伤害并立即摧毁")
	t.check(not state.burning_cells.has(tree_cell), "树木即毁时不保留燃烧")
	state.settle_round()
	t.check(state.burning_cells.has(Vector2i(4, 3)), "火球十字范围内草丛独立燃烧")
	state.settle_round()
	t.eq(state.terrain_at(tree_cell), TerrainDB.PLAIN, "树木已被立即摧毁并可通行")
	var water_cell := Vector2i(2, 4)
	state.add_steam(water_cell)
	fire.cell = water_cell
	t.eq(SkillResolver.targets(state, fire, "fire_burst").size(), 0, "蒸汽中没有合法技能目标")
	t.check(not bool(state.cast_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(5, 4)}).get("ok", false)), "蒸汽中施法失败且不消耗机会")
	t.check(not fire.skill_used, "蒸汽禁用不扣技能资源")
	state.settle_round()
	t.check(state.steam_cells.has(water_cell), "蒸汽持续第一次结算")
	state.settle_round()
	t.check(not state.steam_cells.has(water_cell), "蒸汽第二次结算后消散")
	var water_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[tree_cell, TerrainDB.WATER]])
	var reaction := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], water_terrain)
	reaction.unit_by_uid(1).cell = Vector2i(0, 3)
	var fireball := SkillResolver.resolve_channel(reaction, reaction.unit_by_uid(1), "fire_burst", [tree_cell])
	t.check(bool(fireball.get("ok", false)), "火球术可命中水域")
	t.eq(reaction.steam_cells.get(tree_cell, 0), 2, "火焰与水域反应生成持续两次结算的蒸汽")


func _has_adjacent_pair(terrain: Array) -> bool:
	for cell in GridSpec.all_cells():
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next: Vector2i = cell + dir
			if not GridSpec.is_inside(next):
				continue
			var a := int(terrain[GridSpec.index(cell)])
			var b := int(terrain[GridSpec.index(next)])
			if a == b and a != TerrainDB.PLAIN:
				return true
	return false


func _t_budget_and_protection(t: TestContext) -> void:
	for battle_index in BattleDB.count():
		var cfg := BattleDB.config_for(battle_index)
		var budget := int(cfg.get("lethal_budget", 2))
		var map := MapGenerator.generate(2468, battle_index)
		t.eq((map["nest_exits"] as Array).size(), 1, "第 %d 场只有一个巢穴出口" % (battle_index + 1))
		t.check(int(map["lethal_count"]) <= budget, "第 %d 场致死地形不超预算" % (battle_index + 1))
		var terrain: Array = map["terrain"]
		for cell in map["deploy_cells"]:
			t.eq(int(terrain[GridSpec.index(cell)]), TerrainDB.PLAIN, "部署格被保护")
		t.eq(int(terrain[GridSpec.index(map["nest_cell"])]), TerrainDB.PLAIN, "巢穴格被保护")
		for cell in map["nest_exits"]:
			t.eq(int(terrain[GridSpec.index(cell)]), TerrainDB.PLAIN, "巢穴出口被保护")
		t.eq(int(terrain[GridSpec.index(map["reward_cell"])]), TerrainDB.PLAIN, "奖励格可站立")
		for pair in cfg.get("enemies", []):
			t.eq(int(terrain[GridSpec.index(pair[1])]), TerrainDB.PLAIN, "敌人出生格可站立")


func _t_modification(t: TestContext) -> void:
	var map := MapGenerator.generate(555, 1)
	var cell := _find_plain_cell(map)
	t.check(cell != Vector2i(-1, -1), "找到可改造的平地")
	if cell == Vector2i(-1, -1):
		return
	t.eq(MapGenerator.apply_modification(map, cell, "water"), true, "注水成功")
	t.eq(int(map["terrain"][GridSpec.index(cell)]), TerrainDB.WATER, "平地变水面")
	t.eq(MapGenerator.apply_modification(map, cell, "rock"), false, "水面不能立岩")
	var cell2 := _find_plain_cell(map)
	t.eq(MapGenerator.apply_modification(map, cell2, "rock"), true, "立岩成功")
	t.eq(int(map["terrain"][GridSpec.index(cell2)]), TerrainDB.OBSTACLE, "平地变障碍")
	t.eq(MapGenerator.apply_modification(map, cell2, "clear"), true, "开垦成功")
	t.eq(int(map["terrain"][GridSpec.index(cell2)]), TerrainDB.PLAIN, "障碍变平地")
	var protected_cell: Vector2i = map["reward_cell"]
	t.eq(MapGenerator.apply_modification(map, protected_cell, "clear"), false, "保护格不可改造")
	# 新增工具：种草 / 熔岩 / 深水（需先注水）
	var grass_cell := _find_plain_cell(map)
	t.eq(MapGenerator.apply_modification(map, grass_cell, "grass"), true, "种草成功")
	t.eq(int(map["terrain"][GridSpec.index(grass_cell)]), TerrainDB.GRASS, "平地变草丛")
	var lava_cell := _find_plain_cell(map)
	t.eq(MapGenerator.apply_modification(map, lava_cell, "lava"), true, "熔岩改造成功")
	t.eq(int(map["terrain"][GridSpec.index(lava_cell)]), TerrainDB.LAVA, "平地变熔岩")
	var water_cell := _find_plain_cell(map)
	t.eq(MapGenerator.apply_modification(map, water_cell, "water"), true, "注水（为深水做准备）")
	t.eq(MapGenerator.apply_modification(map, water_cell, "deep"), true, "深水改造成功")
	t.eq(int(map["terrain"][GridSpec.index(water_cell)]), TerrainDB.DEEP, "水面变深水")
	t.eq(MapGenerator.apply_modification(map, grass_cell, "deep"), false, "草丛不能直接加深")


func _find_plain_cell(map: Dictionary) -> Vector2i:
	for cell in GridSpec.all_cells():
		if MapGenerator.mod_protected(map, cell):
			continue
		if int(map["terrain"][GridSpec.index(cell)]) == TerrainDB.PLAIN:
			return cell
	return Vector2i(-1, -1)


func _special_count(terrain: Array) -> int:
	var count := 0
	for cell in GridSpec.all_cells():
		if int(terrain[GridSpec.index(cell)]) != TerrainDB.PLAIN:
			count += 1
	return count
