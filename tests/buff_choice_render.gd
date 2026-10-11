extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene did not open")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	state.reward_cell = state.unit_by_id("ally_fire").cell
	state.reward_state = "ground"
	state.unit_by_id("trainer").hp = 99
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	battle.set("state", state)
	state.finish_player_turn()
	battle.call("_refresh")
	var overlay := battle.find_child("RewardChoiceOverlay", true, false) as Control
	var button_a := battle.find_child("ChoiceA", true, false) as Button
	var button_b := battle.find_child("ChoiceB", true, false) as Button
	if state.phase != "reward_choice" or overlay == null or not overlay.visible or button_a.text == "" or button_b.text == "":
		_fail("Reward selection overlay did not display both choices")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/buff_choice_1280x720.png")
	button_a.pressed.emit()
	if state.phase != "player" or overlay.visible:
		_fail("Choosing a buff did not resume combat")
		return
	print("BUFF_CHOICE_RENDER passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("BUFF_CHOICE_RENDER failed: " + message)
	quit(1)
