extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_movement_and_skills():
		return
	if not _test_victory_and_defeat():
		return
	await _test_scene_flow()


func _test_movement_and_skills() -> bool:
	var state := BattleState.new()
	if state.units.size() != 7 or state.phase != "player" or not _unique_cells(state):
		return _fail("Seven units were not deployed legally")
	var trainer: CombatUnit = state.unit_by_id("trainer")
	if trainer.skill_points != 0 or not trainer.skill_ids.is_empty() or state.can_use_skill(trainer, "fire_burst", Vector2i(2, 3)):
		return _fail("Trainer retained an attack")
	if state.try_player_move("trainer", Vector2i(-1, 3)) or state.try_player_move("trainer", Vector2i(1, 2)):
		return _fail("Illegal movement succeeded")
	if not TurnTestHelper.advance_to_player(state, "trainer") or not state.try_player_move("trainer", Vector2i(0, 1)) or trainer.move_points != 0 or state.try_player_move("trainer", Vector2i(0, 0)):
		return _fail("One-time movement failed")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var target: CombatUnit = state.unit_by_id("wild_a")
	target.cell = Vector2i(3, 2)
	target.move_points = 0
	target.skill_points = 0
	if not state.try_use_skill("ally_fire", "fire_burst", target.cell) or target.hp != CombatConfig.WILD_HP - 2 or fire.skill_points != 0:
		return _fail("Fire skill did not remain available in the shared player phase")
	if not state.try_player_move("ally_fire", Vector2i(0, 2)) or fire.move_points != 0:
		return _fail("Movement was not independent of skill use")
	if not TurnTestHelper.finish_round(state):
		return _fail("Round could not finish")
	if fire.skill_points != CombatConfig.SKILL_POINTS_PER_TURN or trainer.skill_points != 0 or fire.move_points != state.effective_move_range(fire):
		return _fail("Round did not restore movement and skill resources: %s" % str({"outcome": state.outcome, "turn": state.turn_number, "fire_hp": fire.hp, "fire_move": fire.move_points, "fire_skill": fire.skill_points, "trainer_skill": trainer.skill_points}))
	return _unique_cells(state)


func _test_victory_and_defeat() -> bool:
	var state := BattleState.new()
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	state.unit_by_id("wild_b").cell = Vector2i(2, 4)
	state.unit_by_id("wild_c").cell = Vector2i(3, 3)
	for enemy_id in ["wild_a", "wild_b", "wild_c"]:
		state.unit_by_id(enemy_id).hp = 1
	if not state.try_use_skill("ally_fire", "fire_burst", Vector2i(3, 2)):
		return _fail("First enemy was not hit")
	if not state.try_use_skill("ally_water", "electric_arc", Vector2i(2, 4)):
		return _fail("Second enemy was not hit")
	if not state.try_use_skill("ally_rock", "rock_break", Vector2i(3, 3)) or state.outcome != "victory" or state.finish_player_turn():
		return _fail("Skill-only victory did not stop battle")
	state = BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.hp = 1
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").cell = Vector2i(0, 3)
	if not TurnTestHelper.finish_round(state) or trainer.is_alive() or state.outcome != "defeat" or state.finish_player_turn():
		return _fail("Trainer defeat did not stop battle")
	return true


func _test_scene_flow() -> void:
	if change_scene_to_file("res://scenes/main_menu.tscn") != OK:
		_fail("Main menu failed to load")
		return
	await process_frame
	await process_frame
	var start_button := current_scene.find_child("StartButton", true, false) as Button
	if start_button == null:
		_fail("Start button is missing")
		return
	start_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "Battle":
		_fail("Battle scene did not open")
		return
	var battle: Control = current_scene
	var end_button := battle.find_child("EndTurnButton", true, false) as Button
	end_button.pressed.emit()
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var state: BattleState = battle.get("state")
	var capture_button := battle.find_child("CaptureButton", true, false) as Button
	if board == null or state == null or capture_button == null or capture_button.disabled:
		_fail("Trainer movement and capture controls are wrong")
		return
	capture_button.pressed.emit()
	if board.action_mode != "capture":
		_fail("Trainer capture mode is missing")
		return
	(battle as Node).call("_cancel_aim")
	board.cell_pressed.emit(state.unit_by_id("trainer").cell)
	var destination := Vector2i(-1, -1)
	for y in 8:
		for x in 8:
			var candidate := Vector2i(x, y)
			if not state.get_move_path(state.unit_by_id("trainer"), candidate).is_empty():
				destination = candidate
				break
		if destination.x >= 0:
			break
	if destination.x < 0:
		_fail("No legal trainer movement cell on generated map")
		return
	board.cell_pressed.emit(destination)
	if state.unit_by_id("trainer").cell != destination:
		_fail("Board movement failed: %s; selected=%s; mode=%s; phase=%s" % [str(state.unit_by_id("trainer").cell), board.selected_unit_id, board.action_mode, state.phase])
		return
	var restart_button := battle.find_child("RestartButton", true, false) as Button
	restart_button.pressed.emit()
	state = battle.get("state")
	if state.turn_number != 1 or state.unit_by_id("trainer").cell != Vector2i(1, 3):
		_fail("Restart did not reset battle")
		return
	var menu_button := battle.find_child("MenuButton", true, false) as Button
	menu_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "MainMenu":
		_fail("Return to menu failed")
		return
	print("STAGE1_COMBAT passed")
	quit(0)


func _unique_cells(state: BattleState) -> bool:
	var occupied: Dictionary = {}
	for unit in state.units:
		if not unit.is_alive():
			continue
		if occupied.has(unit.cell):
			return false
		occupied[unit.cell] = true
	return true


func _fail(message: String) -> bool:
	push_error("STAGE1_COMBAT failed: " + message)
	quit(1)
	return false
