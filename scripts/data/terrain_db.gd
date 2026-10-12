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

const ALL := [PLAIN, WATER, DEEP, GRASS, OBSTACLE, LAVA, FRAGILE, PIT, ICE, VINES]

const NAMES := {
	PLAIN: "平地",
	WATER: "水面",
	DEEP: "深水",
	GRASS: "草丛",
	OBSTACLE: "障碍",
	LAVA: "熔岩",
	FRAGILE: "易碎地块", PIT: "深坑", ICE: "冰面", VINES: "藤蔓",
}

const COLORS := {
	PLAIN: Color(0.78, 0.76, 0.64),
	WATER: Color(0.44, 0.65, 0.86),
	DEEP: Color(0.15, 0.30, 0.54),
	GRASS: Color(0.42, 0.66, 0.36),
	OBSTACLE: Color(0.42, 0.37, 0.33),
	LAVA: Color(0.86, 0.33, 0.14),
	FRAGILE: Color(0.72, 0.58, 0.43), PIT: Color(0.13, 0.12, 0.18), ICE: Color(0.66, 0.88, 0.98), VINES: Color(0.22, 0.56, 0.30),
}

const DESCRIPTIONS := {
	PLAIN: "无效果。",
	WATER: "非水系单位在回合结算时仍站在浅水上，下一轮获得浸湿（移动力 -1）；水系免疫。",
	DEEP: "不可主动进入；水系单位可进入。任何单位被推入即倒下（我方濒死、野生淘汰）。",
	GRASS: "可燃草丛；受火焰点燃后逐回合向四邻可燃物蔓延。",
	OBSTACLE: "阻挡移动与射线，耐久 2；可被碎岩或推击碰撞破坏，破坏后变平地。",
	LAVA: "不可进入；被推入即倒下（我方濒死、野生淘汰，与深水同规则）。",
	FRAGILE: "可站立；受火球术或碎岩击碎后变为深坑。",
	PIT: "不可主动进入；被推入或脚下塌陷立即倒下。",
	ICE: "可站立；回合末按最后位移方向滑行一格。",
	VINES: "可站立的可燃藤蔓；上方单位下一轮不能移动。",
}


static func name_of(terrain: int) -> String:
	return NAMES.get(terrain, "未知")


static func color_of(terrain: int) -> Color:
	return COLORS.get(terrain, Color.MAGENTA)


static func is_lethal(terrain: int) -> bool:
	return terrain == DEEP or terrain == LAVA or terrain == PIT


static func blocks_rays(terrain: int) -> bool:
	return terrain == OBSTACLE


static func can_stand(terrain: int, element: String) -> bool:
	match terrain:
		PLAIN, GRASS, WATER, FRAGILE, ICE, VINES:
			return true
		DEEP:
			return element == "water"
		_:
			return false


## 主动移动进入该格的消耗；-1 表示不可进入。
static func move_cost(terrain: int, element: String) -> int:
	match terrain:
		PLAIN, GRASS, FRAGILE, ICE, VINES:
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
