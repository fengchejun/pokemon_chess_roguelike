class_name SkillDB
extends RefCounted

## 十一个技能。kind 决定瞄准方式：
##  ray       行列射线（被第一个单位或障碍截断）
##  charge    闪焰冲锋：正交恰 2 格落点
##  unit      单体选中
##  cell      指定落点
##  teleport  自身瞬移
##  direction 造岩：选择方向

const DEFS := {
	"fire_seed": {
		"name": "火种",
		"element": "fire",
		"kind": "ray",
		"min_range": 2,
		"max_range": 8,
		"damage": 2,
		"ranged": true,
		"desc": "沿行列 2 至 8 格射出；命中首个单位造成 2 伤害并附加灼烧；未命中任何单位时，终点格相邻 4 格各受 1 伤害。",
	},
	"flame_charge": {
		"name": "闪焰冲锋",
		"element": "fire",
		"kind": "charge",
		"distance": 2,
		"damage": 0,
		"ranged": false,
		"desc": "越过正交方向 1 格；单位与障碍都能跨过。被跨过的非火系单位获得灼烧；落点为深水或熔岩时倒下（濒死）。",
	},
	"water_flow": {
		"name": "水流",
		"element": "water",
		"kind": "ray",
		"min_range": 1,
		"max_range": 8,
		"damage": 1,
		"ranged": true,
		"desc": "沿行列射出；命中单位造成 1 伤害、击退 1 格并减速 1 回合；命中障碍时在其前一格生成水面；命中空地时在该格生成水面。",
	},
	"rain_dance": {
		"name": "造雨术",
		"element": "water",
		"kind": "cell",
		"range": 5,
		"damage": 0,
		"ranged": false,
		"desc": "曼哈顿距离 5 格内的 3×3 区域：平地与草丛转为水面；跳过障碍、深水与熔岩；可对单位所在格施放。",
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
		"desc": "射程 2：对单位 1 伤害；对障碍 2 点耐久伤害，破坏后地形立即更新。",
	},
	"rock_create": {
		"name": "造岩",
		"element": "rock",
		"kind": "direction",
		"damage": 2,
		"ranged": false,
		"desc": "选择上下左右方向，在正前方横排生成临时障碍（3 格，出界裁剪）；该格有单位时改为造成 2 伤害且不生成；我方的临时障碍在本轮敌方阶段后消失，敌方的在下一轮敌方阶段后消失。",
	},
}

static func get_def(skill_id: String) -> Dictionary:
	return DEFS.get(skill_id, {})


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
