class_name MapGenerator
extends RefCounted

## 旧版逐格区域权重；独立树木与水面蒸汽也由地图生成。

const CENTER_CELLS := [
	Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4),
]

const REGION_WEIGHTS := {
	"草原": {"ground": 49, "water": 12, "fragile": 5, "rock": 8, "plant": 10, "grass": 16},
	"溪谷": {"ground": 49, "water": 22, "fragile": 5, "rock": 8, "plant": 10, "grass": 6},
	"密林": {"ground": 42, "water": 8, "fragile": 4, "rock": 8, "plant": 22, "grass": 16},
	"火谷": {"ground": 49, "water": 8, "fragile": 5, "rock": 17, "plant": 13, "grass": 8},
	"岩窟": {"ground": 52, "water": 8, "fragile": 8, "rock": 20, "plant": 8, "grass": 4},
	"深潭": {"ground": 45, "water": 27, "fragile": 5, "rock": 9, "plant": 8, "grass": 6},
}
const WEIGHT_ORDER := ["ground", "water", "fragile", "rock", "plant", "grass"]


static func generate(run_seed: int, battle_index: int, salt: int = 0, environment_deck: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("map:%d:%d:%d" % [run_seed, battle_index, salt])
	var cfg := BattleDB.config_for(battle_index)
	var lethal_budget := maxi(0, int(cfg.get("lethal_budget", 2)))
	for attempt in 64:
		var result := _attempt(rng, cfg, lethal_budget, environment_deck)
		if not result.is_empty():
			result["region"] = String(cfg.get("region", "?"))
			result["battle_index"] = battle_index
			result["attempt"] = attempt
			return result
	var fallback := _fallback(cfg)
	fallback["battle_index"] = battle_index
	return fallback


static func terrain_counts(map: Dictionary) -> Dictionary:
	var counts := {"water": 0, "grass": 0, "rock": 0, "steam": 0}
	for value in map.get("terrain", []):
		match int(value):
			TerrainDB.WATER: counts["water"] += 1
			TerrainDB.GRASS: counts["grass"] += 1
			TerrainDB.OBSTACLE: counts["rock"] += 1
	counts["steam"] = (map.get("steam_cells", {}) as Dictionary).size()
	return counts


static func card_targets(card_id: String) -> Array:
	match card_id:
		"water", "electric": return ["water"]
		"fire": return ["grass"]
		"rock": return ["rock"]
		"steam_focus": return ["water", "grass", "steam"]
	return []


static func generate_card_preview(run_seed: int, battle_index: int, card_id: String, previous: Dictionary) -> Dictionary:
	## 卡仍先改变区域权重；再用可复现的安全补足保证预览地形严格增加。
	var before := terrain_counts(previous)
	var targets := card_targets(card_id)
	var best: Dictionary = {}
	var best_gap := 999
	for salt in range(1, 49):
		var candidate := generate(run_seed, battle_index, salt, [card_id])
		var after := terrain_counts(candidate)
		var gap := 0
		for key in targets:
			gap += maxi(0, int(before[key]) + 1 - int(after[key]))
		if gap == 0:
			return {"map": candidate, "before": before, "after": after, "guaranteed": true}
		if gap < best_gap:
			best_gap = gap
			best = candidate
	var fixed := best.duplicate(true)
	for key in targets:
		while int(terrain_counts(fixed)[key]) <= int(before[key]):
			if not _add_card_terrain(fixed, String(key)):
				break
	var after := terrain_counts(fixed)
	var guaranteed := true
	for key in targets:
		if int(after[key]) <= int(before[key]):
			guaranteed = false
	return {"map": fixed, "before": before, "after": after, "guaranteed": guaranteed}


static func _add_card_terrain(map: Dictionary, kind: String) -> bool:
	if kind == "steam":
		for cell in GridSpec.all_cells():
			if int(map["terrain"][GridSpec.index(cell)]) == TerrainDB.WATER and not (map["steam_cells"] as Dictionary).has(cell):
				map["steam_cells"][cell] = 2
				return true
		return false
	var new_value := TerrainDB.WATER if kind == "water" else TerrainDB.GRASS if kind == "grass" else TerrainDB.OBSTACLE
	var required: Array = []
	for pair in BattleDB.config_for(int(map.get("battle_index", 0))).get("enemies", []):
		required.append(pair[1])
	required.append(map["reward_cell"])
	required.append_array(map.get("fruit_cells", []))
	for cell in GridSpec.all_cells():
		if mod_protected(map, cell):
			continue
		var index := GridSpec.index(cell)
		if int(map["terrain"][index]) != TerrainDB.PLAIN:
			continue
		map["terrain"][index] = new_value
		if kind != "rock" or _validate(map["terrain"], required):
			if kind == "rock":
				(map["obstacle_cells"] as Array).append(cell)
			return true
		map["terrain"][index] = TerrainDB.PLAIN
	return false


static func _attempt(rng: RandomNumberGenerator, cfg: Dictionary, lethal_budget: int, environment_deck: Array) -> Dictionary:
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
	_scatter(terrain, protected, rng, cfg, lethal_budget, environment_deck)
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
	var tree_cells: Array = []
	var steam_cells := {}
	var steam_chance := 0.02
	if environment_deck.has("steam_focus"):
		steam_chance = 0.11
	var lethal := 0
	for cell in GridSpec.all_cells():
		var terrain_value := int(terrain[GridSpec.index(cell)])
		if TerrainDB.blocks_move(terrain_value):
			obstacle_cells.append(cell)
			if terrain_value == TerrainDB.TREE:
				tree_cells.append(cell)
		if TerrainDB.is_lethal(terrain_value):
			lethal += 1
		if TerrainDB.is_water_body(terrain_value) and rng.randf() < steam_chance:
			steam_cells[cell] = 2
	return {
		"terrain": terrain,
		"obstacle_cells": obstacle_cells,
		"tree_cells": tree_cells,
		"steam_cells": steam_cells,
		"nest_cell": nest_cell,
		"nest_exits": nest_exits.duplicate(),
		"reward_cell": reward,
		"fruit_cells": fruits,
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
		"lethal_count": lethal,
	}


static func _scatter(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, lethal_budget: int, deck: Array) -> void:
	var weights: Dictionary = REGION_WEIGHTS.get(String(cfg.get("region", "草原")), REGION_WEIGHTS["草原"]).duplicate()
	var card_weights := MapCardDB.weights(deck)
	for key in ["water", "grass", "rock"]:
		weights[key] = int(weights[key]) + int(card_weights.get(key, 0))
	var water_clump := 12 + (12 if deck.has("water") and deck.has("rock") else 0) + (20 if deck.has("water") and deck.has("electric") else 0)
	for cell in GridSpec.all_cells():
		if protected.has(cell):
			continue
		var local: Dictionary = weights.duplicate()
		if cell.x >= 2 and cell.x <= 5 and cell.y >= 2 and cell.y <= 5:
			local["grass"] = int(local["grass"]) + 12
		if _adjacent_water(terrain, cell):
			local["water"] = int(local["water"]) + water_clump
			if deck.has("water") and deck.has("rock"):
				local["rock"] = int(local["rock"]) + 12
		match _weighted_pick(local, rng):
			"water": terrain[GridSpec.index(cell)] = TerrainDB.WATER
			"fragile": terrain[GridSpec.index(cell)] = TerrainDB.FRAGILE
			"rock": terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
			"plant": terrain[GridSpec.index(cell)] = TerrainDB.TREE
			"grass": terrain[GridSpec.index(cell)] = TerrainDB.GRASS
	# 致死地形仍服从各场预算，不能因恢复旧版密度堵死通路。
	if lethal_budget > 0 and String(cfg.get("region", "")) == "火谷":
		for _n in mini(2, lethal_budget):
			_place_single(terrain, protected, rng, TerrainDB.LAVA, 1, true)


static func _adjacent_water(terrain: Array, cell: Vector2i) -> bool:
	for near in GridSpec.neighbors4(cell):
		if TerrainDB.is_water_body(int(terrain[GridSpec.index(near)])):
			return true
	return false


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for key in WEIGHT_ORDER:
		total += int(weights[key])
	var roll := rng.randi_range(1, total)
	for key in WEIGHT_ORDER:
		roll -= int(weights[key])
		if roll <= 0:
			return key
	return "ground"


static func _pick_seed(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, value: int, need_interior: bool) -> Vector2i:
	var candidates: Array = []
	for cell in GridSpec.all_cells():
		if protected.has(cell) or int(terrain[GridSpec.index(cell)]) != TerrainDB.PLAIN:
			continue
		if need_interior and (cell.x < 2 or cell.x > GridSpec.W - 3 or cell.y < 1 or cell.y > GridSpec.H - 2):
			continue
		if value == TerrainDB.LAVA and (cell.x < 3 or _near_deploy(cell, 5)):
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
		if TerrainDB.blocks_move(int(terrain[GridSpec.index(cell)])):
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
			if TerrainDB.blocks_move(value) or value == TerrainDB.LAVA or value == TerrainDB.DEEP or value == TerrainDB.FRAGILE or value == TerrainDB.PIT:
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
		"tree_cells": [],
		"steam_cells": {},
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
			if not TerrainDB.blocks_move(value):
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.PLAIN
			(map["obstacle_cells"] as Array).erase(cell)
			(map.get("tree_cells", []) as Array).erase(cell)
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
