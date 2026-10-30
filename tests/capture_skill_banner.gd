extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await process_frame
	var screen = app.current_screen
	var state: BattleState = screen.state
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	var target: CombatUnit = state.alive_units("enemy")[0]
	target.cell = Vector2i(4, 3)
	target.element = "grass"
	target.hp = 999
	for x in range(1, 5):
		state.set_terrain(Vector2i(x, 3), TerrainDB.PLAIN)
	SkillResolver.apply(state, caster, "fire_seed", {"type": "cell", "cell": target.cell}, false)
	screen.refresh_all()
	await create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	root.get_texture().get_image().save_png("res://artifacts/skill_banner_effective.png")
	await create_timer(1.3).timeout
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	caster.moved = false
	target.element = "water"
	SkillResolver.apply(state, caster, "fire_seed", {"type": "cell", "cell": target.cell}, false)
	screen.refresh_all()
	await create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/skill_banner_resisted.png")
	await create_timer(1.5).timeout
	if screen.skill_banner.visible:
		push_error("Banner did not expire")
		quit(1)
		return
	print("SKILL_BANNER_WINDOW_OK effective resisted resize expiry")
	app.queue_free()
	await process_frame
	quit()
