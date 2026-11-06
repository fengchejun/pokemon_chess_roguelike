extends RefCounted

const ACTIONS := Balance.EXPLORATION_ACTIONS
const POSITIONS := {"battle_1": Vector2i(0, 0), "battle_2": Vector2i(1, 0), "event_2": Vector2i(2, 0), "empty_1": Vector2i(3, 0), "empty_2": Vector2i(0, 1), "event_1": Vector2i(1, 1), "boss": Vector2i(2, 1), "battle_3": Vector2i(3, 1), "camp": Vector2i(0, 2), "battle_5": Vector2i(1, 2), "battle_4": Vector2i(2, 2), "empty_3": Vector2i(3, 2), "empty_4": Vector2i(0, 3), "capture_3": Vector2i(1, 3), "group_2": Vector2i(2, 3), "empty_5": Vector2i(3, 3)}
const ROLES := {"camp": "camp", "battle_1": "starter", "battle_2": "capture", "event_2": "shop", "boss": "boss", "battle_3": "capture", "event_1": "group", "battle_5": "request", "battle_4": "treasure", "empty_1": "empty", "empty_2": "empty", "empty_3": "empty", "empty_4": "empty", "empty_5": "empty", "capture_3": "capture", "group_2": "group"}
const NAMES := {"camp": "营地", "starter": "林缘试炼", "capture": "野生栖息地", "shop": "旅行商店", "boss": "本层首领", "group": "嬉戏的宝可梦", "request": "训练家的委托", "treasure": "隔水藏珍", "hunt": "追猎", "empty": "林间空地"}

static func active(run: RunState) -> bool:
	return bool(run.options.get("exploration_v2", false)) and run.floor_index() == 0

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

static func role(run: RunState) -> String:
	var region = run.get_region()
	return String(region.nodes[region.active_node].get("role", ""))

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
	var count := rng.randi_range(1, 3) if kind == "capture" else 2 if kind in ["starter", "group"] else 4 if kind == "hunt" else 3
	var pairs: Array = []
	for index in count:
		pairs.append([pool[rng.randi_range(0, pool.size() - 1)], Vector2i(5 + index % 2, 2 + index)])
	if kind in ["boss", "hunt"]:
		pairs[0][0] = "rock_wild1"
	result["enemies"] = [] if kind in ["treasure", "camp", "shop", "request"] or (kind == "group" and not bool(node.get("battle_selected", false))) else pairs
	result["reinforce"] = pool if kind in ["boss", "hunt"] else []
	result["boss_index"] = 0 if kind in ["boss", "hunt"] else -1
	result["corrupted"] = kind == "hunt"
	result["enemy_level_bonus"] = 1 if kind == "hunt" else 0
	return result

static func prepare_map(run: RunState, map: Dictionary) -> void:
	var kind := role(run)
	if kind not in ["boss", "hunt"]:
		map["nests"] = []
		map["nest_cells"] = []
		map["nest_cell"] = Vector2i(-1, -1)
		map["nest_alive"] = false
	if kind == "treasure":
		var terrain: Array = []
		for cell in GridSpec.all_cells():
			terrain.append(TerrainDB.DEEP if cell.x == 3 else TerrainDB.PLAIN)
		map["terrain"] = terrain
		map["chests"] = {Vector2i(6, 3): true}
		map["obstacle_cells"] = [Vector2i(5, 3), Vector2i(6, 2)]
		for obstacle in map["obstacle_cells"]:
			terrain[GridSpec.index(obstacle)] = TerrainDB.OBSTACLE
		map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1)}
		map["extra_rewards"] = []
		map["food_cells"] = []
		map["treasure_generated"] = true
		map["deploy_area"] = Balance.DEPLOY_AREA.duplicate()
	if kind == "capture":
		map["fixed_deploy_area"] = [Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 2)]
	if kind in ["capture", "starter", "group"]:
		# 先用开阔地形验证捕捉/首战节奏，不叠加致死地形和巢穴压力。
		map["terrain"] = []
		for cell in GridSpec.all_cells():
			map["terrain"].append(TerrainDB.GRASS if cell.x >= 6 and cell.y % 2 == 0 else TerrainDB.PLAIN)
		map["obstacle_cells"] = []
		map["chests"] = {}
		map["extra_rewards"] = []
		map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1)}
		map["food_cells"] = []
		map["treasure_generated"] = true

static func prepare_state(run: RunState, state: BattleState) -> void:
	state.exploration_v2 = true
	state.exploration_role = role(run)
	if state.exploration_role == "treasure":
		state.preserve_node_terrain = true
		state.node_kind = "event"
	if state.exploration_role not in ["boss", "hunt"]:
		state.stop_nests()
	if state.exploration_role == "capture":
		state.capture_deadline = Balance.CAPTURE_ENCOUNTER_ROUNDS
	if state.exploration_role == "starter":
		for enemy in state.alive_units("enemy"):
			enemy.max_hp = 16
			enemy.hp = 16
			enemy.skills = enemy.skills.slice(0, 1)
			enemy.upgrades = {}
	if state.exploration_role == "hunt":
		state.corruption_active = true
		for enemy in state.alive_units("enemy"):
			enemy.set_corrupted(true)
