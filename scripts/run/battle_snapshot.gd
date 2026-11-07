class_name BattleSnapshot
extends RefCounted

## JSON-compatible battle state. Dictionary keys may be Vector2i, so encode pairs.
static func encode(value: Variant) -> Variant:
	if value is int:
		return {"@": "i", "value": str(value)}
	if value is Vector2i:
		return {"@": "v2i", "x": value.x, "y": value.y}
	if value is Vector2:
		return {"@": "v2", "x": value.x, "y": value.y}
	if value is Dictionary:
		var entries: Array = []
		for key in value:
			entries.append([encode(key), encode(value[key])])
		return {"@": "dict", "items": entries}
	if value is Array:
		var entries: Array = []
		for item in value:
			entries.append(encode(item))
		return entries
	return value


static func decode(value: Variant) -> Variant:
	if value is Array:
		var entries: Array = []
		for item in value:
			entries.append(decode(item))
		return entries
	if value is Dictionary:
		match String(value.get("@", "")):
			"i": return int(value["value"])
			"v2i": return Vector2i(int(value["x"]), int(value["y"]))
			"v2": return Vector2(float(value["x"]), float(value["y"]))
			"dict":
				var result := {}
				for pair in value["items"]:
					result[decode(pair[0])] = decode(pair[1])
				return result
	return value


static func _fields(object: Object) -> Dictionary:
	var result := {}
	for property in object.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key := String(property["name"])
			if key in ["units", "spawn_rng", "capture_rng", "terrain_rng", "feedback_enabled", "_boss_effect_depth"]:
				continue
			result[key] = encode(object.get(key))
	return result


static func save_state(state: BattleState) -> Dictionary:
	var members: Array = []
	for unit in state.units:
		members.append(_fields(unit))
	return {"version": 8, "fields": _fields(state), "units": members, "rng": {
		"spawn_seed": str(state.spawn_rng.seed), "spawn_state": str(state.spawn_rng.state),
		"capture_seed": str(state.capture_rng.seed), "capture_state": str(state.capture_rng.state),
		"terrain_seed": str(state.terrain_rng.seed), "terrain_state": str(state.terrain_rng.state),
	}}


static func load_state(snapshot: Dictionary) -> BattleState:
	if not snapshot.has("fields") or not snapshot.has("units") or not snapshot.has("rng"):
		return null
	var state := BattleState.new()
	for key in snapshot["fields"]:
		state.set(key, decode(snapshot["fields"][key]))
	for member in snapshot["units"]:
		var unit := CombatUnit.new()
		for key in member:
			unit.set(key, decode(member[key]))
		if not member.has("parasite_ticks") and unit.parasite_source_uid >= 0:
			unit.parasite_ticks = Balance.PARASITE_TICKS
		unit.element = Elements.canonical(unit.element)
		var had_removed_skill := unit.skills.any(func(id): return SkillDB.get_def(String(id)).is_empty())
		unit.skills = unit.skills.filter(func(id): return not SkillDB.get_def(String(id)).is_empty())
		if had_removed_skill and unit.skills.is_empty() and not unit.is_trainer:
			unit.skills = SpeciesDB.skills_of(unit.species_id).slice(0, 1)
		unit.upgrades.erase("wind_gust_distance")
		unit.upgrades.erase("volt_replace_flex")
		for key in unit.upgrades.keys():
			if String(key).begins_with("trial_"):
				unit.upgrades.erase(key)
		if unit.last_skill_id != "" and SkillDB.get_def(unit.last_skill_id).is_empty():
			unit.last_skill_id = ""
			unit.last_skill_from = Vector2i(-1, -1)
			unit.last_skill_target = {}
			unit.last_skill_upgraded = false
		if int(snapshot.get("version", 1)) < 3:
			RunState.rebase_upgrade_values(unit.upgrades)
		if unit.imprison_ticks <= 0 and unit.vine_ticks > 0:
			unit.imprison_ticks = unit.vine_ticks
		unit.vine_ticks = 0
		unit.vine_sources.clear()
		if unit.frozen and unit.frozen_ticks <= 0:
			unit.frozen_ticks = Balance.FREEZE_TICKS
		elif unit.frozen_ticks > 0:
			unit.frozen = true
		state.units.append(unit)
	state.pending_casts = state.pending_casts.filter(func(cast): return not SkillDB.get_def(String(cast.get("skill_id", ""))).is_empty())
	for side in ["player", "enemy"]:
		var counts: Dictionary = state.skill_use_counts.get(side, {})
		for skill_id in counts.keys():
			if SkillDB.get_def(String(skill_id)).is_empty():
				counts.erase(skill_id)
	if not snapshot["fields"].has("extra_rewards") and state.reward.get("state") in ["map", "guarding"]:
		state.reward["state"] = "absent"
		state.reward["cell"] = Vector2i(-1, -1)
	# 首领节点只保留主巢穴；旧档沿用主巢穴耐久与摧毁状态。
	if state.node_kind == "boss" or state.boss_uid >= 0:
		state.extra_nests.clear()
	for entry in state.enemy_kills:
		if entry.has("uid"):
			state.enemy_outcomes[int(entry["uid"])] = "defeated"
	for entry in state.captured:
		if entry.has("uid"):
			state.enemy_outcomes[int(entry["uid"])] = "captured"
	for current in state.all_nests():
		if not current.has("max_hp"):
			var maximum := Balance.nest_max_hp(state.battle_index)
			current["hp"] = clampi(roundi(int(current.get("hp", 0)) * maximum / 3.0), 0, maximum)
			current["max_hp"] = maximum
	state.mentor.clear()
	state.nest["exits"] = [] # Old exits no longer affect movement, targeting or spawning.
	state.enforce_player_nest_landing_rule()
	var rng: Dictionary = snapshot["rng"]
	state.spawn_rng.seed = int(rng["spawn_seed"])
	state.spawn_rng.state = int(rng["spawn_state"])
	state.capture_rng.seed = int(rng["capture_seed"])
	state.capture_rng.state = int(rng["capture_state"])
	state.terrain_rng.seed = int(rng["terrain_seed"])
	state.terrain_rng.state = int(rng["terrain_state"])
	if not snapshot["fields"].has("natural_essence_cells"):
		state.natural_essence_cells = state.obstacle_durability.keys().filter(func(cell): return not state.obstacle_expire_round.has(cell))
	if state.deploy_area.is_empty():
		state.deploy_area = state.deploy_cells.duplicate()
	if state.nest.has("boss_sheltered") or state.sheltered_boss() != null:
		state.nest["boss_sheltered"] = state.sheltered_boss() != null
	if state.sheltered_boss() != null:
		state.boss_retreat_used = true
	if int(snapshot.get("version", 1)) < 6 and state.round > Balance.CORRUPTION_ROUND and not state.ended:
		state._trigger_timed_corruption()
	state.extraction_cells = state.deploy_area.duplicate()
	state._boss_effect_depth = 0
	state.normalize_nest_terrain()
	state.try_release_boss()
	state.relocate_nest_occupants()
	state.repair_food()
	return state
