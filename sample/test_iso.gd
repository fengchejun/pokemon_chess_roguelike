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
	var view := BoardView.new()
	root.add_child(view)
	for y in 8:
		for x in 8:
			var cell := Vector2i(x,y)
			for offset in [Vector2.ZERO, Vector2(35,0), Vector2(-35,0), Vector2(0,20), Vector2(0,-20)]:
				check(view.cell_at(BoardView.cell_center(cell) + offset) == cell, "Isometric hit test %s %s" % [cell, offset])
	for point in [Vector2(-1,192),Vector2(641,192),Vector2(320,-1),Vector2(320,460)]:
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
	check(not screen.objective_panel.visible, "Long objective panel replaced by round summary")
	check(screen.round_summary.position.x > 900 and screen.round_summary.position.y < 30, "Round and phase occupy top-right")
	check(screen.compact_toolbar.get_child_count() == 3, "Menu speed and retreat share one compact toolbar")
	check(screen.menu_button.position.y == screen.speed_button.position.y and screen.speed_button.position.y == screen.leave_node_button.position.y, "Toolbar controls stay on one row")
	check(screen.team_panel.get_global_rect().end.y <= screen.unit_panel.global_position.y - 4, "Portrait rail leaves clear space for unit details")
	check(screen.unit_body.get_parent() is ScrollContainer, "Status-rich unit details have their own scroll area")
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
