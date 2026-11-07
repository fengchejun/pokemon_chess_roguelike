class_name PushResolver
extends RefCounted

## 强制位移：推击与击退共用。
## 结算顺序：逐格移动 → 单位碰撞加伤 → 致死地形处死；碰撞不损伤障碍或巢穴耐久。


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
			state.emit_collision(target, target.cell, next, -1, summary["from"], "edge")
			break
		if state.is_interaction_cell(next) or state.is_nest_cell(next):
			summary["blocked"] = true
			_summarize_collision(state, summary, target, null, next, collision_bonus, source_side, source_uid, other_relic_bonus)
			break
		var terrain: int = state.terrain_at(next)
		var occupant: CombatUnit = state.unit_at(next)
		if occupant != null:
			_summarize_collision(state, summary, target, occupant, next, collision_bonus, source_side, source_uid, other_relic_bonus)
			break
		if target.side == "player" and state.is_nest_cell(next):
			summary["blocked"] = true
			summary["collisions"].append({"kind": "nest", "cell": next})
			state.log_event("%s 被巢穴边界挡住，不能被推上巢穴格。" % target.display_name)
			break
		if state.terrain_blocks_move(next):
			_summarize_collision(state, summary, target, null, next, collision_bonus, source_side, source_uid, other_relic_bonus)
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
		target.cell = next
		target.last_move_direction = direction
		summary["moved"] = true
		summary["to"] = next
	if summary["moved"] and target.is_alive():
		state.apply_vine_on_landing(target, false)
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
	state.emit_collision(target, target.cell, cell, occupant.uid if occupant != null else -1, summary["from"])
	var blocker_name := "巢穴" if state.is_nest_cell(cell) else "设施" if state.is_interaction_cell(cell) else "障碍"
	if occupant != null:
		blocker_name = occupant.display_name
	state.log_event("%s 撞上%s，受到 %d 伤害。" % [target.display_name, blocker_name, target_damage])
	state.damage_unit(null, target, target_damage, {"no_element": true, "cause": "碰撞", "collision": true, "killer_side": source_side, "killer_uid": source_uid})
	if occupant != null:
		state.damage_unit(null, occupant, other_damage, {"no_element": true, "cause": "被撞", "collision": true, "killer_side": source_side, "killer_uid": source_uid})


## 推击直接命中岩障：先损伤，再搬运；不用于其他击退技能。
static func push_obstacle(state: BattleState, caster: CombatUnit, cell: Vector2i) -> Dictionary:
	var result := {"from": cell, "to": cell, "damage": 0, "destroyed": false, "moved": false, "filled": false, "blocked": false, "hits": [], "terrain_changes": []}
	var source_terrain := state.terrain_at(cell)
	if state.is_chest_cell(cell) or source_terrain != TerrainDB.OBSTACLE or not state.obstacle_durability.has(cell) or GridSpec.manhattan(caster.cell, cell) != 1:
		return result
	var name := TerrainDB.name_of(source_terrain)
	result["damage"] = 1
	result["destroyed"] = state.damage_obstacle(cell, 1, caster.side)
	state._relay_feedback("damage", "岩障耐久 -1", 1, cell, -1)
	if result["destroyed"]:
		return result
	if state.camp_facility_at(cell) != "":
		result["blocked"] = true
		return result
	var next: Vector2i = cell + (cell - caster.cell)
	if not GridSpec.is_inside(next) or state.is_nest_cell(next) or state.is_interaction_cell(next) or state.terrain_blocks_move(next):
		result["blocked"] = true
		state.log_event("%s前方受阻，留在原格。" % name)
		return result
	var occupant := state.unit_at(next)
	if occupant != null:
		var amount := Balance.COLLISION_DAMAGE
		if caster.side == "player":
			amount += int(state.effects.get("push_collision", 0))
			if occupant.side == "enemy":
				amount += 4 * RelicDB.rank(state.relic_stacks, "wall_crash")
		state.emit_collision(null, cell, next, occupant.uid, cell, "rock")
		var hit := state.damage_unit(null, occupant, amount, {"no_element": true, "collision": true, "cause": name + "碰撞", "killer_side": caster.side, "killer_uid": caster.uid})
		result["hits"].append({"uid": occupant.uid, "name": occupant.display_name, "cell": next, "damage": int(hit.get("amount", 0)), "killed": bool(hit.get("killed", false)), "modifier": 0, "statuses": [], "push": null})
		result["blocked"] = true
		state.log_event("%s撞上 %s 后留在原格。" % [name, occupant.display_name])
		return result
	var destination := state.terrain_at(next)
	if TerrainDB.is_lethal(destination):
		state.damage_obstacle(cell, int(state.obstacle_durability[cell]), caster.side)
		state.set_terrain(next, TerrainDB.FRAGILE)
		result["to"] = next
		result["filled"] = true
		result["destroyed"] = true
		result["terrain_changes"].append({"cell": next, "from": destination, "to": TerrainDB.FRAGILE})
		state.log_event("岩障填入%s，目标格变为易碎地块。" % TerrainDB.name_of(destination))
		state._relay_feedback("terrain", "填成易碎格", 0, next, -1)
		return result
	if not TerrainDB.can_stand(destination, "rock"):
		result["blocked"] = true
		return result
	var hp := int(state.obstacle_durability[cell])
	var origin := int(state.obstacle_origin.get(cell, TerrainDB.PLAIN))
	var expiry := int(state.obstacle_expire_round.get(cell, -1))
	var natural := state.natural_essence_cells.has(cell)
	var reward_origin: Vector2i = state.obstacle_reward_origins.get(cell, cell)
	# 藤蔓被覆盖后清除，恢复它下面的实际地貌，不复活已清除的藤蔓。
	var underlay := int(state.vine_origin.get(next, TerrainDB.PLAIN)) if destination == TerrainDB.VINES else destination
	state.obstacle_durability.erase(cell)
	state.obstacle_origin.erase(cell)
	state.obstacle_expire_round.erase(cell)
	state.obstacle_reward_origins.erase(cell)
	state.natural_essence_cells.erase(cell)
	state.set_terrain(cell, origin)
	state.set_terrain(next, source_terrain)
	state.steam_cells.erase(next)
	state.burning_sources.erase(next)
	state.obstacle_durability[next] = hp
	state.obstacle_origin[next] = underlay
	if expiry >= 0:
		state.obstacle_expire_round[next] = expiry
	if natural:
		state.natural_essence_cells.append(next)
		state.obstacle_reward_origins[next] = reward_origin
	result["moved"] = true
	result["to"] = next
	state.log_event("%s被推至 (%d,%d)。" % [name, next.x, next.y])
	state._relay_feedback("terrain", name + "移动", 0, next, -1)
	return result
