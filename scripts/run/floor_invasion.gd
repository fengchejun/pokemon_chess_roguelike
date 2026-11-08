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
	var bonus := 20 if _matches(region, assignment["node"], member.get("equipped_skills", [])) else 0
	var preparation := mini(12, 3 * maxi(0, completed - ready))
	return {"ready": on_site, "base": BASE_DEFENSE, "level": level_bonus, "specialty": bonus, "preparation": preparation, "total": BASE_DEFENSE + level_bonus + bonus + preparation if on_site else 0}


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
	return clampi(total - pressure(region, id), 0, 100)


static func assign(run: RunState, id: String, uid: int) -> bool:
	var region: RegionState = run.get_region()
	var key := str(uid)
	if region.flow_version != 2 or region.invaded or not run.battle_snapshot.is_empty():
		return false
	if not region.nodes.has(id) or id in ["boss", "hunt"] or not region.nodes[id].get("unlocked", false):
		return false
	var previous: Dictionary = region.garrisons.get(key, {})
	if previous.get("node") == id:
		return true
	var member := run.owned_record_by_uid(uid)
	if int(member.get("hp", 0)) <= 0 or region.garrisons.values().filter(func(entry): return entry["node"] == id).size() >= 3:
		return false
	var carried := not run.record_by_uid(uid).is_empty()
	if carried and previous.is_empty() and not run.carried.any(func(record):
		return int(record["uid"]) != uid and int(record["hp"]) > 0 and not region.garrisons.has(str(record["uid"]))):
		return false
	region.garrisons[key] = assignment_for(region, id, carried)
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
