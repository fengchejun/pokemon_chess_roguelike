class_name RelicDB
extends RefCounted

## 遗物定义与抽取。遗物在本局内唯一，不重复获得。
## 升级型遗物只有获得前置遗物后才会进入候选池；领取时会替换前置遗物。

const COMMON := "common"
const RARE := "rare"
const LEGENDARY := "legendary"

const RARITIES := {
	"common": {"name": "普通", "weight": 60, "color": Color("b7c4d4")},
	"rare": {"name": "稀有", "weight": 30, "color": Color("69a9ff")},
	"legendary": {"name": "传奇", "weight": 10, "color": Color("f4bd58")},
}
const DEFERRED_CHOICE_KINDS := ["mage_notes", "worn_chest", "unbalanced_scales", "magic_end"]
const MERCHANT_UNSAFE_IDS := ["mage_notes", "worn_chest", "unbalanced_scales", "mystery_dice", "magic_end"]

const DEFINITIONS := {
	# 普通
	"fire_carbon": {
		"name": "火之碳", "rarity": "common", "category": "属性",
		"description": "火属性伤害 +20%。",
	},
	"water_tear": {
		"name": "水之泪", "rarity": "common", "category": "属性",
		"description": "水属性伤害 +20%。",
	},
	"grass_flute": {
		"name": "草之笛", "rarity": "common", "category": "属性",
		"description": "草属性伤害 +20%。",
	},
	"thunder_fang": {
		"name": "雷之牙", "rarity": "common", "category": "属性",
		"description": "电属性伤害 +20%。",
	},
	"mountain_jade": {
		"name": "山之玉", "rarity": "common", "category": "属性",
		"description": "岩属性伤害 +20%。",
	},
	"healing_berry": {
		"name": "治愈莓果", "rarity": "common", "category": "资源",
		"description": "每场战斗在平地或草丛随机生成 1 个莓果。我方单位触碰后回复 10% 最大生命值，莓果消失。",
	},
	"essence_pouch": {
		"name": "原质收集囊", "rarity": "common", "category": "资源",
		"description": "战斗中每次通过任意来源获得原质时，额外获得 1 点。",
	},
	"mage_notes": {
		"name": "法师笔记", "rarity": "common", "category": "资源",
		"description": "获取后选择 3 只宝可梦，各学习 1 个随机本属性普通技能。",
		"choice": "mage_notes",
	},
	"worn_chest": {
		"name": "破旧宝箱", "rarity": "common", "category": "资源",
		"description": "获取后随机获得 1 件遗物：普通 50%、稀有 30%、传奇 20%。",
		"choice": "worn_chest",
	},
	"terrain_obelisk": {
		"name": "地势方尖碑", "rarity": "common", "category": "地形",
		"description": "生成新地形时，位于其上的我方单位获得相当于 10% 最大生命值的护盾。生成障碍不触发。",
	},
	"leyline_rope": {
		"name": "系脉绳", "rarity": "common", "category": "地形",
		"description": "所有临时地形改为永久存在。",
	},
	"deep_sapphire": {
		"name": "深蓝宝石", "rarity": "common", "category": "地形",
		"description": "同一浅水格累计 3 次后变为深水。",
	},
	"breach_pick": {
		"name": "破垒镐", "rarity": "common", "category": "地形",
		"description": "破坏障碍后，下一次攻击伤害 +5%。",
	},
	"holy_shield_fragment": {
		"name": "圣盾碎片", "rarity": "common", "category": "增益",
		"description": "获得护盾时，护盾值 +5。可通过特殊事件进化。",
		"upgrade_to": "nameless_shield",
	},
	"ward_charm": {
		"name": "驱邪符", "rarity": "common", "category": "增益",
		"description": "受到异常后，下次行动行动力 +1。当前异常结束后才能再次刷新。",
	},
	"broken_sword": {
		"name": "断剑", "rarity": "common", "category": "增益",
		"description": "对敌人造成的伤害 +5%。可升级为无名长剑。",
		"upgrade_to": "nameless_blade",
	},
	"crimson_heart": {
		"name": "赤血之心", "rarity": "common", "category": "增益",
		"description": "全队最大生命值 +15%。获取时全队回复 20 点生命。",
		"choice": "crimson_heart",
	},
	"ember_relic": {
		"name": "余烬", "rarity": "common", "category": "异常",
		"description": "灼烧伤害 +5%。",
	},
	"water_nymph": {
		"name": "水中仙", "rarity": "common", "category": "异常",
		"description": "浸湿额外减少 1 点行动力。",
	},
	"thunder_echo_stone": {
		"name": "电鸣石", "rarity": "common", "category": "异常",
		"description": "处于感电或麻痹状态的目标受到的伤害 +5%。",
	},
	"thorn_mark": {
		"name": "荆之印记", "rarity": "common", "category": "异常",
		"description": "目标受到禁锢或寄生时进入重伤，受到的治疗与护盾效果 -30%。",
	},
	"collision_expert": {
		"name": "碰撞专家", "rarity": "common", "category": "阵型",
		"description": "碰撞伤害 +5 点。",
	},
	"combo_dagger": {
		"name": "连击匕首", "rarity": "common", "category": "阵型",
		"description": "同一敌人每累计受到我方 2 次直接伤害，额外受到 5 点伤害。",
	},
	"marching_banner": {
		"name": "行军旗", "rarity": "common", "category": "阵型",
		"description": "每回合我方第一个行动的单位行动力 +1。",
	},
	"blood_orb": {
		"name": "鲜血宝珠", "rarity": "common", "category": "风险",
		"description": "获取时全队损失 30% 最大生命值。本层造成的伤害 +30%。",
		"choice": "blood_orb",
	},
	"sealed_necronomicon": {
		"name": "未解封的死灵书", "rarity": "common", "category": "风险",
		"description": "队伍最大生命值上限 -20%。获取时全队当前 PP 减半。特殊事件解封后恢复最大生命值上限。",
		"choice": "sealed_necronomicon",
	},

	# 稀有
	"layered_mountains": {
		"name": "山峦叠嶂", "rarity": "rare", "category": "属性",
		"description": "场上每有 1 个岩石格，岩系宝可梦伤害 +10%。",
	},
	"unbalanced_scales": {
		"name": "不平天秤", "rarity": "rare", "category": "资源",
		"description": "摧毁 1 件遗物，换得 2 件随机遗物：普通 50%、稀有 30%、传奇 20%。",
		"choice": "unbalanced_scales",
	},
	"treasure_pocket": {
		"name": "万宝口袋", "rarity": "rare", "category": "资源",
		"description": "战斗所得原质 +30%。战后有 30% 概率获得 1 件遗物。本局资源收益 +50%。",
	},
	"ice_age": {
		"name": "冰河时代", "rarity": "rare", "category": "地形",
		"description": "单位在冰面停留 1 回合后被冰冻。敌方单位位于冰面时行动力 -1。",
	},
	"dragon_blue_flame": {
		"name": "龙脉蓝焰", "rarity": "rare", "category": "地形",
		"description": "燃烧格变为永久蓝焰。站上施放火系技能必定造成烧伤。技能附带或目标已有烧伤时，再 +20% 伤害。",
	},
	"storm_ascension": {
		"name": "天雷证道", "rarity": "rare", "category": "地形",
		"description": "每回合雷击随机 3 格。电系宝可梦被命中后，下次攻击 +50% 伤害并附加麻痹。",
	},
	"forest_myriad": {
		"name": "森罗万象", "rarity": "rare", "category": "地形",
		"description": "第 2 回合起，已有草丛各扩张至自身 3×3，不覆盖浅水以外的特殊地形。草系位于草丛时受伤 -10%，受到火系伤害时受伤 +20%。",
	},
	"crashing_waves": {
		"name": "惊涛骇浪", "rarity": "rare", "category": "地形",
		"description": "第 2 回合起浅水掀起巨浪，对位于浅水的单位造成 10% 最大生命值伤害。水系在浅水或深水时下次行动力 +1。",
	},
	"nameless_shield": {
		"name": "无名盾牌", "rarity": "rare", "category": "增益",
		"description": "所有护盾值 +20%。由圣盾碎片升级获得。",
		"requires": "holy_shield_fragment", "replaces": "holy_shield_fragment",
		"upgrade_to": "dawn_lord_radiance",
	},
	"nameless_blade": {
		"name": "无名长剑", "rarity": "rare", "category": "增益",
		"description": "技能伤害 +30%。由断剑升级获得。",
		"requires": "broken_sword", "replaces": "broken_sword",
		"upgrade_to": "ancient_dragon_roar",
	},
	"white_cloak": {
		"name": "纯白斗篷", "rarity": "rare", "category": "增益",
		"description": "本场战斗中，每名我方单位免疫第一次受到的减益或异常状态。",
	},
	"haste_clock": {
		"name": "急行钟表", "rarity": "rare", "category": "增益",
		"description": "本场所有单位首次行动时行动力 +1。受到行动力减益后，获得相当于自身 10% 最大生命值的护盾。",
	},
	"bottled_dragon_blood": {
		"name": "瓶装龙血", "rarity": "rare", "category": "增益",
		"description": "全队恢复至满生命。最大生命值 +20%，全员技能伤害 +20%。",
		"choice": "bottled_dragon_blood",
	},
	"sun_totem": {
		"name": "太阳图腾", "rarity": "rare", "category": "异常",
		"description": "灼烧可叠至 5 层后引爆并结算全部灼烧。目标因此死亡时，对自身 3×3 造成 20% 最大生命值伤害并传递溢出层数。",
	},
	"sorrow": {
		"name": "悲伤", "rarity": "rare", "category": "异常",
		"description": "浸湿可叠层，3 层时转为冰冻。冰冻目标受到的伤害 +20%。",
	},
	"thorn_crown": {
		"name": "棘之冠", "rarity": "rare", "category": "异常",
		"description": "所有草属性伤害额外附加 1 层重伤。",
	},
	"electric_echo": {
		"name": "电能回响", "rarity": "rare", "category": "异常",
		"description": "感电不再转为麻痹且不衰减。电系技能施加 2 层感电，达到 4 层后清空并使本场电系伤害 +20%。麻痹视为 2 层感电，溢出保留。",
	},
	"safety_button": {
		"name": "保险按钮", "rarity": "rare", "category": "阵型",
		"description": "敌方多于我方：受伤 -10%。我方多于敌方：伤害 +10%。人数相等：全队回复 10% 已损失生命。",
	},
	"impact_code": {
		"name": "撞击准则", "rarity": "rare", "category": "阵型",
		"description": "碰撞额外造成目标 10% 最大生命值伤害。我方造成的强制位移距离 +1。",
	},
	"evil_coin": {
		"name": "邪恶金币", "rarity": "rare", "category": "风险",
		"description": "随机失去 2 件遗物并换为等量金币。每失去 1 件遗物，全队伤害 +20%。",
		"choice": "evil_coin",
	},
	"mystery_dice": {
		"name": "神秘骰子", "rarity": "rare", "category": "风险",
		"description": "掷骰决定效果。\n1：每名队员失去当前最大生命值的一半且 PP 减半，全队永久伤害 -20%。\n2：当前原质减半，下场战斗伤害 -10%。\n3：全队恢复一半最大生命值和 PP，获得原质。\n4：永久伤害 +20%，获得 1 件稀有或 2 件普通遗物。\n5：伤害 +30%，获得 1 件传奇或 2 件稀有遗物。\n6：获得 2 件传奇遗物。",
		"choice": "mystery_dice",
	},

	# 传奇
	"prism_mirror": {
		"name": "五棱玄镜", "rarity": "legendary", "category": "属性",
		"description": "所有属性伤害 +30%。属性克制倍率提升至 1.5 倍。",
	},
	"magic_end": {
		"name": "术之尽头", "rarity": "legendary", "category": "资源",
		"description": "获取时选择 1 个我方单位，从 3 个魔法中学习 1 个。\n超魔死光：直线 6 格造成 40 点伤害，破坏路径障碍，每场 1 次。\n时镜跃迁：移至任意位置并免疫下次攻击，不消耗施法次数，每场 1 次。\n魔之钥：3 名我方单位各从自身技能池学习 2 个技能，可含特殊技能，每局 1 次。",
		"choice": "magic_end",
		"upgrade_skills": ["ultra_death_ray", "time_mirror_leap", "mage_key"],
	},
	"summoner_crown": {
		"name": "召唤之王权", "rarity": "legendary", "category": "资源",
		"description": "召唤不消耗施法次数。召唤物获得相当于召唤者 30% 最大生命值的护盾，护盾不随时间消失。召唤槽 +1，每回合最多召唤 1 个。",
	},
	"dawn_lord_radiance": {
		"name": "晨曦之主的光辉", "rarity": "legendary", "category": "增益",
		"description": "所有获得的护盾值 +30%。战斗开始时全队获得相当于各自 20% 最大生命值的护盾。每次受到治疗时，额外获得相当于自身 10% 最大生命值的护盾，可叠加。我方护盾不随时间消失。由无名盾牌升级获得。",
		"requires": "nameless_shield", "replaces": "nameless_shield",
	},
	"ancient_dragon_roar": {
		"name": "太古龙王的怒号", "rarity": "legendary", "category": "增益",
		"description": "伤害增幅 +50%。本场每击杀 1 个单位，全队伤害增幅 +10%，可累计。由无名长剑升级获得。",
		"requires": "nameless_blade", "replaces": "nameless_blade",
	},
	"dead_poem": {
		"name": "亡者诗篇", "rarity": "legendary", "category": "增益",
		"description": "敌方受到的生命值恢复与护盾效果 -50%，可与重伤叠加。本场首个阵亡的我方单位复活并恢复 50% 最大生命值。",
	},
	"witch_cauldron": {
		"name": "女巫坩埚", "rarity": "legendary", "category": "异常",
		"description": "仅我方生效。获得异常时额外 +1 层或 +1 回合。带异常死亡时，剩余异常转给最近的敌方单位。",
	},
	"fenrir_lock": {
		"name": "芬里尔之锁", "rarity": "legendary", "category": "阵型",
		"description": "每场只触发一次，按首次进入的生命值比例区间生效。\n高于 75%：全队行动力 +2。\n高于 50% 且不高于 75%：当前生命值比例最低的我方单位免疫下次伤害。\n不高于 50%：敌方全员禁锢、清除护盾并受到伤害 +20%。",
	},
	"bagua_compass": {
		"name": "八卦罗盘", "rarity": "legendary", "category": "阵型",
		"description": "同一敌人一回合内受到 2 个以上我方单位攻击时，受到随机 10%～20% 最大生命值的克制元素伤害。",
	},
	"blood_dragon_dance": {
		"name": "血龙狂舞", "rarity": "legendary", "category": "风险",
		"description": "每回合全队损失相当于 10% 最大生命值的真实伤害，无视护盾和减伤。全队伤害增幅 +50%。造成伤害时回复伤害值 30% 的生命。常规治疗无效。",
	},
}


static func ids() -> Array:
	return DEFINITIONS.keys()


static func get_def(relic_id: String) -> Dictionary:
	return DEFINITIONS.get(relic_id, {})


static func name_of(relic_id: String) -> String:
	return String(get_def(relic_id).get("name", relic_id))


static func description_of(relic_id: String) -> String:
	return String(get_def(relic_id).get("description", ""))


static func rarity_of(relic_id: String) -> String:
	return String(get_def(relic_id).get("rarity", "common"))


static func rarity_name(relic_id: String) -> String:
	return String(RARITIES.get(rarity_of(relic_id), RARITIES["common"]).get("name", "普通"))


static func owned(stacks: Dictionary, relic_id: String) -> bool:
	return int(stacks.get(relic_id, 0)) > 0


static func is_upgrade(relic_id: String) -> bool:
	return String(get_def(relic_id).get("requires", "")) != ""


static func requires_followup_choice(relic_id: String) -> bool:
	return DEFERRED_CHOICE_KINDS.has(String(get_def(relic_id).get("choice", "")))


static func merchant_allowed(relic_id: String) -> bool:
	return not MERCHANT_UNSAFE_IDS.has(relic_id)


static func available_ids(stacks: Dictionary) -> Array:
	var result: Array = []
	for relic_id in ids():
		var id := String(relic_id)
		if owned(stacks, id):
			continue
		var requires := String(get_def(id).get("requires", ""))
		if requires != "" and not owned(stacks, requires):
			continue
		var replaced := String(get_def(id).get("replaces", ""))
		if replaced != "" and not owned(stacks, replaced):
			continue
		var base_upgrade_to := String(get_def(id).get("upgrade_to", ""))
		if base_upgrade_to != "" and owned(stacks, base_upgrade_to):
			continue
		result.append(id)
	return result


static func offer(seed_value: int, battle_index: int, choice_index: int, stacks: Dictionary, count: int = 3) -> Array:
	var pool := available_ids(stacks)
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic-v2:%d:%d:%d" % [seed_value, battle_index, choice_index])
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value = pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = value
	var result: Array = []
	var rarities_used := {}
	for relic_id in pool:
		var rarity := rarity_of(String(relic_id))
		if result.is_empty() or result.size() >= count:
			result.append(relic_id)
			rarities_used[rarity] = true
			if result.size() >= count:
				break
		elif not rarities_used.has(rarity) or result.size() >= 2:
			result.append(relic_id)
			rarities_used[rarity] = true
		if result.size() >= count:
			break
	for relic_id in pool:
		if result.size() >= count:
			break
		if not result.has(relic_id):
			result.append(relic_id)
	return result.slice(0, count)


static func random_id(seed_value: int, rarity: String = "", stacks: Dictionary = {}) -> String:
	var pool: Array = []
	for relic_id in available_ids(stacks):
		if rarity == "" or rarity_of(String(relic_id)) == rarity:
			pool.append(String(relic_id))
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic-random:%d:%s" % [seed_value, rarity])
	return pool[rng.randi_range(0, pool.size() - 1)]


static func weighted_random_id(seed_value: int, stacks: Dictionary = {}, weights: Dictionary = {}, allow_choices: bool = true) -> String:
	var pool := available_ids(stacks)
	if not allow_choices:
		pool = pool.filter(func(id): return merchant_allowed(String(id)))
	if pool.is_empty():
		return ""
	var resolved_weights := weights
	if resolved_weights.is_empty():
		for rarity in RARITIES:
			resolved_weights[rarity] = int(RARITIES[rarity]["weight"])
	var total := 0
	for rarity in resolved_weights:
		if pool.any(func(id): return rarity_of(String(id)) == String(rarity)):
			total += maxi(0, int(resolved_weights[rarity]))
	if total <= 0:
		return String(pool[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic-weighted:%d" % seed_value)
	var roll := rng.randi_range(1, total)
	var chosen_rarity := ""
	for rarity in resolved_weights:
		roll -= maxi(0, int(resolved_weights[rarity]))
		if roll <= 0:
			chosen_rarity = String(rarity)
			break
	var matching := pool.filter(func(id): return rarity_of(String(id)) == chosen_rarity)
	if matching.is_empty():
		matching = pool
	return String(matching[rng.randi_range(0, matching.size() - 1)])


static func all_normal_skills_for_element(element: String) -> Array:
	var result: Array = []
	for skill_id in SkillDB.DEFS:
		var id := String(skill_id)
		if SkillDB.element_of(id) == element and not SkillDB.is_special(id):
			result.append(String(skill_id))
	result.sort()
	return result


static func ids_of_rarity(rarity: String) -> Array:
	return ids().filter(func(id): return rarity_of(id) == rarity)


static func display_name_of(relic_id: String) -> String:
	return "%s【%s】" % [name_of(relic_id), rarity_name(relic_id)]
