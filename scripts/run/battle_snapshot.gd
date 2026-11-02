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
			if key in ["units", "spawn_rng", "capture_rng", "terrain_rng", "feedback_enabled"]:
				continue
			result[key] = encode(object.get(key))
	return result


static func save_state(state: BattleState) -> Dictionary:
	var members: Array = []
	for unit in state.units:
		members.append(_fields(unit))
	return {"version": 2, "fields": _fields(state), "units": members, "rng": {
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
		var had_retired_skill := unit.skills.has("wind_gust")
		unit.skills = unit.skills.filter(func(id): return not SkillDB.get_def(String(id)).is_empty())
		if had_retired_skill and unit.skills.is_empty():
			unit.skills = SpeciesDB.skills_of(unit.species_id).slice(0, 1)
		unit.upgrades.erase("wind_gust_distance")
		unit.upgrades.erase("volt_replace_flex")
		if unit.imprison_ticks <= 0 and unit.vine_ticks > 0:
			unit.imprison_ticks = unit.vine_ticks
		unit.vine_ticks = 0
		unit.vine_sources.clear()
		if unit.frozen and unit.frozen_ticks <= 0:
			unit.frozen_ticks = Balance.FREEZE_TICKS
		elif unit.frozen_ticks > 0:
			unit.frozen = true
		state.units.append(unit)
	state.nest["exits"] = [] # Old exits no longer affect movement, targeting or spawning.
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
	state.repair_food()
	return state
