class_name PathFinder
extends RefCounted

## 主动移动寻路：Dijkstra。地面单位中途可穿过己方单位，不能停在其格上；
## 飞行可越过单位、障碍与致死地形，但终点仍需空置且非障碍、非巢穴。


static func reachable(state, unit: CombatUnit) -> Dictionary:
	var budget: int = state.move_budget_for(unit)
	var result := {}
	if budget <= 0 or not unit.is_alive():
		return result
	var start := unit.cell
	var best := {start: 0}
	var frontier: Array = [start]
	var paths := {start: []}
	while not frontier.is_empty():
		# 取当前代价最小的格子（棋盘小，直接线性扫描）
		var current: Vector2i = frontier[0]
		var current_cost: int = best[current]
		for cell in frontier:
			if best[cell] < current_cost or (best[cell] == current_cost and _before(cell, current)):
				current = cell
				current_cost = best[cell]
		frontier.erase(current)
		for dir in GridSpec.DIRS4:
			var next: Vector2i = current + dir
			if not GridSpec.is_inside(next):
				continue
			if not unit.has_buff("flight") and (state.is_nest_cell(next) or TerrainDB.blocks_move(state.terrain_at(next))):
				continue
			var occupant: CombatUnit = state.unit_at(next)
			if not unit.has_buff("flight") and occupant != null and occupant.side != unit.side:
				continue
			var cost: int = state.move_cost_for(unit, next)
			if cost < 0:
				continue
			var total := current_cost + cost
			if total <= budget and total < int(best.get(next, 1 << 30)):
				best[next] = total
				paths[next] = (paths[current] as Array).duplicate() + [next]
				frontier.append(next)
	var out := {}
	for cell in best:
		if cell == start:
			continue
		out[cell] = {"cost": best[cell], "path": paths[cell]}
	var terrain_mode := -1
	if state.terrain_at(start) == TerrainDB.ICE and unit.ice_glide_until_round >= state.round:
		terrain_mode = TerrainDB.ICE
	elif TerrainDB.is_water_body(state.terrain_at(start)) and unit.surf_until_round >= state.round:
		terrain_mode = TerrainDB.WATER
	if terrain_mode >= 0:
		var terrain_paths := _connected_terrain_paths(state, unit, terrain_mode)
		for cell in terrain_paths:
			var route: Array = terrain_paths[cell]
			if not out.has(cell) or route.size() < (out[cell]["path"] as Array).size():
				out[cell] = {"cost": 0, "path": route, "terrain_travel": true}
	return out


static func _connected_terrain_paths(state, unit: CombatUnit, terrain_mode: int) -> Dictionary:
	var routes: Dictionary = {unit.cell: []}
	var queue: Array = [unit.cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for dir in GridSpec.DIRS4:
			var next: Vector2i = current + dir
			if not GridSpec.is_inside(next) or routes.has(next) or state.unit_at(next) != null or state.is_nest_cell(next) or TerrainDB.blocks_move(state.terrain_at(next)):
				continue
			var terrain: int = state.terrain_at(next)
			if terrain_mode == TerrainDB.ICE and terrain != TerrainDB.ICE:
				continue
			if terrain_mode == TerrainDB.WATER and not TerrainDB.is_water_body(terrain):
				continue
			routes[next] = (routes[current] as Array).duplicate() + [next]
			queue.append(next)
	routes.erase(unit.cell)
	return routes


static func stop_cells(state, unit: CombatUnit) -> Dictionary:
	## 可作为移动终点的格子（必须没有单位、不是巢穴）。
	var cells := {}
	var options := reachable(state, unit)
	for cell in options:
		if state.unit_at(cell) == null and not state.is_nest_cell(cell) and not TerrainDB.blocks_move(state.terrain_at(cell)):
			cells[cell] = options[cell]
	return cells


static func _before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


static func path_distance(state, from_cell: Vector2i, to_cell: Vector2i, element: String, flying: bool = false) -> int:
	## 忽略单位占位的距离场，用于 AI 的接近度量。
	var best := {from_cell: 0}
	var frontier: Array = [from_cell]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = best[current]
		if current == to_cell:
			return current_cost
		for dir in GridSpec.DIRS4:
			var next: Vector2i = current + dir
			if not GridSpec.is_inside(next):
				continue
			if not flying and (TerrainDB.blocks_move(state.terrain_at(next)) or state.is_nest_cell(next)):
				continue
			var cost := 1 if flying else TerrainDB.move_cost(state.terrain_at(next), element)
			if cost < 0:
				continue
			var total := current_cost + cost
			if total < int(best.get(next, 1 << 30)):
				best[next] = total
				frontier.append(next)
	return 1 << 30
