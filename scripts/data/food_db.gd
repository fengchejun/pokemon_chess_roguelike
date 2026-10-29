class_name FoodDB
extends RefCounted

const FOODS := {
	"basic": {"name": "基础食物", "rest_cost": 3, "effect": "full_party_heal", "description": "恢复训练家和携带队伍全部生命，濒死成员可重新出战。"},
}


static func definition(id: String) -> Dictionary:
	return FOODS.get(id, {})
