class_name MonsterCatalog
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")

const SPECIES := {
	"fire": {"name": "火系怪物", "glyph": "火", "element": "fire", "speed": 3, "move": 3, "skills": ["fire_burst", "flame_charge", "flame_jet"]},
	"water": {"name": "水系怪物", "glyph": "水", "element": "water", "speed": 2, "move": 3, "skills": ["water_flow", "rain_call"]},
	"rock": {"name": "岩系怪物", "glyph": "岩", "element": "rock", "speed": 1, "move": 2, "skills": ["rock_push", "rock_break", "rock_create"]},
	"electric": {"name": "电系怪物", "glyph": "电", "element": "electric", "speed": 2, "move": 3, "skills": ["lightning", "electric_arc"]},
	"grass": {"name": "草系怪物", "glyph": "草", "element": "grass", "speed": 2, "move": 2, "skills": ["wild_vines", "herbal_heal"]},
	"ice": {"name": "冰系怪物", "glyph": "冰", "element": "ice", "speed": 2, "move": 2, "skills": ["frozen_ground", "freeze_ray"]},
	"wind": {"name": "风系怪物", "glyph": "风", "element": "wind", "speed": 3, "move": 4, "skills": ["tailwind", "double_cast"]},
}

const SPECIES_ORDER: Array[String] = ["fire", "water", "rock", "electric", "grass", "ice", "wind"]
const REGION_ENEMY_WEIGHTS := {
	"wetland": {"fire": 1, "water": 4, "rock": 1, "electric": 4, "grass": 1, "ice": 4, "wind": 1},
	"forest": {"fire": 4, "water": 1, "rock": 1, "electric": 1, "grass": 4, "ice": 1, "wind": 4},
	"ruins": {"fire": 1, "water": 1, "rock": 4, "electric": 4, "grass": 1, "ice": 4, "wind": 1},
}


static func pick_region_enemy(region_id: String, rng: RandomNumberGenerator, excluded: Array[String] = []) -> String:
	var weights: Dictionary = REGION_ENEMY_WEIGHTS.get(region_id, REGION_ENEMY_WEIGHTS["wetland"])
	var total := 0
	for species_id in SPECIES_ORDER:
		if not excluded.has(species_id):
			total += int(weights[species_id])
	var roll: int = rng.randi_range(1, total)
	for species_id in SPECIES_ORDER:
		if excluded.has(species_id):
			continue
		roll -= int(weights[species_id])
		if roll <= 0:
			return species_id
	return SPECIES_ORDER[0]


static func make_record(instance_id: String, species_id: String) -> Dictionary:
	return {"instance_id": instance_id, "species_id": species_id, "level": 1, "experience": 0}


static func make_ally(record: Dictionary, cell: Vector2i) -> CombatUnit:
	var species: Dictionary = SPECIES[record["species_id"]]
	var skills: Array[String] = []
	for skill_id in species["skills"]:
		skills.append(skill_id)
	var unit := CombatUnit.new(record["instance_id"], species["name"], species["glyph"], "player", cell, CombatConfig.MONSTER_HP, int(species["move"]), CombatConfig.SKILL_POINTS_PER_TURN, species["element"], skills)
	unit.speed = int(species["speed"])
	return unit


static func make_enemy(unit_id: String, species_id: String, cell: Vector2i) -> CombatUnit:
	var species: Dictionary = SPECIES[species_id]
	var skills: Array[String] = []
	for skill_id in species["skills"]:
		skills.append(skill_id)
	var unit := CombatUnit.new(unit_id, "野生" + species["name"], "敌" + species["glyph"], "enemy", cell, CombatConfig.WILD_HP, int(species["move"]), CombatConfig.SKILL_POINTS_PER_TURN, species["element"], skills)
	unit.speed = int(species["speed"])
	return unit
