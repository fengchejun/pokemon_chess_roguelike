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
	"火谷": {"ground": 49, "water": 4, "fragile": 5, "rock": 20, "plant": 11, "grass": 4, "blue_fire": 7},
	"岩窟": {"ground": 52, "water": 8, "fragile": 8, "rock": 20, "plant": 8, "grass": 4},
	"深潭": {"ground": 45, "water": 27, "fragile": 5, "rock": 9, "plant": 8, "grass": 6},
}
const WEIGHT_ORDER := ["ground", "water", "fragile", "rock", "plant", "grass", "blue_fire"]
const MAX_ROCK_MOUNTAINS := 4


static func generate(run_seed: int, battle_index: int, salt: int = 0, environment_deck: Array = [], theme_id: String = "", nest_count: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("map:%d:%d:%d" % [run_seed, battle_index, salt])
	var cfg := BattleDB.config_for(battle_index, run_seed, theme_id)
	cfg["nest_count"] = nest_count if nest_count >= 0 else 1
	var lethal_budget := maxi(0, int(cfg.get("lethal_budget", 2)))
	for attempt in 64:
		var result := _attempt(rng, cfg, lethal_budget, environment_deck)
		if not result.is_empty() and _has_landscape_pair(result["terrain"]) and randomize_nests(result, cfg, rng):
			_add_rock_mountains(result, cfg, rng)
			_add_electric_flowers(result, cfg, rng)
			result["region"] = String(cfg.get("region", "?"))
			result["battle_index"] = battle_index
			result["theme_id"] = theme_id
			result["attempt"] = attempt
			return result
	var fallback := _fallback(cfg)
	randomize_nests(fallback, cfg, rng)
	_add_rock_mountains(fallback, cfg, rng)
	_add_electric_flowers(fallback, cfg, rng)
	fallback["battle_index"] = battle_index
	fallback["theme_id"] = theme_id
	return fallback


static func _add_rock_mountains(map: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	if cfg.get("region", "") != "岩窟":
		return
	var terrain: Array = map["terrain"]
	var remaining_count := rng.randi_range(1, MAX_ROCK_MOUNTAINS) - terrain.count(TerrainDB.ROCK_MOUNTAIN)
	if remaining_count <= 0:
		return
	var required: Array = map.get("nest_cells", []).duplicate()
	required.append(map["reward_cell"])
	for pair in cfg.get("enemies", []):
		required.append(pair[1])
	var candidates := CENTER_CELLS.duplicate()
	var remaining := GridSpec.all_cells().filter(func(cell): return not CENTER_CELLS.has(cell))
	# Seeded order inside each distance band keeps central tiles preferred.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp
	remaining.sort_custom(func(a, b): return GridSpec.manhattan(a, Vector2i(3, 3)) < GridSpec.manhattan(b, Vector2i(3, 3)))
	candidates.append_array(remaining)
	for cell in candidates:
		var index := GridSpec.index(cell)
		if mod_protected(map, cell) or required.has(cell) or terrain[index] != TerrainDB.PLAIN:
			continue
		if GridSpec.neighbors4(cell).any(func(near): return TerrainDB.blocks_move(terrain[GridSpec.index(near)])):
			continue
		terrain[index] = TerrainDB.ROCK_MOUNTAIN
		if _validate(terrain, required) and _nests_accessible(map, map.get("nest_cells", [])):
			map["obstacle_cells"].append(cell)
			remaining_count -= 1
			if remaining_count == 0:
				return
		else:
			terrain[index] = TerrainDB.PLAIN


static func _add_electric_flowers(map: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var flowers := {}
	map["electric_flowers"] = flowers
	var count := rng.randi_range(0, 2)
	if count == 0:
		return
	var required: Array = map.get("nest_cells", []).duplicate()
	required.append(map["reward_cell"])
	for pair in cfg.get("enemies", []):
		required.append(pair[1])
	var terrain: Array = map["terrain"]
	var candidates := GridSpec.all_cells().filter(func(cell):
		var base := int(terrain[GridSpec.index(cell)])
		return not mod_protected(map, cell) and not required.has(cell) and not TerrainDB.blocks_move(base) and not GridSpec.neighbors4(cell).any(
			func(near): return terrain[GridSpec.index(near)] == TerrainDB.ROCK_MOUNTAIN
		)
	)
	var blocked := terrain.duplicate()
	while flowers.size() < count and not candidates.is_empty():
		var cell: Vector2i = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var index := GridSpec.index(cell)
		blocked[index] = TerrainDB.OBSTACLE
		if _validate(blocked, required):
			flowers[cell] = true
		else:
			blocked[index] = terrain[index]


static func terrain_counts(map: Dictionary) -> Dictionary:
	var counts := {"water": 0, "grass": 0, "rock": 0, "steam": 0}
	for value in map.get("terrain", []):
		match int(value):
			TerrainDB.WATER: counts["water"] += 1
			TerrainDB.GRASS, TerrainDB.SHALLOW_GRASS: counts["grass"] += 1
			TerrainDB.OBSTACLE: counts["rock"] += 1
	counts["rock"] = maxi(0, int(counts["rock"]) - (map.get("chests", {}) as Dictionary).size())
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
		var candidate := generate(run_seed, battle_index, salt, [card_id], String(previous.get("theme_id", "")), (previous.get("nest_cells", [previous["nest_cell"]]) as Array).size())
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
	for cell in Balance.DEPLOY_AREA:
		protected[cell] = true
	for cell in enemy_cells:
		protected[cell] = true
	protected[nest_cell] = true
	var mountain_cell := Vector2i(-1, -1)
	if cfg.get("region", "") == "岩窟":
		var centers := CENTER_CELLS.filter(func(cell): return not protected.has(cell))
		if not centers.is_empty():
			mountain_cell = centers[rng.randi_range(0, centers.size() - 1)]
			protected[mountain_cell] = true
	_scatter(terrain, protected, rng, cfg, lethal_budget, environment_deck, mountain_cell)
	if GridSpec.is_inside(mountain_cell):
		terrain[GridSpec.index(mountain_cell)] = TerrainDB.ROCK_MOUNTAIN
	_convert_deep(terrain, protected, rng, lethal_budget)
	var reward := _pick_cell(rng, terrain, protected, func(cell: Vector2i) -> bool:
		return int(terrain[GridSpec.index(cell)]) == TerrainDB.PLAIN and cell.x >= 3
	)
	if reward == Vector2i(-1, -1):
		return {}
	protected[reward] = true
	var fruits: Array = []
	var required: Array = []
	required.append_array(enemy_cells)
	required.append(reward)
	required.append(nest_cell)
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
		"nest_exits": [],
		"reward_cell": reward,
		"fruit_cells": fruits,
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
		"deploy_area": Balance.DEPLOY_AREA.duplicate(),
		"lethal_count": lethal,
	}


static func _scatter(terrain: Array, protected: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, lethal_budget: int, deck: Array, mountain_cell: Vector2i) -> void:
	var weights: Dictionary = REGION_WEIGHTS.get(String(cfg.get("region", "草原")), REGION_WEIGHTS["草原"]).duplicate()
	var fire_valley := String(cfg.get("region", "")) == "火谷"
	var card_weights := MapCardDB.weights(deck)
	for key in ["water", "grass", "rock"]:
		weights[key] = int(weights.get(key, 0)) + int(card_weights.get(key, 0))
	var water_clump := (5 if fire_valley else 12) + (12 if deck.has("water") and deck.has("rock") else 0) + (20 if deck.has("water") and deck.has("electric") else 0)
	for cell in GridSpec.all_cells():
		if protected.has(cell):
			continue
		var local: Dictionary = weights.duplicate()
		if cell.x >= 2 and cell.x <= 5 and cell.y >= 2 and cell.y <= 5:
			local["grass"] = int(local["grass"]) + (4 if fire_valley else 12)
		if _adjacent_water(terrain, cell):
			local["water"] = int(local["water"]) + water_clump
			if deck.has("water") and deck.has("rock"):
				local["rock"] = int(local["rock"]) + 12
		if GridSpec.is_inside(mountain_cell) and GridSpec.manhattan(cell, mountain_cell) == 1:
			local["rock"] = 0
			local["plant"] = 0
		match _weighted_pick(local, rng):
			"water": terrain[GridSpec.index(cell)] = TerrainDB.WATER
			"fragile": terrain[GridSpec.index(cell)] = TerrainDB.FRAGILE
			"rock": terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
			"plant": terrain[GridSpec.index(cell)] = TerrainDB.TREE
			"grass": terrain[GridSpec.index(cell)] = generated_grass(rng.seed, cell)
			"blue_fire": terrain[GridSpec.index(cell)] = TerrainDB.BLUE_FIRE
	# 致死地形仍服从各场预算，不能因恢复旧版密度堵死通路。
	if lethal_budget > 0 and String(cfg.get("region", "")) == "火谷":
		for _n in mini(2, lethal_budget):
			_place_single(terrain, protected, rng, TerrainDB.LAVA, 1, true)


static func _adjacent_water(terrain: Array, cell: Vector2i) -> bool:
	for near in GridSpec.neighbors4(cell):
		if TerrainDB.is_water_body(int(terrain[GridSpec.index(near)])):
			return true
	return false


static func generated_grass(seed_value: int, cell: Vector2i) -> int:
	# Keep the grass roll separate from the map RNG sequence.
	var roll := posmod(hash("%d:%d:%d" % [seed_value, cell.x, cell.y]), 3)
	return TerrainDB.GRASS if roll == 0 else TerrainDB.SHALLOW_GRASS


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for key in WEIGHT_ORDER:
		total += int(weights.get(key, 0))
	var roll := rng.randi_range(1, total)
	for key in WEIGHT_ORDER:
		roll -= int(weights.get(key, 0))
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
	for cell in Balance.DEPLOY_AREA:
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
	for deploy in Balance.DEPLOY_AREA:
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
		"nest_exits": [],
		"reward_cell": reward,
		"fruit_cells": [],
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
		"deploy_area": Balance.DEPLOY_AREA.duplicate(),
		"lethal_count": 0,
		"region": String(cfg.get("region", "?")),
		"battle_index": 0,
		"attempt": 99,
	}


static func mod_protected(map: Dictionary, cell: Vector2i) -> bool:
	if map.get("electric_flowers", {}).has(cell):
		return true
	var protected_cells: Array = []
	protected_cells.append_array(map.get("deploy_area", Balance.DEPLOY_AREA))
	protected_cells.append_array(map.get("nest_cells", [map["nest_cell"]]))
	protected_cells.append(map["reward_cell"])
	protected_cells.append_array(map.get("chests", {}).keys())
	protected_cells.append_array(map.get("fruit_cells", []))
	return protected_cells.has(cell)


static func apply_modification(map: Dictionary, cell: Vector2i, kind: String) -> bool:
	if not GridSpec.is_inside(cell) or mod_protected(map, cell):
		return false
	var terrain: Array = map["terrain"]
	var value := int(terrain[GridSpec.index(cell)])
	match kind:
		"water":
			if value not in [TerrainDB.PLAIN, TerrainDB.ICE, TerrainDB.SHALLOW_GRASS, TerrainDB.BLUE_FIRE]:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.water_result(value)
		"grass":
			if value not in [TerrainDB.PLAIN, TerrainDB.ICE]:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.GRASS
		"rock":
			if value not in [TerrainDB.PLAIN, TerrainDB.ICE]:
				return false
			terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
			(map["obstacle_cells"] as Array).append(cell)
		"clear":
			if not TerrainDB.blocks_move(value) or value == TerrainDB.ROCK_MOUNTAIN:
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


static func randomize_nests(map: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> bool:
	var blocked: Array = [map["reward_cell"]]
	for pair in cfg.get("enemies", []):
		blocked.append(pair[1])
	var candidates: Array = []
	for cell in GridSpec.all_cells():
		if cell.x < GridSpec.W / 2 or blocked.has(cell) or _near_deploy(cell, 2) or int(map["terrain"][GridSpec.index(cell)]) != TerrainDB.PLAIN:
			continue
		if _validate(map["terrain"], [cell]):
			candidates.append(cell)
	var selected: Array = []
	while not candidates.is_empty() and selected.size() < int(cfg.get("nest_count", 1)):
		var index := rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates.pop_at(index)
		if selected.any(func(other): return GridSpec.manhattan(cell, other) < 3):
			continue
		if not _nests_accessible(map, selected + [cell]):
			continue
		selected.append(cell)
	if selected.size() != int(cfg.get("nest_count", 1)):
		return false
	map["nest_cells"] = selected
	if not selected.is_empty():
		map["nest_cell"] = selected[0]
	return true


static func _has_landscape_pair(terrain: Array) -> bool:
	for cell in GridSpec.all_cells():
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: Vector2i = cell + direction
			if GridSpec.is_inside(other) and int(terrain[GridSpec.index(cell)]) != TerrainDB.PLAIN and terrain[GridSpec.index(cell)] == terrain[GridSpec.index(other)]:
				return true
	return false


static func _nests_accessible(map: Dictionary, cells: Array) -> bool:
	var blocked: Array = map["terrain"].duplicate()
	for cell in map.get("electric_flowers", {}):
		blocked[GridSpec.index(cell)] = TerrainDB.OBSTACLE
	for cell in cells:
		blocked[GridSpec.index(cell)] = TerrainDB.OBSTACLE
	for cell in cells:
		var accessible := false
		for near in GridSpec.neighbors4(cell):
			if TerrainDB.can_stand(int(blocked[GridSpec.index(near)]), "rock") and _validate(blocked, [near]):
				accessible = true
				break
		if not accessible:
			return false
	return true


static func populate_treasure(map: Dictionary, cfg: Dictionary, seed_value: int, battle_index: int, mode: String, node_id: String = "") -> void:
	if bool(map.get("treasure_generated", false)):
		return
	map["treasure_generated"] = true
	map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1), "owner_uid": -1, "guard_uid": -1}
	map["extra_rewards"] = []
	map["chests"] = {}
	map["carrier_uid"] = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("treasure:%d:%d:%s" % [seed_value, battle_index, node_id])
	var enemies: Array = cfg.get("enemies", []) if mode != "event" else []
	var eligible: Array = []
	for index in range(enemies.size()):
		if index != int(cfg.get("boss_index", -1)):
			eligible.append(index)
	while not eligible.is_empty():
		var index: int = eligible.pop_at(rng.randi_range(0, eligible.size() - 1))
		if rng.randf() < Balance.REWARD_CARRIER_CHANCE:
			map["carrier_uid"] = 100 + index
			break
	if rng.randf() >= (Balance.CHEST_EVENT_CHANCE if mode == "event" else Balance.CHEST_BATTLE_CHANCE):
		return
	var count := 2 if rng.randf() < Balance.CHEST_DOUBLE_CHANCE else 1
	var cells: Array = []
	for cell in GridSpec.all_cells():
		if map.get("electric_flowers", {}).has(cell) or int(map["terrain"][GridSpec.index(cell)]) != TerrainDB.PLAIN or (map.get("deploy_area", Balance.DEPLOY_AREA) as Array).has(cell) or cell == map.get("merchant_cell", Vector2i(-1, -1)) or cell == map.get("portal_cell", Vector2i(-1, -1)):
			continue
		if (map.get("nest_cells", [map["nest_cell"]]) as Array).has(cell) or enemies.any(func(pair): return pair[1] == cell):
			continue
		cells.append(cell)
	while not cells.is_empty() and map["chests"].size() < count:
		var cell: Vector2i = cells.pop_at(rng.randi_range(0, cells.size() - 1))
		var blockers: Array = map.get("nest_cells", [map["nest_cell"]]).duplicate() if mode != "event" else []
		blockers.append_array(map["chests"].keys())
		blockers.append(cell)
		if not _nests_accessible(map, blockers):
			continue
		map["chests"][cell] = 1
		map["terrain"][GridSpec.index(cell)] = TerrainDB.OBSTACLE
		(map["obstacle_cells"] as Array).append(cell)
