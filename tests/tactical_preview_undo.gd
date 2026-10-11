extends SceneTree

const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_multi_unit_undo():
		return
	if not _test_lethal_move_rejected():
		return
	if not _test_action_lock():
		return
	if not _test_enemy_range():
		return
	await _test_ui()


func _test_multi_unit_undo() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	if not state.try_player_move("trainer", Vector2i(0, 3)) or not state.try_player_move("ally_fire", Vector2i(0, 2)) or state.movement_history.size() != 2:
		return _fail("Multiple allies could not move in the same phase")
	if not state.undo_last_move() or fire.cell != Vector2i(1, 2) or fire.move_points == 0 or trainer.cell != Vector2i(0, 3):
		return _fail("Undo did not restore the latest ally movement")
	if not state.undo_last_move() or trainer.cell != Vector2i(1, 3) or trainer.move_points == 0:
		return _fail("Undo did not restore the earlier trainer movement")
	return true


func _test_lethal_move_rejected() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 1)
	fire.hp = 1
	state.terrain.ground[Vector2i(4, 1)] = "collapsed"
	if state.try_player_move("ally_fire", Vector2i(5, 1)) or not fire.is_alive() or fire.cell != Vector2i(3, 1) or fire.move_points == 0 or state.can_undo_move():
		return _fail("Pit-crossing move was accepted or consumed resources")
	state = BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(3, 1)
	trainer.hp = 1
	state.terrain.ground[Vector2i(4, 1)] = "collapsed"
	if state.try_player_move("trainer", Vector2i(5, 1)) or state.outcome != "" or trainer.hp != 1 or trainer.cell != Vector2i(3, 1):
		return _fail("Trainer voluntarily crossed a lethal pit")
	return true


func _test_action_lock() -> bool:
	var state := BattleState.new()
	if not state.try_player_move("ally_fire", Vector2i(0, 2)) or state.try_use_skill("ally_fire", "fire_burst", Vector2i(7, 7)) or not state.can_undo_move():
		return _fail("Invalid skill unexpectedly locked movement undo")
	if not state.try_use_skill("ally_fire", "fire_burst", Vector2i(0, 0)) or state.can_undo_move() or state.undo_last_move():
		return _fail("Valid skill did not commit earlier movement")
	if not state.try_player_move("trainer", Vector2i(0, 3)) or state.can_undo_move():
		return _fail("A committed skill did not keep later movement outside the undo window")
	state = BattleState.new()
	var target: CombatUnit = state.unit_by_id("wild_a")
	state.unit_by_id("ally_rock").cell = Vector2i(3, 4)
	state.unit_by_id("ally_water").cell = Vector2i(0, 4)
	target.cell = Vector2i(2, 3)
	target.hp = 2
	target.wet = true
	target.move_points = 0
	target.skill_points = 0
	TurnTestHelper.advance_to_player(state, "trainer")
	if not state.try_player_move("trainer", Vector2i(2, 4)) or not state.can_undo_move():
		return _fail("Capture fixture did not create undoable movement")
	state.try_capture(target.unit_id)
	if state.can_undo_move():
		return _fail("Capture attempt did not commit previous movement")
	state = BattleState.new()
	TurnTestHelper.advance_to_player(state, "trainer")
	if not state.try_player_move("trainer", Vector2i(0, 3)) or not state.finish_player_turn() or state.can_undo_move():
		return _fail("Ending turn did not close undo history")
	return true


func _test_enemy_range() -> bool:
	var state := BattleState.new()
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	var cells: Array[Vector2i] = state.enemy_move_cells(enemy)
	if cells.is_empty() or cells.has(Vector2i(5, 3)):
		return _fail("Enemy range included blocked rock or was empty")
	for cell in cells:
		if state.distance(enemy.cell, cell) > state.effective_move_range(enemy) or state.unit_at(cell) != null or state.terrain.blocks_move(cell):
			return _fail("Enemy range included an illegal destination")
	state.unit_by_id("ally_fire").cell = cells[0]
	if state.enemy_move_cells(enemy).has(cells[0]):
		return _fail("Enemy range did not update after a cell became occupied")
	return true


func _test_ui() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene failed to open")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	battle.set("state", BattleState.new())
	var initial_state: BattleState = battle.get("state")
	TurnTestHelper.advance_to_player(initial_state, "trainer")
	battle.set("selected_unit_id", "trainer")
	battle.call("_refresh")
	var state: BattleState = battle.get("state")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var undo_button := battle.find_child("UndoMoveButton", true, false) as Button
	var capture_button := battle.find_child("CaptureButton", true, false) as Button
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	if board == null or undo_button == null or capture_button == null or preview == null or not undo_button.disabled:
		_fail("Undo or preview controls were not initialized")
		return
	board.cell_pressed.emit(Vector2i(0, 3))
	if undo_button.disabled or not undo_button.text.contains("1"):
		_fail("Undo button did not activate after movement")
		return
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	board.cell_pressed.emit(enemy.cell)
	if board.inspected_enemy_id != enemy.unit_id or not preview.text.contains("可移动"):
		_fail("Clicking an enemy did not show movement range")
		return
	await process_frame
	undo_button.pressed.emit()
	if state.unit_by_id("trainer").cell != Vector2i(1, 3) or not undo_button.disabled:
		_fail("UI undo did not restore trainer")
		return
	state = BattleState.new()
	battle.set("state", state)
	battle.set("selected_unit_id", "ally_fire")
	battle.set("action_mode", "move")
	battle.call("_refresh")
	board.cell_pressed.emit(state.unit_by_id("ally_fire").cell)
	var fire_button := battle.find_child("SkillButton_fire_burst", true, false) as Button
	fire_button.pressed.emit()
	board.cell_hovered.emit(Vector2i(3, 2))
	if board.action_mode != "skill:fire_burst" or not state.can_use_skill(state.unit_by_id("ally_fire"), "fire_burst", Vector2i(3, 2)) or not preview.text.contains("射程"):
		_fail("Skill preparation did not expose legal range")
		return
	fire_button = battle.find_child("SkillButton_fire_burst", true, false) as Button
	fire_button.pressed.emit()
	TurnTestHelper.advance_to_player(state, "trainer")
	battle.call("_refresh")
	board.cell_pressed.emit(state.unit_by_id("trainer").cell)
	state.unit_by_id("trainer").cell = Vector2i(3, 1)
	state.unit_by_id("trainer").hp = 1
	state.terrain.ground[Vector2i(4, 1)] = "collapsed"
	board.cell_hovered.emit(Vector2i(4, 1))
	if not preview.text.contains("不能主动进入"):
		_fail("Pit hover did not explain the movement restriction")
		return
	board.cell_pressed.emit(Vector2i(4, 1))
	if state.outcome != "" or state.unit_by_id("trainer").cell != Vector2i(3, 1) or state.unit_by_id("trainer").move_points == 0 or not undo_button.disabled:
		_fail("UI accepted a voluntary move into a pit")
		return
	print("TACTICAL_PREVIEW_UNDO passed")
	quit(0)


func _fail(message: String) -> bool:
	push_error("TACTICAL_PREVIEW_UNDO failed: " + message)
	quit(1)
	return false
