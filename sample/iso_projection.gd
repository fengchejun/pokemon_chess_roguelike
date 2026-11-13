extends RefCounted
const HALF_WIDTH := 56.0
const HALF_HEIGHT := 38.0
const ORIGIN := Vector2(448, 0)

static func point(grid: Vector2) -> Vector2:
	var rotated := Vector2(grid.y, 8.0 - grid.x)
	return ORIGIN + Vector2((rotated.x - rotated.y) * HALF_WIDTH, (rotated.x + rotated.y) * HALF_HEIGHT)

static func inverse(local: Vector2) -> Vector2:
	var p := local - ORIGIN
	var rotated := Vector2((p.x / HALF_WIDTH + p.y / HALF_HEIGHT) / 2.0, (p.y / HALF_HEIGHT - p.x / HALF_WIDTH) / 2.0)
	return Vector2(8.0 - rotated.y, rotated.x)

static func diamond(cell: Vector2i) -> PackedVector2Array:
	var g := Vector2(cell)
	return PackedVector2Array([point(g), point(g + Vector2.RIGHT), point(g + Vector2.ONE), point(g + Vector2.DOWN)])
