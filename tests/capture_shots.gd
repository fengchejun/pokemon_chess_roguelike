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
	await _shot("02_theme_choice")
	var chosen_theme := String(app.run.offered_floor_themes[0])
	var theme_button: Button = app.current_screen.find_child("ChooseTheme_%s" % chosen_theme, true, false)
	theme_button.pressed.emit()
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
	battle.state.pending_casts.append({"uid": 100, "side": "enemy", "skill_id": "rock_slide", "cells": [Vector2i(2, 3)], "due_round": battle.state.round + 1})
	battle.refresh_all()
	await process_frame
	await _shot("05_channel_warning")
	battle.state.pending_casts.clear()
	battle.refresh_all()
	app.toggle_debug_console()
	await process_frame
	await _shot("05_battle_debug")
	app.toggle_debug_console()
	battle.select_unit(1)
	await process_frame
	await _shot("06_battle_select")
	battle._on_move_pressed()
	await _shot("06_battle_move_mode")
	battle._show_terrain(Vector2i(2, 3))
	await _shot("06_battle_terrain")
	var terrain_text: String = battle.terrain_label.text
	battle.terrain_label.text = "地块详情换行与滚动检查\n" + "临时藤蔓在指定回合恢复原地形，蒸汽会阻止施放技能，障碍耐久会随攻击减少。\n".repeat(18)
	await process_frame
	battle._fit_terrain_panel()
	await _shot("06_battle_terrain_long")
	battle.terrain_label.text = terrain_text
	battle._fit_terrain_panel()
	battle._show_unit_detail(battle.state.unit_by_uid(1))
	await _shot("06_battle_detail")
	battle._close_modal()
	battle._open_menu()
	await _shot("06_battle_menu")
	battle._close_modal()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await process_frame
	await _shot("06_battle_1600")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	await process_frame
	var move_hover := Vector2i(-1, -1)
	for cell in battle.board.movement_cells:
		if (battle.board.movement_cells[cell]["path"] as Array).size() >= 2:
			move_hover = cell
			break
	if GridSpec.is_inside(move_hover):
		battle._on_board_hovered(move_hover)
	await process_frame
	await _shot("06_battle_move_hover")
	battle._return_to_main_actions()
	battle._on_choose_skill_pressed()
	await _shot("07_battle_skill_list")
	battle._on_skill_pressed("fire_burst")
	await process_frame
	await _shot("07_battle_aim")
	battle._on_board_hovered(Vector2i(6, 2))
	await process_frame
	await _shot("08_battle_preview")
	var wind_preview_unit: CombatUnit = battle.state.unit_by_uid(1)
	var original_preview_skills := wind_preview_unit.skills.duplicate()
	wind_preview_unit.skills = ["wind_gust", "tailwind"]
	battle._on_skill_pressed("wind_gust")
	battle._on_board_hovered(wind_preview_unit.cell + Vector2i.RIGHT)
	await process_frame
	await _shot("08_wind_gust_area")
	battle._on_skill_pressed("tailwind")
	battle._on_board_hovered(wind_preview_unit.cell + Vector2i.RIGHT)
	await process_frame
	await _shot("08_tailwind_area")
	battle._clear_aim()
	wind_preview_unit.skills = original_preview_skills
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
	while not app.run.pending_monster_levels().is_empty():
		var level_entry: Dictionary = app.run.pending_monster_levels()[0]
		var choices: Array = app.run.available_monster_upgrades(int(level_entry["uid"]))
		if choices.is_empty() or not app.run.take_monster_level_choice(int(level_entry["uid"]), int(level_entry["level"]), String(choices[0])):
			break
	while app.run.pending_reward_choices > 0:
		var offers: Array = app.run.reward_choices()
		if offers.is_empty() or not app.run.choose_reward(String(offers[0])):
			break
	settlement._show_next_step()
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
	var supply_offers: Array = app.run.supply_choices()
	if not supply_offers.is_empty():
		app.run.choose_supply_item(String(supply_offers[0]))
	app.leave_supply()
	await process_frame
	await process_frame
	app.run.battle_index = Balance.BATTLES_PER_FLOOR - 1
	app.show_preview([1, 2, 3])
	await process_frame
	await process_frame
	await _shot("13_boss_preview")
	var boss_preview = app.current_screen
	app.begin_battle([1, 2, 3], boss_preview.map)
	await process_frame
	await process_frame
	await _shot("13_boss_battle")
	app.run.battle_index = Balance.BATTLES_PER_RUN
	app.show_run_end()
	await process_frame
	await process_frame
	await _shot("14_run_end")
	print("CAPTURE DONE")
	app.queue_free()
	await process_frame
	quit(0)


func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var path := "res://artifacts/%s.png" % shot_name
	image.save_png(path)
	print("saved ", path)
