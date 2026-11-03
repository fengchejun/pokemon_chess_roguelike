class_name PushResolver
extends RefCounted

## 强制位移：推击与击退共用。
## 结算顺序：逐格移动 → 碰撞加伤 → 障碍/巢穴耐久 → 致死地形处死。


static func push(state, target: CombatUnit, direction: Vector2i, distance: int, collision_bonus: int, cause: String, source_side: String = "", source_uid: int = -1, skill_id: String = "") -> Dictionary:
	var summary := {
		"moved": false,
		"blocked": false,
		"from": target.cell,
		"to": target.cell,
		"death": false,
		"collisions": [],
	}
	if not target.is_alive():
		return summary
	if target.is_boss:
		summary["blocked"] = true
		state.log_event("%s 不会被推动。" % target.display_name)
		return summary
	if state.has_hazard_guard(target):
		summary["blocked"] = true
		state.log_event("%s 站稳脚跟，没有被推离。" % target.display_name)
		return summary
	var other_relic_bonus := 0
	if source_side == "player" and target.side == "enemy":
		other_relic_bonus += 4 * RelicDB.rank(state.relic_stacks, "wall_crash")
		collision_bonus += other_relic_bonus
	for step in distance:
		if not target.is_alive():
			break
		var next: Vector2i = target.cell + direction
		if not GridSpec.is_inside(next):
			summary["collisions"].append({"kind": "edge", "cell": next})
			break
		if state.is_interaction_cell(next) or state.is_nest_cell(next):
			_summarize_collision(state, summary, target, null, next, collision_bonus, source_side, source_uid, other_relic_bonus)
			break
		var terrain: int = state.terrain_at(next)
		var occupant: CombatUnit = state.unit_at(next)
		if occupant != null:
			_summarize_collision(state, summary, target, occupant, next, collision_bonus, source_side, source_uid, other_relic_bonus)
			break
		if not target.has_buff("flight") and TerrainDB.is_lethal(terrain) and (terrain != TerrainDB.DEEP or target.element != "water"):
			target.last_move_direction = direction
			target.cell = next
			state.log_event("%s 被推入%s。" % [target.display_name, TerrainDB.name_of(terrain)])
			state.kill_unit(target, cause + "（%s）" % TerrainDB.name_of(terrain), source_side, source_uid)
			summary["moved"] = true
			summary["to"] = next
			summary["death"] = true
			break
		if TerrainDB.blocks_move(terrain):
			_summarize_collision(state, summary, target, null, next, collision_bonus, source_side, source_uid, other_relic_bonus)
			break
		target.cell = next
		target.last_move_direction = direction
		summary["moved"] = true
		summary["to"] = next
	if summary["moved"] and target.is_alive():
		state.apply_vine_on_landing(target)
	return summary


static func _summarize_collision(state, summary: Dictionary, target: CombatUnit, occupant, cell: Vector2i, collision_bonus: int, source_side: String, source_uid: int, other_relic_bonus: int) -> void:
	var target_damage := Balance.COLLISION_DAMAGE + collision_bonus
	var other_damage := Balance.COLLISION_DAMAGE + (other_relic_bonus if occupant != null and occupant.side == "enemy" else 0)
	var entry := {
		"kind": "unit" if occupant != null else "obstacle",
		"cell": cell,
		"target_damage": target_damage,
		"other_damage": other_damage if occupant != null else 0,
	}
	summary["collisions"].append(entry)
	var blocker_name := "巢穴" if state.is_nest_cell(cell) else "设施" if state.is_interaction_cell(cell) else "障碍"
	if occupant != null:
		blocker_name = occupant.display_name
	state.log_event("%s 撞上%s，受到 %d 伤害。" % [target.display_name, blocker_name, target_damage])
	state.damage_unit(null, target, target_damage, {"no_element": true, "cause": "碰撞", "collision": true, "killer_side": source_side, "killer_uid": source_uid})
	if occupant != null:
		state.damage_unit(null, occupant, other_damage, {"no_element": true, "cause": "被撞", "collision": true, "killer_side": source_side, "killer_uid": source_uid})
	else:
		state.damage_obstacle(cell, 1, source_side)
