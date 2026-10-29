extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.trainer_hp = 1
	app.run.carried[0]["hp"] = 0
	app.show_camp()
	await _shot("res://artifacts/rework_camp_1280.png")
	app.current_screen.find_child("Campfire", true, false).pressed.emit()
	await _shot("res://artifacts/rework_campfire_1280.png")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _shot("res://artifacts/rework_campfire_1600.png")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	app.current_screen.find_child("CampRestButton", true, false).pressed.emit()
	await _shot("res://artifacts/rework_camp_rest_result_1280.png")
	app.leave_camp()
	await _shot("res://artifacts/rework_route_1280.png")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _shot("res://artifacts/rework_route_1600.png")
	app.enter_region_node("event_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var battle = app.current_screen
	battle.state.round = 7
	battle.refresh_all()
	await _shot("res://artifacts/rework_collect_warning_1600.png")
	app.run = RunState.new_run(43)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	for index in range(8):
		region.record_entry("camp")
		region.notifications.append_array(region.complete_visit())
	app.run.region_data = region.to_dict()
	app.show_region()
	await _shot("res://artifacts/rework_support_route_1600.png")
	app.queue_free()
	await process_frame
	quit()
