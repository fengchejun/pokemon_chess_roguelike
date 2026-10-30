class_name RelicDB
extends RefCounted

## 本局常驻遗物。所有数值都是每级增量；状态和额外推距在一级生效。
const MAX_RANK := 3
const DEFINITIONS := {
	"fire_mark": ["火印", "火系技能对敌直伤每级 +2；存活目标附灼烧。"],
	"burn_chaser": ["灼痕", "对已灼烧敌人的技能直伤每级 +5。"],
	"ember_recovery": ["余烬", "技能直接击倒已灼烧敌人时，施法者每级恢复 4 HP。"],
	"water_mark": ["潮印", "水系技能对敌直伤每级 +2；存活目标附浸湿。"],
	"wet_conductor": ["导雷", "电系技能对已浸湿敌人直伤每级 +6。"],
	"rushing_tide": ["激流", "水系技能对水格敌人直伤每级 +5。"],
	"green_pulse": ["绿脉", "站在草丛或藤蔓上的我方单位技能直伤每级 +4。"],
	"root_rest": ["根息", "我方阶段开始时，草丛或藤蔓上的友军每级恢复 2 HP。"],
	"root_bind": ["缠根", "对受藤蔓束缚或待定身敌人的技能直伤每级 +5。"],
	"rock_pulse": ["岩脉", "紧邻障碍的我方单位技能直伤每级 +4。"],
	"rock_armor": ["岩甲", "紧邻障碍的我方单位受到敌方技能直伤每级 −2。"],
	"wall_crash": ["冲壁", "我方推击敌人时碰撞伤害每级 +4。"],
	"frost_wet": ["霜寒", "冰系技能对已浸湿敌人直伤每级 +5。"],
	"wind_pressure": ["风压", "旧版遗物（推风已移除，不再生效；可出售）。"],
	"first_strike": ["猎手", "技能对满血敌人的首次直伤每级 +4。"],
}


static func ids() -> Array:
	return DEFINITIONS.keys().filter(func(id): return id != "wind_pressure")


static func rank(stacks: Dictionary, relic_id: String) -> int:
	return clampi(int(stacks.get(relic_id, 0)), 0, MAX_RANK)


static func name_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[0])


static func description_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[1])


static func offer(seed_value: int, battle_index: int, choice_index: int, stacks: Dictionary, count: int = 3) -> Array:
	var pool: Array = []
	for relic_id in ids():
		if rank(stacks, relic_id) < MAX_RANK:
			pool.append(relic_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic:%d:%d:%d" % [seed_value, battle_index, choice_index])
	var result: Array = []
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


static func on_grass_or_vines(state, unit: CombatUnit) -> bool:
	return GridSpec.is_inside(unit.cell) and [TerrainDB.GRASS, TerrainDB.VINES].has(state.terrain_at(unit.cell))


static func damage_bonus(state, source: CombatUnit, target: CombatUnit, opts: Dictionary) -> int:
	if source == null or source.side != "player" or target.side != "enemy" or not bool(opts.get("skill_direct", false)):
		return 0
	var stacks: Dictionary = state.relic_stacks
	var element := String(opts.get("element", ""))
	var bonus := 0
	if element == "fire":
		bonus += 2 * rank(stacks, "fire_mark")
	if target.burn_ticks > 0:
		bonus += 5 * rank(stacks, "burn_chaser")
	if element == "water":
		bonus += 2 * rank(stacks, "water_mark")
		if state.terrain_at(target.cell) == TerrainDB.WATER:
			bonus += 5 * rank(stacks, "rushing_tide")
	if element == "electric" and target.slow_ticks > 0:
		bonus += 6 * rank(stacks, "wet_conductor")
	if String(opts.get("skill_id", "")) in ["frozen_ground", "ice_glide", "freeze_ray", "ice_shard"] and target.slow_ticks > 0:
		bonus += 5 * rank(stacks, "frost_wet")
	if on_grass_or_vines(state, source):
		bonus += 4 * rank(stacks, "green_pulse")
	if target.vine_ticks > 0 or target.root_pending:
		bonus += 5 * rank(stacks, "root_bind")
	if state.adjacent_to_obstacle(source):
		bonus += 4 * rank(stacks, "rock_pulse")
	if target.hp == target.max_hp:
		bonus += 4 * rank(stacks, "first_strike")
	return bonus


static func incoming_reduction(state, source: CombatUnit, target: CombatUnit, opts: Dictionary) -> int:
	if source == null or source.side != "enemy" or target.side != "player" or not bool(opts.get("skill_direct", false)):
		return 0
	return 2 * rank(state.relic_stacks, "rock_armor") if state.adjacent_to_obstacle(target) else 0
