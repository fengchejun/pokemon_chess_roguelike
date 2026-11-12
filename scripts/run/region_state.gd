class_name RegionState
extends RefCounted

## 区域节点的持久化账本。节点数量、连线和强化数值由流程配置提供。
const Snapshot = preload("res://scripts/run/battle_snapshot.gd")
const NODE_TYPES := ["camp", "battle", "event", "boss"]
const AREA_CELLS := {"battle_1": Vector2i(0, 0), "battle_2": Vector2i(1, 0), "event_2": Vector2i(2, 0), "camp": Vector2i(0, 1), "battle_3": Vector2i(1, 1), "boss": Vector2i(2, 1), "event_1": Vector2i(0, 2), "battle_5": Vector2i(1, 2), "battle_4": Vector2i(2, 2)}

var flow_version := 1
var floor_index: int = 0
var theme: String = ""
var visits: int = 0
var invaded := false
var invasion_origin := ""
var garrisons := {}
var active_node: String = ""
var nodes: Dictionary = {}
var visit_pending: bool = false
var support_triggered: bool = false
var corrupted: bool = false
var boss_level_bonus: int = 0 # 本层累计压力等级，结算差额写入整局
var camp_invaded: bool = false
var notifications: Array = []
var at_camp_scene: bool = false


static func create_floor(floor_value: int, theme_value: String) -> RegionState:
	var specifications: Array = [{"id": "camp", "type": "camp"}, {"id": "event_1", "type": "event"}, {"id": "event_2", "type": "event"}, {"id": "boss", "type": "boss"}]
	for index in range(1, 6):
		specifications.append({"id": "battle_%d" % index, "type": "battle"})
	var region := create(floor_value, theme_value, specifications)
	for id in region.nodes:
		region.nodes[id]["unlocked"] = id == "camp"
		region.nodes[id]["links"] = []
	for id in AREA_CELLS:
		for other in AREA_CELLS:
			if id != other and absi(AREA_CELLS[id].x - AREA_CELLS[other].x) + absi(AREA_CELLS[id].y - AREA_CELLS[other].y) == 1:
				region.nodes[id]["links"].append(other)
	region.nodes["camp"]["unlocked"] = true
	region.nodes["camp"]["visits"] = 1
	for neighbor in region.nodes["camp"]["links"]:
		region.nodes[neighbor]["unlocked"] = true
	region.active_node = "camp"
	region.at_camp_scene = false
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
		region.nodes[id] = {"type": kind, "mode": kind, "visits": 0, "cleared": false, "withdrawn": false, "pending_garrison": false, "pending_replenish": false, "snapshot": {}}
	return region


func node_mode(id: String) -> String:
	if not nodes.has(id):
		return ""
	var node: Dictionary = nodes[id]
	if flow_version == 2 and node.get("role") == "group" and node.get("battle_selected", false) and not node.get("done", false):
		return "battle"
	return String(node.get("mode", "event" if node["type"] == "battle" and bool(node["cleared"]) else node["type"]))


func display_name(id: String) -> String:
	if flow_version == 2:
		if nodes[id].has("rare_species"):
			return "神秘栖息地"
		if nodes[id].get("role") == "treasure":
			return preload("res://scripts/run/exploration_flow.gd").puzzle_name(nodes[id])
		return String(preload("res://scripts/run/exploration_flow.gd").NAMES.get(nodes[id].get("role", ""), id))
	if id == "camp":
		return "营地（敌军占领）" if node_mode(id) == "battle" else "营地"
	if id == "boss":
		return "首领区"
	if id.begins_with("event_") and node_mode(id) == "battle":
		return "探索区 %s（敌军占领）" % id.get_slice("_", 1)
	return "%s %s" % ["战斗区" if id.begins_with("battle_") else "探索区", id.get_slice("_", 1)]


func can_enter_after_invasion(id: String) -> bool:
	if not nodes.has(id):
		return false
	var node: Dictionary = nodes[id]
	if id == invasion_origin or node.get("passable", false):
		return true
	return node.get("links", []).any(func(neighbor): return bool(nodes[neighbor].get("passable", false)))


func record_entry(id: String) -> bool:
	if visit_pending or not nodes.has(id):
		return false
	if invaded:
		if not can_enter_after_invasion(id):
			return false
	elif not bool(nodes[id].get("unlocked", true)):
		return false
	if nodes[id].has("rare_species") and nodes[id].get("done", false) and not nodes[id].get("service_lost", false):
		return false
	if nodes[id]["type"] == "boss" and bool(nodes[id]["cleared"]):
		return false
	if flow_version == 2:
		if not invaded and visits >= Balance.EXPLORATION_ACTIONS:
			return false
		visits += 1
		nodes[id]["revealed"] = true
		if not nodes[id].get("occupied", false) and not nodes[id].get("service_lost", false) and nodes[id].get("role") in ["capture", "group", "shop", "item_shop", "skill_shop", "camp", "treasure", "empty"]:
			nodes[id]["passable"] = true
			unlock_neighbors(id)
	elif nodes[id]["type"] != "boss":
		visits += 1
	nodes[id]["visits"] = int(nodes[id]["visits"]) + 1
	active_node = id
	_apply_pressure()
	at_camp_scene = node_mode(id) == "camp"
	visit_pending = true
	return true


func complete_visit(run = null) -> Array:
	if not visit_pending:
		return []
	visit_pending = false
	if run != null:
		preload("res://scripts/run/floor_invasion.gd").collect(run, self)
	if active_node == "camp":
		at_camp_scene = false
	var result := notifications.duplicate()
	notifications.clear()
	return result


func unlock_neighbors(id: String) -> void:
	for neighbor in nodes[id].get("links", []):
		nodes[neighbor]["revealed"] = true
		if not bool(nodes[neighbor].get("unlocked", false)):
			notifications.append("已解锁：%s" % display_name(String(neighbor)))
		nodes[neighbor]["unlocked"] = true


func _occupy(id: String) -> void:
	var node: Dictionary = nodes[id]
	node["mode"] = "battle"
	node["cleared"] = false
	node["withdrawn"] = false
	node["pending_garrison"] = true
	node["pending_replenish"] = false


func occupy_all(preserve_node: String = "") -> void:
	support_triggered = true
	camp_invaded = true
	at_camp_scene = false
	for id in nodes:
		if id != "boss":
			if id == preserve_node:
				nodes[id]["mode"] = "battle"
				nodes[id]["cleared"] = false
				nodes[id]["pending_garrison"] = false
			else:
				_occupy(id)
	notifications.append("第8次区域移动：敌军全面占领营地及已清理节点；夺回营地后恢复食物回复服务，首领驻军+2。")


func _apply_pressure() -> void:
	if flow_version == 2:
		return
	if active_node == "boss":
		return
	if visits >= Balance.INVASION_VISITS and not support_triggered:
		occupy_all()
	if visits >= Balance.CORRUPTION_VISITS:
		if not corrupted:
			corrupted = true
			notifications.append("第11次区域移动：本层全地图敌军及后续增援黑化，最大生命与技能威力+10%，击杀无经验。")
		var new_bonus := (visits - 8) / 3
		if new_bonus > boss_level_bonus:
			boss_level_bonus = new_bonus
			notifications.append("全体敌人等级再次+1，跨层保留；黑化不会叠加。")


func next_pressure_text() -> String:
	if flow_version == 2:
		return "入侵已结算 · 可继续夺回节点并挑战 Boss" if invaded else "剩余%d行动；结算当前节点后触发入侵" % maxi(0, Balance.EXPLORATION_ACTIONS - visits)
	if not corrupted:
		return "再移动%d次全面占领；再移动%d次全图黑化" % [maxi(0, Balance.INVASION_VISITS - visits), maxi(0, Balance.CORRUPTION_VISITS - visits)] if not support_triggered else "敌军已入侵；再移动%d次全图黑化" % maxi(0, Balance.CORRUPTION_VISITS - visits)
	return "全图已黑化；再移动%d次等级+1" % maxi(0, 11 + boss_level_bonus * 3 - visits)


func store_battle(id: String, battle: BattleState) -> bool:
	if not nodes.has(id) or battle == null:
		return false
	var node: Dictionary = nodes[id]
	if not ["battle", "boss", "event", "camp"].has(node_mode(id)):
		return false
	var persisted := battle.clone()
	if battle.ended:
		persisted.clear_node_temporaries()
	node["snapshot"] = Snapshot.save_state(persisted)
	if battle.ended and battle.end_reason in ["victory", "explored"]:
		unlock_neighbors(id)
	if flow_version == 2:
		if node.get("occupied", false):
			if battle.ended and battle.end_reason == "victory" and battle.battle_objective_met():
				node["occupied"] = false
				node["recaptured"] = true
				node["done"] = true
				node["cleared"] = true
				node["passable"] = true
			return true
		if battle.ended and node.has("rare_species"):
			node["done"] = true
		if battle.ended and battle.end_reason in ["victory", "explored"]:
			if node.get("role") in ["starter", "battle", "elite", "boss", "hunt", "group"] and battle.battle_objective_met():
				node["cleared"] = true
				node["passable"] = true
				node["done"] = true
			if node.get("role") == "treasure" and battle.chests.is_empty() and battle.all_rewards().all(func(point): return point.get("credited", false)):
				node["done"] = true
		return true
	if node["type"] == "boss":
		var boss := battle.unit_by_uid(battle.boss_uid)
		node["cleared"] = boss != null and (not boss.is_alive() or boss.side == "player")
	elif node_mode(id) == "battle":
		node["cleared"] = battle.battle_objective_met()
		if bool(node["cleared"]):
			node["mode"] = "camp" if node["type"] == "camp" else "event"
			node["pending_garrison"] = false
			node["pending_replenish"] = false
			if node["type"] == "camp":
				camp_invaded = false
				notifications.append("营地驻军已清除，食物回复服务重新开放。")
		elif battle.end_reason == "escape":
			node["pending_replenish"] = true
			notifications.append("%s 撤退；下次进入存活敌军回到出生格并回满生命，空缺补足 4 名。" % display_name(id))
	elif battle.end_reason == "escape" and not support_triggered and not bool(node.get("withdrawn", false)):
		node["mode"] = "battle"
		node["pending_garrison"] = true
		notifications.append("%s 停留超时；下次进入出现 3 名新驻军与新巢穴。" % display_name(id))
	return true


func load_battle(id: String) -> BattleState:
	if not nodes.has(id) or (nodes[id]["snapshot"] as Dictionary).is_empty():
		return null
	var battle := Snapshot.load_state(nodes[id]["snapshot"])
	if battle != null and (corrupted or bool(nodes[id].get("corrupted", false))):
		battle.corruption_active = true
		for unit in battle.units:
			if unit.side == "enemy" and unit.is_alive():
				unit.set_corrupted(true)
	# 兼容旧版已离开节点但仍保存临时效果的快照。战斗中途读档不走此分支。
	if battle != null and battle.ended:
		battle.clear_node_temporaries()
	return battle


func resume_node(id: String, players: Array, cfg: Dictionary = {}) -> BattleState:
	var battle := load_battle(id)
	if battle == null:
		return null
	battle.clear_node_temporaries()
	battle.corruption_active = battle.corruption_active or corrupted or bool(nodes[id].get("corrupted", false)) or bool(cfg.get("corrupted", false))
	battle.timed_corruption_triggered = false
	battle.occupation_applied = false
	var survivors: Array = []
	var occupied := {}
	for unit in battle.units:
		if unit.side != "enemy":
			continue
		if unit.is_alive():
			var fresh := CombatUnit.make(unit.species_id, "enemy", unit.uid)
			for field in ["cell", "max_hp", "move_points", "skills", "enemy_level", "combat_level", "is_boss", "upgrades", "reg_index", "spawned_from_nest", "spawn_round", "reward_carrier", "inspired", "corrupted", "corruption_hp_bonus"]:
				fresh.set(field, unit.get(field))
			var original: Vector2i = battle.enemy_origins.get(unit.uid, Vector2i(-1, -1))
			if not GridSpec.is_inside(original) and unit.uid >= 100 and unit.uid - 100 < (cfg.get("enemies", []) as Array).size():
				original = cfg["enemies"][unit.uid - 100][1]
			if not GridSpec.is_inside(original):
				original = unit.cell
			var cells := GridSpec.all_cells()
			cells.sort_custom(func(a, b):
				var da := GridSpec.manhattan(a, original)
				var db := GridSpec.manhattan(b, original)
				return da < db if da != db else a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
			for cell in cells:
				if not occupied.has(cell) and not battle.is_interaction_cell(cell) and not battle.is_nest_cell(cell) and not battle.terrain_blocks_move(cell) and TerrainDB.can_stand(battle.terrain_at(cell), fresh.element):
					fresh.cell = cell
					occupied[cell] = true
					break
			battle.enemy_origins[unit.uid] = original
			fresh.hp = fresh.max_hp
			survivors.append(fresh)
		else:
			survivors.append(unit)
	battle.storm_strikes.clear()
	battle.storm_last_round = 0
	battle.boss_retreat_used = false
	battle.nest["boss_sheltered"] = false
	battle.units = survivors
	if bool(nodes[id].get("pending_garrison", false)):
		battle.nest["alive"] = true
		battle.nest["hp"] = Balance.nest_max_hp(battle.battle_index)
		battle.nest["max_hp"] = battle.nest["hp"]
		battle.nest["pending_waves"] = 0
		battle.nest["scheduled_waves"] = []
		battle.add_garrison(maxi(0, 3 - battle.alive_enemy_count()), cfg.get("reinforce", []), (cfg.get("enemies", []) as Array).map(func(pair): return pair[1]))
	elif node_mode(id) == "battle" and flow_version != 2:
		battle.add_garrison(maxi(0, 4 - battle.alive_enemy_count()), cfg.get("reinforce", []), (cfg.get("enemies", []) as Array).map(func(pair): return pair[1]))
	elif id == "boss" and support_triggered:
		battle.add_garrison(maxi(0, 5 - battle.alive_enemy_count()), cfg.get("reinforce", []), (cfg.get("enemies", []) as Array).map(func(pair): return pair[1]))
	for player in players:
		var placed := false
		var candidates: Array = battle.deploy_cells.duplicate()
		candidates.append_array(GridSpec.all_cells())
		for cell in candidates:
			if battle.unit_at(cell) == null and not battle.is_interaction_cell(cell) and not battle.is_nest_cell(cell) and not battle.terrain_blocks_move(cell) and TerrainDB.can_stand(battle.terrain_at(cell), player.element):
				player.cell = cell
				battle.units.append(player)
				placed = true
				break
		if not placed:
			return null
	battle.experience_recipients = players.filter(func(u): return u.summon_owner_uid < 0).map(func(u): return u.uid)
	battle.escape_penalties.clear()
	battle.experience_events.clear()
	battle.experience_gains.clear()
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
	battle.speech_seen.clear()
	battle.food_collected = 0
	battle.food_applied = 0
	battle.food_wait.clear()
	battle.capture_aid = false
	battle.reward.erase("run_settled_outcome")
	for current in battle.all_nests():
		current["destroyed_by_player"] = false
	battle.set_enemy_level_bonus(int(cfg.get("enemy_level_bonus", battle.enemy_level_bonus)))
	battle.start_round()
	return battle


func to_dict() -> Dictionary:
	return {"flow_version": flow_version, "floor": floor_index, "theme": theme, "visits": visits, "invaded": invaded, "invasion_origin": invasion_origin, "garrisons": garrisons.duplicate(true), "active_node": active_node, "nodes": nodes.duplicate(true), "visit_pending": visit_pending, "support_triggered": support_triggered, "corrupted": corrupted, "boss_level_bonus": boss_level_bonus, "camp_invaded": camp_invaded, "notifications": notifications.duplicate(), "at_camp_scene": at_camp_scene}


static func from_dict(data: Dictionary) -> RegionState:
	var region := RegionState.new()
	region.flow_version = int(data.get("flow_version", 1))
	region.floor_index = int(data.get("floor", 0))
	region.theme = String(data.get("theme", ""))
	region.visits = int(data.get("visits", 0))
	region.invaded = bool(data.get("invaded", false))
	region.invasion_origin = String(data.get("invasion_origin", ""))
	region.garrisons = data.get("garrisons", {}).duplicate(true)
	region.active_node = String(data.get("active_node", ""))
	region.nodes = (data.get("nodes", {}) as Dictionary).duplicate(true)
	region.visit_pending = bool(data.get("visit_pending", false))
	region.support_triggered = bool(data.get("support_triggered", false))
	region.corrupted = bool(data.get("corrupted", region.visits >= Balance.CORRUPTION_VISITS))
	region.boss_level_bonus = int(data.get("boss_level_bonus", 0))
	region.camp_invaded = bool(data.get("camp_invaded", false))
	region.notifications = (data.get("notifications", []) as Array).duplicate()
	region.at_camp_scene = bool(data.get("at_camp_scene", false))
	for id in region.nodes:
		var node: Dictionary = region.nodes[id]
		if not node.has("mode"):
			node["mode"] = "event" if node["type"] == "battle" and bool(node.get("cleared", false)) else node["type"]
	return region
