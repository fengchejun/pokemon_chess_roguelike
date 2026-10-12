extends RefCounted

## 地图生成（v2.2）：可复现、与卡组无关、保护格与致死预算、地形密度、改造


func run(t: TestContext) -> void:
	t.begin("地图生成")
	_t_reproducible(t)
	_t_landscape(t)
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
		t.check(special <= 21, "地形总量受预算约束（第 %d 场：%d 格）" % [battle_index + 1, special])
		t.check(special >= 4, "地貌仍有基本变化（第 %d 场：%d 格）" % [battle_index + 1, special])
		t.check(_has_adjacent_pair(terrain), "地貌存在成簇 / 成带（第 %d 场）" % (battle_index + 1))
		var lethal := 0
		for cell in GridSpec.all_cells():
			if TerrainDB.is_lethal(int(terrain[GridSpec.index(cell)])):
				lethal += 1
		t.eq(lethal, int(map["lethal_count"]), "致死地形统计一致（第 %d 场）" % (battle_index + 1))


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
