class_name MapGenerator
extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const Cards = preload("res://scripts/environment_card_system.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const SPAWNS: Array[Vector2i] = [Vector2i(1, 3), Vector2i(1, 2), Vector2i(1, 4), Vector2i(2, 3), Vector2i(6, 2), Vector2i(6, 5), Vector2i(6, 3)]
const NEST_CELLS: Array[Vector2i] = [Vector2i(7, 1), Vector2i(7, 6), Vector2i(6, 0), Vector2i(6, 7)]
const REGIONS: Dictionary = {
	"wetland": {"name": "湿地", "weights": {"ground": 49, "water": 22, "fragile": 5, "rock": 8, "plant": 10, "grass": 6}},
	"forest": {"name": "森林", "weights": {"ground": 42, "water": 8, "fragile": 4, "rock": 8, "plant": 22, "grass": 16}},
	"ruins": {"name": "遗迹", "weights": {"ground": 52, "water": 8, "fragile": 8, "rock": 20, "plant": 8, "grass": 4}},
}
const REGION_ORDER: Array[String] = ["wetland", "forest", "ruins"]


static func region_for_battle(battle_count: int) -> String:
	return REGION_ORDER[ battle_count % REGION_ORDER.size() ]


static func generate(region_id: String, deck: Array[String], seed_value: int) -> Dictionary:
	var region: Dictionary = REGIONS.get(region_id, REGIONS["wetland"])
	var weights: Dictionary = region["weights"].duplicate(true)
	for card_id in deck:
		var card: Dictionary = Cards.CARDS.get(card_id, {})
		for terrain_type in card.get("weights", {}).keys():
			weights[terrain_type] = int(weights.get(terrain_type, 0)) + int(card["weights"][terrain_type])
	var elements: Dictionary = Cards.deck_elements(deck)
	var combinations: Array[String] = []
	var water_clump_bonus := 12
	var rock_water_bonus := 0
	var steam_chance := 0.02
	if elements.has("water") and elements.has("rock"):
		combinations.append("水+岩：水道与岩障更容易相邻")
		water_clump_bonus += 12
		rock_water_bonus = 12
	if elements.has("water") and elements.has("electric"):
		combinations.append("水+电：连通水域更容易形成")
		water_clump_bonus += 20
	if elements.has("water") and elements.has("fire"):
		combinations.append("水+火：雾出现率提高")
		steam_chance = 0.20 if deck.has("steam_focus") else 0.11
	var rng := RandomNumberGenerator.new()
	for attempt in 12:
		rng.seed = seed_value + attempt * 104729
		var layout := {"ground": {}, "objects": {}, "steam": {}}
		var nest_cell: Vector2i = NEST_CELLS[rng.randi_range(0, NEST_CELLS.size() - 1)]
		var exit_cell: Vector2i = nest_cell + Vector2i.LEFT
		layout["nest"] = {"cell": nest_cell, "exit": exit_cell, "hp": CombatConfig.NEST_HP}
		for y in GridSpec.HEIGHT:
			for x in GridSpec.WIDTH:
				var cell := Vector2i(x, y)
				if SPAWNS.has(cell) or cell == nest_cell or cell == exit_cell:
					continue
				var local_weights: Dictionary = weights.duplicate()
				if x >= 2 and x <= 5 and y >= 2 and y <= 5:
					local_weights["grass"] += 12
				if _adjacent_water(layout["ground"], cell):
					local_weights["water"] += water_clump_bonus
					local_weights["rock"] += rock_water_bonus
				var choice := _weighted_pick(local_weights, rng)
				if choice == "water":
					layout["ground"][cell] = "deep_water" if rng.randf() < CombatConfig.DEEP_WATER_CHANCE else "shallow_water"
				elif choice == "fragile" or choice == "grass":
					layout["ground"][cell] = choice
				elif choice == "rock":
					layout["objects"][cell] = TerrainManager.make_rock()
				elif choice == "plant":
					layout["objects"][cell] = TerrainManager.make_plant()
		for cell in layout["ground"].keys():
			if layout["ground"][cell] in ["shallow_water", "deep_water"] and rng.randf() < steam_chance:
				layout["steam"][cell] = 2
		if is_playable(layout):
			var reached: Dictionary = _reachable(layout)
			var item_candidates: Array[Vector2i] = []
			for y in range(1, 7):
				for x in range(2, 6):
					var cell := Vector2i(x, y)
					if reached.has(cell) and layout["ground"].get(cell, "ground") in ["ground", "grass", "shallow_water"] and not layout["objects"].has(cell) and not SPAWNS.has(cell):
						item_candidates.append(cell)
			if item_candidates.is_empty():
				continue
			layout["reward"] = {"cell": item_candidates[rng.randi_range(0, item_candidates.size() - 1)]}
			layout["info"] = _info(region_id, deck, combinations, layout, false)
			return layout
	var fallback := {"ground": {Vector2i(3, 2): "shallow_water", Vector2i(4, 2): "shallow_water", Vector2i(4, 4): "grass"}, "objects": {Vector2i(5, 4): TerrainManager.make_plant()}, "steam": {}, "nest": {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": CombatConfig.NEST_HP}, "reward": {"cell": Vector2i(3, 4)}}
	fallback["info"] = _info(region_id, deck, combinations, fallback, true)
	return fallback


static func is_playable(layout: Dictionary) -> bool:
	var ground: Dictionary = layout.get("ground", {})
	var objects: Dictionary = layout.get("objects", {})
	var nest: Dictionary = layout.get("nest", {})
	for spawn in SPAWNS:
		if ground.get(spawn, "ground") in ["fragile", "collapsed", "deep_water"] or objects.has(spawn) or nest.get("cell", Vector2i(-1, -1)) == spawn:
			return false
	if not nest.is_empty():
		for cell in [nest["cell"], nest["exit"]]:
			if not GridSpec.is_inside(cell) or ground.get(cell, "ground") in ["fragile", "collapsed", "deep_water"] or objects.has(cell) or SPAWNS.has(cell):
				return false
	var reached: Dictionary = _reachable(layout)
	for spawn in SPAWNS:
		if not reached.has(spawn):
			return false
	if not nest.is_empty() and not reached.has(nest["exit"]):
		return false
	var reward: Dictionary = layout.get("reward", {})
	if not reward.is_empty() and (not reached.has(reward["cell"]) or ground.get(reward["cell"], "ground") in ["fragile", "collapsed", "deep_water"] or objects.has(reward["cell"]) or SPAWNS.has(reward["cell"])):
		return false
	return true


static func _reachable(layout: Dictionary) -> Dictionary:
	var ground: Dictionary = layout.get("ground", {})
	var objects: Dictionary = layout.get("objects", {})
	var nest: Dictionary = layout.get("nest", {})
	var reached: Dictionary = {SPAWNS[0]: true}
	var queue: Array[Vector2i] = [SPAWNS[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next_cell: Vector2i = cell + direction
			if not GridSpec.is_inside(next_cell) or reached.has(next_cell) or objects.has(next_cell) or ground.get(next_cell, "ground") in ["fragile", "collapsed", "deep_water"] or nest.get("cell", Vector2i(-1, -1)) == next_cell:
				continue
			reached[next_cell] = true
			queue.append(next_cell)
	return reached


static func _adjacent_water(ground: Dictionary, cell: Vector2i) -> bool:
	for direction in DIRECTIONS:
		if ground.get(cell + direction, "") in ["shallow_water", "deep_water", "water"]:
			return true
	return false


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for key in ["ground", "water", "fragile", "rock", "plant", "grass"]:
		total += int(weights[key])
	var roll := rng.randi_range(1, total)
	for key in ["ground", "water", "fragile", "rock", "plant", "grass"]:
		roll -= int(weights[key])
		if roll <= 0:
			return key
	return "ground"


static func _info(region_id: String, deck: Array[String], combinations: Array[String], layout: Dictionary, fallback: bool) -> Dictionary:
	var ground: Dictionary = layout["ground"]
	var objects: Dictionary = layout["objects"]
	var counts := {"water": 0, "shallow_water": 0, "deep_water": 0, "grass": 0, "fragile": 0, "rock": 0, "plant": 0, "steam": layout["steam"].size()}
	for kind in ground.values():
		counts[kind] += 1
		if kind in ["shallow_water", "deep_water"]:
			counts["water"] += 1
	for object in objects.values():
		counts[object["type"]] += 1
	return {"region_id": region_id, "region_name": REGIONS[region_id]["name"], "cards": deck.duplicate(), "combinations": combinations, "counts": counts, "fallback": fallback}
