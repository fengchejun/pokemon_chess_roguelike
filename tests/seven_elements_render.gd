extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.get_node("RunManager").start_new_run()
	if change_scene_to_file("res://scenes/starter_selection.tscn") != OK:
		_fail("Starter selection failed to open")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/seven_starters_1280x720.png")
	for species_id in ["electric", "grass", "ice"]:
		current_scene.call("_toggle", species_id)
	current_scene.call("_confirm")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	if battle == null or battle.name != "Battle":
		_fail("Selected starters failed to open battle")
		return
	battle.set("selected_unit_id", "ally_electric")
	battle.call("_refresh")
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/seven_elements_battle_1280x720.png")
	var state: BattleState = battle.get("state")
	state.terrain.set_vine(Vector2i(3, 3))
	state.terrain.set_ice(Vector2i(4, 3))
	battle.set("hover_cell", Vector2i(4, 3))
	battle.call("_refresh")
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://artifacts/seven_elements_terrain_1280x720.png")
	print("SEVEN_ELEMENTS_RENDER passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("SEVEN_ELEMENTS_RENDER failed: " + message)
	quit(1)
