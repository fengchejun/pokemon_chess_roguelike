class_name BoardView
extends Control

signal cell_clicked(cell: Vector2i)
signal cell_right_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const TILE := 72.0

var terrain: Array = []
var obstacle_durability: Dictionary = {}
var burning_cells: Dictionary = {}
var steam_cells: Dictionary = {}
var nest: Dictionary = {}
var pending_casts: Array = []
var battle_round: int = 0
var reward: Dictionary = {}
var fruits: Array = []
var units: Array = []
var deploy_cells: Array = []

var movement_cells: Dictionary = {}
var enemy_cells_view: Array = []
var attack_cells: Array = []
var area_cells: Array = []
var ray_cells: Array = []
var path_cells: Array = []
var markers: Array = []
var arrows: Array = []
var badges: Array = []

var selected_uid: int = -1
var hover_cell := Vector2i(-1, -1)


func _ready() -> void:
	custom_minimum_size = Vector2(GridSpec.W * TILE, GridSpec.H * TILE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_from_state(state: BattleState) -> void:
	if state == null:
		return
	terrain = state.terrain.duplicate()
	obstacle_durability = state.obstacle_durability.duplicate()
	burning_cells = state.burning_cells.duplicate()
	steam_cells = state.steam_cells.duplicate()
	nest = state.nest.duplicate(true)
	pending_casts = state.pending_casts.duplicate(true)
	battle_round = state.round
	reward = state.reward.duplicate(true)
	fruits = state.fruits.duplicate()
	units = state.units.duplicate()
	deploy_cells = state.deploy_cells.duplicate()
	queue_redraw()


func set_map_preview(map: Dictionary, preview_units: Array = []) -> void:
	terrain = (map.get("terrain", []) as Array).duplicate()
	obstacle_durability = {}
	burning_cells = {}
	steam_cells = map.get("steam_cells", {}).duplicate()
	for cell in map.get("obstacle_cells", []):
		obstacle_durability[cell] = Balance.TREE_DURABILITY if terrain[GridSpec.index(cell)] == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
	nest = {
		"cell": map.get("nest_cell", Vector2i(-1, -1)),
		"exits": map.get("nest_exits", []).duplicate(),
		"hp": Balance.NEST_DURABILITY,
		"alive": true,
	}
	pending_casts = []
	battle_round = 0
	reward = {"state": "map", "cell": map.get("reward_cell", Vector2i(-1, -1)), "owner_uid": -1}
	fruits = map.get("fruit_cells", []).duplicate()
	units = preview_units
	deploy_cells = map.get("deploy_cells", Balance.DEPLOY_CELLS.duplicate())
	queue_redraw()


func clear_overlays() -> void:
	movement_cells = {}
	enemy_cells_view = []
	attack_cells = []
	area_cells = []
	ray_cells = []
	path_cells = []
	markers = []
	arrows = []
	badges = []
	queue_redraw()


func cell_at(position: Vector2) -> Vector2i:
	var cell := Vector2i(int(position.x / TILE), int(position.y / TILE))
	if not GridSpec.is_inside(cell):
		return Vector2i(-1, -1)
	return cell


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 72.0 + 36.0, cell.y * 72.0 + 36.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := cell_at(event.position)
		if cell == Vector2i(-1, -1):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cell_right_clicked.emit(cell)
	elif event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()


func _draw() -> void:
	var font := UIKit.font()
	var hovered := Vector2i(-1, -1)
	for y in GridSpec.H:
		for x in GridSpec.W:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * TILE, y * TILE, TILE, TILE)
			_draw_terrain(rect, terrain[GridSpec.index(cell)])
			if burning_cells.has(cell):
				draw_circle(rect.position + Vector2(55, 17), 9.0, Color(1.0, 0.32, 0.08, 0.88))
			if steam_cells.has(cell):
				draw_circle(rect.position + Vector2(28, 25), 17.0, Color(0.92, 0.94, 0.96, 0.38))
				draw_circle(rect.position + Vector2(46, 42), 13.0, Color(0.92, 0.94, 0.96, 0.33))
	# 覆盖层：移动范围 / 攻击范围 / 区域 / 射线
	for cell in movement_cells:
		_draw_fill(cell, Color(0.35, 0.6, 1.0, 0.28))
		var cost := int(movement_cells[cell]["cost"])
		draw_string(font, cell_center(cell) + Vector2(20, 28), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.9, 1.0, 0.9))
	for cell in enemy_cells_view:
		_draw_fill(cell, Color(1.0, 0.35, 0.3, 0.20))
	for cell in area_cells:
		_draw_fill(cell, Color(1.0, 0.55, 0.2, 0.22))
	for cell in attack_cells:
		_draw_fill(cell, Color(1.0, 0.85, 0.35, 0.38))
		if GridSpec.is_inside(cell):
			draw_rect(Rect2(cell.x * TILE + 2, cell.y * TILE + 2, TILE - 4, TILE - 4), Color(1.0, 0.8, 0.3, 0.85), false, 2.0)
	# 绘制网格线
	for x in GridSpec.W + 1:
		draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, GridSpec.H * TILE), Color(0, 0, 0, 0.35), 1.0)
	for y in GridSpec.H + 1:
		draw_line(Vector2(0, y * TILE), Vector2(GridSpec.W * TILE, y * TILE), Color(0, 0, 0, 0.35), 1.0)
	for cell in deploy_cells:
		if GridSpec.is_inside(cell):
			draw_rect(Rect2(cell.x * TILE + 2, cell.y * TILE + 2, TILE - 4, TILE - 4), Color(0.5, 0.75, 1.0, 0.5), false, 2.0)
	if not ray_cells.is_empty():
		var points: PackedVector2Array = []
		for cell in ray_cells:
			points.append(cell_center(cell))
		if points.size() >= 2:
			draw_polyline(points, Color(1.0, 0.9, 0.4, 0.8), 3.0)
	if not path_cells.is_empty():
		var route: PackedVector2Array = []
		for cell in path_cells:
			route.append(cell_center(cell))
		if route.size() >= 2:
			draw_polyline(route, Color(0.6, 1.0, 0.7, 0.9), 3.0)
	# 物件
	_draw_objects(font)
	# 单位
	for unit in units:
		if unit.is_alive():
			_draw_unit(font, unit)
	_draw_pending_casts(font)
	_draw_nest_exit(font)
	# 标记与箭头
	for arrow in arrows:
		_draw_arrow(arrow)
	for marker in markers:
		_draw_marker(font, marker)
	if badges.size() > 0:
		for badge in badges:
			var cell: Vector2i = badge.get("cell", Vector2i(-1, -1))
			if GridSpec.is_inside(cell):
				draw_string(font, cell_center(cell) + Vector2(-30, -26), String(badge.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(badge.get("size", 12)), badge.get("color", UIKit.ACCENT))
	if GridSpec.is_inside(hover_cell):
		hovered = hover_cell
		draw_rect(Rect2(hovered.x * TILE + 1, hovered.y * TILE + 1, TILE - 2, TILE - 2), Color(1, 1, 1, 0.75), false, 2.0)


func _draw_fill(cell: Vector2i, color: Color) -> void:
	if not GridSpec.is_inside(cell):
		return
	draw_rect(Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE), color)


func _draw_terrain(rect: Rect2, value: int) -> void:
	var color := TerrainDB.color_of(value)
	draw_rect(rect, color)
	match value:
		TerrainDB.WATER:
			for line_index in 3:
				var y := rect.position.y + 16.0 + line_index * 20.0
				draw_line(Vector2(rect.position.x + 8, y), Vector2(rect.position.x + 34, y), Color(1, 1, 1, 0.25), 2.0)
				draw_line(Vector2(rect.position.x + 28, y + 8), Vector2(rect.position.x + 62, y + 8), Color(1, 1, 1, 0.25), 2.0)
		TerrainDB.DEEP:
			draw_rect(Rect2(rect.position + Vector2(6, 6), rect.size - Vector2(12, 12)), Color(0, 0, 0.15, 0.35))
			for line_index in 2:
				var y := rect.position.y + 24.0 + line_index * 24.0
				draw_line(Vector2(rect.position.x + 10, y), Vector2(rect.position.x + 62, y), Color(0.6, 0.8, 1.0, 0.28), 2.0)
		TerrainDB.GRASS:
			for tuft in 3:
				var base := rect.position + Vector2(14 + tuft * 20, 48)
				draw_line(base, base + Vector2(-6, -12), Color(0.16, 0.4, 0.16, 0.9), 2.0)
				draw_line(base + Vector2(-2, 0), base + Vector2(2, -16), Color(0.16, 0.4, 0.16, 0.9), 2.0)
				draw_line(base + Vector2(4, 0), base + Vector2(10, -12), Color(0.16, 0.4, 0.16, 0.9), 2.0)
		TerrainDB.OBSTACLE:
			draw_rect(Rect2(rect.position + Vector2(8, 8), rect.size - Vector2(16, 16)), Color(0.30, 0.26, 0.23))
			draw_rect(Rect2(rect.position + Vector2(8, 8), rect.size - Vector2(16, 16)), Color(0.55, 0.49, 0.44), false, 3.0)
			draw_line(rect.position + Vector2(18, 50), rect.position + Vector2(34, 22), Color(0.6, 0.54, 0.48), 2.0)
		TerrainDB.TREE:
			draw_rect(Rect2(rect.position + Vector2(32, 42), Vector2(9, 24)), Color(0.35, 0.22, 0.12))
			draw_circle(rect.position + Vector2(36, 29), 22.0, Color(0.13, 0.36, 0.16))
		TerrainDB.LAVA:
			draw_rect(rect, Color(0.78, 0.22, 0.08))
			for bubble in 3:
				var center := rect.position + Vector2(16 + bubble * 20, 24 + (bubble % 2) * 22)
				draw_circle(center, 5.0, Color(1.0, 0.6, 0.1, 0.9))
		TerrainDB.FRAGILE:
			draw_line(rect.position + Vector2(12, 12), rect.position + Vector2(43, 39), Color(0.35, 0.22, 0.16), 3.0)
			draw_line(rect.position + Vector2(43, 39), rect.position + Vector2(24, 61), Color(0.35, 0.22, 0.16), 3.0)
		TerrainDB.PIT:
			draw_rect(Rect2(rect.position + Vector2(8, 8), rect.size - Vector2(16, 16)), Color(0.03, 0.03, 0.06))
		TerrainDB.ICE:
			draw_line(rect.position + Vector2(8, 52), rect.position + Vector2(58, 14), Color.WHITE, 3.0)
		TerrainDB.VINES:
			for offset in [18, 36, 54]:
				draw_circle(rect.position + Vector2(offset, 35), 6.0, Color(0.10, 0.38, 0.16))


func _draw_objects(font: Font) -> void:
	if not nest.is_empty() and bool(nest.get("alive", false)):
		var cell: Vector2i = nest["cell"]
		var center := cell_center(cell)
		var points := PackedVector2Array([
			center + Vector2(0, -22), center + Vector2(20, 0),
			center + Vector2(0, 22), center + Vector2(-20, 0),
		])
		draw_colored_polygon(points, Color(0.55, 0.3, 0.7, 0.95))
		draw_polyline(points + PackedVector2Array([points[0]]), Color(0.9, 0.8, 1.0), 2.0)
		draw_string(font, center + Vector2(-10, 8), "巢", HORIZONTAL_ALIGNMENT_CENTER, 20, 18, Color.WHITE)
		draw_string(font, center + Vector2(-20, -26), "耐久 %d/3" % int(nest.get("hp", 3)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.8, 1.0))
	if not reward.is_empty():
		var state_name := String(reward.get("state", ""))
		if state_name == "map" or state_name == "guarding":
			_draw_star(reward["cell"])
	for fruit_cell in fruits:
		var center := cell_center(fruit_cell)
		draw_circle(center + Vector2(0, -2), 8.0, Color(0.9, 0.25, 0.35))
		draw_circle(center + Vector2(0, -26), 4.0, Color(0.3, 0.75, 0.35))


func _draw_nest_exit(font: Font) -> void:
	if not bool(nest.get("alive", false)):
		return
	for cell in nest.get("exits", []):
		if not GridSpec.is_inside(cell):
			continue
		var occupant: CombatUnit = null
		for unit in units:
			if unit.is_alive() and unit.cell == cell:
				occupant = unit
				break
		var color := Color(0.95, 0.75, 0.25)
		if occupant != null:
			color = Color(1.0, 0.35, 0.36) if occupant.side == "enemy" else Color(0.4, 0.85, 1.0)
		elif int(nest.get("pending_waves", 0)) > 0 or Balance.nest_warning_due(battle_round):
			color = Color(1.0, 0.5, 0.18)
		var rect := Rect2(cell.x * TILE + 3, cell.y * TILE + 3, TILE - 6, TILE - 6)
		draw_rect(rect, color, false, 4.0)
		# 单位占据出口时，角标仍绘制在其上方。
		draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(35, 16)), Color(0.08, 0.10, 0.13, 0.92))
		draw_string(font, rect.position + Vector2(4, 15), "出口", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _draw_pending_casts(font: Font) -> void:
	var marked := {}
	for cast in pending_casts:
		var color := Color(0.35, 0.88, 1.0) if String(cast["side"]) == "player" else Color(1.0, 0.32, 0.32)
		for center in cast["cells"]:
			var cells: Array = [center]
			if String(cast["skill_id"]) == "fire_burst":
				cells = []
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var area: Vector2i = center + Vector2i(dx, dy)
						if GridSpec.is_inside(area):
							cells.append(area)
			for cell in cells:
				var rect := Rect2(cell.x * TILE + 5, cell.y * TILE + 5, TILE - 10, TILE - 10)
				draw_rect(rect, color, false, 3.0)
				marked[cell] = int(marked.get(cell, 0)) + 1
		var caster: CombatUnit = null
		for unit in units:
			if unit.uid == int(cast["uid"]) and unit.is_alive():
				caster = unit
				break
		if caster != null:
			draw_string(font, cell_center(caster.cell) + Vector2(15, 30), "吟", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	for cell in marked:
		var count := int(marked[cell])
		var label := "蓄%d" % count if count > 1 else "蓄"
		draw_rect(Rect2(cell.x * TILE + 2, cell.y * TILE + 2, 32 if count > 1 else 20, 17), Color(0.08, 0.10, 0.13, 0.92))
		draw_string(font, Vector2(cell.x * TILE + 4, cell.y * TILE + 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _draw_star(cell: Vector2i) -> void:
	var center := cell_center(cell) + Vector2(0, -22)
	var points := PackedVector2Array()
	for index in 10:
		var radius := 10.0 if index % 2 == 0 else 4.5
		var angle := -PI / 2.0 + index * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(1.0, 0.85, 0.2))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.7, 0.55, 0.1), 1.5)


func _draw_unit(font: Font, unit: CombatUnit) -> void:
	var center := cell_center(unit.cell)
	var radius := 26.0
	var fill := Elements.color_of(unit.element)
	if unit.is_trainer:
		fill = Color(0.72, 0.7, 0.62)
	if unit.is_trainer:
		draw_rect(Rect2(center - Vector2(radius - 3, radius - 3), Vector2((radius - 3) * 2, (radius - 3) * 2)), fill)
		draw_rect(Rect2(center - Vector2(radius - 3, radius - 3), Vector2((radius - 3) * 2, (radius - 3) * 2)), _border_color(unit), false, 3.0)
	else:
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0, TAU, 48, _border_color(unit), 3.0)
	if unit.uid == selected_uid:
		draw_arc(center, radius + 4, 0, TAU, 48, UIKit.ACCENT, 3.0)
	draw_string(font, center + Vector2(-14, 10), unit.glyph, HORIZONTAL_ALIGNMENT_CENTER, 28, 26, Color(0.1, 0.1, 0.12))
	# 生命条
	var bar_rect := Rect2(center.x - 22, center.y + 20, 44, 7)
	draw_rect(bar_rect, Color(0.1, 0.1, 0.1, 0.85))
	var ratio := clampf(float(unit.hp) / float(maxi(1, unit.max_hp)), 0, 1)
	var hp_color := Color(0.45, 0.85, 0.45)
	if ratio <= 0.34:
		hp_color = Color(0.9, 0.35, 0.3)
	elif ratio <= 0.67:
		hp_color = Color(0.95, 0.75, 0.3)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), hp_color)
	draw_string(font, center + Vector2(-34, -7), "%d/%d" % [unit.hp, unit.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	# 状态徽章
	var badges_text := ""
	if unit.burn_ticks > 0:
		badges_text += "灼"
	if unit.root_pending or unit.move_cancelled:
		badges_text += "定"
	if unit.slow_ticks > 0:
		badges_text += "缓"
	if badges_text != "":
		draw_string(font, center + Vector2(20, -3), badges_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.3))
	if not unit.attachments.is_empty():
		var aura_text := ""
		var aura_keys: Array = unit.attachments.keys()
		aura_keys.sort_custom(func(a: String, b: String) -> bool: return Elements.order_index(a) < Elements.order_index(b))
		for aura_element in aura_keys.slice(0, 2):
			aura_text += "%s%d" % [Elements.name_of(String(aura_element)), (unit.attachments[aura_element] as Array).size()]
		if aura_keys.size() > 2:
			aura_text += "+%d" % (aura_keys.size() - 2)
		draw_rect(Rect2(center + Vector2(-34, -35), Vector2(68, 16)), Color(0.09, 0.12, 0.14, 0.85))
		draw_string(font, center + Vector2(-31, -22), aura_text, HORIZONTAL_ALIGNMENT_LEFT, 64, 11, Color(1.0, 0.95, 0.45))
	if unit.capture_used:
		draw_string(font, center + Vector2(20, 32), "捕", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.9))
	if unit.fresh_spawn:
		draw_string(font, center + Vector2(-30, -18), "新", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.8, 0.4))
	if String(reward.get("state", "")) == "carried" and int(reward.get("owner_uid", -1)) == unit.uid:
		draw_string(font, center + Vector2(-31, 33), "奖", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.2))
	if not unit.battle_buffs.is_empty():
		draw_string(font, center + Vector2(19, 32), "增", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.88, 0.3))


func _border_color(unit: CombatUnit) -> Color:
	if unit.side == "player":
		return Color(0.4, 0.7, 1.0)
	return Color(1.0, 0.45, 0.4)


func _draw_arrow(arrow: Dictionary) -> void:
	var from := cell_center(arrow["from"])
	var to := cell_center(arrow["to"])
	var color: Color = arrow.get("color", Color(1, 0.5, 0.4, 0.9))
	draw_line(from, to, color, 4.0)
	var dir := (to - from).normalized()
	var left := to - dir.rotated(0.5) * 16.0
	var right := to - dir.rotated(-0.5) * 16.0
	draw_colored_polygon(PackedVector2Array([to, left, right]), color)


func _draw_marker(font: Font, marker: Dictionary) -> void:
	var cell: Vector2i = marker.get("cell", Vector2i(-1, -1))
	if not GridSpec.is_inside(cell):
		return
	var center := cell_center(cell)
	var kind := String(marker.get("kind", "damage"))
	if kind == "lethal":
		_skull(center + Vector2(22, -22))
	elif kind == "damage":
		var text := String(marker.get("text", "?"))
		draw_circle(center + Vector2(22, -22), 13.0, Color(0.85, 0.15, 0.15, 0.95))
		draw_string(font, center + Vector2(11, -17), text, HORIZONTAL_ALIGNMENT_CENTER, 22, 14, Color.WHITE)
	elif kind == "text":
		draw_string(font, center + marker.get("offset", Vector2(-30, -24)), String(marker.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(marker.get("size", 12)), marker.get("color", UIKit.ACCENT))


func _skull(center: Vector2) -> void:
	draw_circle(center, 12.0, Color(0.95, 0.95, 0.95))
	draw_rect(Rect2(center + Vector2(-8, 6), Vector2(16, 8)), Color(0.95, 0.95, 0.95))
	draw_circle(center + Vector2(-4.5, -1), 2.8, Color(0.1, 0.1, 0.12))
	draw_circle(center + Vector2(4.5, -1), 2.8, Color(0.1, 0.1, 0.12))
	draw_line(center + Vector2(0, 3), center + Vector2(0, 7), Color(0.1, 0.1, 0.12), 1.5)
