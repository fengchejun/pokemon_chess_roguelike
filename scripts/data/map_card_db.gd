class_name MapCardDB
extends RefCounted

## 战前使用一张的消耗性地貌卡；只改变本场地图生成倾向。

const CARDS := {
	"water": {"name": "水脉", "desc": "提高本场浅水生成倾向。", "water": 8},
	"fire": {"name": "火种", "desc": "提高本场可燃草丛生成倾向。", "grass": 7},
	"rock": {"name": "岩脊", "desc": "提高本场障碍生成倾向。", "rock": 7},
	"electric": {"name": "电潮", "desc": "小幅提高本场水域生成倾向。", "water": 4},
	"steam_focus": {"name": "雾泉", "desc": "同时提高本场浅水与可燃草丛倾向，并提高水面蒸汽生成率。", "water": 3, "grass": 3},
}

const ALL_IDS := ["water", "fire", "rock", "electric", "steam_focus"]


static func get_card(card_id: String) -> Dictionary:
	return CARDS.get(card_id, {})


static func offer(deck: Array, seed_value: int, count: int = 3) -> Array:
	var pool := ALL_IDS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


static func weights(deck: Array) -> Dictionary:
	var result := {"water": 0, "grass": 0, "rock": 0}
	for card_id in deck:
		var card := get_card(String(card_id))
		for key in result:
			result[key] += int(card.get(key, 0))
	return result
