extends RefCounted

const MAX_CARRIERS := 4
const BASE_DEFENSE := 26
const DEFENSE_XP := 6


static func specialty(region: RegionState, id: String) -> String:
	if id == "camp":
		return "药草治疗或急救"
	if region.theme == "water":
		return "造雨术、冰封大地或放电"
	if region.nodes[id].get("links", []).size() >= 3:
		return "疯狂藤蔓、造岩或推击"
	return "远程伤害招式"


static func _matches(region: RegionState, id: String, skills: Array) -> bool:
	var required := []
	if id == "camp":
		required = ["herbal_heal", "first_aid"]
	elif region.theme == "water":
		required = ["rain_call", "frozen_ground", "electric_arc"]
	elif region.nodes[id].get("links", []).size() >= 3:
		required = ["wild_vines", "rock_create", "rock_push", "push"]
	if not required.is_empty():
		return skills.any(func(skill): return required.has(skill))
	return skills.any(func(skill):
		var definition := SkillDB.get_def(skill)
		return bool(definition.get("ranged", false)) and int(definition.get("damage", 0)) > 0)


static func breakdown(region: RegionState, assignment: Dictionary, member: Dictionary) -> Dictionary:
	var ready := int(assignment["ready"])
	var completed := region.visits - int(region.visit_pending)
	var available := int(member.get("hp", 0)) > 0
	var on_site := available and (completed >= ready or bool(assignment.get("immediate", false)))
	var level_bonus := 2 * (int(member.get("level", 1)) - 1)
	var collecting: bool = assignment.get("duty", "guard") == "gather"
	var bonus := 20 if not collecting and _matches(region, assignment["node"], member.get("equipped_skills", [])) else 0
	var preparation := 0 if collecting else mini(12, 3 * maxi(0, completed - ready))
	var base := int(BASE_DEFENSE / 2) if collecting else BASE_DEFENSE
	if collecting:
		level_bonus = int(level_bonus / 2)
	return {"ready": on_site, "base": base, "level": level_bonus, "specialty": bonus, "preparation": preparation, "total": base + level_bonus + bonus + preparation if on_site else 0}


static func contribution(region: RegionState, assignment: Dictionary, member: Dictionary) -> int:
	return int(breakdown(region, assignment, member)["total"])


static func pressure(region: RegionState, id: String) -> int:
	var location := 10 if id == "camp" else 15 if region.nodes[id].get("links", []).size() >= 3 else 0
	return location + 5 * region.floor_index


static func assignment_for(region: RegionState, id: String, carried: bool) -> Dictionary:
	var immediate := carried and region.active_node == id
	return {"node": id, "ready": region.visits + (0 if immediate else 1), "immediate": immediate}


static func chance(run: RunState, region: RegionState, id: String) -> int:
	var total := 0
	for key in region.garrisons:
		var assignment: Dictionary = region.garrisons[key]
		if assignment["node"] == id:
			total += contribution(region, assignment, run.owned_record_by_uid(int(key)))
	return clampi(total + 10 * int(region.nodes[id].get("fortification", 0)) - pressure(region, id), 0, 100)


static func assign(run: RunState, id: String, uid: int, duty: String = "guard") -> bool:
	var region: RegionState = run.get_region()
	var key := str(uid)
	if region.flow_version != 2 or region.invaded or not run.battle_snapshot.is_empty():
		return false
	if not region.nodes.has(id) or id in ["boss", "hunt"] or not region.nodes[id].get("unlocked", false):
		return false
	var previous: Dictionary = region.garrisons.get(key, {})
	if duty not in ["guard", "gather"]:
		return false
	if duty == "gather" and (not region.nodes[id].get("passable", false) or resource_kind(id).is_empty() or int(region.nodes[id].get("gathered_batches", 0)) >= 2):
		return false
	if previous.get("node") == id and previous.get("duty", "guard") == duty:
		return true
	var member := run.owned_record_by_uid(uid)
	if int(member.get("hp", 0)) <= 0 or (previous.get("node") != id and region.garrisons.values().filter(func(entry): return entry["node"] == id).size() >= 3):
		return false
	var carried := not run.record_by_uid(uid).is_empty()
	if carried and previous.is_empty() and not run.carried.any(func(record):
		return int(record["uid"]) != uid and int(record["hp"]) > 0 and not region.garrisons.has(str(record["uid"]))):
		return false
	region.garrisons[key] = assignment_for(region, id, carried)
	region.garrisons[key]["duty"] = duty
	region.garrisons[key]["gather_tick"] = region.visits - int(region.visit_pending)
	run.region_data = region.to_dict()
	return true


static func recall(run: RunState, uid: int) -> bool:
	var region: RegionState = run.get_region()
	if region.invaded or not run.battle_snapshot.is_empty() or not region.garrisons.erase(str(uid)):
		return false
	run.region_data = region.to_dict()
	return true


static func resolve(run: RunState, region: RegionState) -> bool:
	if region.invaded or region.visit_pending or region.visits < Balance.EXPLORATION_ACTIONS:
		return false
	region.invaded = true
	region.invasion_origin = region.active_node
	var occupied := []
	for id in region.nodes:
		if id in ["boss", "hunt"]:
			continue
		var node: Dictionary = region.nodes[id]
		node["gather_progress"] = 0
		var probability := chance(run, region, id)
		var held := posmod(hash("defense:%d:%d:%s" % [run.seed, region.floor_index, id]), 100) < probability
		node["defense"] = {"held": held, "chance": probability}
		if held:
			continue
		occupied.append(id)
		node["occupied"] = true
		node["mode"] = "battle"
		node["done"] = false
		node["passable"] = false
		node["cleared"] = false
		node["snapshot"] = {}
		node["pending_garrison"] = false
		node["pending_replenish"] = false
		node["service_lost"] = node["role"] not in ["starter", "battle", "elite"]
		node["reward_pending"] = false
		for field in ["merchant", "mentor"]:
			node.erase(field)
	occupied.sort_custom(func(a, b):
		return hash("supply:%d:%d:%s" % [run.seed, region.floor_index, a]) < hash("supply:%d:%d:%s" % [run.seed, region.floor_index, b]))
	for id in occupied.slice(0, MAX_CARRIERS):
		region.nodes[id]["invasion_carrier"] = true
	for key in region.garrisons:
		var assignment: Dictionary = region.garrisons[key]
		var member := run.owned_record_by_uid(int(key))
		if member.is_empty():
			continue
		if region.nodes[assignment["node"]]["defense"]["held"] and contribution(region, assignment, member) > 0:
			var growth := MonsterProgression.award_xp(member, DEFENSE_XP)
			var locked: Array = member.get("defense_locked_levels", [])
			for level in [2, 4, 6, 8, 10]:
				if level > int(growth["level_before"]) and level <= int(growth["level_after"]) and not locked.has(level):
					locked.append(level)
			member["defense_locked_levels"] = locked
		if run.carried.has(member):
			run.carried.erase(member)
			run.storage.append(member)
	region.garrisons.clear()
	run.pending_region_entry_backup.clear()
	run.region_data = region.to_dict()
	return true


# Stable node IDs also give existing exploration saves finite deposits.
static func resource_kind(id: String) -> String:
	if id in ["battle_1", "battle_2"]:
		return "food"
	if id in ["elite_1", "battle_3", "battle_4"]:
		return "materials"
	return ""


static func resource_text(id: String, node: Dictionary) -> String:
	var kind := resource_kind(id)
	if kind.is_empty():
		return ""
	return "%s · 剩%d批 · 进度%d/3" % ["食物" if kind == "food" else "建材", maxi(0, 2 - int(node.get("gathered_batches", 0))), int(node.get("gather_progress", 0))]


static func collect(run: RunState, region: RegionState) -> void:
	if region.flow_version != 2 or region.invaded or region.visit_pending:
		return
	for key in region.garrisons:
		var assignment: Dictionary = region.garrisons[key]
		if assignment.get("duty", "guard") != "gather":
			continue
		var id := String(assignment["node"])
		var member := run.owned_record_by_uid(int(key))
		var elapsed := maxi(0, region.visits - maxi(int(assignment["ready"]), int(assignment.get("gather_tick", region.visits))))
		assignment["gather_tick"] = region.visits
		if int(member.get("hp", 0)) <= 0 or not region.nodes[id].get("passable", false):
			continue
		var node: Dictionary = region.nodes[id]
		var progress := int(node.get("gather_progress", 0)) + elapsed
		var batches := int(node.get("gathered_batches", 0))
		while progress >= 3 and batches < 2:
			progress -= 3
			batches += 1
			if resource_kind(id) == "food":
				run.add_food("basic", 1)
			else:
				run.building_materials += 1
			region.notifications.append("%s采集完成：%s +1" % [region.display_name(id), "食物" if resource_kind(id) == "food" else "建材"])
		node["gathered_batches"] = batches
		node["gather_progress"] = 0 if batches >= 2 else progress


static func fortify(run: RunState, id: String) -> bool:
	var region: RegionState = run.get_region()
	if region.flow_version != 2 or region.invaded or not run.battle_snapshot.is_empty() or run.building_materials <= 0:
		return false
	if not region.nodes.has(id) or id in ["boss", "hunt"] or not region.nodes[id].get("unlocked", false) or int(region.nodes[id].get("fortification", 0)) >= 2:
		return false
	run.building_materials -= 1
	region.nodes[id]["fortification"] = int(region.nodes[id].get("fortification", 0)) + 1
	run.region_data = region.to_dict()
	return true
