extends SceneTree
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	root.size = Vector2i(1280,720)
	var material_set = preload("res://sample/unified_materials.gd")
	for terrain_id in TerrainDB.ALL:
		var texture: AtlasTexture = material_set.ground(terrain_id)
		check(texture != null and texture.atlas != null and texture.region.has_area(), "Every actual terrain uses an imported pixel material")
	check(material_set.nest_index({"alive":true,"hp":30,"max_hp":30}) == 11, "Healthy nest has intact artwork")
	check(material_set.nest_index({"alive":true,"hp":15,"max_hp":30}) == 12, "Half-health nest switches to damaged artwork")
	check(material_set.nest_index({"alive":false,"hp":0,"max_hp":30}) == 13, "Destroyed nest switches to ruins")
	var view := BoardView.new()
	root.add_child(view)
	for y in 8:
		for x in 8:
			var cell := Vector2i(x,y)
			for offset in [Vector2.ZERO, Vector2(35,0), Vector2(-35,0), Vector2(0,20), Vector2(0,-20)]:
				check(view.cell_at(BoardView.cell_center(cell) + offset) == cell, "Isometric hit test %s %s" % [cell, offset])
	for point in [Vector2(-1,192),Vector2(897,304),Vector2(448,-1),Vector2(448,640)]:
		check(view.cell_at(point) == Vector2i(-1,-1), "Outside diamond must not select a cell")
	view.queue_free()
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1,2,3]))
	app.run.region_mode = false
	app.run.seed = 20261111
	app.run.offered_floor_themes = ["grass"]
	app.run.choose_floor_theme("grass")
	app.show_preview([1,2,3])
	app.begin_battle([1,2,3], app.current_screen.map)
	var screen = app.current_screen
	screen.battle_notice.finish_all()
	screen.speech_layer.set_suppressed(true)
	await process_frame
	await process_frame
	screen.playback.finish_all()
	screen.battle_notice.finish_all()
	var state = screen._display_state()
	check(screen.size == Vector2(1280,720), "Interaction tests run in actual 16:9 game viewport")
	check(not screen.objective_panel.visible, "Long objective panel replaced by round summary")
	check(screen.round_summary.position.x > 900 and screen.round_summary.position.y < 30, "Round and phase occupy top-right")
	check(screen.compact_toolbar.get_child_count() == 3, "Menu speed and retreat share one compact toolbar")
	check(screen.menu_button.position.y == screen.speed_button.position.y and screen.speed_button.position.y == screen.leave_node_button.position.y, "Toolbar controls stay on one row")
	check(screen.team_panel.get_global_rect().end.y <= screen.unit_panel.global_position.y - 4, "Portrait rail leaves clear space for unit details")
	check(screen.unit_body.get_parent() is ScrollContainer, "Status-rich unit details have their own scroll area")
	var projection = preload("res://sample/iso_projection.gd")
	var board_polygon := PackedVector2Array()
	for grid in [Vector2.ZERO, Vector2(8,0), Vector2(8,8), Vector2(0,8)]:
		var world: Vector2 = screen.board.get_global_transform() * projection.point(grid)
		board_polygon.append(world)
		check(Rect2(Vector2.ZERO, Vector2(1280,720)).has_point(world), "Expanded board vertex stays inside viewport")
		check(Rect2(Vector2.ZERO, Vector2(1280,720)).has_point(world + Vector2(0,45)), "Platform depth and shadow remain inside viewport")
	check(board_polygon[1].x - board_polygon[3].x >= 896, "Board enlarged to 896 pixels wide")
	for panel in [screen.compact_toolbar, screen.team_panel, screen.round_summary, screen.unit_panel, screen.terrain_panel]:
		var rect: Rect2 = panel.get_global_rect()
		var polygon := PackedVector2Array([rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)])
		check(Geometry2D.intersect_polygons(board_polygon, polygon).is_empty(), "Corner HUD does not cover board surface")
	var last_card = screen.team_list.get_child(screen.team_list.get_child_count() - 1)
	check(last_card.get_global_rect().end.y <= screen.team_scroll.get_global_rect().end.y + 1, "All four portrait cards and both bars are visible")
	var speed_before: float = app.battle_playback_speed
	screen.speed_button.pressed.emit()
	check(app.battle_playback_speed != speed_before, "Compact speed button remains functional")
	for member in state.units:
		if member.side != "player": continue
		var card = screen.find_child("TeamPortraitCard_%d" % member.uid, true, false)
		check(card != null and card.get_child_count() == 3, "Portrait card has only portrait and two bars")
		var portrait = card.get_child(0)
		check(portrait is Button and portrait.text.is_empty(), "Portrait has no visible name")
		check(portrait.tooltip_text.contains(member.display_name), "Member identity remains available on hover")
		var health = card.get_child(1)
		check(health.value == member.hp and health.max_value == member.max_hp, "Health bar uses live state")
		check(health.get_child(0).text == "%d/%d" % [member.hp, member.max_hp], "Health value centered as n/n")
		var experience = card.get_child(2)
		check(experience.get_child(0).text.contains("/"), "Experience displays only fraction")
	var second = screen.find_child("SelectPortrait_2", true, false)
	second.pressed.emit()
	check(screen.selected_uid == 2, "Portrait button selects its actual unit")
	check(screen.unit_panel.visible, "Selected-unit details restored below compact portrait rail")
	var unit = screen.state.unit_by_uid(1)
	var origin: Vector2i = unit.cell
	screen.select_unit(1)
	var options: Dictionary = screen.state.move_options(unit)
	check(not options.is_empty(), "Test scenario offers movement")
	if not options.is_empty():
		var target: Vector2i = options.keys()[0]
		screen._on_move_pressed()
		check(screen.board.movement_cells.has(target), "Projected movement overlay contains actual target")
		var click := InputEventMouseButton.new()
		click.position = BoardView.cell_center(target)
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		screen.board._gui_input(click)
		check(unit.cell == target, "Mouse click on projected diamond performs actual movement")
		screen.playback.finish_all()
		screen.battle_notice.finish_all()
		screen.do_undo()
		check(unit.cell == origin, "Undo restores logical grid position")
	screen.playback.finish_all()
	screen.battle_notice.finish_all()
	screen.select_unit(1)
	screen._on_choose_skill_pressed()
	var action_rect: Rect2 = screen.action_panel.get_global_rect()
	var action_polygon := PackedVector2Array([action_rect.position, Vector2(action_rect.end.x,action_rect.position.y), action_rect.end, Vector2(action_rect.position.x,action_rect.end.y)])
	var selected_center: Vector2 = screen.board.get_global_transform() * BoardView.cell_center(unit.cell)
	check(action_rect.position.x >= selected_center.x + 40, "Action popup opens immediately right of selected unit")
	check(Rect2(Vector2.ZERO, Vector2(1280,720)).encloses(action_rect), "Context action popup stays inside viewport")
	var saved_cell: Vector2i = unit.cell
	for edge_cell in [Vector2i(0,0), Vector2i(7,0), Vector2i(7,7), Vector2i(0,7)]:
		unit.cell = edge_cell
		screen._position_action_panel()
		var popup: Rect2 = screen.action_panel.get_global_rect()
		var anchor: Vector2 = screen.board.get_global_transform() * BoardView.cell_center(edge_cell)
		check(Rect2(Vector2.ZERO, Vector2(1280,720)).encloses(popup), "Popup remains in viewport at every board corner %s rect=%s screen=%s" % [edge_cell, popup, screen.size])
		if anchor.x + 48 + popup.size.x <= 1264:
			check(popup.position.x >= anchor.x + 40, "Popup prefers unit right when room exists")
		else:
			check(popup.end.x <= anchor.x - 40, "Popup flips left at right screen boundary")
	unit.cell = saved_cell
	screen._position_action_panel()
	check(screen.find_child("SkillButton_fire_burst", true, false) != null, "Actual skill action remains connected")
	var skill := String(unit.skills[0])
	screen._on_skill_pressed(skill)
	check(screen.aim_skill == skill, "Skill enters targeting state on isometric board")
	check(not screen.board.attack_cells.is_empty(), "Skill target range projected from live state")
	if not screen.board.attack_cells.is_empty():
		var target: Vector2i = screen.board.attack_cells[0]
		var click := InputEventMouseButton.new()
		click.position = BoardView.cell_center(target)
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		screen.board._gui_input(click)
		check(unit.skill_used or not screen.state.pending_casts.is_empty(), "Clicking projected skill target consumes action or starts channel")
		screen.playback.finish_all()
	app.queue_free()
	await process_frame
	print("ISO_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
