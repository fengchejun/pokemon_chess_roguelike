class_name Elements
extends RefCounted

## 五属性单环；冰系技能归水，风系技能归电，机制与 ID 仍保留。

const MATCHUPS_ENABLED := true

const LIST := ["fire", "water", "grass", "rock", "electric"]

const NAMES := {
	"fire": "火",
	"water": "水",
	"grass": "草",
	"electric": "电",
	"rock": "岩",
}

const FULL_NAMES := {
	"fire": "火系",
	"water": "水系",
	"grass": "草系",
	"electric": "电系",
	"rock": "岩系",
}

const COLORS := {
	"fire": Color(0.91, 0.42, 0.25),
	"water": Color(0.36, 0.60, 0.90),
	"grass": Color(0.40, 0.72, 0.38),
	"electric": Color(0.93, 0.79, 0.25),
	"rock": Color(0.62, 0.51, 0.40),
	"": Color(0.75, 0.73, 0.68),
}

const BEATS := {
	"grass": ["rock"],
	"rock": ["electric"],
	"electric": ["water"],
	"water": ["fire"],
	"fire": ["grass"],
}


static func modifier(attacker: String, defender: String) -> int:
	if not MATCHUPS_ENABLED:
		return 0
	if attacker == "" or defender == "" or not BEATS.has(attacker) or not BEATS.has(defender):
		return 0
	if BEATS[attacker].has(defender):
		return 1
	if BEATS[defender].has(attacker):
		return -1
	return 0


static func direct_damage(base: int, attacker: String, defender: String) -> int:
	if base <= 0:
		return 0
	var relation := modifier(attacker, defender)
	if relation == 0:
		return base
	return maxi(1, roundi(float(base) * (1.25 if relation > 0 else 0.75)))


static func name_of(element: String) -> String:
	return NAMES.get(element, "无")


static func counter_hint(element: String) -> String:
	if not MATCHUPS_ENABLED:
		return ""
	if not BEATS.has(element):
		return "无属性克制"
	var prey_names: PackedStringArray = []
	var predator_names: PackedStringArray = []
	for prey in BEATS[element]:
		prey_names.append(name_of(String(prey)))
	for attacker in LIST:
		if BEATS[attacker].has(element):
			predator_names.append(name_of(attacker))
	return "克制：%s（技能直接伤害 ×1.25）；被克：%s（×0.75）" % ["、".join(prey_names), "、".join(predator_names)]


static func color_of(element: String) -> Color:
	return COLORS.get(element, COLORS[""])


static func order_index(element: String) -> int:
	var index := LIST.find(element)
	return index if index >= 0 else 99


static func counter_pairs() -> Array:
	if not MATCHUPS_ENABLED:
		return []
	var pairs: Array = []
	for attacker in LIST:
		for defender in BEATS[attacker]:
			pairs.append([attacker, defender])
	return pairs
