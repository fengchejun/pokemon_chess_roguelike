extends RefCounted

## Shared coordinates for the fixed-size board.
const WIDTH: int = 8
const HEIGHT: int = 8


static func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT
