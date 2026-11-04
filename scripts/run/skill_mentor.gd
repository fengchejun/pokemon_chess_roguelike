class_name SkillMentor
extends RefCounted

static func ensure_region(region: RegionState, _seed: int) -> void:
	if region.nodes.values().any(func(n): return n.has("mentor")):
		return
	for id in ["event_1", "event_2"]:
		if not region.nodes[id].has("merchant"):
			region.nodes[id]["mentor"] = {"cell": [-1, -1], "services": 0}
			return

static func choose_cell(state: BattleState, positions: Dictionary = {}) -> Vector2i:
	var trainer := state.trainer()
	if trainer == null:
		return Vector2i(-1, -1)
	for cell in state.move_options(trainer):
		if state.deploy_area.has(cell) or positions.values().has(cell) or state.unit_at(cell) != null or state.food_cells.has(cell) or state.is_nest_cell(cell):
			continue
		if state.all_rewards().any(func(point): return point.get("cell") == cell and point.get("state") in ["map", "guarding"]):
			continue
		return cell
	return Vector2i(-1, -1)

static func cost(data: Dictionary) -> int:
	return 12 + 8 * int(data.get("services", 0))

static func train(_run: RunState, _state: BattleState, _uid: int, _skill_id: String) -> Dictionary:
	return {"ok": false, "reason": "技能强化已迁移至商人，请使用空刻印槽强化。"}
