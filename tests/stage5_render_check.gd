extends SceneTree

const Cards = preload("res://scripts/environment_card_system.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var run: RunState = root.get_node("RunManager").run_state
	run.run_seed = 24680
	run.environment_cards = ["water", "fire"]
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/stage5_battle.png")
	var battle: Control = current_scene
	var state: BattleState = battle.get("state")
	var preview_state := BattleState.new()
	preview_state.unit_by_id("trainer").wet = true
	preview_state.unit_by_id("trainer").move_points = 2
	battle.set("state", preview_state)
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	board.cell_pressed.emit(preview_state.unit_by_id("ally_fire").cell)
	var skill_button := battle.find_child("SkillButton_fire_burst", true, false) as Button
	skill_button.pressed.emit()
	board.hover_cell = Vector2i(4, 2)
	board.cell_hovered.emit(Vector2i(4, 2))
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/terrain_status_preview.png")
	battle.set("action_mode", "skill:flame_charge")
	battle.set("hover_cell", Vector2i(3, 2))
	battle.call("_refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/flame_charge_preview.png")
	battle.set("selected_unit_id", "ally_water")
	battle.set("action_mode", "skill:rain_call")
	battle.set("hover_cell", Vector2i(4, 4))
	battle.call("_refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/rain_call_preview.png")
	preview_state.terrain.objects.clear()
	preview_state.try_use_skill("ally_rock", "rock_create", Vector2i(3, 3))
	battle.set("selected_unit_id", "ally_rock")
	battle.set("action_mode", "skill:rock_create")
	battle.set("hover_cell", Vector2i(3, 3))
	battle.call("_refresh")
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/temporary_rock_wall.png")
	battle.set("state", state)
	battle.set("selected_unit_id", "trainer")
	battle.set("action_mode", "move")
	battle.set("hover_cell", Vector2i(-1, -1))
	state.unit_by_id("trainer").max_hp = 99
	state.unit_by_id("trainer").hp = 99
	while state.outcome == "" and state.turn_number < 4:
		state.finish_player_turn()
	battle.call("_refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/combat_rework_round4.png")
	run.battle_count = 1
	run.last_reward = {"outcome": "escape", "kills": 1, "captures": 0, "escaped": 2, "experience": 2}
	run.offered_environment_cards = Cards.offer(run.environment_cards, 42)
	for index in 3:
		run.roster.append(run.roster[index].duplicate(true))
		run.roster.back()["instance_id"] = "reserve_%d" % index
	if change_scene_to_file("res://scenes/between_battles.tscn") != OK:
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/stage5_camp.png")
	run.last_reward["bonus_card"] = true
	run.bonus_choice_active = true
	current_scene.call("_refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/combat_rework_bonus.png")
	print("STAGE5_RENDER_CHECK passed")
	quit(0)
