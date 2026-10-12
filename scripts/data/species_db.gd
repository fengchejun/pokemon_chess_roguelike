class_name SpeciesDB
extends RefCounted

## 物种表。初始队伍每属性一只；野生单位使用同一套规则。

const SPECIES := {
	"trainer": {
		"name": "训练家", "glyph": "训", "element": "", "hp": 7, "move": 3,
		"skills": [], "is_trainer": true,
	},
	"fire_starter": {
		"name": "小火龙", "glyph": "焰", "element": "fire", "hp": 6, "move": 3,
		"skills": ["fire_seed", "flame_charge"],
	},
	"water_starter": {
		"name": "杰尼龟", "glyph": "泡", "element": "water", "hp": 6, "move": 3,
		"skills": ["water_flow", "rain_dance"],
	},
	"grass_starter": {
		"name": "妙蛙种子", "glyph": "芽", "element": "grass", "hp": 6, "move": 3,
		"skills": ["seed_sow", "drain"],
	},
	"electric_starter": {
		"name": "皮卡丘", "glyph": "电", "element": "electric", "hp": 5, "move": 3,
		"skills": ["discharge", "volt_step"],
	},
	"rock_starter": {
		"name": "小拳石", "glyph": "石", "element": "rock", "hp": 7, "move": 2,
		"skills": ["push", "rock_smash", "rock_create"],
	},
	"fire_wild1": {
		"name": "六尾", "glyph": "狐", "element": "fire", "hp": 5, "move": 3,
		"skills": ["fire_seed"],
	},
	"fire_wild2": {
		"name": "卡蒂狗", "glyph": "犬", "element": "fire", "hp": 5, "move": 3,
		"skills": ["fire_seed", "flame_charge"],
	},
	"water_wild1": {
		"name": "可达鸭", "glyph": "鸭", "element": "water", "hp": 5, "move": 3,
		"skills": ["water_flow"],
	},
	"water_wild2": {
		"name": "蚊香蝌蚪", "glyph": "蝌", "element": "water", "hp": 5, "move": 3,
		"skills": ["water_flow", "rain_dance"],
	},
	"grass_wild1": {
		"name": "走路草", "glyph": "草", "element": "grass", "hp": 5, "move": 3,
		"skills": ["drain", "seed_sow"],
	},
	"grass_wild2": {
		"name": "喇叭芽", "glyph": "花", "element": "grass", "hp": 5, "move": 3,
		"skills": ["drain"],
	},
	"electric_wild1": {
		"name": "小磁怪", "glyph": "磁", "element": "electric", "hp": 5, "move": 3,
		"skills": ["discharge"],
	},
	"electric_wild2": {
		"name": "霹雳电球", "glyph": "球", "element": "electric", "hp": 5, "move": 3,
		"skills": ["discharge", "volt_step"],
	},
	"rock_wild1": {
		"name": "大岩蛇", "glyph": "蛇", "element": "rock", "hp": 6, "move": 2,
		"skills": ["push", "rock_smash"],
	},
	"rock_wild2": {
		"name": "隆隆石", "glyph": "岩", "element": "rock", "hp": 6, "move": 2,
		"skills": ["rock_smash", "rock_create"],
	},
}

const STARTER_TEAM := [
	"fire_starter", "water_starter", "grass_starter", "electric_starter", "rock_starter",
]


static func get_species(species_id: String) -> Dictionary:
	return SPECIES.get(species_id, {})


static func name_of(species_id: String) -> String:
	return get_species(species_id).get("name", species_id)


static func element_of(species_id: String) -> String:
	return get_species(species_id).get("element", "")


static func hp_of(species_id: String) -> int:
	return int(get_species(species_id).get("hp", 4))


static func move_of(species_id: String) -> int:
	return int(get_species(species_id).get("move", 3))


static func skills_of(species_id: String) -> Array:
	return get_species(species_id).get("skills", [])


static func is_trainer(species_id: String) -> bool:
	return bool(get_species(species_id).get("is_trainer", false))
