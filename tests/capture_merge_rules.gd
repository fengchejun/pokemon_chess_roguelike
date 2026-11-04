extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	print("MERGE_UI_SHOT ", name)
	root.get_texture().get_image().save_png("res://artifacts/merge_" + name + ".png")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var id := "event_1" if region.nodes["event_1"].has("merchant") else "event_2"
	region.nodes[id]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var screen = app.current_screen
	var state: BattleState = screen.state
	state.award_battle_experience("qa", 6)
	app.run.sync_from_battle(state)
	app.run.essence = 100
	for cell in GridSpec.neighbors4(state.merchant["cell"]):
		if state.unit_at(cell) == null and TerrainDB.can_stand(state.terrain_at(cell), ""):
			state.trainer().cell = cell
			break
	screen.playback.finish_all()
	screen.battle_notice.finish_all()
	screen.refresh_all()
	screen._show_merchant()
	await _shot("merchant_1280")
	var record: Dictionary = app.run.record_by_uid(1)
	var skill := String(RunState.upgrade_info(app.run.available_monster_upgrades(1)[0])["requires_skill"])
	var result: Dictionary = app.purchase_skill_upgrade(state, 1, skill)
	print("MERGE_UI_MERCHANT ", result)
	screen._show_merchant(result["reason"])
	await _shot("merchant_purchased_1280")
	screen._close_modal()
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 6, "monster_exp": [], "kills": 1, "captures": 0}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	await _shot("learning_1280")
	app.run = RunState.new_run(7701)
	var battle := TestScenario.make_state(["rock_starter", "water_starter", "electric_starter"], [["fire_wild1", Vector2i(4, 3)]])
	battle.node_kind = "battle"
	battle.unit_by_uid(1).cell = Vector2i(2, 3)
	battle.unit_by_uid(100).cell = Vector2i(4, 3)
	battle.apply_guard_rock_shield(battle.unit_by_uid(1), 10, 1)
	battle.apply_freeze(battle.unit_by_uid(100))
	battle.award_battle_experience("qa", 16)
	var combat = load("res://scripts/ui/battle_screen.gd").new()
	combat.state = battle
	app._switch(combat)
	combat.playback.finish_all()
	combat.battle_notice.finish_all()
	combat.select_unit(1)
	combat.refresh_all()
	await create_timer(1.2).timeout
	combat.battle_notice.finish_all()
	print("MERGE_UI_BATTLE ", app.current_screen.name, " ", battle.ended, " ", battle.end_reason)
	await _shot("battle_1280")
	app.queue_free()
	await process_frame
	quit()
