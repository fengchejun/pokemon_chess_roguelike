extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene did not open")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	battle.set("state", state)
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var undo_button := battle.find_child("UndoMoveButton", true, false) as Button
	var action_bar := battle.find_child("ActionBar", true, false) as Control
	if board == null or undo_button == null or action_bar == null or battle.find_child("ModeButton", true, false) != null:
		return _fail("New action bar or undo button is missing")
	board.cell_pressed.emit(state.unit_by_id("trainer").cell)
	var capture_button := battle.find_child("CaptureButton", true, false) as Button
	if capture_button == null or capture_button.disabled:
		return _fail("Trainer capture button is missing")
	var destination := Vector2i(0, 3)
	if state.get_move_path(state.unit_by_id("trainer"), destination).is_empty():
		return _fail("Test movement destination is unavailable")
	board.cell_pressed.emit(destination)
	if state.unit_by_id("trainer").cell != destination or undo_button.disabled:
		return _fail("Direct movement did not preserve undo")
	board.cell_pressed.emit(state.unit_by_id("ally_fire").cell)
	var burst := battle.find_child("SkillButton_fire_burst", true, false) as Button
	var charge := battle.find_child("SkillButton_flame_charge", true, false) as Button
	if burst == null or charge == null or burst.disabled or charge.disabled:
		return _fail("All learned fire skills were not shown")
	burst.pressed.emit()
	if board.action_mode != "skill:fire_burst" or undo_button.disabled:
		return _fail("Choosing a skill locked movement undo")
	burst = battle.find_child("SkillButton_fire_burst", true, false) as Button
	burst.pressed.emit()
	if board.action_mode != "move" or undo_button.disabled:
		return _fail("Clicking the same skill did not cancel aiming")
	burst = battle.find_child("SkillButton_fire_burst", true, false) as Button
	burst.pressed.emit()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	battle.call("_unhandled_input", escape)
	if board.action_mode != "move" or undo_button.disabled:
		return _fail("Esc did not cancel aiming")
	burst = battle.find_child("SkillButton_fire_burst", true, false) as Button
	burst.pressed.emit()
	var right_click := InputEventMouseButton.new()
	right_click.pressed = true
	right_click.button_index = MOUSE_BUTTON_RIGHT
	battle.call("_unhandled_input", right_click)
	if board.action_mode != "move" or undo_button.disabled:
		return _fail("Right click did not cancel aiming")
	burst = battle.find_child("SkillButton_fire_burst", true, false) as Button
	burst.pressed.emit()
	board.cell_pressed.emit(Vector2i(7, 7))
	if board.action_mode != "skill:fire_burst" or undo_button.disabled:
		return _fail("Invalid skill click locked undo or left aiming")
	board.cell_pressed.emit(state.unit_by_id("ally_water").cell)
	if board.action_mode != "move" or board.selected_unit_id != "ally_water":
		return _fail("Switching ally did not return to direct movement")
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.skill_points = 0
	battle.call("_refresh")
	var water_flow := battle.find_child("SkillButton_water_flow", true, false) as Button
	if water_flow == null or not water_flow.disabled or not water_flow.text.contains("技能点不足"):
		return _fail("Missing skill points are not shown on the button")
	water.skill_points = 1
	state.terrain.steam[water.cell] = 1
	battle.call("_refresh")
	water_flow = battle.find_child("SkillButton_water_flow", true, false) as Button
	if water_flow == null or not water_flow.disabled or not water_flow.text.contains("雾中禁用"):
		return _fail("Fog restriction is not shown on the button")
	undo_button.pressed.emit()
	if state.unit_by_id("trainer").cell != Vector2i(1, 3):
		return _fail("Movement could not be undone after aiming and cancellation")
	print("BOTTOM_ACTION_BAR passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("BOTTOM_ACTION_BAR failed: " + message)
	quit(1)
