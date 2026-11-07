class_name TerrainDB
extends RefCounted

## v2 地形与迁回的易碎地块、深坑、冰面、藤蔓。

const PLAIN := 0
const WATER := 1
const DEEP := 2
const GRASS := 3
const OBSTACLE := 4
const LAVA := 5
const FRAGILE := 6
const PIT := 7
const ICE := 8
const VINES := 9
const TREE := 10
const SHALLOW_GRASS := 11
const BLUE_FIRE := 12
const ROCK_MOUNTAIN := 13

const ALL := [PLAIN, WATER, DEEP, GRASS, OBSTACLE, LAVA, FRAGILE, PIT, ICE, VINES, TREE, SHALLOW_GRASS, BLUE_FIRE, ROCK_MOUNTAIN]

const NAMES := {
	PLAIN: "平地",
	WATER: "水面",
	DEEP: "深水",
	GRASS: "草丛",
	OBSTACLE: "障碍",
	LAVA: "熔岩",
	FRAGILE: "易碎地块", PIT: "深坑", ICE: "冰面", VINES: "藤蔓",
	TREE: "树木", SHALLOW_GRASS: "浅草", BLUE_FIRE: "蓝火", ROCK_MOUNTAIN: "岩山",
}

const COLORS := {
	PLAIN: Color(0.78, 0.76, 0.64),
	WATER: Color(0.44, 0.65, 0.86),
	DEEP: Color(0.15, 0.30, 0.54),
	GRASS: Color(0.42, 0.66, 0.36),
	OBSTACLE: Color(0.42, 0.37, 0.33),
	LAVA: Color(0.86, 0.33, 0.14),
	FRAGILE: Color(0.72, 0.58, 0.43), PIT: Color(0.13, 0.12, 0.18), ICE: Color(0.66, 0.88, 0.98), VINES: Color(0.22, 0.56, 0.30),
	TREE: Color(0.22, 0.43, 0.22),
	SHALLOW_GRASS: Color("98b76c"), BLUE_FIRE: Color("274e79"), ROCK_MOUNTAIN: Color("776b64"),
}

const DESCRIPTIONS := {
	PLAIN: "无效果。",
	WATER: "我方阶段结束时，浅水中的敌人获得浸湿；敌方阶段结束时，浅水中的我方获得浸湿。下一次移动力 -1；水系免疫。",
	DEEP: "水系可主动进入；非水系地面单位被推入，或脚下藤蔓消失后会溺水。飞行单位不受地面影响。",
	GRASS: "可燃草丛。单位在其中受到的伤害降低10%。",
	OBSTACLE: "阻挡移动与射线，耐久 2；可被直接攻击破坏；单位碰撞不扣耐久，破坏后变平地。",
	LAVA: "不可进入；被推入即倒下（我方濒死、野生淘汰，与深水同规则）。",
	FRAGILE: "可站立；受火球术或碎岩击碎后变为深坑。",
	PIT: "地面单位不可主动进入；被推入、脚下塌陷或临时藤蔓消失时立即坠落。飞行单位不受地面影响。",
	ICE: "可站立；回合末按最后位移方向滑行一格。每轮结算时每块旧冰面最多随机冻结一格相邻水域，新冰下一轮才能继续扩张。",
	VINES: "可站立的可燃藤蔓；进入时使地面单位获得禁锢。技能生成的藤蔓下轮末恢复原地貌，燃烧可提前移除。",
	SHALLOW_GRASS: "可燃浅草。铺水会使它生长为草丛。",
	ROCK_MOUNTAIN: "阻挡移动和射线，无法推动。需要命中两次碎岩才能破坏。",
	BLUE_FIRE: "持续燃烧的地面，会灼烧地面单位并引燃邻接可燃地形，覆盖地形后熄灭。",
	TREE: "独立树木：阻挡移动与射线，耐久 1；受 1 点物体伤害即被摧毁。火球术仍可越过。",
}


static func name_of(terrain: int) -> String:
	return NAMES.get(terrain, "未知")


static func color_of(terrain: int) -> Color:
	return COLORS.get(terrain, Color.MAGENTA)


static func is_lethal(terrain: int) -> bool:
	return terrain == DEEP or terrain == LAVA or terrain == PIT


static func blocks_move(terrain: int) -> bool:
	return terrain in [OBSTACLE, TREE, ROCK_MOUNTAIN]


static func blocks_rays(terrain: int) -> bool:
	return terrain in [OBSTACLE, TREE, ROCK_MOUNTAIN]


static func can_stand(terrain: int, element: String) -> bool:
	match terrain:
		PLAIN, GRASS, SHALLOW_GRASS, BLUE_FIRE, WATER, FRAGILE, ICE, VINES:
			return true
		DEEP:
			return element == "water"
		_:
			return false


## 主动移动进入该格的消耗；-1 表示不可进入。
static func move_cost(terrain: int, element: String) -> int:
	match terrain:
		PLAIN, GRASS, SHALLOW_GRASS, BLUE_FIRE, FRAGILE, ICE, VINES:
			return 1
		WATER:
			return 1
		DEEP:
			return 1 if element == "water" else -1
		_:
			return -1


static func is_soft_ground(terrain: int) -> bool:
	## 播种可用：只有平地能长出草丛。
	return terrain == PLAIN


static func is_water_body(terrain: int) -> bool:
	return terrain == WATER or terrain == DEEP


static func can_convert_to_water(terrain: int) -> bool:
	return water_result(terrain) != terrain


static func is_grass(terrain: int) -> bool:
	return terrain in [SHALLOW_GRASS, GRASS, VINES]


static func is_flammable(terrain: int) -> bool:
	return is_grass(terrain) or terrain == TREE


static func water_result(terrain: int) -> int:
	if terrain == SHALLOW_GRASS:
		return GRASS
	if terrain in [PLAIN, FRAGILE, ICE, BLUE_FIRE]:
		return WATER
	return terrain
