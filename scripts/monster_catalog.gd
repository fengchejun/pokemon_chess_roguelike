class_name MonsterCatalog
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")

const SPECIES := {
	"fire": {"name": "火系怪物", "glyph": "火", "element": "fire", "speed": 3, "move": 3, "skills": ["fire_burst", "flame_charge", "flame_jet"]},
	"water": {"name": "水电怪物", "glyph": "水", "element": "water", "speed": 2, "move": 3, "skills": ["water_flow", "electric_arc", "rain_call"]},
	"rock": {"name": "岩系怪物", "glyph": "岩", "element": "rock", "speed": 1, "move": 2, "skills": ["rock_push", "rock_break", "rock_create"]},
}


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
