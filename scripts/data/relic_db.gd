class_name RelicDB
extends RefCounted

## 本局常驻遗物。所有数值都是每级增量；状态和额外推距在一级生效。
const MAX_RANK := 3
# 稀有度独立于遗物等级，用于分级战利品。
const COMMON := "common"
const RARE := "rare"
const LEGENDARY := "legendary"
const RARITY_NAMES := {
	COMMON: "普通遗物",
	RARE: "稀有遗物",
	LEGENDARY: "传奇遗物",
}
const DEFINITIONS := {
	"fire_mark": ["火印", "火系技能对敌直伤每级 +2；存活目标附灼烧。", COMMON],
	"burn_chaser": ["灼痕", "对已灼烧敌人的技能直伤每级 +5。", COMMON],
	"ember_recovery": ["余烬", "技能直接击倒已灼烧敌人时，施法者每级恢复 4 HP。", COMMON],
	"water_mark": ["潮印", "水系技能对敌直伤每级 +2；存活目标附浸湿。", COMMON],
	"wet_conductor": ["导雷", "电系技能对已浸湿敌人直伤每级 +6。", COMMON],
	"rushing_tide": ["激流", "水系技能对水格敌人直伤每级 +5。", COMMON],
	"green_pulse": ["绿脉", "站在草丛或藤蔓上的我方单位技能直伤每级 +4。", COMMON],
	"root_rest": ["根息", "我方阶段开始时，草丛或藤蔓上的友军每级恢复 2 HP。", COMMON],
	"root_bind": ["缠根", "对受禁锢或待定身敌人的技能直伤每级 +5。", COMMON],
	"rock_pulse": ["岩脉", "紧邻障碍的我方单位技能直伤每级 +4。", COMMON],
	"rock_armor": ["岩甲", "紧邻障碍的我方单位受到敌方技能直伤每级 −2。", COMMON],
	"wall_crash": ["冲壁", "我方推击敌人时碰撞伤害每级 +4。", COMMON],
	"frost_wet": ["霜寒", "冰系技能对已浸湿敌人直伤每级 +5。", COMMON],
	"wind_pressure": ["风压", "旧版遗物（推风已移除，不再生效；可出售）。", COMMON],
	"first_strike": ["猎手", "技能对满血敌人的首次直伤每级 +4。", COMMON],
	"warm_crystal": ["余温晶石", "对站在火焰或蓝火上的敌人，技能直伤每级 +4。", RARE],
	"flow_scale": ["导流鳞", "站在浅水或深水中的我方单位，技能直伤每级 +4。", RARE],
	"formation_stone": ["固阵石", "与友军正交相邻的我方单位，受到的敌方技能直伤每级 −2。", RARE],
	"breach_emblem": ["破阵徽", "对生命不超过一半的敌人，技能直伤每级 +3。", RARE],
	"furnace_core": ["赤炉核心", "火焰增幅每吸收一格火焰，额外蓄积每级 3 点直伤。", LEGENDARY],
	"rain_beacon": ["暴雨信标", "电系技能对站在水格上的敌人，直伤每级 +6。", LEGENDARY],
	"forest_shelter": ["森之庇护", "我方阶段开始时，深草或藤蔓上的存活友军每级恢复 3 HP。", LEGENDARY],
	"ridge_crown": ["山脊王冠", "紧邻障碍的我方单位技能直伤每级 +6，受到的敌方技能直伤每级 −3。", LEGENDARY],
	"pulling_hammer": ["牵引重锤", "我方推击造成的碰撞伤害每级额外 +6。", LEGENDARY],
	"companion_oath": ["同行誓约", "捕获时每只有效支援伙伴每级额外提供 2 个百分点，每级最多 +6 个百分点。", LEGENDARY],
}


static func ids() -> Array:
	return DEFINITIONS.keys().filter(func(id): return id != "wind_pressure")


static func ids_of_rarity(rarity: String) -> Array:
	return ids().filter(func(id): return rarity_of(id) == rarity)


static func rank(stacks: Dictionary, relic_id: String) -> int:
	return clampi(int(stacks.get(relic_id, 0)), 0, MAX_RANK)


static func name_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[0])


static func rarity_of(relic_id: String) -> String:
	var definition: Array = DEFINITIONS.get(relic_id, [])
	return String(definition[2]) if definition.size() > 2 else COMMON


static func rarity_name_of(relic_id: String) -> String:
	return String(RARITY_NAMES.get(rarity_of(relic_id), RARITY_NAMES[COMMON]))


static func display_name_of(relic_id: String) -> String:
	return "%s【%s】" % [name_of(relic_id), rarity_name_of(relic_id)]


static func description_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[1])


static func offer(seed_value: int, battle_index: int, choice_index: int, stacks: Dictionary, count: int = 3) -> Array:
	var pool: Array = []
	for relic_id in ids_of_rarity(COMMON):
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
	if target.imprison_ticks > 0 or target.root_pending:
		bonus += 5 * rank(stacks, "root_bind")
	if state.adjacent_to_obstacle(source):
		bonus += 4 * rank(stacks, "rock_pulse") + 6 * rank(stacks, "ridge_crown")
	if state.is_burning_ground(target.cell):
		bonus += 4 * rank(stacks, "warm_crystal")
	if TerrainDB.is_water_body(state.terrain_at(source.cell)):
		bonus += 4 * rank(stacks, "flow_scale")
	if target.hp * 2 <= target.max_hp:
		bonus += 3 * rank(stacks, "breach_emblem")
	if element == "electric" and TerrainDB.is_water_body(state.terrain_at(target.cell)):
		bonus += 6 * rank(stacks, "rain_beacon")
	if target.hp == target.max_hp:
		bonus += 4 * rank(stacks, "first_strike")
	return bonus


static func incoming_reduction(state, source: CombatUnit, target: CombatUnit, opts: Dictionary) -> int:
	if source == null or source.side != "enemy" or target.side != "player" or not bool(opts.get("skill_direct", false)):
		return 0
	var stacks: Dictionary = state.relic_stacks
	var reduction := 2 * rank(stacks, "rock_armor") + 3 * rank(stacks, "ridge_crown") if state.adjacent_to_obstacle(target) else 0
	if state.alive_units("player").any(func(ally): return GridSpec.manhattan(ally.cell, target.cell) == 1):
		reduction += 2 * rank(stacks, "formation_stone")
	return reduction
