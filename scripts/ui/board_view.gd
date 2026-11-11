class_name BoardView
extends Control

signal cell_clicked(cell: Vector2i)
signal cell_right_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const TILE := 72.0
const Materials = preload("res://sample/unified_materials.gd")
const Iso = preload("res://sample/iso_projection.gd")
const SampleArt = preload("res://sample/pixel_art.gd")

var biome := "rock" # Presentation only; terrain mechanics remain in TerrainDB.
var terrain: Array = []
var obstacle_durability: Dictionary = {}
var electric_flowers: Dictionary = {}
var burning_cells: Dictionary = {}
var steam_cells: Dictionary = {}
var vine_origin: Dictionary = {}
var vine_expire_round: Dictionary = {}
var nest: Dictionary = {}
var extra_nests: Array = []
var pending_casts: Array = []
var nest_guard_counts: Dictionary = {}
var storm_strikes: Array = []
var battle_round: int = 0
var reward: Dictionary = {}
var extra_rewards: Array = []
var chests: Dictionary = {}
var fruits: Array = []
var food_cells: Array = []
var mentor_cell := Vector2i(-1, -1)
var merchant_cell := Vector2i(-1, -1)
var units: Array = []
var deploy_cells: Array = []
var extraction_cells: Array = []
var capture_exits: Array = []
var ice_slides: Array = []

var camp_facilities: Dictionary = {}
var show_movement_costs := true
var movement_cells: Dictionary = {}
var enemy_cells_view: Array = []
var attack_cells: Array = []
var area_cells: Array = []
var ray_cells: Array = []
var path_cells: Array = []
var markers: Array = []
var arrows: Array = []
var badges: Array = []

var presentation_offsets: Dictionary = {} # 只用于展示位移与回弹，不改变单位格子。
var selected_uid: int = -1
var hover_cell := Vector2i(-1, -1)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(896, 654)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_from_state(state: BattleState) -> void:
	if state == null:
		return
	var screen := get_parent()
	if screen != null:
		for property in screen.get_property_list():
			if property["name"] == "app":
				var application = screen.get("app")
				if application != null and application.run != null:
					biome = application.run.current_theme()
				break
	camp_facilities = state.camp_facilities.duplicate(true)
	terrain = state.terrain.duplicate()
	extraction_cells = state.extraction_cells.duplicate() if state.uses_extraction() else []
	capture_exits = state.capture_exits.duplicate()
	obstacle_durability = state.obstacle_durability.duplicate()
	electric_flowers = state.electric_flowers.duplicate()
	burning_cells = state.burning_cells.duplicate()
	steam_cells = state.steam_cells.duplicate()
	vine_origin = state.vine_origin.duplicate()
	vine_expire_round = state.vine_expire_round.duplicate()
	nest_guard_counts.clear()
	for current in state.all_nests():
		nest_guard_counts[current["cell"]] = state.nest_guard_charges(current["cell"])
	nest = state.nest.duplicate(true)
	extra_nests = state.extra_nests.duplicate(true)
	pending_casts = state.pending_casts.duplicate(true)
	storm_strikes = state.storm_strikes.duplicate(true)
	battle_round = state.round
	reward = state.reward.duplicate(true)
	extra_rewards = state.extra_rewards.duplicate(true)
	chests = state.chests.duplicate()
	fruits = []
	food_cells = state.food_cells.duplicate()
	mentor_cell = state.mentor.get("cell", Vector2i(-1, -1))
	merchant_cell = state.merchant.get("cell", Vector2i(-1, -1)) if state.node_kind == "event" else Vector2i(-1, -1)
	units = []
	for unit in state.units:
		units.append(unit.dup())
	deploy_cells = state.deploy_cells.duplicate()
	ice_slides = []
	if not state.ended:
		for unit in state.units:
			var slide := state.ice_slide_outcome(unit)
			if not slide.is_empty():
				ice_slides.append(slide)
	queue_redraw()


func set_map_preview(map: Dictionary, preview_units: Array = []) -> void:
	biome = String(map.get("theme_id", "rock"))
	camp_facilities = map.get("camp_facilities", {}).duplicate(true)
	extraction_cells = map.get("extraction_cells", []).duplicate()
	capture_exits = map.get("capture_exits", []).duplicate()
	nest_guard_counts.clear()
	storm_strikes = map.get("storm_strikes", []).duplicate(true)
	terrain = (map.get("terrain", []) as Array).duplicate()
	obstacle_durability = {}
	burning_cells = {}
	steam_cells = map.get("steam_cells", {}).duplicate()
	vine_origin = {}
	vine_expire_round = {}
	for cell in map.get("obstacle_cells", []):
		obstacle_durability[cell] = Balance.TREE_DURABILITY if terrain[GridSpec.index(cell)] == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
	electric_flowers = map.get("electric_flowers", {}).duplicate()
	for cell in electric_flowers:
		obstacle_durability[cell] = 2 if TerrainDB.is_grass(terrain[GridSpec.index(cell)]) else 1
	obstacle_durability.merge(map.get("obstacle_durability", {}), true)
	nest = {
		"cell": map.get("nest_cell", Vector2i(-1, -1)),
		"exits": [],
		"hp": int(map.get("nest_hp", map.get("nest_max_hp", Balance.NEST_BASE_HP))),
		"max_hp": int(map.get("nest_max_hp", Balance.NEST_BASE_HP)),
		"alive": bool(map.get("nest_alive", true)),
	}
	extra_nests = []
	if map.has("nests"):
		var stored: Array = map["nests"]
		nest = stored[0].duplicate(true) if not stored.is_empty() else {}
		extra_nests = stored.slice(1).duplicate(true)
	else:
		for cell in map.get("nest_cells", [nest["cell"]]):
			if cell != nest["cell"]:
				var other := nest.duplicate(true)
				other["cell"] = cell
				extra_nests.append(other)
	pending_casts = []
	battle_round = 0
	extra_rewards = map.get("extra_rewards", []).duplicate(true)
	chests = map.get("chests", {}).duplicate()
	reward = map.get("reward", {"state": "map", "cell": map.get("reward_cell", Vector2i(-1, -1)), "owner_uid": -1}).duplicate(true)
	fruits = []
	food_cells = map.get("food_cells", []).duplicate()
	mentor_cell = map.get("mentor_cell", Vector2i(-1, -1))
	merchant_cell = map.get("merchant_cell", Vector2i(-1, -1))
	units = preview_units
	deploy_cells = map.get("deploy_area", Balance.DEPLOY_AREA).duplicate()
	ice_slides = []
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
	var grid := Iso.inverse(position)
	var cell := Vector2i(floori(grid.x), floori(grid.y))
	return cell if GridSpec.is_inside(cell) else Vector2i(-1,-1)

static func cell_center(cell: Vector2i) -> Vector2:
	return Iso.point(Vector2(cell) + Vector2.ONE * 0.5)

static func project_point(cartesian: Vector2) -> Vector2:
	return Iso.point(cartesian / TILE)

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
	if terrain.size() < 64: return
	var font := UIKit.font()
	var depth := Vector2(0, 30)
	var corners := PackedVector2Array([Iso.point(Vector2.ZERO), Iso.point(Vector2(8, 0)), Iso.point(Vector2(8, 8)), Iso.point(Vector2(0, 8))])
	var shadow := PackedVector2Array()
	for p in corners: shadow.append(p + Vector2(0, 45))
	draw_colored_polygon(shadow, Color(0.02, 0.02, 0.03, 0.65))
	for index in 8:
		var left := Iso.point(Vector2(0, index))
		var left_end := Iso.point(Vector2(0, index + 1))
		var front := Iso.point(Vector2(index, 8))
		var front_end := Iso.point(Vector2(index + 1, 8))
		var right := Iso.point(Vector2(8, index))
		var right_end := Iso.point(Vector2(8, index + 1))
		for edge in [[front, front_end, Color("363641")], [right, right_end, Color("242631")]]:
			var face := PackedVector2Array([edge[0], edge[1], edge[1] + depth, edge[0] + depth])
			draw_colored_polygon(face, edge[2])
			draw_line(edge[0] + depth, edge[1] + depth, Color("11111b"), 2)
			draw_line(edge[0], edge[0] + depth, Color("171821"), 1)
	for sum in 15:
		for x in 8:
			var y := sum - x
			if y < 0 or y > 7: continue
			var cell := Vector2i(x, y)
			var value: int = terrain[GridSpec.index(cell)]
			_draw_clean_ground(cell, value)
	for cell in extraction_cells: _draw_fill(cell, Color(0.2, 0.85, 0.65, 0.2))
	for cell in deploy_cells: _iso_outline(cell, Color("75bda1"), 1)
	for cell in capture_exits: _draw_fill(cell, Color(1, 0.6, 0.2, 0.3))
	for cell in movement_cells: _draw_fill(cell, Color(0.35, 0.75, 0.9, 0.38))
	for cell in enemy_cells_view: _draw_fill(cell, Color(1, 0.3, 0.3, 0.28))
	for cell in area_cells: _draw_fill(cell, Color(1, 0.6, 0.2, 0.35))
	for cell in attack_cells:
		_draw_fill(cell, Color(1, 0.85, 0.4, 0.35))
		_iso_outline(cell, Color("f9e2af"), 2)
	for path in [path_cells, ray_cells]:
		var points := PackedVector2Array()
		for cell in path: points.append(cell_center(cell))
		if points.size() > 1: draw_polyline(points, Color("f9e2af"), 3)
	for strike in storm_strikes:
		_draw_fill(strike["cell"], Color(1, 0.5, 0.1, 0.4))
		_iso_outline(strike["cell"], Color("f9e2af"), 2)
	for cast in pending_casts:
		for cell in cast.get("cells", []): _iso_outline(cell, Color("cba6f7"), 2)
	for cell in vine_expire_round: _iso_outline(cell, Color("cba6f7"), 2)
	# All upright objects and actors share the same ground-depth order.
	for sum in 15:
		for x in 8:
			var y := sum - x
			if y < 0 or y > 7: continue
			var cell := Vector2i(x, y)
			var center := cell_center(cell)
			var value: int = terrain[GridSpec.index(cell)]
			var actors := units.filter(func(u): return u.is_on_board() and u.cell == cell)
			var obstacle_rect := Rect2(center + Vector2(-56, -95), Vector2(112, 112)) if value == TerrainDB.TREE else Rect2(center + Vector2(-52, -66), Vector2(104, 96))
			var obscures := units.any(func(u): return u.is_on_board() and u.cell.x + u.cell.y < x + y and obstacle_rect.intersects(Rect2(cell_center(u.cell) + Vector2(-40,-60), Vector2(80,86))))
			var tint := Color(1, 1, 1, 0.5 if obscures else 1.0)
			if value == TerrainDB.ROCK_MOUNTAIN:
				draw_texture_rect(Materials.tile(9), Rect2(center + Vector2(-55,-94), Vector2(110,120)), false, tint)
			elif value in [TerrainDB.TREE, TerrainDB.OBSTACLE]:
				draw_texture_rect(SampleArt.tile(12 if value == TerrainDB.TREE else 13), obstacle_rect, false, tint)
			if value == TerrainDB.BLUE_FIRE:
				draw_texture_rect(Materials.tile(10), Rect2(center + Vector2(-27,-46), Vector2(54,54)), false)
			elif burning_cells.has(cell):
				draw_texture_rect(SampleArt.tile(10), Rect2(center + Vector2(-21, -37), Vector2(42, 42)), false, Color(0.55, 0.7, 1) if value == TerrainDB.BLUE_FIRE else Color.WHITE)
			if chests.has(cell): draw_texture_rect(SampleArt.tile(14), Rect2(center + Vector2(-24,-30), Vector2(48,48)), false)
			for current in [nest] + extra_nests:
				if current.get("cell", Vector2i(-1,-1)) == cell: _draw_nest_object(font, current)
			for point in [reward] + extra_rewards:
				if point.get("cell", Vector2i(-1,-1)) == cell and point.get("state") in ["map", "guarding"]: _draw_star(cell)
			if cell in food_cells: draw_texture_rect(SampleArt.tile(8), Rect2(center + Vector2(-14,-23), Vector2(28,28)), false)
			if electric_flowers.has(cell):
				draw_circle(center + Vector2(0,-10), 10, Color("f9e2af"))
				draw_string(font, center + Vector2(-7,-5), "电", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("313244"))
			if value == TerrainDB.GRASS and actors.is_empty(): Materials.draw_grass(self,center)
			for unit in actors: _draw_unit(font, unit)
	for arrow in arrows: _draw_arrow(arrow)
	for marker in markers: _draw_marker(font, marker)
	for badge in badges:
		if GridSpec.is_inside(badge.get("cell", Vector2i(-1,-1))): draw_string(font, cell_center(badge["cell"]) + Vector2(-25,-27), String(badge.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.ACCENT)
	if GridSpec.is_inside(hover_cell): _iso_outline(hover_cell, Color.WHITE, 2)

func _draw_clean_ground(cell: Vector2i, value: int) -> void:
	var shape := Iso.diamond(cell)
	Materials.paint(self, Materials.surface(shape,value), value, biome)
	if Materials.is_liquid(value): Materials.draw_banks(self,shape,Materials.bank_edges(terrain,cell),biome)

func _surface_shape(cell: Vector2i) -> PackedVector2Array:
	return Materials.surface(Iso.diamond(cell),terrain[GridSpec.index(cell)])

func _iso_outline(cell: Vector2i, color: Color, width: float) -> void:
	if not GridSpec.is_inside(cell): return
	var p := _surface_shape(cell)
	draw_polyline(p + PackedVector2Array([p[0]]), color, width)


func _draw_fill(cell: Vector2i, color: Color) -> void:
	if not GridSpec.is_inside(cell):
		return
	draw_colored_polygon(_surface_shape(cell), color)


func _draw_terrain(rect: Rect2, value: int) -> void:
	var tile := SampleArt.terrain_index(value)
	if tile >= 0:
		draw_texture_rect(SampleArt.tile(tile), rect, false, Color(0.83, 0.83, 0.86))
		if value in [TerrainDB.TREE, TerrainDB.OBSTACLE]:
			draw_texture_rect(SampleArt.tile(12 if value == TerrainDB.TREE else 13), rect.grow(-3), false)
		draw_rect(rect, Color(0.08, 0.1, 0.13, 0.24), false, 1)
		return
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
		TerrainDB.BLUE_FIRE:
			var base := rect.position + Vector2(36, 50)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-16, -4), base + Vector2(-11, -19), base + Vector2(-3, -15), base + Vector2(4, -34), base + Vector2(16, -12), base + Vector2(12, 2), base + Vector2(-6, 6)]), Color("46a7f3"))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 2), base + Vector2(1, -15), base + Vector2(8, -5), base + Vector2(5, 3)]), Color("c0efff"))
		TerrainDB.SHALLOW_GRASS:
			for offset in [16, 36, 56]:
				var tuft := rect.position + Vector2(offset, 48)
				draw_line(tuft, tuft + Vector2(-4, -6), Color("527646"), 2)
				draw_line(tuft, tuft + Vector2(4, -8), Color("527646"), 2)
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
		TerrainDB.ROCK_MOUNTAIN:
			var origin := rect.position
			draw_colored_polygon(PackedVector2Array([origin + Vector2(6, 60), origin + Vector2(26, 28), origin + Vector2(35, 12), origin + Vector2(54, 32), origin + Vector2(66, 60)]), Color("493f3c"))
			draw_colored_polygon(PackedVector2Array([origin + Vector2(6, 60), origin + Vector2(35, 12), origin + Vector2(39, 44), origin + Vector2(31, 60)]), Color("b1a093"))
			draw_string(ThemeDB.fallback_font, origin + Vector2(50, 22), "∞", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffefc7"))
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
	for current in [nest] + extra_nests:
		_draw_nest_object(font, current)
	if GridSpec.is_inside(mentor_cell):
		var center := cell_center(mentor_cell)
		draw_circle(center, 22, Color("4b7988"))
		draw_string(font, center + Vector2(-16, 7), "师", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("ffe6a8"))
	for point in [reward] + extra_rewards:
		if point.get("state") in ["map", "guarding"]:
			_draw_star(point["cell"])
	for cell in chests:
		var center := cell_center(cell)
		draw_rect(Rect2(center - Vector2(22, 16), Vector2(44, 32)), Color("a66d32"))
		draw_rect(Rect2(center - Vector2(22, 16), Vector2(44, 32)), Color("f4cf78"), false, 3)
		draw_line(center - Vector2(22, 5), center + Vector2(22, -5), Color("f4cf78"), 2)
		draw_rect(Rect2(center - Vector2(3, 7), Vector2(6, 13)), Color("ffe39a"))
	for food_cell in food_cells:
		var center := cell_center(food_cell)
		draw_rect(Rect2(center - Vector2(12, 12), Vector2(24, 24)), Color("b58c4b"))
		draw_string(UIKit.font(), center + Vector2(-10, 7), "粮", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw_nest_status(font: Font) -> void:
	for current in [nest] + extra_nests:
		_draw_one_nest_status(font, current)

func _draw_one_nest_status(font: Font, nest: Dictionary) -> void:
	if not bool(nest.get("alive", false)):
		return
	var cell: Vector2i = nest["cell"]
	var color := Color(1.0, 0.72, 0.32) if int(nest_guard_counts.get(cell, 0)) > 0 else Color(0.75, 0.58, 1.0)
	var rect := Rect2(Vector2(cell) * TILE + Vector2(3, 3), Vector2.ONE * (TILE - 6))
	draw_rect(rect, color, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(62, 17)), Color(0.08, 0.10, 0.13, 0.92))
	draw_string(font, rect.position + Vector2(2, 13), "巢%d%s" % [int(nest.get("hp", 0)), "·护%d" % int(nest_guard_counts.get(cell, 0)) if int(nest_guard_counts.get(cell, 0)) > 0 else "·首领" if bool(nest.get("boss_sheltered", false)) else "·待产" if int(nest.get("pending_waves", 0)) > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_pending_casts(font: Font) -> void:
	var marked := {}
	var labels := {}
	for cast in pending_casts:
		var color := Color(0.35, 0.88, 1.0) if String(cast["side"]) == "player" else Color(1.0, 0.32, 0.32)
		var is_heal := String(cast["skill_id"]) == "herbal_heal"
		if is_heal:
			color = Color(0.4, 1.0, 0.5)
		var is_tsunami := String(cast["skill_id"]) == "tsunami"
		var first_cell: Vector2i = cast["cells"][0] if not cast["cells"].is_empty() else Vector2i(-1, -1)
		for center in cast["cells"]:
			var cells: Array = [center]
			if is_heal:
				cells = SkillResolver.support_area(center, 2, false)
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
				if not is_tsunami or cell == first_cell:
					labels[cell] = "治疗" if is_heal else "海啸" if is_tsunami else ""
		var caster: CombatUnit = null
		for unit in units:
			if unit.uid == int(cast["uid"]) and unit.is_alive():
				caster = unit
				break
		if caster != null:
			draw_string(font, cell_center(caster.cell) + Vector2(15, 30), "吟", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	for cell in marked:
		if not labels.has(cell):
			continue
		var count := int(marked[cell])
		var label := String(labels[cell]) if String(labels[cell]) != "" else ("蓄%d" % count if count > 1 else "蓄")
		draw_rect(Rect2(cell.x * TILE + 2, cell.y * TILE + 2, 36 if label in ["海啸", "治疗"] else (32 if count > 1 else 20), 17), Color(0.08, 0.10, 0.13, 0.92))
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
	var center := cell_center(unit.cell) + Vector2(presentation_offsets.get(unit.uid, Vector2.ZERO))
	var body_border := _border_color(unit)
	var ground_value: int = terrain[GridSpec.index(unit.cell)] if terrain.size() == 64 else TerrainDB.PLAIN
	var art_index := SampleArt.unit_index(unit.species_id)
	if art_index >= 0:
		draw_rect(Rect2(center + Vector2(-29, 17), Vector2(58, 8)), Color(0.04, 0.04, 0.07, 0.5))
		draw_texture_rect(SampleArt.tile(art_index), Rect2(center + Vector2(-48, -66), Vector2(96, 96)), false)
	else:
		var radius := 26.0
		var fill := Elements.color_of(unit.element)
		if unit.is_trainer:
			fill = Color(0.72, 0.7, 0.62)
		if unit.is_trainer:
			draw_rect(Rect2(center - Vector2(radius - 3, radius - 3), Vector2((radius - 3) * 2, (radius - 3) * 2)), fill)
			draw_rect(Rect2(center - Vector2(radius - 3, radius - 3), Vector2((radius - 3) * 2, (radius - 3) * 2)), body_border, false, 3.0)
		else:
			draw_circle(center, radius, fill)
			draw_arc(center, radius, 0, TAU, 48, body_border, 3.0)
		draw_string(font, center + Vector2(-14, 10), unit.glyph, HORIZONTAL_ALIGNMENT_CENTER, 28, 26, Color(0.1, 0.1, 0.12))
	# Environment covers the body only; selection, life and statuses stay above it.
	if ground_value == TerrainDB.GRASS: Materials.draw_grass(self,cell_center(unit.cell))
	elif ground_value in [TerrainDB.WATER,TerrainDB.DEEP]:
		Materials.draw_water_cover(self,_surface_shape(unit.cell),center,ground_value,biome)
	if unit.uid == selected_uid:
		if art_index >= 0: draw_rect(Rect2(center+Vector2(-40,-54),Vector2(80,80)),UIKit.ACCENT,false,2)
		else: draw_arc(center,30,0,TAU,48,UIKit.ACCENT,3)
	if unit.is_boss:
		draw_string(font, center + Vector2(-30, -30), "首", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.2))
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
	# 状态徽章
	var badges_text := ""
	if unit.guard_nest.x >= 0 and GridSpec.manhattan(unit.cell, unit.guard_nest) == 1 and not unit.frozen and unit.paralyzed_ticks <= 0:
		badges_text += "护"
	if unit.burn_ticks > 0:
		badges_text += "灼"
	if unit.parasite_source_uid >= 0:
		badges_text += "寄"
	if unit.fire_amp_stacks > 0:
		badges_text += "增"
	if unit.mirror_until_round > 0 and unit.mirror_until_round >= battle_round:
		badges_text += "镜"
	if unit.mountain_form_ticks > 0:
		badges_text += "山"
	if unit.shield_hp > 0:
		badges_text += "盾"
	if unit.root_pending or unit.move_cancelled:
		badges_text += "定"
	if unit.imprison_ticks > 0:
		badges_text += "禁"
	if unit.slow_ticks > 0:
		badges_text += "缓"
	if badges_text != "":
		draw_string(font, center + Vector2(20, -18), badges_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.3))
	if unit.capture_used:
		draw_string(font, center + Vector2(20, 32), "捕", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.9))
	if unit.corrupted:
		draw_arc(center, 30, 0, TAU, 32, Color("7c3fb3"), 3.0)
		draw_string(font, center + Vector2(-28, -19), "黑", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d4a0f3"))
	if unit.reward_carrier:
		draw_string(font, center + Vector2(18, -18), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe17d"))
	if unit.fresh_spawn:
		draw_string(font, center + Vector2(-30, -18), "新", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.8, 0.4))
	if ([reward] + extra_rewards).any(func(point): return point.get("state") == "carried" and int(point.get("owner_uid", -1)) == unit.uid and not bool(point.get("credited", false))):
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


func _draw_ice_slide_arrow(slide: Dictionary) -> void:
	var from: Vector2i = slide["from"]
	var dir := Vector2(slide["direction"])
	var center := cell_center(from)
	var start := center + dir * 27.0
	var tip := center + dir * (32.0 if bool(slide["blocked"]) else 49.0)
	var color := Color(0.64, 0.79, 0.86, 0.95) if bool(slide["blocked"]) else Color(1.0, 0.35, 0.24, 0.98) if bool(slide["lethal"]) else Color(0.12, 0.89, 1.0, 0.98)
	if bool(slide["blocked"]):
		var across := Vector2(-dir.y, dir.x) * 7.0
		draw_line(center + dir * 19.0, tip, Color(0.08, 0.13, 0.18, 0.95), 6.0)
		draw_line(center + dir * 19.0, tip, color, 3.0)
		draw_line(tip - across - dir * 5.0, tip + across - dir * 5.0, Color(0.08, 0.13, 0.18, 0.95), 5.0)
		draw_line(tip - across - dir * 5.0, tip + across - dir * 5.0, color, 2.5)
		return
	draw_line(start, tip, Color(0.05, 0.11, 0.16, 0.95), 7.0)
	draw_line(start, tip, color, 4.0)
	var left := tip - dir.rotated(0.55) * 11.0
	var right := tip - dir.rotated(-0.55) * 11.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)


func _draw_marker(font: Font, marker: Dictionary) -> void:
	var cell: Vector2i = marker.get("cell", Vector2i(-1, -1))
	if not GridSpec.is_inside(cell):
		return
	var center := cell_center(cell)
	var kind := String(marker.get("kind", "damage"))
	if kind == "facility":
		var box := Rect2(center - Vector2(33, 29), Vector2(66, 58))
		draw_rect(box, Color(0.06, 0.09, 0.13, 0.94))
		draw_rect(Rect2(box.position + Vector2(3, 3), box.size - Vector2(6, 6)), marker.get("color", UIKit.ACCENT))
		draw_rect(box, Color(0.94, 0.91, 0.73), false, 2.0)
		var label := String(marker.get("text", ""))
		var font_size := 17 if label.length() >= 3 else 21
		var lines := label.split("\n")
		for index in lines.size():
			var baseline := center.y + font.get_ascent(font_size) * 0.35 + (index - (lines.size() - 1) / 2.0) * 21
			draw_string(font, Vector2(box.position.x + 2, baseline), lines[index], HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 4, font_size, Color.WHITE)
	elif kind == "lethal":
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


func _draw_nest_object(font: Font, nest: Dictionary) -> void:
	if nest.is_empty(): return
	var cell: Vector2i = nest.get("cell", Vector2i(-1,-1))
	if not GridSpec.is_inside(cell): return
	var visual := nest.duplicate()
	visual["guards"] = int(nest_guard_counts.get(cell,0))
	Materials.draw_nest(self,font,cell_center(cell),visual)

func _draw_storm_strikes(font: Font) -> void:
	for strike in storm_strikes:
		var cell: Vector2i = strike["cell"]
		var rect := Rect2(Vector2(cell) * TILE + Vector2(3, 3), Vector2.ONE * (TILE - 6))
		draw_rect(rect, Color(1.0, 0.68, 0.1, 0.12))
		draw_rect(rect, Color("ffbf43"), false, 3.0)
		draw_line(rect.position + Vector2(3, 3), rect.end - Vector2(3, 3), Color(1.0, 0.67, 0.15, 0.4), 2.0)
		draw_line(rect.position + Vector2(rect.size.x - 3, 3), rect.position + Vector2(3, rect.size.y - 3), Color(1.0, 0.67, 0.15, 0.65), 2.0)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 15)), Color("352413"))
		draw_string(font, rect.position + Vector2(2, 12), "轮末雷50%", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffe39b"))
