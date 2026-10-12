class_name GridSpec
extends RefCounted

const W := Balance.GRID_W
const H := Balance.GRID_H

const DIRS4 := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const DIR_NAMES := {
	Vector2i(0, -1): "上",
	Vector2i(0, 1): "下",
	Vector2i(-1, 0): "左",
	Vector2i(1, 0): "右",
}


static func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < W and cell.y >= 0 and cell.y < H


static func index(cell: Vector2i) -> int:
	return cell.y * W + cell.x


static func cell_of(index_value: int) -> Vector2i:
	return Vector2i(index_value % W, index_value / W)


static func all_cells() -> Array:
	var cells: Array = []
	for y in H:
		for x in W:
			cells.append(Vector2i(x, y))
	return cells


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func neighbors4(cell: Vector2i) -> Array:
	var cells: Array = []
	for dir in DIRS4:
		var next: Vector2i = cell + dir
		if is_inside(next):
			cells.append(next)
	return cells


static func neighbors8(cell: Vector2i) -> Array:
	var cells: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var next := cell + Vector2i(dx, dy)
			if is_inside(next):
				cells.append(next)
	return cells


static func dir_name(dir: Vector2i) -> String:
	return DIR_NAMES.get(dir, "?")
