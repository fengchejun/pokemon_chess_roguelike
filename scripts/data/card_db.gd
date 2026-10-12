class_name CardDB
extends RefCounted

## 环境卡（v2.2）：不再影响地图生成，改为“站位增益”——
## 关联某种地形位置，为处在相应位置的我方棋子提供增益；风险条款可选。
## 必死格（深水 / 熔岩）无法站位，采用“紧邻免强制位移”的邻位设计。

const CARDS := {
	"stream": {
		"name": "溪流",
		"element": "water",
		"anchor": "水面",
		"effect": "我方单位进入水面不额外消耗移动力（穿流而行）",
		"extra": "",
		"risk": "",
		"effect_types": {"water_ignore": 1},
	},
	"forest": {
		"name": "密林",
		"element": "grass",
		"anchor": "草丛",
		"effect": "站在草丛中的我方单位：受到的远程伤害 −1，造成的直接伤害 +1",
		"extra": "",
		"risk": "",
		"effect_types": {"grass_reduction": 1, "grass_strike": 1},
	},
	"ridge": {
		"name": "岩脊",
		"element": "rock",
		"anchor": "障碍旁",
		"effect": "紧邻障碍的我方单位：受到的远程伤害 −1；其推击伤害 +1（借石发力）",
		"extra": "",
		"risk": "",
		"effect_types": {"obstacle_cover": 1, "push_damage": 1},
	},
	"magma": {
		"name": "熔脉",
		"element": "fire",
		"anchor": "熔岩旁",
		"effect": "紧邻熔岩的我方单位：不会被强制位移（免疫推击与击退）；你的火系技能 +1 伤害",
		"extra": "",
		"risk": "熔岩对双方同样致命",
		"effect_types": {"lava_guard": 1, "fire_bonus": 1},
	},
	"tide": {
		"name": "潮汐",
		"element": "water",
		"anchor": "深水旁",
		"effect": "紧邻深水的我方单位：不会被强制位移（免疫推击与击退）；你的水系技能射程 +1",
		"extra": "",
		"risk": "",
		"effect_types": {"deep_guard": 1, "water_range": 1},
	},
}

const ALL_IDS := ["stream", "forest", "ridge", "magma", "tide"]


static func get_card(card_id: String) -> Dictionary:
	return CARDS.get(card_id, {})


static func name_of(card_id: String) -> String:
	return get_card(card_id).get("name", card_id)


## 汇总已拥有卡牌的站位增益。
static func active_effects(card_ids: Array) -> Dictionary:
	var effects := {
		"water_range": 0,
		"water_ignore": 0,
		"grass_reduction": 0,
		"grass_strike": 0,
		"obstacle_cover": 0,
		"push_damage": 0,
		"lava_guard": 0,
		"deep_guard": 0,
		"fire_bonus": 0,
	}
	for card_id in card_ids:
		var card := get_card(card_id)
		for key in card.get("effect_types", {}):
			if effects.has(key):
				effects[key] += int(card["effect_types"][key])
	return effects
