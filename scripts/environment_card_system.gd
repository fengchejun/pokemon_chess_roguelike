class_name EnvironmentCardSystem
extends RefCounted

const CARDS: Dictionary = {
	"water": {"name": "水脉", "elements": ["water"], "description": "水域↑；配火生雾、配电连片导电、配岩形成水岩障；水也限制走位。", "weights": {"water": 8}},
	"fire": {"name": "火种", "elements": ["fire"], "description": "草丛与可燃植物↑；配水生雾；点燃可能伤及己方。", "weights": {"plant": 7, "grass": 5}},
	"rock": {"name": "岩脊", "elements": ["rock"], "description": "岩石↑；配水形成水岩障；可撞击，也可能阻路。", "weights": {"rock": 7}},
	"electric": {"name": "电潮", "elements": ["electric"], "description": "水域↑；配水更易连片导电；敌我都可能触电。", "weights": {"water": 4}},
	"steam_focus": {"name": "雾泉", "elements": ["water", "fire"], "description": "水域和可燃物↑；触发水火组合，雾更多；站在雾中的怪物不能施法。", "weights": {"water": 3, "plant": 3, "grass": 2}},
}


static func offer(deck: Array[String], seed_value: int, count: int = 3) -> Array[String]:
	var pool: Array[String] = []
	for card_id in CARDS.keys():
		if not deck.has(card_id):
			pool.append(card_id)
	if pool.size() < count:
		for card_id in CARDS.keys():
			if not pool.has(card_id):
				pool.append(card_id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[String] = []
	while not pool.is_empty() and result.size() < count:
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


static func deck_elements(deck: Array[String]) -> Dictionary:
	var elements: Dictionary = {}
	for card_id in deck:
		if not CARDS.has(card_id):
			continue
		for element in CARDS[card_id]["elements"]:
			elements[element] = true
	return elements


static func card_text(card_id: String) -> String:
	var card: Dictionary = CARDS.get(card_id, {})
	return "%s：%s" % [card.get("name", card_id), card.get("description", "")]
