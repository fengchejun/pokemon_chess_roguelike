extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")


static func preview(state: RefCounted, attacker: CombatUnit, target: CombatUnit) -> Dictionary:
	return preview_direction(state, target, target.cell - attacker.cell, int(CombatConfig.SKILLS["rock_push"]["damage"]), 2 if attacker.upgraded_skill_id == "rock_push" else 1)


static func preview_direction(state: RefCounted, target: CombatUnit, direction: Vector2i, base_damage: int, push_distance: int = 1) -> Dictionary:
	var result := {
		"destination": target.cell,
		"collision_unit": null,
		"collision_object": false,
		"collision_cell": target.cell,
		"direct_damage": base_damage,
		"collision_damage": 0,
		"target_damage": base_damage,
		"other_damage": 0,
		"description": "目标受 %d 点技能直伤，推进 %d 格" % [base_damage, push_distance]
	}
	for step in range(1, push_distance + 1):
		var destination: Vector2i = target.cell + direction * step
		if not GridSpec.is_inside(destination):
			result.description = "抵达棋盘边缘：直伤 %d，无额外碰撞伤害" % base_damage
			break
		var occupant: CombatUnit = state.unit_at(destination)
		if occupant != null and (not target.flying or step == push_distance):
			result.collision_unit = occupant
			result.collision_damage = CombatConfig.COLLISION_DAMAGE
			result.other_damage = CombatConfig.COLLISION_DAMAGE
			result.description = "撞上 %s：直伤 %d，双方各受 %d 点碰撞伤" % [occupant.display_name, base_damage, CombatConfig.COLLISION_DAMAGE]
			break
		var obstacle: Dictionary = state.terrain.object_at(destination)
		if (obstacle.get("blocks_move", false) or state.is_nest_at(destination)) and (not target.flying or step == push_distance):
			result.collision_object = true
			result.collision_cell = destination
			result.collision_damage = CombatConfig.COLLISION_DAMAGE
			result.description = "撞上障碍：直伤 %d，碰撞 %d" % [base_damage, CombatConfig.COLLISION_DAMAGE]
			break
		result.destination = destination
		if not target.flying and (state.terrain.is_collapsed(destination) or state.terrain.is_deep_water(destination) and target.element_type != "water"):
			result.description = "推入致死地形：目标立即死亡"
			break
	result.target_damage += int(result.collision_damage)
	return result
