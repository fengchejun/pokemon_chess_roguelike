class_name BattleBuffDB
extends RefCounted

## 奖励格的一场战斗强化。技能强化只提供给已学会对应技能的怪物。

const DEFS := {
	"move_plus": {"name": "疾行", "desc": "本场移动力 +1。"},
	"flight": {"name": "飞行", "desc": "越过单位、障碍和致死地形；停在深水、深坑和火焰上不受地面效果。"},
	"status_immune": {"name": "净化", "desc": "免疫灼烧与浸湿，并立即清除这两种状态。"},
	"direct_guard": {"name": "守护", "desc": "受到的技能直接伤害 -1；不抵消碰撞、导电、燃烧或坠落。"},
	"fire_burst": {"name": "火球余焰", "desc": "火球术的外围命中也施加灼烧。", "skill": "fire_burst"},
	"flame_charge": {"name": "冲锋炽痕", "desc": "闪焰冲锋沿途额外造成 1 点直接伤害。", "skill": "flame_charge"},
	"water_flow": {"name": "湍流", "desc": "水流击退距离增加 1 格。", "skill": "water_flow"},
	"rain_call": {"name": "骤雨", "desc": "造雨术立即浸湿范围内的非水系单位。", "skill": "rain_call"},
	"electric_arc": {"name": "湿电", "desc": "放电命中的单位获得浸湿。", "skill": "electric_arc"},
	"rock_break": {"name": "裂岩", "desc": "碎岩可击碎易碎地块。", "skill": "rock_break"},
	"rock_push": {"name": "猛推", "desc": "推击击退距离增加 1 格。", "skill": "rock_push"},
	"rock_create": {"name": "坚壁", "desc": "造岩短墙多持续一轮。", "skill": "rock_create"},
}


static func eligible(unit: CombatUnit) -> Array:
	var result: Array = []
	for id in DEFS:
		var skill_id := String(DEFS[id].get("skill", ""))
		if skill_id == "" or (not unit.is_trainer and unit.skills.has(skill_id)):
			result.append(id)
	result.sort()
	return result


static func offer(unit: CombatUnit, run_seed: int, battle_index: int) -> Array:
	var pool := eligible(unit)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("battle_buff:%d:%d:%d" % [run_seed, battle_index, unit.uid])
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var old = pool[i]
		pool[i] = pool[j]
		pool[j] = old
	return pool.slice(0, mini(2, pool.size()))


static func name_of(id: String) -> String:
	return String(DEFS.get(id, {}).get("name", id))


static func desc_of(id: String) -> String:
	return String(DEFS.get(id, {}).get("desc", ""))
