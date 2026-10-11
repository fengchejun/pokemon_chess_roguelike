extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")


static func preview(state: RefCounted, attacker: CombatUnit, target: CombatUnit) -> Dictionary:
	return preview_direction(state, target, target.cell - attacker.cell, int(CombatConfig.SKILLS["rock_push"]["damage"]))


static func preview_direction(state: RefCounted, target: CombatUnit, direction: Vector2i, base_damage: int) -> Dictionary:
	var destination: Vector2i = target.cell + direction * CombatConfig.PUSH_DISTANCE
	var result := {
		"destination": target.cell,
		"collision_unit": null,
		"collision_object": false,
		"target_damage": base_damage,
		"other_damage": 0,
		"description": "目标受 %d 伤，推进一格" % base_damage
	}
	if not GridSpec.is_inside(destination):
		result.target_damage += CombatConfig.COLLISION_DAMAGE
		result.description = "撞上棋盘边界：目标受 %d 伤（含碰撞追加 %d 伤）" % [result.target_damage, CombatConfig.COLLISION_DAMAGE]
		return result
	var occupant: CombatUnit = state.unit_at(destination)
	if occupant != null:
		result.collision_unit = occupant
		result.target_damage += CombatConfig.COLLISION_DAMAGE
		result.other_damage = CombatConfig.COLLISION_DAMAGE
		result.description = "撞上 %s：目标受 %d 伤，碰撞单位受 %d 伤" % [occupant.display_name, result.target_damage, CombatConfig.COLLISION_DAMAGE]
		return result
	var obstacle: Dictionary = state.terrain.object_at(destination)
	if obstacle.get("blocks_move", false) or state.is_nest_at(destination):
		result.collision_object = true
		result.target_damage += CombatConfig.COLLISION_DAMAGE
		result.description = "撞上%s：目标受 %d 伤，障碍受 %d 点耐久伤害" % ["巢穴" if state.is_nest_at(destination) else "岩石" if obstacle.get("type", "") == "rock" else "植物", result.target_damage, CombatConfig.PUSH_OBJECT_DAMAGE]
		return result
	result.destination = destination
	if state.terrain.is_deep_water(destination) and target.element_type != "water":
		result.description = "推入深水：目标将立即淹死"
	elif state.terrain.is_collapsed(destination):
		result.description = "推入塌陷深坑：目标将立即坠落"
	return result
