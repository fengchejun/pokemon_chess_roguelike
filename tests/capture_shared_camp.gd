extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(8102)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	await create_timer(1.5).timeout
	DirAccess.make_dir_recursive_absolute("res://outputs/shared_camp")
	root.get_texture().get_image().save_png("res://outputs/shared_camp/peace.png")
	var state: BattleState = app.current_screen.state
	app.sync_and_save(state)
	app.leave_camp()
	var region = app.run.get_region()
	region.visits = 7
	app.run.region_data = region.to_dict()
	app.enter_region_node("camp")
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://outputs/shared_camp/invasion_preview.png")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png("res://outputs/shared_camp/invasion.png")
	state = app.current_screen.state
	state.damage_obstacle(Vector2i(3, 3), 2, "enemy")
	state.damage_obstacle(Vector2i(6, 3), 5, "enemy")
	app.sync_and_save(state)
	app.current_screen.refresh_all()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://outputs/shared_camp/destroyed.png")
	quit()
