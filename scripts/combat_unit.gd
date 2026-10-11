class_name CombatUnit
extends RefCounted

var unit_id: String
var display_name: String
var glyph: String
var team: String
var cell: Vector2i
var max_hp: int
var hp: int
var move_points: int
var base_move: int
var skill_points: int
var capture_points: int = 0
var burned: bool = false
var wet: bool = false
var burn_damage_from_round: int = 0
var skill_wet_through_round: int = 0
var wet_move_from_round: int = 0
var speed: int = 0
var eligible_round: int = 1
var element_type: String
var skill_ids: Array[String]
var battle_skill_uses: Dictionary = {}
var battle_buff: String = ""
var upgraded_skill_id: String = ""
var flying: bool = false
var debuff_immune: bool = false
var direct_damage_reduction: int = 0
var bonus_move: int = 0


func _init(
	new_id: String,
	new_name: String,
	new_glyph: String,
	new_team: String,
	new_cell: Vector2i,
	new_hp: int,
	new_move_points: int,
	new_skill_points: int,
	new_element_type: String = "",
	new_skill_ids: Array[String] = []
) -> void:
	unit_id = new_id
	display_name = new_name
	glyph = new_glyph
	team = new_team
	cell = new_cell
	max_hp = new_hp
	hp = new_hp
	move_points = new_move_points
	base_move = new_move_points
	skill_points = new_skill_points
	element_type = new_element_type
	skill_ids = new_skill_ids.duplicate()


func is_alive() -> bool:
	return hp > 0
