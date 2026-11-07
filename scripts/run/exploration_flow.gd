extends RefCounted

const EVENT_NODES := {"group": "event_1", "request": "battle_5"}
const MAX_EVENTS := 3
const ACTIONS := Balance.EXPLORATION_ACTIONS
const POSITIONS := {"battle_1": Vector2i(0, 0), "battle_2": Vector2i(1, 0), "event_2": Vector2i(2, 0), "empty_1": Vector2i(3, 0), "empty_2": Vector2i(0, 1), "event_1": Vector2i(1, 1), "boss": Vector2i(2, 1), "battle_3": Vector2i(3, 1), "camp": Vector2i(0, 2), "battle_5": Vector2i(1, 2), "battle_4": Vector2i(2, 2), "empty_3": Vector2i(3, 2), "empty_4": Vector2i(0, 3), "capture_3": Vector2i(1, 3), "group_2": Vector2i(2, 3), "empty_5": Vector2i(3, 3)}
const ROLES := {"camp": "camp", "battle_1": "starter", "battle_2": "capture", "event_2": "shop", "boss": "boss", "battle_3": "capture", "event_1": "group", "battle_5": "request", "battle_4": "treasure", "empty_1": "empty", "empty_2": "empty", "empty_3": "empty", "empty_4": "empty", "empty_5": "empty", "capture_3": "capture", "group_2": "group"}
const RARE_HABITAT := "rare_habitat"
const RARE_SPECIES := ["torkoal", "cloyster", "ampharos"]
const NAMES := {"camp": "营地", "starter": "林缘试炼", "battle": "普通战斗", "elite": "精英战斗", "item_shop": "道具商店", "skill_shop": "技能商店", "capture": "野生栖息地", "shop": "旅行商店", "boss": "本层首领", "group": "嬉戏的宝可梦", "request": "训练家的委托", "treasure": "隔水藏珍", "hunt": "追猎", "empty": "林间空地"}

static func active(run: RunState) -> bool:
	return bool(run.options.get("exploration_v2", false))

# Original prototype layout retained for regression fixtures and legacy coordinates.
static func create(floor_value: int, theme: String) -> RegionState:
	var region := RegionState.new()
	region.floor_index = floor_value
	region.theme = theme
	region.flow_version = 2
	region.active_node = "camp"
	for id in POSITIONS:
		var role: String = ROLES[id]
		region.nodes[id] = {"type": "boss" if role == "boss" else "camp" if role == "camp" else "battle" if role in ["starter", "capture"] else "event", "mode": "boss" if role == "boss" else "camp" if role == "camp" else "battle" if role in ["starter", "capture"] else "event", "role": role, "visits": 1 if id == "camp" else 0, "revealed": id in ["camp", "boss"], "unlocked": id == "camp", "passable": id == "camp", "cleared": false, "done": false, "snapshot": {}, "links": [], "pending_garrison": false, "pending_replenish": false}
	for pair in [["camp", "empty_2"], ["empty_2", "battle_1"], ["battle_1", "battle_2"], ["battle_2", "event_2"], ["event_2", "empty_1"], ["empty_1", "battle_3"], ["battle_3", "boss"], ["camp", "empty_4"], ["empty_4", "capture_3"], ["capture_3", "group_2"], ["group_2", "empty_5"], ["empty_5", "empty_3"], ["empty_3", "battle_4"], ["battle_4", "battle_5"], ["battle_5", "event_1"], ["event_1", "empty_2"], ["camp", "battle_5"], ["battle_4", "boss"]]:
		region.nodes[pair[0]]["links"].append(pair[1])
		region.nodes[pair[1]]["links"].append(pair[0])
	region.unlock_neighbors("camp")
	return region

static func generate(floor_value: int, theme: String, run_seed: int) -> RegionState:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("region:%d:%d" % [run_seed, floor_value])
	var region := RegionState.new()
	region.floor_index = floor_value
	region.theme = theme
	region.flow_version = 2
	region.active_node = "camp"
	var centers := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]
	var boss_cell: Vector2i = centers[rng.randi_range(0, centers.size() - 1)]
	var edge: Array = []
	for y in 4:
		for x in 4:
			if x in [0, 3] or y in [0, 3]:
				edge.append(Vector2i(x, y))
	var camp_cell: Vector2i = edge[rng.randi_range(0, edge.size() - 1)]
	var cells := [camp_cell]
	var target_count := rng.randi_range(14, 15)
	# Grow a connected set while reserving the center boss cell.
	while cells.size() < target_count - 1:
		var frontier: Array = []
		for cell in cells:
			for next in adjacent_cells(cell):
				if next != boss_cell and not cells.has(next) and not frontier.has(next):
					frontier.append(next)
		cells.append(frontier[rng.randi_range(0, frontier.size() - 1)])
	var links := {camp_cell: []}
	var queue := [camp_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var neighbors := adjacent_cells(cell)
		while not neighbors.is_empty():
			var next: Vector2i = neighbors.pop_at(rng.randi_range(0, neighbors.size() - 1))
			if cells.has(next) and not links.has(next):
				links[next] = [cell]
				links[cell].append(next)
				queue.append(next)
	# A reachable boss entrance cannot depend on completing a commission.
	var first_battle_cell: Vector2i = links[camp_cell][0]
	var leaves := cells.filter(func(cell): return cell != camp_cell and cell != first_battle_cell and links[cell].size() == 1)
	var request_cell: Vector2i = leaves[rng.randi_range(0, leaves.size() - 1)]
	var boss_neighbors := adjacent_cells(boss_cell).filter(func(cell): return links.has(cell) and cell != request_cell)
	var entrance: Vector2i = boss_neighbors[rng.randi_range(0, boss_neighbors.size() - 1)]
	links[boss_cell] = [entrance]
	links[entrance].append(boss_cell)
	var spare_edges: Array = []
	for cell in cells:
		for next in adjacent_cells(cell):
			if links.has(next) and next != boss_cell and not links[cell].has(next) and (cell.y * 4 + cell.x) < (next.y * 4 + next.x):
				spare_edges.append([cell, next])
	for i in mini(rng.randi_range(2, 4), spare_edges.size()):
		var pair: Array = spare_edges.pop_at(rng.randi_range(0, spare_edges.size() - 1))
		links[pair[0]].append(pair[1])
		links[pair[1]].append(pair[0])
	var roles := {"battle_1": "battle", "battle_2": "capture", "elite_1": "elite",
		"event_2": "item_shop", "shop_2": "skill_shop", "battle_4": "treasure",
		"camp": "camp", "boss": "boss", "battle_5": "request"}
	var ids := ["battle_2", "elite_1", "event_2", "shop_2", "battle_4"]
	var event_types := EVENT_NODES.keys()
	event_types.erase("request")
	for index in mini(MAX_EVENTS - 1, event_types.size()):
		var event_type: String = event_types.pop_at(rng.randi_range(0, event_types.size() - 1))
		var event_id: String = EVENT_NODES[event_type]
		roles[event_id] = event_type
		ids.append(event_id)
	for index in target_count - 4 - ids.size():
		var combat_id := "combat_%d" % (index + 1)
		ids.append(combat_id)
		roles[combat_id] = "battle"
	var by_cell := {camp_cell: "camp", boss_cell: "boss", first_battle_cell: "battle_1", request_cell: "battle_5"}
	for cell in cells:
		if not by_cell.has(cell):
			by_cell[cell] = ids.pop_at(rng.randi_range(0, ids.size() - 1))
	for cell in by_cell:
		var id: String = by_cell[cell]
		var kind: String = roles[id]
		var type := "event"
		if kind in ["camp", "boss"]:
			type = kind
		elif kind in ["battle", "elite", "capture"]:
			type = "battle"
		region.nodes[id] = {
			"type": type, "mode": type, "role": kind, "position": [cell.x, cell.y],
			"visits": 1 if id == "camp" else 0, "revealed": id in ["camp", "boss"],
			"unlocked": id == "camp", "passable": id == "camp", "cleared": false,
			"done": false, "snapshot": {}, "links": links[cell].map(func(next): return by_cell[next]),
			"pending_garrison": false, "pending_replenish": false,
		}
	region.nodes["battle_5"]["commission"] = commission(run_seed, floor_value, theme)
	region.nodes["battle_4"]["puzzle"] = posmod(hash("puzzle:%d" % run_seed) + floor_value, 4)
	region.unlock_neighbors("camp")
	return region

static func adjacent_cells(cell: Vector2i) -> Array:
	var result: Array = []
	for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var next: Vector2i = cell + step
		if next.x in range(4) and next.y in range(4):
			result.append(next)
	return result

static func position(id: String, node: Dictionary) -> Vector2i:
	var coords: Array = node.get("position", [])
	if coords.size() == 2:
		return Vector2i(int(coords[0]), int(coords[1]))
	return POSITIONS.get(id, Vector2i(-1, -1))

static func _rare_habitat_site(region: RegionState) -> Array:
	var occupied := {}
	for id in region.nodes:
		occupied[position(id, region.nodes[id])] = id
	var shop := position(region.active_node, region.nodes[region.active_node])
	var site := []
	var closest := 1 << 30
	for y in 4:
		for x in 4:
			var cell := Vector2i(x, y)
			if occupied.has(cell):
				continue
			for near in adjacent_cells(cell):
				var anchor := String(occupied.get(near, ""))
				if anchor in ["", "boss", "hunt"]:
					continue
				var distance := GridSpec.manhattan(near, shop)
				if distance < closest:
					closest = distance
					site = [cell, anchor]
	return site


static func intel_unavailable(region: RegionState) -> String:
	if region.nodes.has(RARE_HABITAT):
		return "本层已解锁过神秘栖息地。"
	if region.visits >= Balance.EXPLORATION_ACTIONS:
		return "本层行动已耗尽，无法前往神秘栖息地。"
	if _rare_habitat_site(region).is_empty():
		return "本层地图没有可以连接的空位。"
	return ""


static func unlock_rare_habitat(region: RegionState, run_seed: int) -> bool:
	if not intel_unavailable(region).is_empty():
		return false
	var site := _rare_habitat_site(region)
	var cell: Vector2i = site[0]
	var anchor: String = site[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rare-habitat:%d:%d" % [run_seed, region.floor_index])
	region.nodes[RARE_HABITAT] = {
		"type": "battle", "mode": "battle", "role": "capture", "position": [cell.x, cell.y],
		"rare_species": RARE_SPECIES[rng.randi_range(0, RARE_SPECIES.size() - 1)],
		"visits": 0, "revealed": true, "unlocked": true, "passable": false,
		"cleared": false, "done": false, "snapshot": {}, "links": [anchor],
	}
	region.nodes[anchor]["links"].append(RARE_HABITAT)
	return true


static func commission(run_seed: int, floor_value: int, theme: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("commission:%d:%d" % [run_seed, floor_value])
	var tier := rng.randi_range(1, 3)
	var primary: Array = BattleDB.THEMES.get(theme, BattleDB.THEMES["grass"])["primary"]
	var species := String(primary[rng.randi_range(0, primary.size() - 1)])
	var element := SpeciesDB.element_of(species)
	var skill := ""
	if tier == 3:
		var base := SpeciesDB.skills_of(species)
		var candidates := SkillDB.learnable_ids_for(element).filter(func(id): return not base.has(id) and not SkillDB.is_special(id))
		if candidates.is_empty():
			candidates = base
		skill = candidates[rng.randi_range(0, candidates.size() - 1)]
	return {"tier": tier, "species": species, "element": element, "skill": skill}

static func request_terms(node: Dictionary, theme: String) -> Dictionary:
	return node.get("commission", {"tier": 2, "species": request_species(theme), "skill": ""})

static func request_matches(terms: Dictionary, member: Dictionary) -> bool:
	var species := String(member["species_id"])
	if int(terms["tier"]) == 1:
		return SpeciesDB.element_of(species) == terms["element"]
	if species != terms["species"]:
		return false
	return int(terms["tier"]) != 3 or member.get("equipped_skills", []).has(terms["skill"])

static func request_description(terms: Dictionary) -> String:
	var tier := int(terms["tier"])
	if tier == 1:
		return "一档 · 任意%s系宝可梦" % Elements.name_of(terms["element"])
	var species := SpeciesDB.name_of(terms["species"])
	if tier == 2:
		return "二档 · %s" % species
	return "三档 · 携带「%s」的%s" % [SkillDB.name_of(terms["skill"]), species]

static func role(run: RunState) -> String:
	var region = run.get_region()
	return String(region.nodes[region.active_node].get("role", ""))

static func request_species(theme: String) -> String:
	return String(BattleDB.THEMES.get(theme, BattleDB.THEMES["grass"])["primary"][0])

static func configure(run: RunState, cfg: Dictionary) -> Dictionary:
	var result := cfg.duplicate(true)
	var region = run.get_region()
	var node: Dictionary = region.nodes[region.active_node]
	var kind := String(node.get("role", ""))
	var visit := int(node["visits"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("encounter:%d:%s:%d" % [run.seed, region.active_node, visit])
	var pool: Array = BattleDB.THEMES.get(region.theme, BattleDB.THEMES["grass"])["primary"].duplicate()
	pool.append_array(["water_wild1", "electric_wild1", "grass_wild1", "rock_wild1"])
	var count := 3
	if kind in ["starter", "battle", "elite"]:
		count += region.floor_index
	elif kind == "group":
		count = 2
	elif kind == "hunt":
		count = 4
	var pairs: Array = []
	for index in count:
		pairs.append([pool[rng.randi_range(0, pool.size() - 1)], Vector2i(5 + index % 2, 2 + index)])
	if region.active_node == RARE_HABITAT:
		pairs = [[node["rare_species"], Vector2i(5, 2)]]
	elif kind in ["boss", "hunt"]:
		pairs[0][0] = "rock_wild1"
	result["enemies"] = [] if kind in ["treasure", "camp", "shop", "item_shop", "skill_shop", "request"] or (kind == "group" and not bool(node.get("battle_selected", false))) else pairs
	result["reinforce"] = pool if kind in ["boss", "hunt"] else []
	result["boss_index"] = 0 if kind in ["boss", "hunt"] else -1
	result["corrupted"] = kind == "hunt"
	result["enemy_level_bonus"] = 1 if kind in ["hunt", "elite"] else 0
	return result

const PUZZLE_NAMES := ["隔水藏珍", "岩垒藏珍", "断崖藏珍", "熔沟藏珍"]
const PUZZLE_HINTS := [
	"深水横断棋盘。过河后，对宝箱四周的任一岩山施放两次碎岩即可打开通路。",
	"宝箱四周有岩障。先破开一个入口，再取走箱内奖励。",
	"两列深坑之间只留下一条易碎通路。留意技能落点，避免击碎脚下的路。",
	"熔沟间有两条通路。可绕行上侧，也可破开下侧岩门。",
]

static func puzzle_description(node: Dictionary) -> String:
	return PUZZLE_HINTS[int(node.get("puzzle", 0))] + " 可暂离，地形和损耗保留。"

static func puzzle_name(node: Dictionary) -> String:
	return PUZZLE_NAMES[int(node.get("puzzle", 0))]

static func prepare_map(run: RunState, map: Dictionary) -> void:
	var kind := role(run)
	if kind not in ["boss", "hunt"]:
		map["nests"] = []
		map["nest_cells"] = []
		map["nest_cell"] = Vector2i(-1, -1)
		map["nest_alive"] = false
	if kind == "treasure":
		var region = run.get_region()
		var variant := int(region.nodes[region.active_node].get("puzzle", 0))
		var terrain: Array = []
		terrain.resize(GridSpec.W * GridSpec.H)
		terrain.fill(TerrainDB.PLAIN)
		var obstacles: Array = []
		match variant:
			0:
				for y in GridSpec.H:
					terrain[GridSpec.index(Vector2i(3, y))] = TerrainDB.DEEP
				obstacles = GridSpec.neighbors4(Vector2i(6, 3))
			1:
				obstacles = GridSpec.neighbors4(Vector2i(6, 3))
				for y in [0, 1, 5, 6]:
					terrain[GridSpec.index(Vector2i(3, y))] = TerrainDB.TREE
			2:
				for y in GridSpec.H:
					for x in [3, 4]:
						terrain[GridSpec.index(Vector2i(x, y))] = TerrainDB.FRAGILE if y == 4 else TerrainDB.PIT
				terrain[GridSpec.index(Vector2i(5, 4))] = TerrainDB.ICE
			3:
				for y in GridSpec.H:
					if y in [1, 5]:
						continue
					for x in [3, 4]:
						terrain[GridSpec.index(Vector2i(x, y))] = TerrainDB.LAVA
				obstacles = [Vector2i(4, 5), Vector2i(5, 2)]
		for obstacle in obstacles:
			terrain[GridSpec.index(obstacle)] = TerrainDB.ROCK_MOUNTAIN if variant == 0 else TerrainDB.OBSTACLE
		map["terrain"] = terrain
		map["steam_cells"] = {}
		map["electric_flowers"] = {}
		map["chests"] = {Vector2i(6, 3): true}
		map["obstacle_cells"] = GridSpec.all_cells().filter(func(cell): return TerrainDB.blocks_move(terrain[GridSpec.index(cell)]))
		if variant == 0:
			decorate_terrain(run, map, kind)
		map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1)}
		map["extra_rewards"] = []
		map["food_cells"] = []
		map["treasure_generated"] = true
		map["deploy_area"] = Balance.DEPLOY_AREA.duplicate()
	if kind == "capture":
		map["fixed_deploy_area"] = Balance.DEPLOY_AREA.duplicate()
	if kind in ["starter", "battle", "elite", "group"]:
		# 普通遭遇保留原生成器的地形，只清除这类节点不提供的宝箱奖励。
		map["chests"] = {}
		map["extra_rewards"] = []
		map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1)}
		map["food_cells"] = []
		map["treasure_generated"] = true

	if kind == "capture":
		preload("res://scripts/rules/capture_encounter.gd").prepare_map(map)

static func decorate_terrain(run: RunState, map: Dictionary, kind: String) -> void:
	# 完整地形池按种子抽取；保护部署点、遭遇起点与谜题既有解法，不强求每图全类型。
	var reserved: Array = Balance.DEPLOY_AREA.duplicate()
	reserved.append_array(map.get("fixed_deploy_area", []))
	reserved.append_array(map.get("obstacle_cells", []))
	reserved.append_array(GridSpec.neighbors8(Vector2i(6, 3)))
	reserved.append_array([Vector2i(5, 2), Vector2i(6, 3), Vector2i(5, 4), Vector2i(5, 3), Vector2i(6, 4), Vector2i(7, 3)])
	for cell in GridSpec.all_cells():
		if kind == "treasure" and cell.x in [2, 3, 4]: reserved.append(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("landscape:%d:%s:%d" % [run.seed, run.get_region().active_node, run.get_region().nodes[run.get_region().active_node]["visits"]])
	var candidates: Array = GridSpec.all_cells().filter(func(cell): return not reserved.has(cell))
	var pool := TerrainDB.ALL.duplicate()
	pool.erase(TerrainDB.ROCK_MOUNTAIN)
	if run.current_theme() != "fire":
		pool.erase(TerrainDB.BLUE_FIRE)
	for index in mini(10, candidates.size()):
		var cell: Vector2i = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var terrain: int = pool[rng.randi_range(0, pool.size() - 1)]
		if terrain in [TerrainDB.SHALLOW_GRASS, TerrainDB.GRASS]:
			terrain = MapGenerator.generated_grass(rng.seed, cell)
		map["terrain"][GridSpec.index(cell)] = terrain
	# 清理生成器可能留在受保护遭遇格上的岩石/致死地形。
	for cell in map.get("fixed_deploy_area", []) + GridSpec.all_cells().filter(func(c): return kind == "treasure" and c.x in [2, 4]) + [Vector2i(5, 2), Vector2i(6, 3), Vector2i(5, 4)]:
		if not map.get("chests", {}).has(cell): map["terrain"][GridSpec.index(cell)] = TerrainDB.PLAIN
	map["obstacle_cells"] = GridSpec.all_cells().filter(func(cell): return TerrainDB.blocks_move(int(map["terrain"][GridSpec.index(cell)])))

static func prepare_state(run: RunState, state: BattleState) -> void:
	state.exploration_v2 = true
	state.exploration_role = role(run)
	state.retreat_disabled = state.is_boss_encounter()
	if state.exploration_role == "treasure":
		state.preserve_node_terrain = true
		state.node_kind = "event"
	if state.exploration_role not in ["boss", "hunt"]:
		state.stop_nests()
	if state.exploration_role == "capture":
		state.capture_deadline = Balance.CAPTURE_ENCOUNTER_ROUNDS
		state.capture_exits = preload("res://scripts/rules/capture_encounter.gd").EXITS.duplicate()
	if state.exploration_role == "starter" and run.floor_index() == 0:
		for enemy in state.alive_units("enemy"):
			enemy.max_hp = 16
			enemy.hp = 16
			enemy.skills = enemy.skills.slice(0, 1)
			enemy.upgrades = {}
	if state.exploration_role == "hunt":
		state.corruption_active = true
		for enemy in state.alive_units("enemy"):
			enemy.set_corrupted(true)
