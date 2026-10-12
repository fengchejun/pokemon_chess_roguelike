class_name TerrainDB
extends RefCounted

## v2.0 六类地形：平地、水面、深水、草丛、障碍、熔岩。

const PLAIN := 0
const WATER := 1
const DEEP := 2
const GRASS := 3
const OBSTACLE := 4
const LAVA := 5

const ALL := [PLAIN, WATER, DEEP, GRASS, OBSTACLE, LAVA]

const NAMES := {
	PLAIN: "平地",
	WATER: "水面",
	DEEP: "深水",
	GRASS: "草丛",
	OBSTACLE: "障碍",
	LAVA: "熔岩",
}

const COLORS := {
	PLAIN: Color(0.78, 0.76, 0.64),
	WATER: Color(0.44, 0.65, 0.86),
	DEEP: Color(0.15, 0.30, 0.54),
	GRASS: Color(0.42, 0.66, 0.36),
	OBSTACLE: Color(0.42, 0.37, 0.33),
	LAVA: Color(0.86, 0.33, 0.14),
}

const DESCRIPTIONS := {
	PLAIN: "无效果。",
	WATER: "非水系单位每进入一格额外消耗 1 移动力；水系单位免疫。",
	DEEP: "不可主动进入；水系单位可进入。任何单位被推入即倒下（我方濒死、野生淘汰）。",
	GRASS: "隐蔽：草丛中的单位不能被 2 格以外的远程单体技能选中；近战与范围不受影响。",
	OBSTACLE: "阻挡移动与射线，耐久 2；可被碎岩或推击碰撞破坏，破坏后变平地。",
	LAVA: "不可进入；被推入即倒下（我方濒死、野生淘汰，与深水同规则）。",
}


static func name_of(terrain: int) -> String:
	return NAMES.get(terrain, "未知")


static func color_of(terrain: int) -> Color:
	return COLORS.get(terrain, Color.MAGENTA)


static func is_lethal(terrain: int) -> bool:
	return terrain == DEEP or terrain == LAVA


static func blocks_rays(terrain: int) -> bool:
	return terrain == OBSTACLE


static func can_stand(terrain: int, element: String) -> bool:
	match terrain:
		PLAIN, GRASS, WATER:
			return true
		DEEP:
			return element == "water"
		_:
			return false


## 主动移动进入该格的消耗；-1 表示不可进入。
static func move_cost(terrain: int, element: String) -> int:
	match terrain:
		PLAIN, GRASS:
			return 1
		WATER:
			return 1 if element == "water" else 1 + Balance.WATER_EXTRA_COST
		DEEP:
			return 1 if element == "water" else -1
		_:
			return -1


static func is_soft_ground(terrain: int) -> bool:
	## 播种可用：只有平地能长出草丛。
	return terrain == PLAIN


static func is_water_body(terrain: int) -> bool:
	return terrain == WATER or terrain == DEEP
