extends SceneTree

const GridSpec = preload("res://scripts/grid_spec.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if GridSpec.WIDTH != 8 or GridSpec.HEIGHT != 8:
		_fail("Board size is not 8x8")
		return
	if not GridSpec.is_inside(Vector2i(0, 0)) or not GridSpec.is_inside(Vector2i(7, 7)):
		_fail("Valid grid coordinates were rejected")
		return
	if GridSpec.is_inside(Vector2i(-1, 0)) or GridSpec.is_inside(Vector2i(8, 7)):
		_fail("Out-of-bounds grid coordinates were accepted")
		return

	var load_error := change_scene_to_file("res://scenes/main_menu.tscn")
	if load_error != OK:
		_fail("Main menu could not load")
		return
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "MainMenu":
		_fail("Main menu is not active")
		return
	var preview_button := current_scene.find_child("PreviewButton", true, false) as Button
	if preview_button == null:
		_fail("Preview button is missing")
		return
	preview_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "BoardPreview":
		_fail("Board preview did not open")
		return
	if current_scene.find_child("BoardGrid", true, false) == null:
		_fail("Board grid is missing")
		return
	var back_button := current_scene.find_child("BackButton", true, false) as Button
	if back_button == null:
		_fail("Back button is missing")
		return
	back_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "MainMenu":
		_fail("Back button did not return to main menu")
		return
	print("STAGE0_SMOKE passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("STAGE0_SMOKE failed: " + message)
	quit(1)
