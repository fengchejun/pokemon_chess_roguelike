class_name Elements
extends RefCounted

## 七属性主环：风 → 草 → 岩 → 电 → 水 → 火 → 冰 → 风；额外火克草。

const LIST := ["wind", "grass", "rock", "electric", "water", "fire", "ice"]

const NAMES := {
	"fire": "火",
	"water": "水",
	"grass": "草",
	"electric": "电",
	"rock": "岩",
	"ice": "冰",
	"wind": "风",
}

const FULL_NAMES := {
	"fire": "火系",
	"water": "水系",
	"grass": "草系",
	"electric": "电系",
	"rock": "岩系",
	"ice": "冰系",
	"wind": "风系",
}

const COLORS := {
	"fire": Color(0.91, 0.42, 0.25),
	"water": Color(0.36, 0.60, 0.90),
	"grass": Color(0.40, 0.72, 0.38),
	"electric": Color(0.93, 0.79, 0.25),
	"rock": Color(0.62, 0.51, 0.40),
	"ice": Color(0.49, 0.83, 0.94),
	"wind": Color(0.62, 0.78, 0.70),
	"": Color(0.75, 0.73, 0.68),
}

const BEATS := {
	"wind": ["grass"],
	"grass": ["rock"],
	"rock": ["electric"],
	"electric": ["water"],
	"water": ["fire"],
	"fire": ["ice", "grass"],
	"ice": ["wind"],
}


static func modifier(attacker: String, defender: String) -> int:
	if attacker == "" or defender == "" or not BEATS.has(attacker) or not BEATS.has(defender):
		return 0
	if BEATS[attacker].has(defender):
		return 1
	if BEATS[defender].has(attacker):
		return -1
	return 0


static func name_of(element: String) -> String:
	return NAMES.get(element, "无")


static func counter_hint(element: String) -> String:
	if not BEATS.has(element):
		return "无属性克制"
	var prey_names: PackedStringArray = []
	var predator_names: PackedStringArray = []
	for prey in BEATS[element]:
		prey_names.append(name_of(String(prey)))
	for attacker in LIST:
		if BEATS[attacker].has(element):
			predator_names.append(name_of(attacker))
	return "克制：%s（直接伤害 +1）；被克：%s（直接伤害 -1）" % ["、".join(prey_names), "、".join(predator_names)]


static func color_of(element: String) -> Color:
	return COLORS.get(element, COLORS[""])


static func order_index(element: String) -> int:
	var index := LIST.find(element)
	return index if index >= 0 else 99


static func counter_pairs() -> Array:
	var pairs: Array = []
	for attacker in LIST:
		for defender in BEATS[attacker]:
			pairs.append([attacker, defender])
	return pairs
