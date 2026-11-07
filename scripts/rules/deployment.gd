class_name Deployment
extends RefCounted

static func legal(map: Dictionary, enemies: Array, unit: CombatUnit, cell: Vector2i) -> bool:
	if not GridSpec.is_inside(cell) or enemies.any(func(other): return other.is_alive() and other.cell == cell):
		return false
	if (map.get("nest_cells", [map["nest_cell"]]) as Array).has(cell) or cell == map.get("merchant_cell", Vector2i(-1, -1)) or cell == map.get("portal_cell", Vector2i(-1, -1)) or cell == map.get("mentor_cell", Vector2i(-1, -1)):
		return false
	if map.get("electric_flowers", {}).has(cell):
		return false
	var terrain := int(map["terrain"][GridSpec.index(cell)])
	return TerrainDB.can_stand(terrain, unit.element) or (unit.has_buff("flight") and terrain != TerrainDB.OBSTACLE and terrain != TerrainDB.TREE)

static func distance(cell: Vector2i) -> int:
	var result := 100
	for origin in Balance.DEPLOY_AREA:
		result = mini(result, GridSpec.manhattan(origin, cell))
	return result

static func prepare(map: Dictionary, enemies: Array, players: Array, previous: Dictionary) -> Dictionary:
	var area: Array = (map.get("fixed_deploy_area", Balance.DEPLOY_AREA) as Array).filter(func(cell): return players.any(func(unit): return legal(map, enemies, unit, cell)))
	var candidates := GridSpec.all_cells()
	candidates.sort_custom(func(a, b):
		var da := distance(a)
		var db := distance(b)
		return da < db if da != db else a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	if area.size() < players.size():
		for cell in previous.values():
			if not area.has(cell) and players.any(func(unit): return legal(map, enemies, unit, cell)):
				area.append(cell)
	var result: Dictionary = {}
	# Match the most constrained unit first, so water/flight mobility cannot consume its only slot.
	var ordered := players.duplicate()
	ordered.sort_custom(func(a, b): return area.filter(func(c): return legal(map, enemies, a, c)).size() < area.filter(func(c): return legal(map, enemies, b, c)).size())
	for unit in ordered:
		var default_cell: Vector2i = Balance.DEPLOY_CELLS[players.find(unit)] if players.find(unit) < Balance.DEPLOY_CELLS.size() else Vector2i(-1, -1)
		var cell: Vector2i = previous.get(unit.uid, default_cell)
		if area.has(cell) and not result.values().has(cell) and legal(map, enemies, unit, cell):
			result[unit.uid] = cell
	for unit in ordered:
		if result.has(unit.uid):
			continue
		var choices := area.duplicate()
		choices.append_array(candidates)
		for cell in choices:
			if not result.values().has(cell) and legal(map, enemies, unit, cell):
				result[unit.uid] = cell
				if not area.has(cell):
					area.append(cell)
				break
	return {"area": area, "positions": result}

static func valid(map: Dictionary, enemies: Array, players: Array, positions: Dictionary) -> bool:
	var used: Array = []
	for unit in players:
		var cell: Vector2i = positions.get(unit.uid, Vector2i(-1, -1))
		if used.has(cell) or not (map.get("deploy_area", []) as Array).has(cell) or not legal(map, enemies, unit, cell):
			return false
		used.append(cell)
	return true
