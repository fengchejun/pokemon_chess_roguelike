extends SceneTree

## 视觉验证：开窗口运行各界面并截图到 res://artifacts。
## 用法：godot --path . -s res://tests/capture_shots.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	await _shot("01_menu")
	app.start_new_run()
	await process_frame
	await process_frame
	await _shot("02_collection")
	for id in [1, 2, 3]:
		var collection_box: CheckBox = app.current_screen.find_child("Collection_%d" % id, true, false)
		collection_box.button_pressed = true
	var collection_start: Button = app.current_screen.find_child("StartFromCollectionButton", true, false)
	collection_start.pressed.emit()
	await process_frame
	await process_frame
	for uid in [1, 2, 3]:
		var deploy_box: CheckBox = app.current_screen.find_child("Deploy_%d" % int(uid), true, false)
		if deploy_box != null:
			deploy_box.button_pressed = true
	await process_frame
	await _shot("02_prep")
	app.show_preview([1, 2, 3])
	await process_frame
	await process_frame
	await _shot("03_preview")
	var preview_screen = app.current_screen
	preview_screen._set_mod_kind("water")
	preview_screen._on_cell_clicked(Vector2i(3, 5))
	await process_frame
	await _shot("04_preview_mod")
	app.begin_battle([1, 2, 3], preview_screen.map)
	await process_frame
	await process_frame
	var battle = app.current_screen
	await _shot("05_battle")
	battle.select_unit(1)
	await process_frame
	await _shot("06_battle_select")
	battle.state.add_attachment(battle.state.unit_by_uid(1), "water")
	battle.state.add_attachment(battle.state.unit_by_uid(1), "rock")
	battle.state.add_attachment(battle.state.unit_by_uid(100), "electric")
	battle.refresh_all()
	await _shot("06_battle_attachments")
	battle._on_skill_pressed("fire_burst")
	await process_frame
	await _shot("07_battle_aim")
	battle._on_board_hovered(Vector2i(6, 2))
	await process_frame
	await _shot("08_battle_preview")
	battle.do_end_turn()
	await create_timer(1.4).timeout
	await _shot("09_enemy_phase")
	if not battle.state.ended:
		for enemy in battle.state.alive_units("enemy"):
			battle.state.kill_unit(enemy, "截图清场", "player")
		battle.refresh_all()
	await process_frame
	await process_frame
	await _shot("10_settlement")
	var settlement = app.current_screen
	# 捕获处理选项（名单满员）
	while app.run.carried.size() < Balance.CARRIED_LIMIT:
		app.run._add_capture("fire_wild1", 4)
	app.run.pending_captures.append({"species_id": "water_wild1", "hp": 3})
	settlement._show_next_step()
	await process_frame
	await _shot("11_capture_choice")
	var capture_button: Button = settlement.find_child("CaptureToStorageButton", true, false)
	if capture_button != null:
		capture_button.pressed.emit()
	await process_frame
	await _shot("12_settlement_done")
	settlement.continue_button.pressed.emit()
	await process_frame
	await process_frame
	app.run.trainer_hp = 2
	app.run.battle_index = Balance.SUPPLY_INTERVAL
	app.run.pending_supply = true
	app.show_supply()
	await process_frame
	await process_frame
	await _shot("13_supply")
	app.leave_supply()
	await process_frame
	await process_frame
	app.run.battle_index = Balance.BATTLES_PER_RUN
	app.show_run_end()
	await process_frame
	await process_frame
	await _shot("14_run_end")
	print("CAPTURE DONE")
	quit(0)


func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var path := "res://artifacts/%s.png" % shot_name
	image.save_png(path)
	print("saved ", path)
