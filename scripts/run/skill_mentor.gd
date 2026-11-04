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

static func train(run: RunState, state: BattleState, uid: int, skill_id: String) -> Dictionary:
	if state.ended or state.node_kind != "event" or state.mentor.is_empty() or not state.can_interact_at(state.mentor["cell"]):
		return {"ok": false, "reason": "训练家需在收集区与技能导师相邻。"}
	var price := cost(state.mentor)
	if run.record_by_uid(uid).is_empty() or not run.available_monster_upgrades(uid).has(RunState.upgrade_id_for_skill(skill_id)):
		return {"ok": false, "reason": "请选择携带队伍中尚未强化的已学招式。"}
	if run.essence < price:
		return {"ok": false, "reason": "原质不足，需要%d。" % price}
	run.apply_mentor_upgrade(uid, skill_id)
	run.essence -= price
	state.mentor["services"] = int(state.mentor.get("services", 0)) + 1
	var unit := state.unit_by_uid(uid)
	if unit != null:
		unit.upgrades = run.record_by_uid(uid)["upgrades"].duplicate()
	return {"ok": true, "reason": "%s 已强化，消耗%d原质。" % [SkillDB.name_of(skill_id), price]}
