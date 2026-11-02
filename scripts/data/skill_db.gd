class_name SkillDB
extends RefCounted

## 七系目标技能与旧版兼容技能。kind 决定瞄准方式：
##  ray       行列射线（被第一个单位或障碍截断）
##  charge    闪焰冲锋：正交1至2格选方向，逐格前进并在撞击时停下
##  unit      单体选中
##  cell      指定落点
##  teleport  自身瞬移
##  direction 造岩：选择方向

const DEFS := {
	"fire_burst": {"name": "火球术", "element": "fire", "kind": "ray", "min_range": 2, "max_range": 4, "damage": 18, "ranged": true, "channel": true, "desc": "锁定射程 2–4 的格子，下次本方阶段开始落下；九宫格内各受 18 点基础伤害。吟唱后下一阶段不能行动，可被死亡、冻结或麻痹打断。"},
	"fire_amplify": {"name": "火焰增幅", "element": "fire", "kind": "self", "damage": 0, "ranged": false, "desc": "熄灭自身曼哈顿 2 格内所有燃烧格，每格积累 5 点增幅；下一次实际造成技能直伤时，每个受击单位额外承受全部增幅。"},
	"flame_jet": {"name": "喷射火焰", "element": "fire", "kind": "direction", "damage": 10, "adjacent_bonus": 3, "ranged": true, "desc": "沿选定方向喷射 3 格；障碍截断；命中单位受到 10 点基础伤害并灼烧，紧邻自身的单位额外受到 3 点伤害。"},
	"rain_call": {"name": "造雨术", "element": "water", "kind": "cell", "range": 4, "damage": 0, "ranged": false, "desc": "指定曼哈顿距离 4 格内中心，周围 3×3 格化为浅水；障碍与深坑不变。"},
	"surf": {"name": "冲浪", "element": "water", "kind": "self", "damage": 0, "ranged": false, "desc": "施放当回合及后两回合，沿相连浅水或深水移动不消耗普通移动机会，可重复移动并越过敌方单位；不能停在单位或障碍格。"},
	"mirror_water_moon": {"name": "镜花水月", "element": "water", "kind": "self", "damage": 0, "ranged": false, "battle_limit": 1, "category": "special", "desc": "水系特殊技能，每场限用一次。施加持续三回合的镜花水月：可移动到任意未被占用的浅水或深水格且不消耗普通移动机会；水系技能基础直伤 +5。施放时使全场敌人浸湿一回合；首次受到实际伤害时提前结束状态并免疫该次伤害。"},
	"tsunami": {"name": "海啸", "element": "water", "kind": "direction", "damage": 18, "ranged": true, "channel": true, "desc": "选择方向警示前方宽 5、长 5 的固定区域；下次本方阶段开始，对区域内当时站在水格上的敌方单位造成 18 点基础直伤；施法者该阶段不能行动。"},
	"rock_push": {"name": "推击", "element": "rock", "kind": "unit", "range": 1, "damage": 13, "ranged": false, "desc": "对相邻单位造成 13 点基础伤害并推开一格。"},
	"rock_break": {"name": "碎岩", "element": "rock", "kind": "unit", "range": 2, "damage": 10, "ranged": true, "desc": "曼哈顿 2 格内攻击单位造成 10 点基础伤害，命中障碍扣 1 点耐久；解除冰冻时无视冰冻免伤并造成三倍伤害。"},
	"rock_slide": {"name": "岩崩", "element": "rock", "kind": "cell", "range": 3, "damage": 30, "ranged": true, "channel": true, "desc": "锁定曼哈顿 3 格内一格；下次本方阶段开始，对该格当时的单位造成 30 点基础伤害，可误伤友军。"},
	"earth_shake": {"name": "撼地", "element": "rock", "kind": "direction", "damage": 18, "ranged": true, "channel": true, "desc": "蓄力锁定前方 3×3 格；下一本方阶段开始，对范围内敌人造成 18 点基础伤害，摧毁岩障和树木；平地变易碎地块、易碎地块变深坑。破障格本次不再改变地形，站在塌陷格上的地面单位立即坠落。"},
	"lightning": {"name": "打雷", "element": "electric", "kind": "self", "damage": 18, "ranged": true, "channel": true, "desc": "锁定全场所有敌方单位当前格子；下次本方阶段开始，对固定落点上的单位造成 18 点基础伤害并感电，可误伤友军。"},
	"electric_arc": {"name": "放电", "element": "electric", "kind": "cell", "range": 2, "damage": 10, "ranged": true, "desc": "可指定曼哈顿距离两格内的单位造成 10 点基础伤害，也可选择水域沿连通水域传导；附近存在水域不限制旱地目标。"},
	"volt_replace": {"name": "伏特替换", "element": "electric", "kind": "unit", "range": 3, "damage": 0, "ranged": false, "desc": "与曼哈顿 1～3 格内的单位交换位置，或移动到范围内可站立空格；无视途中障碍。"},
	"wild_vines": {"name": "疯狂藤蔓", "element": "grass", "kind": "direction", "damage": 0, "ranged": false, "desc": "在前方两格生成藤蔓；障碍阻挡生成。生成时或后来停在藤蔓上的地面单位，下一次移动机会受阻。"},
	"herbal_heal": {"name": "药草治疗", "element": "grass", "kind": "self", "damage": 0, "ranged": false, "channel": true, "desc": "锁定宣告时自身所在格；下次本方阶段开始，为该格曼哈顿 2 格内友军回复 8 HP；可被打断，结算阶段不能行动。"},
	"leech_seed": {"name": "寄生种子", "element": "grass", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "使相邻敌人寄生；每次整轮结算目标失去 4 HP、存活的施法者恢复至多 4 HP。目标受到其他实际伤害时先清除寄生。"},
	"tree_man": {"name": "大树守卫", "element": "grass", "kind": "cell", "range": 3, "damage": 0, "ranged": false, "desc": "立即在曼哈顿 3 格内空格召唤树人，基础 10 HP；落点周围八格每处水域 +3 HP、草丛/藤蔓 +5 HP、树木 +5 HP 和 5 技能威力。每名单位最多拥有一个存活召唤物，出生轮不能行动。"},
	"tree_wrath": {"name": "大树之怒", "element": "grass", "kind": "unit", "range": 1, "damage": 10, "ranged": false, "desc": "对相邻一格的一名敌方单位造成 10 点基础伤害。"},
	"frozen_ground": {"name": "冰封大地", "element": "water", "kind": "direction", "damage": 0, "ranged": false, "desc": "前方 3×3 地形生成冰面，可覆盖深水和深坑。"},
	"ice_glide": {"name": "溜冰", "element": "water", "kind": "self", "damage": 0, "ranged": false, "desc": "施放当回合及后两回合，沿相连冰面移动不消耗普通移动机会，可重复移动并越过敌方单位；不能停在单位或障碍格。"},
	"freeze_ray": {"name": "急冻光线", "element": "water", "kind": "ray", "min_range": 1, "max_range": 6, "damage": 0, "ranged": true, "desc": "射程 6；树木与岩障截断射线。冻结命中的第一个敌人；受攻击解除。"},
	"ice_shard": {"name": "冰锥", "element": "water", "kind": "unit", "range": 3, "damage": 11, "ranged": true, "desc": "对 3 格内一个敌人造成 11 点基础直伤。"},
	"water_magic_burst": {"name": "水魔爆", "element": "water", "kind": "cell", "range": 4, "damage": 8, "ranged": true, "desc": "选择曼哈顿 4 格内的落点，可越过障碍；五格十字内敌人各受 8 点基础直伤，中心敌人额外受 3 点，外侧四格敌人沿远离中心方向被推 1 格。"},
	"ice_breath": {"name": "冰之息", "element": "water", "kind": "ray", "min_range": 1, "max_range": 6, "damage": 8, "ranged": true, "freeze_combo": true, "desc": "沿正交方向延伸最多 6 格，攻击首个敌人并造成 8 点基础直伤；若其已有浸湿，则清除浸湿并施加冰冻。"},
	"tailwind": {"name": "磁场加速", "element": "electric", "kind": "self", "damage": 0, "ranged": false, "desc": "自身及横纵各延伸 2 格的 5×5 区域内友军，下一次可用移动机会移动力 +2。"},
	"double_cast": {"name": "电力引擎", "element": "electric", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "令一名相邻友军本轮额外施法一次；强化后可依次选择两名相邻友军。蓄力宣告后获得的额外施法可在当轮使用，下一轮蓄力锁定仍生效。"},
	"fire_seed": {
		"name": "火种",
		"element": "fire",
		"kind": "ray",
		"min_range": 2,
		"max_range": 6,
		"damage": 11,
		"splash_damage": 8,
		"ranged": true,
		"desc": "沿行列 2 至 6 格射出，树木与岩障截断；命中首个单位造成 11 点基础伤害并附加灼烧；未命中单位时，终点相邻 4 格各受 8 点基础伤害。",
	},
	"flame_charge": {
		"name": "闪焰冲锋",
		"element": "fire",
		"kind": "charge",
		"distance": 2,
		"damage": 11,
		"ranged": false,
		"desc": "选择正交 1～2 格内的位置作为方向，冲撞最多 2 格；撞到单位或障碍就停下。单位受 11 点基础伤害并被推 1 格，障碍受 1 点耐久伤害；沿途致死地形仍会使地面单位倒下。",
	},
	"flame_rush": {
		"name": "炎袭",
		"element": "fire",
		"kind": "teleport",
		"damage": 10,
		"ranged": false,
		"desc": "全图选择一格未被占用、可站立的燃烧格并跃迁过去；对落点周围八格内的敌人各造成 10 点基础直伤。",
	},
	"windfire_breath": {
		"name": "风怒炎息",
		"element": "fire",
		"kind": "direction",
		"damage": 12,
		"ranged": false,
		"desc": "选择方向，覆盖正前方两排共 8 格；命中范围内敌人各造成 12 点基础直伤，并沿远离施法者的方向推动 1 格。",
	},
	"furnace_fist": {
		"name": "炎炉拳",
		"element": "fire",
		"kind": "unit",
		"range": 1,
		"damage": 10,
		"ranged": false,
		"desc": "攻击曼哈顿距离 1 格内的一名敌人，造成 10 点基础直伤并回复自身 5 HP；目标命中前已灼烧时回复 10 HP，并清除其灼烧。",
	},
	"skyfire": {
		"name": "天火",
		"element": "fire",
		"kind": "cell",
		"global_range": true,
		"damage": 8,
		"ranged": true,
		"desc": "全图选择中心，生成中心与上下左右共 5 格十字火焰；十字内所有单位受 8 点基础直伤并尝试附加灼烧。火焰保留两轮。",
	},
	"combustion": {
		"name": "爆燃",
		"element": "fire",
		"kind": "unit",
		"range": 2,
		"damage": 8,
		"ranged": true,
		"desc": "攻击曼哈顿距离 2 格内一名敌人，造成 8 点基础直伤；目标命中前已灼烧时改为基础 16 点，并清除其灼烧。",
	},
	"burn_out": {
		"name": "燃尽",
		"element": "fire",
		"kind": "self",
		"damage": 0,
		"ranged": false,
		"desc": "对全场敌人造成施法者最大生命一半的基础直伤并尝试附加灼烧；随后损失施法者最大生命一半的当前 HP，可能因此倒下。",
	},
	"water_flow": {
		"name": "水炮",
		"element": "water",
		"kind": "ray",
		"min_range": 1,
		"max_range": 3,
		"damage": 11,
		"ranged": true,
		"desc": "沿行列射程 3，树木与岩障截断；命中单位造成 11 点基础伤害、击退 1 格并减速；命中障碍时在其前一格生成水面。",
	},
	"rain_dance": {
		"name": "造雨术",
		"element": "water",
		"kind": "cell",
		"range": 4,
		"damage": 0,
		"ranged": false,
		"desc": "曼哈顿距离 4 格内的 3×3 区域：平地与草丛转为水面；跳过障碍、深水与熔岩；可对单位所在格施放。",
	},
	"discharge": {
		"name": "放电",
		"element": "electric",
		"kind": "unit",
		"range": 3,
		"damage": 13,
		"ranged": true,
		"desc": "射程 3 的单体：13 点基础伤害；命中后目标下一次移动机会被取消（定身）。",
	},
	"volt_step": {
		"name": "电光步",
		"element": "electric",
		"kind": "teleport",
		"range": 2,
		"damage": 0,
		"ranged": false,
		"desc": "瞬移最多 2 格；可越过单位，不可越过障碍与深水、熔岩；落点必须可站立且无单位。",
	},
	"seed_sow": {
		"name": "播种",
		"element": "grass",
		"kind": "cell",
		"range": 3,
		"damage": 0,
		"ranged": false,
		"desc": "射程 3：目标平地生成草丛；可对单位所在格施放（脚下成荫）。",
	},
	"drain": {
		"name": "吸取",
		"element": "grass",
		"kind": "unit",
		"range": 2,
		"damage": 10,
		"ranged": true,
		"desc": "射程 2 单体：10 点基础伤害；自身回复 5 生命（不超过上限）。",
	},
	"push": {
		"name": "推击",
		"element": "rock",
		"kind": "unit",
		"range": 1,
		"damage": 13,
		"ranged": false,
		"desc": "相邻 1 格单体：13 点基础伤害并沿方向推开 1 格；碰撞按地形结算，被推入深水或熔岩立即淘汰。",
	},
	"rock_smash": {
		"name": "碎岩",
		"element": "rock",
		"kind": "unit",
		"range": 2,
		"damage": 10,
		"ranged": true,
		"desc": "射程 2：对单位 10 点基础伤害；对障碍每次命中最多扣 1 点耐久，破坏后地形立即更新。",
	},
	"rock_create": {
		"name": "造岩",
		"element": "rock",
		"kind": "direction",
		"damage": 10,
		"ranged": false,
		"desc": "选择上下左右方向，在正前方横排生成临时障碍（3 格，出界裁剪）；该格有单位时改为造成 10 点基础伤害且不生成；我方的临时障碍在本轮敌方阶段后消失，敌方的在下一轮敌方阶段后消失。",
	},
}

static func get_def(skill_id: String) -> Dictionary:
	if is_placeholder(skill_id):
		var parts := skill_id.split("_")
		var numeral := "Ⅰ" if parts[2] == "1" else "Ⅱ"
		return {
			"name": "%s元素试招%s" % ["冰" if parts[1] == "ice" else "风" if parts[1] == "wind" else Elements.name_of(parts[1]), numeral],
			"element": "water" if parts[1] == "ice" else "electric" if parts[1] == "wind" else parts[1], "kind": "unit", "range": 2,
			"damage": 10, "ranged": true, "placeholder": true,
			"desc": "临时占位技能：射程 2，单体造成 10 点基础直伤，无状态或地形效果；强化后基础直伤 20、射程 3。正式技能尚待设计。",
		}
	return DEFS.get(skill_id, {})


static func placeholder_ids_for(element: String) -> Array:
	if not Elements.LIST.has(element) and not ["ice", "wind"].has(element):
		return []
	return ["trial_%s_1" % element, "trial_%s_2" % element]


static func learnable_ids_for(element: String) -> Array:
	var ids := placeholder_ids_for(element)
	match element:
		"fire": ids.append_array(["fire_amplify", "flame_rush", "windfire_breath", "furnace_fist", "skyfire", "combustion", "burn_out"])
		"water": ids.append_array(["surf", "water_magic_burst", "ice_breath", "tsunami", "frozen_ground", "ice_glide", "freeze_ray", "ice_shard", "trial_ice_1", "trial_ice_2"])
		"electric": ids.append_array(["tailwind", "double_cast", "trial_wind_1", "trial_wind_2"])
		"grass": ids.append_array(["leech_seed", "tree_man"])
		"rock": ids.append_array(["rock_slide", "earth_shake"])
	return ids


static func is_placeholder(skill_id: String) -> bool:
	var parts := skill_id.split("_")
	return parts.size() == 3 and parts[0] == "trial" and ["fire", "water", "grass", "electric", "rock", "ice", "wind"].has(parts[1]) and ["1", "2"].has(parts[2])


static func is_special(skill_id: String) -> bool:
	return String(get_def(skill_id).get("category", "normal")) == "special"


static func has_tag(skill_id: String, tag: String) -> bool:
	return bool(get_def(skill_id).get(tag, false))


static func special_ids_for(element: String) -> Array:
	var result: Array = []
	for skill_id in DEFS:
		if String(DEFS[skill_id].get("element", "")) == element and is_special(String(skill_id)):
			result.append(String(skill_id))
	result.sort()
	return result


static func name_of(skill_id: String) -> String:
	return get_def(skill_id).get("name", skill_id)


static func element_of(skill_id: String) -> String:
	return get_def(skill_id).get("element", "")


static func is_ranged(skill_id: String) -> bool:
	return bool(get_def(skill_id).get("ranged", false))


static func kind_of(skill_id: String) -> String:
	return get_def(skill_id).get("kind", "")


static func damage_of(skill_id: String) -> int:
	return int(get_def(skill_id).get("damage", 0))


static func battle_limit_of(skill_id: String) -> int:
	return int(get_def(skill_id).get("battle_limit", 0))
