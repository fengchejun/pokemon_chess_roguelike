class_name MapGenerator
extends RefCounted

## 生成流程（v2.2）：地貌与卡组无关 —— 骨架与保护格 → 按“簇 / 带 + 散点”生成 →
## 致死地形预算 → 战前预览与地形改造。种子可复现：同区域、同种子得到同一张地图。

const CENTER_CELLS := [
	Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4),
]

## 特殊地形总量上限（占非保护区域比例），避免地图被地形淹没。
const SPECIAL_BUDGET_RATIO := 0.38


static func generate(run_seed: int, battle_index: int, salt: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("map:%d:%d:%d" % [run_seed, battle_index, salt])
	var cfg := BattleDB.config_for(battle_index)
	var lethal_budget := maxi(0, int(cfg.get("lethal_budget", 2)))
	for attempt in 12:
		var result := _attempt(rng, cfg, lethal_budget)
		if not result.is_empty():
			result["region"] = String(cfg.get("region", "?"))
			result["battle_index"] = battle_index
			result["attempt"] = attempt
			return result
	return _fallback(cfg)


static func _attempt(rng: RandomNumberGenerator, cfg: Dictionary, lethal_budget: int) -> Dictionary:
	var terrain: Array = []
	for index in GridSpec.W * GridSpec.H:
		terrain.append(TerrainDB.PLAIN)
	var protected := {}
	var enemy_cells: Array = []
	for pair in cfg.get("enemies", []):
		enemy_cells.append(pair[1])
	var nest_cell: Vector2i = cfg["nest_cell"]
	var nest_exits: Array = cfg["nest_exits"]
	for cell in Balance.DEPLOY_CELLS:
		protected[cell] = true
	for cell in enemy_cells:
		protected[cell] = true
	protected[nest_cell] = true
	for cell in nest_exits:
		protected[cell] = true
	_scatter(terrain, protected, rng, lethal_budget)
	_convert_deep(terrain, protected, rng, lethal_budget)
	var reward := _pick_cell(rng, terrain, protected, func(cell: Vector2i) -> bool:
		return int(terrain[GridSpec.index(cell)]) == TerrainDB.PLAIN and cell.x >= 3
	)
	if reward == Vector2i(-1, -1):
		return {}
	protected[reward] = true
	var fruits: Array = []
	for index in Balance.FRUITS_PER_BATTLE:
		var fruit := _pick_cell(rng, terrain, protected, func(cell: Vector2i) -> bool:
			return int(terrain[GridSpec.index(cell)]) == TerrainDB.PLAIN
		)
		if fruit == Vector2i(-1, -1):
			return {}
		fruits.append(fruit)
		protected[fruit] = true
	var required: Array = []
	required.append_array(enemy_cells)
	required.append(reward)
	required.append_array(fruits)
	if not _validate(terrain, required):
		return {}
	var obstacle_cells: Array = []
	var lethal := 0
	for cell in GridSpec.all_cells():
		var terrain_value := int(terrain[GridSpec.index(cell)])
		if terrain_value == TerrainDB.OBSTACLE:
			obstacle_cells.append(cell)
		elif TerrainDB.is_lethal(terrain_value):
			lethal += 1
	return {
		"terrain": terrain,
		"obstacle_cells": obstacle_cells,
		"nest_cell": nest_cell,
		"nest_exits": nest_exits.duplicate(),
		"reward_cell": reward,
		"fruit_cells": fruits,
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
		"lethal_count": lethal,
	}


static func _scatter(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, lethal_budget: int) -> void:
	## 地貌按“簇 / 带”生成并受总量预算约束；簇带之外加低概率散点制造斑驳感。
	var free_total := 0
	for cell in GridSpec.all_cells():
		if not protected.has(cell) and int(terrain[GridSpec.index(cell)]) == TerrainDB.PLAIN:
			free_total += 1
	var special_cap := int(free_total * SPECIAL_BUDGET_RATIO)
	var special_used := 0
	for _feature in rng.randi_range(1, 2):
		special_used += _grow_blob(terrain, protected, rng, TerrainDB.WATER, rng.randi_range(3, 6), special_cap - special_used, false)
	for _feature in rng.randi_range(1, 2):
		special_used += _grow_blob(terrain, protected, rng, TerrainDB.GRASS, rng.randi_range(2, 4), special_cap - special_used, false)
	for _feature in rng.randi_range(1, 2):
		special_used += _grow_blob(terrain, protected, rng, TerrainDB.OBSTACLE, rng.randi_range(2, 3), special_cap - special_used, true)
	for _dot in rng.randi_range(1, 3):
		special_used += _place_single(terrain, protected, rng, TerrainDB.WATER, special_cap - special_used, false)
	for _dot in rng.randi_range(1, 3):
		special_used += _place_single(terrain, protected, rng, TerrainDB.GRASS, special_cap - special_used, false)
	for _dot in rng.randi_range(0, 2):
		special_used += _place_single(terrain, protected, rng, TerrainDB.OBSTACLE, special_cap - special_used, true)
	var lethal_now := _count_terrain(terrain, TerrainDB.LAVA) + _count_terrain(terrain, TerrainDB.DEEP)
	for _feature in clampi(lethal_budget - lethal_now, 0, 2):
		if lethal_now >= lethal_budget:
			break
		var added := _grow_blob(terrain, protected, rng, TerrainDB.LAVA, 1, special_cap - special_used, true)
		special_used += added
		lethal_now += added


static func _pick_seed(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, value: int, need_interior: bool) -> Vector2i:
	var candidates: Array = []
	for cell in GridSpec.all_cells():
		if protected.has(cell) or int(terrain[GridSpec.index(cell)]) != TerrainDB.PLAIN:
			continue
		if need_interior and (cell.x < 2 or cell.x > GridSpec.W - 3 or cell.y < 1 or cell.y > GridSpec.H - 2):
			continue
		if value == TerrainDB.LAVA and (cell.x < 3 or _near_deploy(cell, 5)):
			continue
		if value == TerrainDB.OBSTACLE and _near_deploy(cell, 2):
			continue
		candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _place_single(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, value: int, budget_left: int, need_interior: bool) -> int:
	if budget_left <= 0:
		return 0
	var seed_cell := _pick_seed(terrain, protected, rng, value, need_interior)
	if seed_cell == Vector2i(-1, -1):
		return 0
	terrain[GridSpec.index(seed_cell)] = value
	return 1


static func _grow_blob(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, value: int, size: int, budget_left: int, need_interior: bool) -> int:
	size = mini(size, budget_left)
	if size <= 0:
		return 0
	var seed_cell := _pick_seed(terrain, protected, rng, value, need_interior)
	if seed_cell == Vector2i(-1, -1):
		return 0
	var blob: Array = [seed_cell]
	terrain[GridSpec.index(seed_cell)] = value
	var placed := 1
	var guard := 0
	var dir: Vector2i = GridSpec.DIRS4[rng.randi_range(0, GridSpec.DIRS4.size() - 1)]
	while placed < size and guard < 40:
		guard += 1
		var anchor: Vector2i = blob[rng.randi_range(0, blob.size() - 1)]
		if rng.randf() < 0.3:
			## 30% 概率转向：夹带少量折弯，避免几何般规整的块状。
			dir = GridSpec.DIRS4[rng.randi_range(0, GridSpec.DIRS4.size() - 1)]
		var next: Vector2i = anchor + dir
		if not GridSpec.is_inside(next) or protected.has(next):
			continue
		if int(terrain[GridSpec.index(next)]) != TerrainDB.PLAIN:
			continue
		if value == TerrainDB.LAVA and (next.x < 3 or _near_deploy(next, 5)):
			continue
		if value == TerrainDB.OBSTACLE and _near_deploy(next, 2):
			continue
		terrain[GridSpec.index(next)] = value
		blob.append(next)
		placed += 1
	return placed


static func _count_terrain(terrain: Array, value: int) -> int:
	var count := 0
	for cell in GridSpec.all_cells():
		if int(terrain[GridSpec.index(cell)]) == value:
			count += 1
	return count


static func _convert_deep(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, lethal_budget: int) -> void:
	var lava_count := 0
	var candidates: Array = []
	for cell in GridSpec.all_cells():
		var value := int(terrain[GridSpec.index(cell)])
		if value == TerrainDB.LAVA:
			lava_count += 1
		elif value == TerrainDB.WATER and not protected.has(cell) and not _near_deploy(cell, 3):
			if CENTER_CELLS.has(cell):
				continue
			candidates.append(cell)
	var deep_quota := maxi(0, lethal_budget - lava_count)
	while deep_quota > 0 and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[index]
		candidates.remove_at(index)
		terrain[GridSpec.index(cell)] = TerrainDB.DEEP
		deep_quota -= 1


static func _pick_cell(rng: RandomNumberGenerator, terrain: Array, protected: Dictionary, predicate: Callable) -> Vector2i:
	var candidates: Array = []
	for cell in GridSpec.all_cells():
		if protected.has(cell):
			continue
		if predicate.call(cell):
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _validate(terrain: Array, required_cells: Array) -> bool:
	var reached := {}
	var frontier: Array = []
	for cell in Balance.DEPLOY_CELLS:
		if int(terrain[GridSpec.index(cell)]) == TerrainDB.OBSTACLE:
			return false
		reached[cell] = true
		frontier.append(cell)
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for dir in GridSpec.DIRS4:
			var next: Vector2i = current + dir
			if not GridSpec.is_inside(next) or reached.has(next):
				continue
			var value := int(terrain[GridSpec.index(next)])
			if value == TerrainDB.OBSTACLE or value == TerrainDB.LAVA:
				continue
			reached[next] = true
			frontier.append(next)
	for cell in required_cells:
		if not reached.has(cell):
			return false
	return true


static func _near_deploy(cell: Vector2i, distance: int) -> bool:
	for deploy in Balance.DEPLOY_CELLS:
		if GridSpec.manhattan(cell, deploy) < distance:
			return true
	return false


static func _fallback(cfg: Dictionary) -> Dictionary:
	var terrain: Array = []
	for index in GridSpec.W * GridSpec.H:
		terrain.append(TerrainDB.PLAIN)
	var nest_cell: Vector2i = cfg["nest_cell"]
	var enemy_cells: Array = []
	for pair in cfg.get("enemies", []):
		enemy_cells.append(pair[1])
	var reward := Vector2i(3, 3)
	while enemy_cells.has(reward):
		reward.x += 1
	return {
		"terrain": terrain,
		"obstacle_cells": [],
		"nest_cell": nest_cell,
		"nest_exits": (cfg["nest_exits"] as Array).duplicate(),
		"reward_cell": reward,
		"fruit_cells": [Vector2i(2, 6), Vector2i(4, 1)],
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
		"lethal_count": 0,
		"region": String(cfg.get("region", "?")),
		"battle_index": 0,
		"attempt": 99,
	}


static func mod_protected(map: Dictionary, cell: Vector2i) -> bool:
	var protected_cells: Array = []
	protected_cells.append_array(map.get("deploy_cells", Balance.DEPLOY_CELLS))
	protected_cells.append(map["nest_cell"])
	protected_cells.append_array(map["nest_exits"])
	protected_cells.append(map["reward_cell"])
	protected_cells.append_array(map.get("fruit_cells", []))
	return protected_cells.has(cell)


static func apply_modification(map: Dictionary, cell: Vector2i, kind: String) -> bool:
	if not GridSpec.is_inside(cell) or mod_protected(map, cell):
		return false
	var terrain: Array = map["terrain"]
	var value := int(terrain[GridSpec.index(cell)])
	match kind:
		"water":
			if value != TerrainDB.PLAIN:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.WATER
		"grass":
			if value != TerrainDB.PLAIN:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.GRASS
		"rock":
			if value != TerrainDB.PLAIN:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
			(map["obstacle_cells"] as Array).append(cell)
		"clear":
			if value != TerrainDB.OBSTACLE:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.PLAIN
			(map["obstacle_cells"] as Array).erase(cell)
		"deep":
			if value != TerrainDB.WATER:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.DEEP
		"lava":
			if value != TerrainDB.PLAIN:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.LAVA
		_:
			return false
	return true
