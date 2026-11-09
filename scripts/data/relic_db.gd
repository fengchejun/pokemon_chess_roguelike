class_name RelicDB
extends RefCounted

## 当前遗物固定生效、全局唯一，不升级也不重复获得。
const DEFINITIONS := {
	"echo_gear": {
		"name": "回响齿轮",
		"category": "cycle",
		"description": "每名我方单位每场第3、6次成功施法不消耗PP，最多触发2次；吟唱和额外施法计数。",
	},
	"still_chant": {
		"name": "静咏刻印",
		"category": "cycle",
		"description": "每名我方单位每场前2次未移动时的成功施法不消耗PP。",
	},
	"overload_coil": {
		"name": "过载线圈",
		"category": "cycle",
		"description": "每项技能本场第一次降至0PP时，施法者获得8护盾并清除减速和定身；每项技能限一次。",
	},
	"echo_hourglass": {
		"name": "残响沙漏",
		"category": "cycle",
		"description": "我方吟唱成功宣告后被打断时返还1PP，每场最多一次。",
	},
	"flank_prism": {
		"name": "夹击棱镜",
		"category": "formation",
		"description": "目标相邻格内有另一名存活友军时，我方技能实际直伤+5；同一技能对同一目标限一次。",
	},
	"weakness_ledger": {
		"name": "弱点账本",
		"category": "formation",
		"description": "每轮首次命中标记目标，后续其他技能对标记目标实际直伤+3；每轮标记一个目标。",
	},
	"relay_sigil": {
		"name": "接力徽记",
		"category": "formation",
		"description": "每轮第一名成功施法且正交相邻友军的单位，使该友军下一次移动力+1。",
	},
	"watch_line": {
		"name": "守望刻线",
		"category": "formation",
		"description": "我方单位本轮未移动时，下一次具有明确射程的技能射程+1；每人每轮一次。",
	},
	"status_aftershock": {
		"name": "连锁余波",
		"category": "status",
		"description": "携带减益的敌人倒下时，将一种减益传给3格内最近敌人，每轮最多一次；冰冻不转移。",
	},
	"suppression_lock": {
		"name": "压制枷锁",
		"category": "status",
		"description": "每轮首次有我方单位获得冰冻、麻痹、定身或禁锢时，该单位剩余PP最高的技能失去1PP。",
	},
	"cleanse_circuit": {
		"name": "净化回路",
		"category": "status",
		"description": "每轮第一次主动清除我方异常时，目标获得4护盾和本回合移动力+1。",
	},
	"freeze_crack": {
		"name": "冻结裂响",
		"category": "status",
		"description": "冰冻敌人本次冰冻期间第一次受到我方技能直伤时，其四邻敌人各受2点固定伤害。",
	},
	"terrain_resonance": {
		"name": "地貌共鸣",
		"category": "terrain",
		"description": "我方生成或转换地形后，站在新地形上的每名友军获得3护盾；每人每轮一次。",
	},
	"migration_tracks": {
		"name": "迁徙足印",
		"category": "terrain",
		"description": "我方阶段开始时，站在草丛、藤蔓或冰面上的友军本回合移动力+1。",
	},
	"symbiotic_roots": {
		"name": "共生根系",
		"category": "terrain",
		"description": "我方召唤物最大生命+10；召唤物离场时，其主人最低PP技能恢复1PP，每轮每人一次。",
	},
	"overwrite_compass": {
		"name": "覆写罗盘",
		"category": "terrain",
		"description": "每场第一次成功施放并实际改变地形的技能不消耗PP。",
	},
	"herb_satchel": {
		"name": "采药袋",
		"category": "journey",
		"description": "每场额外生成1个果实，所有果实恢复量+2HP。",
	},
	"camp_ember": {
		"name": "篝火余温",
		"category": "journey",
		"description": "营地休息消耗-1份食物；HP为0的携带成员恢复至75%最大生命。",
	},
	"homeward_waypoint": {
		"name": "归途路标",
		"category": "journey",
		"description": "每层第一次返回营地不计入区域入侵压力，仍记录营地访问。",
	},
	"merchant_credentials": {
		"name": "行商凭据",
		"category": "journey",
		"description": "商人普通道具和技能强化费用降低2原质，最低1原质。",
	},
	"pressure_breaker": {
		"name": "逆压者",
		"category": "risk",
		"description": "黑化或超过第8轮的战斗中，每轮第一名成功施法者不消耗PP；每场最多3次。",
	},
	"nest_wedge": {
		"name": "破巢楔",
		"category": "risk",
		"description": "每座巢穴每轮首次受到玩家技能直伤+6；毁巢后每名存活我方单位最低PP技能恢复1PP。",
	},
	"boss_hunt": {
		"name": "猎首令",
		"category": "risk",
		"description": "每轮首次对首领的技能直伤+6；首领首次鼓舞延后到下一轮开始。",
	},
	"last_stand_ember": {
		"name": "背水火种",
		"category": "risk",
		"description": "每场第一次有非召唤物友军降至三分之一生命以下时，其获得8护盾和本回合移动力+1。",
	},
}


static func ids() -> Array:
	return DEFINITIONS.keys()


static func owned(stacks: Dictionary, relic_id: String) -> bool:
	return int(stacks.get(relic_id, 0)) > 0


static func name_of(relic_id: String) -> String:
	return String((DEFINITIONS.get(relic_id, {}) as Dictionary).get("name", relic_id))


static func description_of(relic_id: String) -> String:
	return String((DEFINITIONS.get(relic_id, {}) as Dictionary).get("description", ""))


static func category_of(relic_id: String) -> String:
	return String((DEFINITIONS.get(relic_id, {}) as Dictionary).get("category", ""))


static func offer(seed_value: int, battle_index: int, choice_index: int, stacks: Dictionary, count: int = 3) -> Array:
	var pool: Array = []
	for relic_id in ids():
		if not owned(stacks, String(relic_id)):
			pool.append(String(relic_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic:%d:%d:%d" % [seed_value, battle_index, choice_index])
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp = pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = temp
	var result: Array = []
	if pool.is_empty():
		return result
	result.append(pool[0])
	var first_category := category_of(String(pool[0]))
	for relic_id in pool.slice(1):
		if category_of(String(relic_id)) != first_category:
			result.append(relic_id)
			break
	for relic_id in pool:
		if result.size() >= count:
			break
		if not result.has(relic_id):
			result.append(relic_id)
	return result
