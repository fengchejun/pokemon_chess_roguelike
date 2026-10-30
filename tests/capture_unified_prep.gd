extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func shot(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + label + ".png")

func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	for id in ["rock_starter", "electric_starter", "water_wild1"]:
		app.run.carried.append(app.run._make_record(id))
	app.show_prep()
	var screen = app.current_screen
	for uid in [1, 2, 3]:
		screen.check_boxes[uid].button_pressed = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	await shot("unified_prep_1280")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await shot("unified_prep_1600")
	screen.find_child("PreviewToolsToggle", true, false).pressed.emit()
	await shot("unified_prep_tools")
	screen._on_start()
	await process_frame
	if app.current_screen.name != "BattleScreen":
		push_error("Merged screen did not start battle")
		quit(1)
		return
	print("UNIFIED_PREP_WINDOW_OK roster map tools direct_start")
	app.queue_free()
	await process_frame
	quit()
