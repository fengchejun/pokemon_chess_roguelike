class_name BattleBuffSystem
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")

const BASE_BUFFS: Array[String] = ["move_plus", "flying", "debuff_immune", "direct_guard"]
const NAMES := {
	"move_plus": "疾行：移动力 +1",
	"flying": "飞行：越过单位、障碍和危险地形，免疫地面效果",
	"debuff_immune": "净化：免疫灼烧与浸湿，并立即解除它们",
	"direct_guard": "护体：技能直接伤害 -1",
}
const SKILL_UPGRADES := {
	"fire_burst": "火球术：外围命中的单位也会灼烧",
	"flame_charge": "闪焰冲锋：沿途单位额外受 1 点直伤",
	"water_flow": "水流：击退距离变为 2 格",
	"rain_call": "造雨术：范围内非水系单位立即浸湿",
	"electric_arc": "放电：导电命中的非水系单位立即浸湿",
	"rock_break": "碎岩：可以击碎易碎地块",
	"rock_push": "推击：击退距离变为 2 格",
	"rock_create": "造岩：短墙多持续一轮敌方行动",
}


static func candidates(unit: CombatUnit) -> Array[String]:
	var result: Array[String] = BASE_BUFFS.duplicate()
	for skill_id in unit.skill_ids:
		if CombatConfig.SKILLS.has(skill_id) and SKILL_UPGRADES.has(skill_id):
			result.append("skill_upgrade:" + skill_id)
	return result


static func offer(unit: CombatUnit, rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[String] = candidates(unit)
	var result: Array[String] = []
	for choice in 2:
		var index: int = rng.randi_range(0, pool.size() - 1)
		result.append(pool.pop_at(index))
	return result


static func description(buff_id: String) -> String:
	if buff_id.begins_with("skill_upgrade:"):
		return SKILL_UPGRADES.get(buff_id.trim_prefix("skill_upgrade:"), buff_id)
	return NAMES.get(buff_id, buff_id)


static func short_name(buff_id: String) -> String:
	if buff_id.begins_with("skill_upgrade:"):
		return "%s强化" % CombatConfig.SKILLS[buff_id.trim_prefix("skill_upgrade:")]["name"]
	return {"move_plus": "疾行", "flying": "飞行", "debuff_immune": "净化", "direct_guard": "护体"}.get(buff_id, buff_id)


static func enemy_choice(choices: Array[String], unit: CombatUnit) -> String:
	if (unit.burned or unit.wet) and choices.has("debuff_immune"):
		return "debuff_immune"
	var ranking: Array[String] = []
	if unit.burned or unit.wet:
		ranking.assign(["debuff_immune", "direct_guard", "flying", "move_plus"])
	else:
		ranking.assign(["direct_guard", "flying", "move_plus", "debuff_immune"])
	for choice in choices:
		if choice.begins_with("skill_upgrade:"):
			return choice
	for preferred in ranking:
		if choices.has(preferred):
			return preferred
	return choices[0]
