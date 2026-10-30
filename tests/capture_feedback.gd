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
	await process_frame
	var screen = app.current_screen
	var state: BattleState = screen.state
	var enemy: CombatUnit = state.alive_units("enemy")[0]
	enemy.cell = Vector2i(4, 3)
	state.damage_unit(null, enemy, 12, {"no_element": true})
	enemy.element = "grass"
	state.apply_burn(enemy, null)
	var ally: CombatUnit = state.unit_by_uid(1)
	state.feedback_heal(ally, 8)
	var fallen: CombatUnit = state.alive_units("enemy")[1]
	fallen.cell = Vector2i(6, 5)
	state.set_terrain(fallen.cell, TerrainDB.PIT)
	state.kill_unit(fallen, "地面塌陷", "player", ally.uid)
	screen.board.set_from_state(state)
	await create_timer(0.38).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	root.get_texture().get_image().save_png("res://artifacts/battle_feedback.png")
	# Verify edge placement at a second real window size.
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await process_frame
	state.emit_feedback(ally, "action", "开始吟唱")
	state._relay_feedback("status", "藤蔓束缚", 1, Vector2i.ZERO, ally.uid)
	state._relay_feedback("death", "溺水", 0, Vector2i(7, 7), fallen.uid)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/battle_feedback_wide.png")
	await create_timer(2.0).timeout
	print("FEEDBACK_WINDOW_OK active=", screen.feedback_layer.entries.size())
	var trainer: CombatUnit = state.unit_by_uid(Balance.TRAINER_UID)
	state.damage_unit(null, trainer, 999, {"no_element": true})
	screen._refresh_after_action()
	await create_timer(0.25).timeout
	if app.current_screen != screen:
		push_error("Final feedback skipped before settlement")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/battle_feedback_final.png")
	await create_timer(1.5).timeout
	if app.current_screen == screen:
		push_error("Settlement did not resume")
		quit(1)
		return
	print("FEEDBACK_FINAL_SETTLEMENT_OK")
	app.queue_free()
	await process_frame
	quit()
