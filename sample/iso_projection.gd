extends RefCounted
const HALF_WIDTH := 40.0
const HALF_HEIGHT := 28.0
const ORIGIN := Vector2(320, 0)

static func point(grid: Vector2) -> Vector2:
	return ORIGIN + Vector2((grid.x - grid.y) * HALF_WIDTH, (grid.x + grid.y) * HALF_HEIGHT)

static func inverse(local: Vector2) -> Vector2:
	var p := local - ORIGIN
	return Vector2((p.x / HALF_WIDTH + p.y / HALF_HEIGHT) / 2.0, (p.y / HALF_HEIGHT - p.x / HALF_WIDTH) / 2.0)

static func diamond(cell: Vector2i) -> PackedVector2Array:
	var g := Vector2(cell)
	return PackedVector2Array([point(g), point(g + Vector2.RIGHT), point(g + Vector2.ONE), point(g + Vector2.DOWN)])
