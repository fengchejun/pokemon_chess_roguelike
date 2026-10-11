extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Returns the shortest voluntary route, excluding the starting cell.
static func find_path(state: RefCounted, unit: CombatUnit, target: Vector2i, max_steps: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if unit == null or max_steps <= 0 or target == unit.cell or not state.can_enter_voluntarily(unit, target):
		return empty
	var frontier: Array = [{"cell": unit.cell, "path": empty}]
	var visited: Dictionary = {unit.cell: true}
	while not frontier.is_empty():
		var entry: Dictionary = frontier.pop_front()
		var current: Vector2i = entry["cell"]
		var path: Array[Vector2i] = entry["path"]
		if path.size() >= max_steps:
			continue
		for direction in DIRECTIONS:
			var next_cell: Vector2i = current + direction
			if visited.has(next_cell) or not state.can_traverse_voluntarily(unit, next_cell):
				continue
			var next_path: Array[Vector2i] = path.duplicate()
			next_path.append(next_cell)
			if next_cell == target:
				return next_path
			visited[next_cell] = true
			frontier.append({"cell": next_cell, "path": next_path})
	return empty
