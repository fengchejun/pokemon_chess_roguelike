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
	var trainer: CombatUnit = screen.state.unit_by_uid(Balance.TRAINER_UID)
	for cell in GridSpec.neighbors4(screen.state.merchant["cell"]):
		if screen.state.unit_at(cell) == null and TerrainDB.can_stand(screen.state.terrain_at(cell), ""):
			trainer.cell = cell
			break
	# 界面夹具提供余额以展示完整商品；不用于经济平衡结论。
	app.run.essence = 100
	screen.refresh_all()
	await _shot("res://artifacts/merchant_npc_1280.png")
	screen._on_board_clicked(screen.state.merchant["cell"])
	await _shot("res://artifacts/merchant_trade_1280.png")
	screen._trade("buy", "potion")
	await _shot("res://artifacts/merchant_purchased_1280.png")
	screen._close_modal()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	screen._show_merchant()
	await _shot("res://artifacts/merchant_trade_1600.png")
	screen._close_modal()
	screen.select_unit(trainer.uid)
	screen.action_mode = "items"
	screen._rebuild_skill_buttons()
	await _shot("res://artifacts/merchant_items_1600.png")
	app.queue_free()
	await process_frame
	quit()
