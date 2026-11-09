extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_camp()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_camp.png")
	app.leave_camp()
	app.enter_region_node("event_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await process_frame
	await process_frame
	var gathering = app.current_screen
	for unit in gathering.state.alive_units("player"):
		var options: Dictionary = gathering.state.move_options(unit)
		var found := false
		for cell in gathering.state.food_cells:
			if options.has(cell):
				gathering.select_unit(unit.uid)
				gathering._on_move_pressed()
				gathering._on_board_clicked(cell)
				found = true
				break
		if found:
			break
	for wait_index in range(2):
		gathering.do_end_turn()
		while gathering.busy:
			await create_timer(.05).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_gathering_1280.png")
	print("WINDOW_GATHERED_FOOD ", gathering.state.food_collected)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_gathering_1600.png")
	gathering.leave_node_button.pressed.emit()
	await process_frame
	await process_frame
	app.continue_after_settlement()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_return.png")
	print("WINDOW_RETURN_SCREEN ", app.current_screen.name)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var combat = app.current_screen
	# 高生命夹具隔离验证八回合路由，不用于平衡性结论。
	for unit in combat.state.alive_units("player"):
		unit.max_hp = 500
		unit.hp = 500
	for turn in range(8):
		combat.do_end_turn()
		while is_instance_valid(combat) and combat.busy:
			await create_timer(.05).timeout
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_eight_round_settlement.png")
	print("WINDOW_EIGHT_ROUND_SCREEN ", app.current_screen.name)
	app.run.trainer_hp = mini(app.run.trainer_hp, SpeciesDB.hp_of("trainer"))
	app.continue_after_settlement()
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var revisit = app.current_screen
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_combat_revisit.png")
	for enemy in revisit.state.alive_units("enemy"):
		revisit.state.kill_unit(enemy, "验收夹具清场", "enemy")
	while bool(revisit.state.nest.get("alive", false)):
		revisit.state.damage_nest(2)
	revisit.refresh_all()
	revisit.leave_node_button.pressed.emit()
	await process_frame
	await process_frame
	app.run.discard_unavailable_reward_choices()
	app.continue_after_settlement()
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/region_cleared_revisit.png")
	print("WINDOW_CLEARED_NODE_MODE ", app.current_screen.state.node_kind)
	app.queue_free()
	await process_frame
	quit()
