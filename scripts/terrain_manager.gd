class_name TerrainManager
extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var ground: Dictionary = {}
var objects: Dictionary = {}
var steam: Dictionary = {}
var burning: Dictionary = {}
var vine_underlay: Dictionary = {}
var ice_underlay: Dictionary = {}


func _init(layout: Dictionary = {}) -> void:
	if not layout.is_empty():
		ground = layout.get("ground", {}).duplicate(true)
		objects = layout.get("objects", {}).duplicate(true)
		steam = layout.get("steam", {}).duplicate(true)
		burning = layout.get("burning", {}).duplicate(true)
		vine_underlay = layout.get("vine_underlay", {}).duplicate(true)
		ice_underlay = layout.get("ice_underlay", {}).duplicate(true)
		return
	# Stable fixture for stage 0–4 rule regression.
	for cell in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(4, 2)]:
		ground[cell] = "shallow_water"
	for cell in [Vector2i(4, 1), Vector2i(4, 4)]:
		ground[cell] = "fragile"
	objects[Vector2i(5, 3)] = make_rock()
	objects[Vector2i(5, 4)] = make_plant()


static func make_rock() -> Dictionary:
	return {"type": "rock", "hp": 2, "blocks_move": true, "blocks_attack": true, "pushable": false, "destructible": true, "element": "rock"}


static func make_plant() -> Dictionary:
	return {"type": "plant", "hp": 2, "blocks_move": true, "blocks_attack": false, "pushable": false, "destructible": true, "element": "grass", "burning": false, "burn_turns": 0}


func ground_at(cell: Vector2i) -> String:
	return ground.get(cell, "ground")


func object_at(cell: Vector2i) -> Dictionary:
	return objects.get(cell, {})


func blocks_move(cell: Vector2i) -> bool:
	return not object_at(cell).is_empty() and object_at(cell).get("blocks_move", false)


func is_fragile(cell: Vector2i) -> bool:
	return ground_at(cell) == "fragile"


func is_collapsed(cell: Vector2i) -> bool:
	return ground_at(cell) == "collapsed"


func collapse_fragile(cell: Vector2i) -> bool:
	if not is_fragile(cell):
		return false
	ground[cell] = "collapsed"
	burning.erase(cell)
	steam.erase(cell)
	return true


func is_water(cell: Vector2i) -> bool:
	return ground_at(cell) in ["water", "shallow_water", "deep_water"]


func is_shallow_water(cell: Vector2i) -> bool:
	return ground_at(cell) in ["water", "shallow_water"]


func is_deep_water(cell: Vector2i) -> bool:
	return ground_at(cell) == "deep_water"


func is_flammable(cell: Vector2i) -> bool:
	return ground_at(cell) in ["grass", "vine"] or object_at(cell).get("type", "") == "plant"


func is_vine(cell: Vector2i) -> bool:
	return ground_at(cell) == "vine"


func is_ice(cell: Vector2i) -> bool:
	return ground_at(cell) == "ice"


func set_vine(cell: Vector2i) -> bool:
	if not GridSpec.is_inside(cell) or ground_at(cell) not in ["ground", "grass", "shallow_water", "water"] or not object_at(cell).is_empty():
		return false
	vine_underlay[cell] = ground_at(cell)
	ground[cell] = "vine"
	return true


func remove_vine(cell: Vector2i) -> void:
	if not is_vine(cell):
		return
	var previous: String = vine_underlay.get(cell, "ground")
	vine_underlay.erase(cell)
	if previous == "ground":
		ground.erase(cell)
	else:
		ground[cell] = previous
	burning.erase(cell)


func set_ice(cell: Vector2i) -> bool:
	if not GridSpec.is_inside(cell) or is_ice(cell) or not object_at(cell).is_empty():
		return false
	ice_underlay[cell] = {"ground": ground_at(cell), "vine_underlay": vine_underlay.get(cell, "")}
	ground[cell] = "ice"
	burning.erase(cell)
	steam.erase(cell)
	return true


func melt_ice(cell: Vector2i) -> bool:
	if not is_ice(cell):
		return false
	var saved: Dictionary = ice_underlay.get(cell, {"ground": "ground", "vine_underlay": ""})
	ice_underlay.erase(cell)
	var previous: String = saved["ground"]
	if previous == "ground":
		ground.erase(cell)
	else:
		ground[cell] = previous
	if previous == "vine" and str(saved["vine_underlay"]) != "":
		vine_underlay[cell] = saved["vine_underlay"]
	return true


func is_burning(cell: Vector2i) -> bool:
	return int(burning.get(cell, 0)) > 0


func is_steam(cell: Vector2i) -> bool:
	return int(steam.get(cell, 0)) > 0


func set_water(cell: Vector2i) -> bool:
	if not GridSpec.is_inside(cell) or ground_at(cell) not in ["ground", "grass", "vine"] or not object_at(cell).is_empty():
		return false
	vine_underlay.erase(cell)
	ground[cell] = "shallow_water"
	extinguish_fire(cell)
	return true


func set_rain_water(cell: Vector2i) -> bool:
	if not GridSpec.is_inside(cell) or ground_at(cell) not in ["ground", "grass", "fragile", "vine"] or not object_at(cell).is_empty():
		return false
	vine_underlay.erase(cell)
	ground[cell] = "shallow_water"
	extinguish_fire(cell)
	return true


func extinguish_fire(cell: Vector2i) -> void:
	burning.erase(cell)
	var object: Dictionary = object_at(cell)
	if object.get("type", "") == "plant" and object.get("burning", false):
		object["burning"] = false
		object["burn_turns"] = 0
		objects[cell] = object


func add_rock(cell: Vector2i, expire_after_enemy_round: int = 0) -> bool:
	if not GridSpec.is_inside(cell) or blocks_move(cell) or is_deep_water(cell) or is_fragile(cell) or is_collapsed(cell):
		return false
	var rock: Dictionary = make_rock()
	if expire_after_enemy_round > 0:
		rock["expire_after_enemy_round"] = expire_after_enemy_round
		rock["underlying_ground"] = ground_at(cell)
	objects[cell] = rock
	ground.erase(cell)
	burning.erase(cell)
	steam.erase(cell)
	return true


func expire_temporary_rocks(enemy_round: int) -> Array[Vector2i]:
	var expired: Array[Vector2i] = []
	for cell in objects.keys():
		var object: Dictionary = objects[cell]
		if object.get("type", "") == "rock" and int(object.get("expire_after_enemy_round", 0)) > 0 and int(object["expire_after_enemy_round"]) <= enemy_round:
			_remove_rock(cell, object)
			expired.append(cell)
	return expired


func _remove_rock(cell: Vector2i, object: Dictionary) -> void:
	objects.erase(cell)
	if object.has("underlying_ground"):
		var previous_ground: String = object["underlying_ground"]
		if previous_ground == "ground":
			ground.erase(cell)
		else:
			ground[cell] = previous_ground


func damage_object(cell: Vector2i, amount: int) -> Dictionary:
	var object: Dictionary = object_at(cell)
	if object.is_empty() or not object.get("destructible", false):
		return {}
	object["hp"] = maxi(0, int(object["hp"]) - amount)
	var destroyed: bool = object["hp"] <= 0
	var result := {"type": object["type"], "hp": object["hp"], "destroyed": destroyed}
	if destroyed:
		if object.get("type", "") == "rock":
			_remove_rock(cell, object)
		else:
			objects.erase(cell)
		burning.erase(cell)
	else:
		objects[cell] = object
	return result


func ignite_plant(cell: Vector2i) -> bool:
	if not is_flammable(cell):
		return false
	if burning.has(cell):
		return false
	burning[cell] = CombatConfig.BURNING_TURNS
	var object: Dictionary = object_at(cell)
	if object.get("type", "") == "plant":
		object["burning"] = true
		object["burn_turns"] = CombatConfig.BURNING_TURNS
		objects[cell] = object
	return true


func add_steam(cell: Vector2i) -> void:
	steam[cell] = 2


func connected_water(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_water(start):
		return result
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		result.append(cell)
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if GridSpec.is_inside(neighbor) and is_water(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return result


func ranged_blocker(start: Vector2i, target: Vector2i) -> String:
	if abs(start.x - target.x) + abs(start.y - target.y) <= 1:
		return ""
	var delta := target - start
	var steps: int = maxi(absi(delta.x), absi(delta.y))
	for step in range(1, steps + 1):
		var cell := Vector2i(roundi(float(start.x) + float(delta.x * step) / float(steps)), roundi(float(start.y) + float(delta.y * step) / float(steps)))
		if cell != target and object_at(cell).get("blocks_attack", false):
			return "object"
	return ""
