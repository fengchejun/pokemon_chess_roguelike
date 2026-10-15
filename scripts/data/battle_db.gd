class_name BattleDB
extends RefCounted

## 每场战斗配置：区域、敌方编成、巢穴、增援池与致死地形预算。
## 区域依场次轮换；阶段 7 才做路线选择。

const CONFIGS := [
	{
		"region": "草原",
		"enemies": [["fire_wild1", Vector2i(6, 2)], ["grass_wild1", Vector2i(6, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [Vector2i(6, 0)],
		"reinforce": ["fire_wild1", "grass_wild1"],
		"lethal_budget": 1,
	},
	{
		"region": "溪谷",
		"enemies": [["water_wild1", Vector2i(6, 2)], ["rock_wild1", Vector2i(5, 5)], ["fire_wild1", Vector2i(6, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [Vector2i(6, 0)],
		"reinforce": ["water_wild1", "rock_wild1"],
		"lethal_budget": 2,
	},
	{
		"region": "密林",
		"enemies": [["electric_wild1", Vector2i(5, 2)], ["grass_wild1", Vector2i(6, 3)], ["water_wild2", Vector2i(6, 6)]],
		"nest_cell": Vector2i(7, 1),
		"nest_exits": [Vector2i(6, 1)],
		"reinforce": ["electric_wild1", "wind_wild1"],
		"lethal_budget": 2,
	},
	{
		"region": "火谷",
		"enemies": [["fire_wild1", Vector2i(5, 1)], ["fire_wild2", Vector2i(6, 3)], ["rock_wild2", Vector2i(6, 6)], ["electric_wild1", Vector2i(5, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [Vector2i(6, 0)],
		"reinforce": ["fire_wild1", "rock_wild2"],
		"lethal_budget": 3,
	},
	{
		"region": "岩窟",
		"enemies": [["rock_wild1", Vector2i(7, 2)], ["rock_wild2", Vector2i(6, 4)], ["water_wild1", Vector2i(5, 6)], ["ice_wild1", Vector2i(7, 6)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [Vector2i(6, 0)],
		"reinforce": ["rock_wild2", "ice_wild1"],
		"lethal_budget": 3,
	},
	{
		"region": "深潭",
		"enemies": [["water_wild1", Vector2i(5, 1)], ["water_wild2", Vector2i(6, 2)], ["electric_wild2", Vector2i(6, 4)], ["rock_wild1", Vector2i(6, 6)], ["wind_wild1", Vector2i(5, 5)]],
		"nest_cell": Vector2i(7, 0),
		"nest_exits": [Vector2i(6, 0)],
		"reinforce": ["electric_wild2", "water_wild2"],
		"lethal_budget": 4,
	},
]


static func config_for(battle_index: int) -> Dictionary:
	return CONFIGS[clampi(battle_index, 0, CONFIGS.size() - 1)]


static func count() -> int:
	return CONFIGS.size()
