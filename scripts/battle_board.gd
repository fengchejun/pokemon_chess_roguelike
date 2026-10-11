class_name BattleBoard
extends "res://scripts/board_grid.gd"

signal cell_pressed(cell: Vector2i)
signal directed_skill_pressed(cell: Vector2i)

const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const ALLY_COLOR := Color("#357eb5")
const TRAINER_COLOR := Color("#214c97")
const ENEMY_COLOR := Color("#bb4d52")
const MOVE_HIGHLIGHT := Color("#70d8a0", 0.45)
const SELECT_COLOR := Color("#ffe18a")
const FRAGILE_COLOR := Color("#9b7858", 0.78)
const COLLAPSED_COLOR := Color("#3c2639", 0.96)
const COLLAPSE_PREVIEW_COLOR := Color("#ff714c", 0.96)
const PUSH_COLOR := Color("#f3bb55", 0.50)
const ROUTE_COLOR := Color("#ffe18a", 0.55)
const SKILL_COLOR := Color("#cfb97b", 0.45)
const RAIN_PREVIEW_COLOR := Color("#65bde8", 0.68)
const SKILL_RANGE_FILL := Color("#f5c96b", 0.24)
const ENEMY_MOVE_RANGE_COLOR := Color("#ef6476", 0.85)
const ENEMY_MOVE_RANGE_FILL := Color("#ef6476", 0.16)
const WATER_COLOR := Color("#3d8fb3", 0.72)
const DEEP_WATER_COLOR := Color("#17446e", 0.95)
const GRASS_COLOR := Color("#5a9a54", 0.80)
const NEST_COLOR := Color("#8d477e", 0.95)
const REWARD_COLOR := Color("#f6d76c", 0.95)
const ROCK_COLOR := Color("#636e70", 0.9)
const PLANT_COLOR := Color("#327b4e", 0.88)
const STEAM_COLOR := Color("#dce5e6", 0.66)
const BURN_COLOR := Color("#df7836", 0.72)
const BURN_RANGE_COLOR := Color("#df7836", 0.22)

var battle_state: BattleState
var selected_unit_id: String = ""
var inspected_enemy_id: String = ""
var action_mode: String = "move"
var hover_cell: Vector2i = Vector2i(-1, -1)

signal cell_hovered(cell: Vector2i)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell: Vector2i = get_cell_at(event.position)
		if GridSpec.is_inside(cell):
			if event.shift_pressed and action_mode in ["skill:rock_create", "skill:rain_call"]:
				directed_skill_pressed.emit(cell)
			else:
				cell_pressed.emit(cell)
			accept_event()
	elif event is InputEventMouseMotion:
		var cell: Vector2i = get_cell_at(event.position)
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()


func _draw() -> void:
	super._draw()
	if battle_state == null:
		return
	for y in GridSpec.HEIGHT:
		for x in GridSpec.WIDTH:
			var cell := Vector2i(x, y)
			if battle_state.terrain.is_deep_water(cell):
				_draw_highlight(cell, DEEP_WATER_COLOR)
			elif battle_state.terrain.is_water(cell):
				_draw_highlight(cell, WATER_COLOR)
			elif battle_state.terrain.ground_at(cell) == "grass":
				_draw_highlight(cell, GRASS_COLOR)
			elif battle_state.terrain.is_fragile(cell):
				_draw_highlight(cell, FRAGILE_COLOR)
			elif battle_state.terrain.is_collapsed(cell):
				_draw_highlight(cell, COLLAPSED_COLOR)
			var object: Dictionary = battle_state.terrain.object_at(cell)
			if not object.is_empty():
				_draw_highlight(cell, ROCK_COLOR if object["type"] == "rock" else BURN_COLOR if object.get("burning", false) else PLANT_COLOR)
			if battle_state.terrain.is_steam(cell):
				_draw_highlight(cell, STEAM_COLOR)
	for burning_cell in battle_state.terrain.burning.keys():
		_draw_highlight(burning_cell, BURN_COLOR)
	if not battle_state.nest.is_empty() and int(battle_state.nest.get("hp", 0)) > 0:
		_draw_highlight(battle_state.nest["cell"], NEST_COLOR)
		draw_rect(get_cell_rect(battle_state.nest["exit"]).grow(-9.0), NEST_COLOR, false, 3.0)
	if battle_state.reward_state == "ground":
		var reward_rect: Rect2 = get_cell_rect(battle_state.reward_cell).grow(-20.0)
		draw_rect(reward_rect, REWARD_COLOR)
	var selected: CombatUnit = battle_state.unit_by_id(selected_unit_id)
	if selected != null and selected.is_alive() and battle_state.phase == "player":
		for y in GridSpec.HEIGHT:
			for x in GridSpec.WIDTH:
				var cell := Vector2i(x, y)
				if action_mode == "capture" and battle_state.can_capture(battle_state.unit_at(cell)):
					draw_rect(get_cell_rect(cell).grow(-5.0), SELECT_COLOR, false, 3.0)
				elif action_mode.begins_with("skill:") and battle_state.can_use_skill(selected, action_mode.trim_prefix("skill:"), cell):
					draw_rect(get_cell_rect(cell).grow(-4.0), SKILL_RANGE_FILL)
					draw_rect(get_cell_rect(cell).grow(-5.0), SKILL_COLOR, false, 3.0)
				elif action_mode == "move" and battle_state.can_player_move(selected, cell):
					draw_rect(get_cell_rect(cell).grow(-5.0), MOVE_HIGHLIGHT)
		var route: Array[Vector2i] = []
		if action_mode == "move":
			route = battle_state.get_move_path(selected, hover_cell)
		if not route.is_empty():
			var last_center: Vector2 = get_cell_rect(selected.cell).get_center()
			for route_cell in route:
				var route_center: Vector2 = get_cell_rect(route_cell).get_center()
				draw_line(last_center, route_center, ROUTE_COLOR, 4.0)
				draw_rect(get_cell_rect(route_cell).grow(-8.0), ROUTE_COLOR, false, 3.0)
				last_center = route_center
		if action_mode == "skill:rock_push":
			var hovered: CombatUnit = battle_state.unit_at(hover_cell)
			var preview: Dictionary = battle_state.preview_skill_push(selected, action_mode.trim_prefix("skill:"), hover_cell) if hovered != null else {}
			if not preview.is_empty():
				var landing_cell: Vector2i = preview["destination"]
				if landing_cell != hovered.cell:
					_draw_highlight(landing_cell, PUSH_COLOR)
		elif action_mode.begins_with("skill:") and battle_state.can_use_skill(selected, action_mode.trim_prefix("skill:"), hover_cell):
			var skill_id: String = action_mode.trim_prefix("skill:")
			var impact: Vector2i = battle_state.projected_skill_impact(selected, skill_id, hover_cell)
			for cell in EnvironmentResolver.skill_area(battle_state, skill_id, impact, selected.cell):
				_draw_highlight(cell, RAIN_PREVIEW_COLOR if skill_id == "rain_call" else SKILL_COLOR)
				if skill_id == "rain_call":
					draw_rect(get_cell_rect(cell).grow(-6.0), WATER_COLOR, false, 3.0)
				if (skill_id in ["rock_create", "fire_burst"] or skill_id == "rock_break" and selected.upgraded_skill_id == "rock_break") and battle_state.terrain.is_fragile(cell):
					_draw_collapse_preview(cell)
			if skill_id == "flame_charge":
				draw_line(get_cell_rect(selected.cell).get_center(), get_cell_rect(impact).get_center(), ROUTE_COLOR, 5.0)
				if battle_state.terrain.is_deep_water(impact) or battle_state.terrain.is_collapsed(impact):
					_draw_collapse_preview(impact)
			if skill_id == "water_flow" and (not battle_state.terrain.object_at(impact).is_empty() or battle_state.is_nest_at(impact)):
				var delta: Vector2i = impact - selected.cell
				var water_cell: Vector2i = impact - Vector2i(signi(delta.x), signi(delta.y))
				_draw_highlight(water_cell, WATER_COLOR)
			if skill_id == "water_flow":
				var push_result: Dictionary = battle_state.preview_skill_push(selected, skill_id, hover_cell)
				if not push_result.is_empty() and push_result["destination"] != impact:
					_draw_highlight(push_result["destination"], PUSH_COLOR)
			if impact != hover_cell:
				draw_rect(get_cell_rect(impact).grow(-4.0), SELECT_COLOR, false, 3.0)
	var inspected_enemy: CombatUnit = battle_state.unit_by_id(inspected_enemy_id)
	if inspected_enemy != null and inspected_enemy.is_alive():
		for cell in battle_state.enemy_move_cells(inspected_enemy):
			draw_rect(get_cell_rect(cell).grow(-7.0), ENEMY_MOVE_RANGE_FILL)
			draw_rect(get_cell_rect(cell).grow(-8.0), ENEMY_MOVE_RANGE_COLOR, false, 3.0)
	for y in GridSpec.HEIGHT:
		for x in GridSpec.WIDTH:
			var cell := Vector2i(x, y)
			var cell_rect: Rect2 = get_cell_rect(cell)
			var marker := ""
			if battle_state.is_nest_at(cell):
				marker = "巢!" if battle_state.nest_spawn_notice() != "" else "巢%d" % battle_state.nest["hp"]
			elif battle_state.terrain.is_burning(cell):
				marker = "燃"
			elif battle_state.terrain.is_steam(cell):
				marker = "雾%d" % battle_state.terrain.steam[cell]
			elif not battle_state.terrain.object_at(cell).is_empty():
				var object: Dictionary = battle_state.terrain.object_at(cell)
				if object.get("burning", false):
					marker = "燃%d" % object["burn_turns"]
				elif object.has("expire_after_enemy_round"):
					marker = "岩%d" % maxi(1, int(object["expire_after_enemy_round"]) - battle_state.turn_number + 1)
				else:
					marker = "岩" if object["type"] == "rock" else "木"
			elif battle_state.terrain.is_fragile(cell):
				marker = "裂"
			elif battle_state.terrain.is_collapsed(cell):
				marker = "坑"
			elif battle_state.terrain.is_deep_water(cell):
				marker = "深"
			elif battle_state.terrain.is_shallow_water(cell):
				marker = "浅"
			elif battle_state.terrain.ground_at(cell) == "grass":
				marker = "草"
			if marker != "":
				draw_string(ThemeDB.fallback_font, cell_rect.position + Vector2(5, 18), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	for unit in battle_state.units:
		if not unit.is_alive():
			continue
		_draw_unit(unit)


func _draw_highlight(cell: Vector2i, color: Color) -> void:
	draw_rect(get_cell_rect(cell).grow(-3.0), color)


func _draw_collapse_preview(cell: Vector2i) -> void:
	draw_rect(get_cell_rect(cell).grow(-5.0), COLLAPSE_PREVIEW_COLOR, false, 4.0)


func _draw_unit(unit: CombatUnit) -> void:
	var cell_rect: Rect2 = get_cell_rect(unit.cell)
	var center: Vector2 = cell_rect.get_center()
	var radius: float = cell_rect.size.x * 0.32
	var unit_color: Color = ENEMY_COLOR if unit.team == "enemy" else TRAINER_COLOR if unit.unit_id == "trainer" else ALLY_COLOR
	draw_circle(center, radius, unit_color)
	if unit.burned:
		draw_arc(center, radius + 6.0, 0.0, TAU, 32, BURN_COLOR, 3.0)
	if unit.wet:
		draw_circle(center + Vector2(-radius * 0.8, -radius * 0.8), 5.0, WATER_COLOR)
	if unit.battle_buff != "":
		draw_circle(center + Vector2(radius * 0.8, -radius * 0.8), 6.0, REWARD_COLOR)
	if unit.unit_id == selected_unit_id:
		draw_arc(center, radius + 3.0, 0.0, TAU, 48, SELECT_COLOR, 3.0)
	elif unit.unit_id == inspected_enemy_id:
		draw_arc(center, radius + 3.0, 0.0, TAU, 48, ENEMY_MOVE_RANGE_COLOR, 3.0)
	var font: Font = ThemeDB.fallback_font
	var font_size := 20
	var text_size: Vector2 = font.get_string_size(unit.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x / 2.0, font.get_ascent(font_size) / 3.0), unit.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	var bar_rect := Rect2(cell_rect.position + Vector2(8, cell_rect.size.y - 10), Vector2(cell_rect.size.x - 16, 5))
	draw_rect(bar_rect, Color("#29302c"))
	var health_ratio: float = clampf(float(unit.hp) / float(unit.max_hp), 0.0, 1.0)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y)), Color("#f3d779") if unit.team == "enemy" else Color("#8ee0b7"))
