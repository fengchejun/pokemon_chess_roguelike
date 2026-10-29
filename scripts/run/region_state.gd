class_name RegionState
extends RefCounted

## 区域节点的持久化账本。节点数量、连线和强化数值由流程配置提供。
const Snapshot = preload("res://scripts/run/battle_snapshot.gd")
const NODE_TYPES := ["camp", "battle", "event", "boss"]

var floor_index: int = 0
var theme: String = ""
var visits: int = 0
var active_node: String = ""
var nodes: Dictionary = {}


static func create_floor(floor_value: int, theme_value: String) -> RegionState:
	var specifications: Array = [{"id": "camp", "type": "camp"}, {"id": "event_1", "type": "event"}, {"id": "event_2", "type": "event"}, {"id": "boss", "type": "boss"}]
	for index in range(1, 6):
		specifications.append({"id": "battle_%d" % index, "type": "battle"})
	var region := create(floor_value, theme_value, specifications)
	var edges := [["camp", "battle_1"], ["camp", "event_1"], ["battle_1", "battle_2"], ["event_1", "battle_3"], ["battle_2", "event_2"], ["battle_3", "event_2"], ["event_2", "battle_4"], ["battle_3", "battle_5"], ["battle_4", "boss"], ["battle_5", "boss"]]
	for id in region.nodes:
		region.nodes[id]["unlocked"] = id == "camp"
		region.nodes[id]["links"] = []
	for edge in edges:
		region.nodes[edge[0]]["links"].append(edge[1])
		region.nodes[edge[1]]["links"].append(edge[0])
	return region


static func create(floor_value: int, theme_value: String, specifications: Array) -> RegionState:
	var region := RegionState.new()
	region.floor_index = floor_value
	region.theme = theme_value
	for specification in specifications:
		var id := String(specification.get("id", ""))
		var kind := String(specification.get("type", ""))
		if id == "" or region.nodes.has(id) or not NODE_TYPES.has(kind):
			return null
		region.nodes[id] = {"type": kind, "visits": 0, "cleared": false, "snapshot": {}}
	return region


func node_mode(id: String) -> String:
	if not nodes.has(id):
		return ""
	var node: Dictionary = nodes[id]
	if node["type"] == "battle" and bool(node["cleared"]):
		return "event"
	return String(node["type"])


func record_entry(id: String) -> bool:
	if not nodes.has(id):
		return false
	if not bool(nodes[id].get("unlocked", true)):
		return false
	if nodes[id]["type"] == "boss" and bool(nodes[id]["cleared"]):
		return false
	if nodes[id]["type"] != "boss":
		visits += 1
	nodes[id]["visits"] = int(nodes[id]["visits"]) + 1
	for neighbor in nodes[id].get("links", []):
		nodes[neighbor]["unlocked"] = true
	active_node = id
	return true


func store_battle(id: String, battle: BattleState) -> bool:
	if not nodes.has(id) or battle == null:
		return false
	var node: Dictionary = nodes[id]
	if not ["battle", "boss"].has(String(node["type"])):
		return false
	node["snapshot"] = Snapshot.save_state(battle)
	if node["type"] == "boss":
		var boss := battle.unit_by_uid(battle.boss_uid)
		node["cleared"] = boss != null and (not boss.is_alive() or boss.side == "player")
	else:
		node["cleared"] = battle.alive_enemy_count() == 0 and not bool(battle.nest.get("alive", false))
	return true


func load_battle(id: String) -> BattleState:
	if not nodes.has(id) or (nodes[id]["snapshot"] as Dictionary).is_empty():
		return null
	return Snapshot.load_state(nodes[id]["snapshot"])


func resume_node(id: String, players: Array) -> BattleState:
	var battle := load_battle(id)
	if battle == null:
		return null
	var survivors: Array = []
	for unit in battle.units:
		if unit.side != "enemy":
			continue
		if unit.is_alive():
			var fresh := CombatUnit.make(unit.species_id, "enemy", unit.uid)
			for field in ["cell", "max_hp", "move_points", "skills", "enemy_level", "combat_level", "is_boss", "upgrades", "reg_index"]:
				fresh.set(field, unit.get(field))
			fresh.hp = fresh.max_hp
			survivors.append(fresh)
		else:
			survivors.append(unit)
	battle.units = survivors
	for player in players:
		var placed := false
		var candidates: Array = battle.deploy_cells.duplicate()
		candidates.append_array(GridSpec.all_cells())
		for cell in candidates:
			if battle.unit_at(cell) == null and not battle.is_nest_cell(cell) and TerrainDB.can_stand(battle.terrain_at(cell), player.element):
				player.cell = cell
				battle.units.append(player)
				placed = true
				break
		if not placed:
			return null
	battle.round = 0
	battle.phase = BattleState.PHASE_PLAYER
	battle.ended = false
	battle.end_reason = ""
	battle.node_kind = node_mode(id)
	battle.enemy_kills.clear()
	battle.captured.clear()
	battle.deaths.clear()
	battle.undo_stack.clear()
	battle.pending_casts.clear()
	battle.channel_claims.clear()
	battle.skill_use_counts = {"player": {}, "enemy": {}}
	battle.events.clear()
	battle.reward.erase("run_settled_outcome")
	battle.nest["destroyed_by_player"] = false
	battle.start_round()
	return battle


func to_dict() -> Dictionary:
	return {"floor": floor_index, "theme": theme, "visits": visits, "active_node": active_node, "nodes": nodes.duplicate(true)}


static func from_dict(data: Dictionary) -> RegionState:
	var region := RegionState.new()
	region.floor_index = int(data.get("floor", 0))
	region.theme = String(data.get("theme", ""))
	region.visits = int(data.get("visits", 0))
	region.active_node = String(data.get("active_node", ""))
	region.nodes = (data.get("nodes", {}) as Dictionary).duplicate(true)
	return region
