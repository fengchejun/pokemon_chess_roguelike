class_name MapCardDB
extends RefCounted

## 持续整局的地图倾向卡，与 v2 的战前站位增益卡分开保存。

const CARDS := {
	"water": {"name": "水脉", "desc": "提高后续战场的浅水生成倾向；与火、电、岩有组合。", "water": 8},
	"fire": {"name": "火种", "desc": "提高可燃草丛生成倾向；与水组合更易出现湿润草地。", "grass": 7},
	"rock": {"name": "岩脊", "desc": "提高障碍生成倾向；与水组合更易形成水岩相邻地形。", "rock": 7},
	"electric": {"name": "电潮", "desc": "提高水域生成倾向；与水组合更易出现连通水面。", "water": 4},
	"steam_focus": {"name": "雾泉", "desc": "同时提高浅水与可燃草丛倾向。", "water": 3, "grass": 3},
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
	if deck.has("water") and deck.has("electric"):
		result["water"] += 5
	if deck.has("water") and deck.has("fire"):
		result["grass"] += 3
	if deck.has("water") and deck.has("rock"):
		result["rock"] += 2
	return result
