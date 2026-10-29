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
	app.leave_camp()
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var screen = app.current_screen
	for enemy in screen.state.alive_units("enemy"):
		screen.state.kill_unit(enemy, "经验显示验收", "player", 1)
	screen._refresh_after_action()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/battle_live_xp_1280.png")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://artifacts/battle_live_xp_1600.png")
	app.queue_free()
	await process_frame
	quit()
