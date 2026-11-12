class_name FoodDB
extends RefCounted

const FOODS := {
	"basic": {"name": "基础食物", "rest_cost": 3, "effect": "full_party_heal", "description": "恢复训练家与受伤队员全部生命，并将队伍所有已学技能 PP 回满；濒死队员恢复一半生命。"},
}


static func definition(id: String) -> Dictionary:
	return FOODS.get(id, {})
