extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + path + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
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
	var screen = app.current_screen
	var state: BattleState = screen.state
	var nest_cell := Vector2i(4, 3)
	state.nest["cell"] = nest_cell
	state.nest["pending_waves"] = 1
	state.set_terrain(nest_cell, TerrainDB.PLAIN)
	state.set_terrain(Vector2i(3, 3), TerrainDB.PLAIN)
	var ally := state.unit_by_uid(1)
	ally.cell = Vector2i(3, 3)
	if not ally.skills.has("discharge"):
		ally.skills.append("discharge")
	screen.refresh_all()
	screen.select_unit(1)
	screen._show_terrain(nest_cell)
	var preview := state.preview_skill(ally, "discharge", {"type": "nest", "cell": nest_cell})
	screen._preview_overlays(preview)
	await _shot("nest_empty_target")
	state._try_spawn_wave()
	screen.refresh_all()
	screen._show_terrain(nest_cell)
	screen._cancel_action()
	await _shot("nest_enemy_cover")
	screen.select_unit(1)
	var spawn := state.unit_at(nest_cell)
	spawn.hp = 1
	var before := int(state.nest["hp"])
	if not screen.do_cast("discharge", {"type": "unit", "unit": spawn.uid, "cell": nest_cell}) or state.nest["hp"] != before:
		push_error("Nest cover attack failed")
		quit(1)
		return
	await create_timer(1.5).timeout
	ally.skill_used = false
	ally.moved = false
	state.nest["pending_waves"] = 1
	if not state.move_unit(ally, nest_cell):
		push_error("Cannot stand on nest")
		quit(1)
		return
	state._try_spawn_wave()
	screen.refresh_all()
	screen._show_terrain(nest_cell)
	screen._cancel_action()
	await screen._wait_playback()
	await _shot("nest_player_block")
	if state.unit_at(nest_cell) != ally or state.nest["pending_waves"] != 1:
		push_error("Nest blocking failed")
		quit(1)
		return
	print("NEST_WINDOW_OK empty_target enemy_cover player_block")
	app.queue_free()
	await process_frame
	quit()
