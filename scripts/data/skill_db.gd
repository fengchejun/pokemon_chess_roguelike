class_name SkillDB
extends RefCounted

## 七系目标技能与旧版兼容技能。kind 决定瞄准方式：
##  ray       行列射线（被第一个单位或障碍截断）
##  charge    闪焰冲锋：正交两格方向，逐格前进并在撞击时停下
##  unit      单体选中
##  cell      指定落点
##  teleport  自身瞬移
##  direction 造岩：选择方向

const DEFS := {
	"fire_burst": {"name": "火球术", "element": "fire", "kind": "ray", "min_range": 2, "max_range": 4, "damage": 4, "ranged": true, "channel": true, "desc": "锁定射程 2–4 的格子，下次本方阶段开始落下；九宫格内各受 4 伤。吟唱后下一阶段不能行动，可被死亡、冻结或麻痹打断。"},
	"fire_amplify": {"name": "火焰增幅", "element": "fire", "kind": "self", "damage": 0, "ranged": false, "desc": "熄灭自身曼哈顿 2 格内所有燃烧格，每格积累 1 点增幅；下一次实际造成技能直伤时，每个受击单位额外承受全部增幅。"},
	"flame_jet": {"name": "喷射火焰", "element": "fire", "kind": "direction", "damage": 1, "ranged": true, "desc": "沿选定方向喷射 3 格；障碍截断；命中单位受到 1 伤并灼烧，紧邻自身的单位额外受到 1 伤。"},
	"rain_call": {"name": "造雨术", "element": "water", "kind": "cell", "range": 4, "damage": 0, "ranged": false, "desc": "指定曼哈顿距离 4 格内中心，周围 3×3 格化为浅水；障碍与深坑不变。"},
	"surf": {"name": "冲浪", "element": "water", "kind": "self", "damage": 0, "ranged": false, "desc": "施放后的两个本方行动阶段，若站在浅水或深水，可一次移动到同一片相连水域的任意空格；中途不能穿过单位或障碍。"},
	"tsunami": {"name": "海啸", "element": "water", "kind": "direction", "damage": 4, "ranged": true, "channel": true, "desc": "选择方向警示前方宽 5、长 4 的固定区域；下次本方阶段开始，对区域内当时站在水格上的敌方单位造成 4 点直伤；施法者该阶段不能行动。"},
	"rock_push": {"name": "推击", "element": "rock", "kind": "unit", "range": 1, "damage": 2, "ranged": false, "desc": "对相邻单位造成 2 伤并推开一格。"},
	"rock_break": {"name": "碎岩", "element": "rock", "kind": "unit", "range": 2, "damage": 1, "ranged": true, "desc": "曼哈顿 2 格内攻击单位造成 1 点伤害，命中障碍扣 1 点耐久；解除冰冻时无视冰冻免伤并造成三倍伤害。"},
	"rock_slide": {"name": "岩崩", "element": "rock", "kind": "cell", "range": 3, "damage": 8, "ranged": true, "channel": true, "desc": "锁定曼哈顿 3 格内一格；下次本方阶段开始，对该格当时的单位造成 8 点伤害，可误伤友军。"},
	"lightning": {"name": "打雷", "element": "electric", "kind": "self", "damage": 4, "ranged": true, "channel": true, "desc": "锁定全场所有敌方单位当前格子；下次本方阶段开始，对固定落点上的单位造成 4 点伤害并感电，可误伤友军。"},
	"electric_arc": {"name": "放电", "element": "electric", "kind": "cell", "range": 2, "damage": 1, "ranged": true, "desc": "指定两格内水域沿连通水域传导；若射程内没有水域，也可指定一名单位造成 1 点伤害。"},
	"volt_replace": {"name": "伏特替换", "element": "electric", "kind": "unit", "range": 2, "damage": 0, "ranged": false, "desc": "与相隔恰好两格的单位交换位置；也可移动到两格内可站立的空格，无视途中障碍。"},
	"wild_vines": {"name": "疯狂藤蔓", "element": "grass", "kind": "direction", "damage": 0, "ranged": false, "desc": "在前方两格生成藤蔓；障碍阻挡生成。生成时或后来停在藤蔓上的地面单位，下一次移动机会受阻。"},
	"herbal_heal": {"name": "药草治疗", "element": "grass", "kind": "self", "damage": 0, "ranged": false, "desc": "自身周围 3×3 范围内所有己方单位回复 1 HP。"},
	"leech_seed": {"name": "寄生种子", "element": "grass", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "使相邻敌人寄生；每次整轮结算目标失去 1 HP、存活的施法者恢复 1 HP。目标受到其他实际伤害时先清除寄生。"},
	"tree_man": {"name": "大树守卫", "element": "grass", "kind": "cell", "range": 3, "damage": 0, "ranged": false, "desc": "曼哈顿 3 格内召唤一名树人；每名施法者只能维持一名。基础 1 HP，浅水 +2 HP，草丛 +3 HP；出生轮不能移动或施法，死亡后可重新召唤。"},
	"tree_wrath": {"name": "大树之怒", "element": "grass", "kind": "unit", "range": 1, "damage": 1, "ranged": false, "desc": "对相邻一格的一名敌方单位造成 1 点伤害。"},
	"frozen_ground": {"name": "冰封大地", "element": "ice", "kind": "direction", "damage": 0, "ranged": false, "desc": "前方 3×3 地形生成冰面，可覆盖深水和深坑。"},
	"ice_glide": {"name": "溜冰", "element": "ice", "kind": "self", "damage": 0, "ranged": false, "desc": "施放后的两个本方行动阶段，若站在冰面，可一次移动到同一片相连冰面的任意空格；中途不能穿过单位或障碍。"},
	"freeze_ray": {"name": "急冻光线", "element": "ice", "kind": "ray", "min_range": 1, "max_range": 4, "damage": 0, "ranged": true, "desc": "射程 4；树木与岩障截断射线。冻结命中的第一个敌人；受攻击解除。"},
	"ice_shard": {"name": "冰锥", "element": "ice", "kind": "unit", "range": 3, "damage": 1, "ranged": true, "desc": "对 3 格内一个敌人造成 1 点直接伤害。"},
	"tailwind": {"name": "顺风", "element": "wind", "kind": "direction", "damage": 0, "ranged": false, "desc": "前方 2×3 的友军下一次可用移动机会，移动力 +2。"},
	"double_cast": {"name": "风力引擎", "element": "wind", "kind": "unit", "range": 1, "damage": 0, "ranged": false, "desc": "相邻友军本轮获得一次额外技能机会。"},
	"wind_gust": {"name": "推风", "element": "wind", "kind": "unit", "range": 2, "damage": 0, "ranged": true, "desc": "推动 2 格内一个敌人 1 格；撞击与落入危险地形照常结算。"},
	"fire_seed": {
		"name": "火种",
		"element": "fire",
		"kind": "ray",
		"min_range": 2,
		"max_range": 6,
		"damage": 2,
		"ranged": true,
		"desc": "沿行列 2 至 6 格射出，树木与岩障截断；命中首个单位造成 2 伤害并附加灼烧；未命中单位时，终点相邻 4 格各受 1 伤害。",
	},
	"flame_charge": {
		"name": "闪焰冲锋",
		"element": "fire",
		"kind": "charge",
		"distance": 2,
		"damage": 1,
		"ranged": false,
		"desc": "沿正交方向冲撞最多 2 格；撞到单位或障碍就停下。单位受 1 伤并被推 1 格，障碍受 1 点耐久伤害；沿途致死地形仍会使地面单位倒下。",
	},
	"water_flow": {
		"name": "水炮",
		"element": "water",
		"kind": "ray",
		"min_range": 1,
		"max_range": 4,
		"damage": 1,
		"ranged": true,
		"desc": "沿行列射程 4，树木与岩障截断；命中单位造成 1 伤害、击退 1 格并减速；命中障碍时在其前一格生成水面。",
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
		"damage": 2,
		"ranged": true,
		"desc": "射程 3 的单体：2 伤害；命中后目标下一次移动机会被取消（定身）。",
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
		"damage": 1,
		"ranged": true,
		"desc": "射程 2 单体：1 伤害；自身回复 1 生命（不超过上限）。",
	},
	"push": {
		"name": "推击",
		"element": "rock",
		"kind": "unit",
		"range": 1,
		"damage": 2,
		"ranged": false,
		"desc": "相邻 1 格单体：2 伤害并沿方向推开 1 格；碰撞按地形结算，被推入深水或熔岩立即淘汰。",
	},
	"rock_smash": {
		"name": "碎岩",
		"element": "rock",
		"kind": "unit",
		"range": 2,
		"damage": 1,
		"ranged": true,
		"desc": "射程 2：对单位 1 伤害；对障碍每次命中最多扣 1 点耐久，破坏后地形立即更新。",
	},
	"rock_create": {
		"name": "造岩",
		"element": "rock",
		"kind": "direction",
		"damage": 1,
		"ranged": false,
		"desc": "选择上下左右方向，在正前方横排生成临时障碍（3 格，出界裁剪）；该格有单位时改为造成 1 伤害且不生成；我方的临时障碍在本轮敌方阶段后消失，敌方的在下一轮敌方阶段后消失。",
	},
}

static func get_def(skill_id: String) -> Dictionary:
	if is_placeholder(skill_id):
		var parts := skill_id.split("_")
		var numeral := "Ⅰ" if parts[2] == "1" else "Ⅱ"
		return {
			"name": "%s元素试招%s" % [Elements.name_of(parts[1]), numeral],
			"element": parts[1], "kind": "unit", "range": 2,
			"damage": 1, "ranged": true, "placeholder": true,
			"desc": "临时占位技能：射程 2，单体造成 1 点直接伤害，无状态或地形效果；强化后射程 3。正式技能尚待设计。",
		}
	return DEFS.get(skill_id, {})


static func placeholder_ids_for(element: String) -> Array:
	if not ["fire", "water", "grass", "electric", "rock", "ice", "wind"].has(element):
		return []
	return ["trial_%s_1" % element, "trial_%s_2" % element]


static func learnable_ids_for(element: String) -> Array:
	var ids := placeholder_ids_for(element)
	match element:
		"fire": ids.append("fire_amplify")
		"water": ids.append_array(["surf", "tsunami"])
		"grass": ids.append_array(["leech_seed", "tree_man"])
		"rock": ids.append("rock_slide")
		"ice": ids.append("ice_glide")
	return ids


static func is_placeholder(skill_id: String) -> bool:
	var parts := skill_id.split("_")
	return parts.size() == 3 and parts[0] == "trial" and ["fire", "water", "grass", "electric", "rock", "ice", "wind"].has(parts[1]) and ["1", "2"].has(parts[2])


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
