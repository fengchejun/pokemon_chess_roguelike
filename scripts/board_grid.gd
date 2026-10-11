extends Control

const GridSpec = preload("res://scripts/grid_spec.gd")
const LIGHT_TILE := Color("#86a88a")
const DARK_TILE := Color("#729477")
const GRID_LINE := Color("#263d36")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	for y in GridSpec.HEIGHT:
		for x in GridSpec.WIDTH:
			var cell_rect := get_cell_rect(Vector2i(x, y))
			var tile_color: Color = LIGHT_TILE if (x + y) % 2 == 0 else DARK_TILE
			draw_rect(cell_rect, tile_color)
			draw_rect(cell_rect, GRID_LINE, false, 1.0)

	draw_rect(_board_rect(), GRID_LINE, false, 3.0)


func get_cell_rect(cell: Vector2i) -> Rect2:
	var board_rect: Rect2 = _board_rect()
	var cell_size: Vector2 = board_rect.size / Vector2(GridSpec.WIDTH, GridSpec.HEIGHT)
	return Rect2(board_rect.position + Vector2(cell) * cell_size, cell_size)


func get_cell_at(local_position: Vector2) -> Vector2i:
	var board_rect: Rect2 = _board_rect()
	if not board_rect.has_point(local_position):
		return Vector2i(-1, -1)
	var cell_size: Vector2 = board_rect.size / Vector2(GridSpec.WIDTH, GridSpec.HEIGHT)
	var cell := Vector2i(floori((local_position.x - board_rect.position.x) / cell_size.x), floori((local_position.y - board_rect.position.y) / cell_size.y))
	return cell if GridSpec.is_inside(cell) else Vector2i(-1, -1)


func _board_rect() -> Rect2:
	var cell_size: float = minf(size.x / GridSpec.WIDTH, size.y / GridSpec.HEIGHT)
	var board_size := Vector2(cell_size * GridSpec.WIDTH, cell_size * GridSpec.HEIGHT)
	return Rect2((size - board_size) / 2.0, board_size)
