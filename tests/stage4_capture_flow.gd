extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_six_round_escape():
		return
	if not _test_capture_range_and_guarantees():
		return
	if not _test_capture_rules_and_rewards():
		return
	if not _test_captured_ally_actions_and_loss():
		return
	if not _test_kill_and_defeat_rewards():
		return
	if not _test_full_roster_resolution():
		return
	if not await _test_capture_ui():
		return
	if not await _test_pending_roster_ui():
		return
	await _test_battle_to_roster_flow()


func _test_six_round_escape() -> bool:
	var state := BattleState.new()
	state.unit_by_id("trainer").hp = 99
	for turn in range(1, CombatConfig.MAX_PLAYER_ROUNDS + 1):
		if state.turn_number != turn or not TurnTestHelper.finish_round(state):
			return _fail("Round advancement failed before escape")
		if turn < CombatConfig.MAX_PLAYER_ROUNDS and (state.outcome != "" or state.phase != "player"):
			return _fail("Battle ended before final settlement")
	if state.outcome != "escape" or state.phase != "finished" or state.turn_number != CombatConfig.MAX_PLAYER_ROUNDS or state.escaped_enemy_ids.size() != 3 or state.finish_player_turn():
		return _fail("Final settlement did not produce a distinct escape result")
	var run := RunState.new()
	var result := run.apply_battle_result(state)
	if result.get("outcome", "") != "escape" or result.get("experience", -1) != 0 or result.get("escaped", 0) != 3:
		return _fail("Escape incorrectly counted as victory or awarded experience")
	return true


func _test_capture_range_and_guarantees() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var target: CombatUnit = state.unit_by_id("wild_a")
	trainer.cell = Vector2i(3, 3)
	target.hp = 2
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			target.cell = trainer.cell + Vector2i(dx, dy)
			if not state.can_capture(target):
				return _fail("A target in the trainer's eight surrounding cells was not capturable")
	state.terrain.objects[Vector2i(4, 3)] = TerrainManager.make_rock()
	state.terrain.objects[Vector2i(3, 4)] = TerrainManager.make_rock()
	target.cell = Vector2i(4, 4)
	if not state.can_capture(target):
		return _fail("Corner obstacles incorrectly blocked diagonal capture")
	target.cell = trainer.cell + Vector2i(2, 0)
	if state.can_capture(target):
		return _fail("A target outside the surrounding ring was capturable")
	target.cell = Vector2i(4, 4)
	target.hp = 3
	target.wet = true
	if state.can_capture(target):
		return _fail("A debuff incorrectly raised the half-health capture limit")
	target.hp = 2
	target.wet = false
	var normal_chance: float = state.capture_chance(target)
	if normal_chance <= 0.0 or normal_chance >= 1.0:
		return _fail("An unmarked 2 HP target should still use the original random chance")
	for guaranteed_case in [{"hp": 1, "wet": false, "burned": false}, {"hp": 2, "wet": true, "burned": false}, {"hp": 2, "wet": false, "burned": true}]:
		var test_state := BattleState.new()
		var test_trainer: CombatUnit = test_state.unit_by_id("trainer")
		var test_target: CombatUnit = test_state.unit_by_id("wild_a")
		test_target.cell = test_trainer.cell + Vector2i(1, 1)
		test_target.hp = guaranteed_case["hp"]
		test_target.wet = guaranteed_case["wet"]
		test_target.burned = guaranteed_case["burned"]
		if not test_state.can_capture(test_target) or test_state.capture_chance(test_target) != 1.0:
			return _fail("Guaranteed capture condition or preview chance was incorrect")
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.seed = 1234
		test_state.capture_rng.seed = 1234
		if not test_state.try_capture(test_target.unit_id) or test_state.capture_rng.randf() != expected_rng.randf():
			return _fail("Guaranteed capture failed or consumed a random number")
	return true


func _test_capture_rules_and_rewards() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var target: CombatUnit = state.unit_by_id("wild_a")
	state.unit_by_id("ally_rock").cell = Vector2i(3, 4)
	state.unit_by_id("ally_water").cell = Vector2i(0, 4)
	target.cell = Vector2i(2, 3)
	if state.can_capture(target):
		return _fail("Healthy target was capturable")
	target.hp = 2
	target.wet = false
	target.move_points = 0
	target.skill_points = 0
	if not TurnTestHelper.advance_to_player(state, "trainer"):
		return _fail("Trainer speed group was not reached")
	if not state.can_capture(target) or not state.try_player_move("trainer", Vector2i(2, 4)) or trainer.move_points != 0 or not state.can_capture(target):
		return _fail("Capture eligibility or movement independence failed")
	state.capture_rng.seed = _seed_for_roll(state.capture_chance(target), false)
	if state.try_capture(target.unit_id) or trainer.capture_points != 0 or target.hp != 2 or state.try_capture(target.unit_id):
		return _fail("Failed capture did not consume exactly one opportunity")
	TurnTestHelper.finish_round(state)
	if trainer.capture_points != CombatConfig.CAPTURE_ATTEMPTS_PER_TURN:
		return _fail("Capture opportunity did not refresh")
	state = BattleState.new()
	trainer = state.unit_by_id("trainer")
	target = state.unit_by_id("wild_a")
	state.unit_by_id("ally_rock").cell = Vector2i(3, 3)
	target.cell = Vector2i(2, 4)
	target.hp = 1
	target.wet = false
	target.move_points = 0
	target.skill_points = 0
	TurnTestHelper.advance_to_player(state, "trainer")
	state.capture_rng.seed = _seed_for_roll(state.capture_chance(target), true)
	if not state.try_capture(target.unit_id) or trainer.move_points != CombatConfig.PLAYER_MOVE_POINTS or not state.try_player_move("trainer", Vector2i(2, 3)):
		return _fail("Capture before movement consumed the separate movement opportunity")
	var run := RunState.new()
	state = BattleState.new(run)
	trainer = state.unit_by_id("trainer")
	target = state.unit_by_id("wild_a")
	state.unit_by_id("ally_rock").cell = Vector2i(2, 4)
	target.cell = Vector2i(2, 3)
	target.hp = 1
	target.wet = true
	target.move_points = 0
	target.skill_points = 0
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.capture_rng.seed = _seed_for_roll(state.capture_chance(target), true)
	TurnTestHelper.advance_to_player(state, "trainer")
	if not state.try_capture(target.unit_id) or state.outcome != "victory" or state.captured_records.size() != 1 or not state.defeated_enemy_ids.is_empty():
		return _fail("Successful capture did not end battle without counting a kill")
	var reward: Dictionary = run.apply_battle_result(state)
	if reward.get("experience", -1) != CombatConfig.EXPERIENCE_PER_CAPTURE or run.roster.size() != 4 or run.roster[0]["experience"] != CombatConfig.EXPERIENCE_PER_CAPTURE or not run.apply_battle_result(state).is_empty():
		return _fail("Capture reward, roster addition, or one-time settlement failed")
	if not run.toggle_active("ally_fire") or not run.toggle_active(run.roster[3]["instance_id"]):
		return _fail("Captured monster could not be selected for next battle")
	var next_battle := BattleState.new(run)
	if next_battle.unit_by_id(run.roster[3]["instance_id"]) == null or next_battle.units.size() != 7:
		return _fail("Next battle did not deploy chosen captured monster")
	return true


func _test_captured_ally_actions_and_loss() -> bool:
	var run := RunState.new()
	var state := BattleState.new(run)
	var target: CombatUnit = state.unit_by_id("wild_a")
	target.cell = Vector2i(2, 4)
	target.hp = 1
	target.burned = true
	target.wet = true
	if not state.try_capture(target.unit_id) or target.team != "player" or target.hp != 1 or target.max_hp != CombatConfig.WILD_HP or not target.burned or not target.wet:
		return _fail("Capture did not preserve the monster on the board with its HP and debuffs")
	if not state.current_player_ids().has(target.unit_id) or target.move_points != state.effective_move_range(target) or target.skill_points != CombatConfig.SKILL_POINTS_PER_TURN or state.outcome != "":
		return _fail("Captured monster was not immediately controllable")
	if not state.try_player_move(target.unit_id, Vector2i(3, 4)) or not state.try_use_skill(target.unit_id, "fire_burst", Vector2i(3, 6)):
		return _fail("Captured monster could not move and use a skill in the capture round")
	state.apply_environment_damage(target, target.hp, "捕获后受伤")
	if target.is_alive() or state.defeated_enemy_ids.has(target.unit_id):
		return _fail("Death of a captured ally was counted as an enemy kill")
	for enemy_id in ["wild_b", "wild_c"]:
		var enemy: CombatUnit = state.unit_by_id(enemy_id)
		state.apply_environment_damage(enemy, enemy.hp, "测试清场")
	if state.outcome != "victory":
		return _fail("The battle did not end after remaining enemies were defeated")
	var reward: Dictionary = run.apply_battle_result(state)
	if run.roster.size() != 3 or not run.pending_captures.is_empty() or reward.get("captures", -1) != 0 or reward.get("lost_captures", -1) != 1 or reward.get("experience", -1) != 2 * CombatConfig.EXPERIENCE_PER_KILL + CombatConfig.EXPERIENCE_PER_CAPTURE:
		return _fail("Dead captured monster entered the roster or the settlement miscounted its loss")
	return true


func _seed_for_roll(chance: float, should_succeed: bool) -> int:
	var rng := RandomNumberGenerator.new()
	for seed in 10000:
		rng.seed = seed
		if (rng.randf() < chance) == should_succeed:
			return seed
	return -1


func _test_kill_and_defeat_rewards() -> bool:
	var run := RunState.new()
	var state := BattleState.new(run)
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	state.unit_by_id("wild_a").hp = 1
	if not state.try_use_skill("ally_fire", "fire_burst", Vector2i(3, 2)) or state.defeated_enemy_ids != ["wild_a"]:
		return _fail("Killed enemy was not recorded exactly once")
	state.unit_by_id("trainer").hp = 99
	for turn in CombatConfig.MAX_PLAYER_ROUNDS:
		TurnTestHelper.finish_round(state)
	var reward: Dictionary = run.apply_battle_result(state)
	if state.outcome != "escape" or reward.get("experience", -1) != CombatConfig.EXPERIENCE_PER_KILL or run.roster[1]["experience"] != CombatConfig.EXPERIENCE_PER_KILL or not run.apply_battle_result(state).is_empty():
		return _fail("Partial kill reward during escape was missing or duplicated")
	run = RunState.new()
	state = BattleState.new(run)
	state.unit_by_id("trainer").hp = 1
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").cell = Vector2i(0, 3)
	TurnTestHelper.finish_round(state)
	reward = run.apply_battle_result(state)
	if state.outcome != "defeat" or reward.get("experience", -1) != 0 or run.total_experience != 0:
		return _fail("Defeat incorrectly awarded experience")
	return true


func _test_full_roster_resolution() -> bool:
	for choice in ["replace", "decline"]:
		var run := RunState.new()
		for index in 3:
			run.roster.append(MonsterCatalog.make_record("reserve_%d" % index, "fire"))
		var original_ids: Array[String] = []
		for record in run.roster:
			original_ids.append(record["instance_id"])
		var state := BattleState.new(run)
		state.unit_by_id("ally_rock").cell = Vector2i(2, 4)
		var target: CombatUnit = state.unit_by_id("wild_a")
		target.cell = Vector2i(2, 3)
		target.hp = 1
		target.wet = true
		target.move_points = 0
		target.skill_points = 0
		state.unit_by_id("wild_b").hp = 0
		state.unit_by_id("wild_c").hp = 0
		state.capture_rng.seed = _seed_for_roll(state.capture_chance(target), true)
		TurnTestHelper.advance_to_player(state, "trainer")
		if not state.try_capture(target.unit_id):
			return _fail("Full-roster capture fixture failed")
		run.apply_battle_result(state)
		if run.roster.size() != 6 or run.pending_captures.size() != 1 or run.can_start_battle():
			return _fail("Full-roster capture was not held safely before next battle")
		var incoming_id: String = run.pending_captures.front()["instance_id"]
		if choice == "replace":
			if not run.replace_with_pending(incoming_id, "ally_fire") or run.has_roster_member("ally_fire") or not run.has_roster_member(incoming_id) or not run.active_ids.has(incoming_id):
				return _fail("Replacement lost the new monster or did not update deployment")
			for original_id in original_ids:
				if original_id != "ally_fire" and not run.has_roster_member(original_id):
					return _fail("Replacement discarded an unrelated existing monster")
		else:
			if not run.decline_pending(incoming_id) or run.has_roster_member(incoming_id) or run.active_ids != ["ally_fire", "ally_water", "ally_rock"]:
				return _fail("Declining capture changed the original team")
			for original_id in original_ids:
				if not run.has_roster_member(original_id):
					return _fail("Declining capture lost an existing monster")
		if not run.choose_environment_card(run.offered_environment_cards.front()) or run.roster.size() != 6 or not run.pending_captures.is_empty() or not run.can_start_battle() or BattleState.new(run).units.size() != 7:
			return _fail("Full-roster decision did not allow a legal next battle")
	return true


func _test_pending_roster_ui() -> bool:
	var manager: Node = root.get_node("RunManager")
	manager.start_new_run()
	var run: RunState = manager.run_state
	for index in 3:
		run.roster.append(MonsterCatalog.make_record("reserve_%d" % index, "fire"))
	run.pending_captures.append(run.make_capture_record("water"))
	run.last_reward = {"outcome": "victory", "kills": 0, "captures": 1, "escaped": 0, "experience": 1}
	run.battle_count = 1
	run.offered_environment_cards.clear()
	if change_scene_to_file("res://scenes/between_battles.tscn") != OK:
		return _fail("Full-roster UI could not open")
	await process_frame
	await process_frame
	var camp: Control = current_scene
	var next_button := camp.find_child("NextButton", true, false) as Button
	var choice := camp.find_child("ReplaceChoice", true, false) as OptionButton
	var replace_button := camp.find_child("ReplaceButton", true, false) as Button
	var decline_button := camp.find_child("DeclineButton", true, false) as Button
	if next_button == null or choice == null or replace_button == null or decline_button == null or not next_button.disabled or choice.item_count != 6:
		return _fail("Pending capture did not block the next battle or show six replacement choices")
	var captured_id: String = run.pending_captures.front()["instance_id"]
	choice.select(0)
	replace_button.pressed.emit()
	if not run.has_roster_member(captured_id) or run.has_roster_member("ally_fire") or next_button.disabled:
		return _fail("Postbattle replace button did not resolve pending capture")
	run.pending_captures.append(run.make_capture_record("rock"))
	camp.call("_refresh")
	if not next_button.disabled:
		return _fail("Second pending capture did not block battle")
	var preserved_ids: Array[String] = []
	for record in run.roster:
		preserved_ids.append(record["instance_id"])
	decline_button.pressed.emit()
	for instance_id in preserved_ids:
		if not run.has_roster_member(instance_id):
			return _fail("Postbattle decline button removed an existing member")
	if not run.pending_captures.is_empty() or next_button.disabled:
		return _fail("Postbattle decline button did not unblock next battle")
	return true


func _test_capture_ui() -> bool:
	root.get_node("RunManager").start_new_run()
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene failed to open for capture UI")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state: BattleState = battle.get("state")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var capture_button := battle.find_child("CaptureButton", true, false) as Button
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	state.unit_by_id("ally_rock").cell = Vector2i(3, 3)
	var target: CombatUnit = state.unit_by_id("wild_a")
	target.cell = Vector2i(2, 4)
	target.hp = 2
	target.wet = true
	target.move_points = 0
	target.skill_points = 0
	state.capture_rng.seed = _seed_for_roll(state.capture_chance(target), true)
	TurnTestHelper.advance_to_player(state, "trainer")
	battle.set("selected_unit_id", "trainer")
	battle.call("_refresh")
	capture_button = battle.find_child("CaptureButton", true, false) as Button
	capture_button.pressed.emit()
	board.cell_hovered.emit(target.cell)
	if not capture_button.text.contains("捕获") or not capture_button.tooltip_text.contains("周围八格") or not preview.text.contains("可尝试") or not preview.text.contains("100%"):
		return _fail("Capture mode did not show chance and eligibility")
	board.cell_pressed.emit(target.cell)
	var new_ally_skill := battle.find_child("SkillButton_fire_burst", true, false) as Button
	var team_track := battle.find_child("TeamStatusTrack", true, false) as Control
	if not target.is_alive() or target.team != "player" or state.unit_by_id("trainer").capture_points != 0 or state.captured_records.size() != 1 or board.selected_unit_id != target.unit_id or new_ally_skill == null or team_track == null or team_track.get_child_count() != 5:
		return _fail("Capture click did not convert and select the new ally")
	return true


func _test_battle_to_roster_flow() -> void:
	root.get_node("RunManager").start_new_run()
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene failed to open")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state: BattleState = battle.get("state")
	state.unit_by_id("trainer").hp = 99
	for turn in CombatConfig.MAX_PLAYER_ROUNDS:
		TurnTestHelper.finish_round(state)
	battle.call("_refresh")
	var result_button := battle.find_child("ResultButton", true, false) as Button
	if result_button == null or result_button.disabled or not (battle.find_child("StatusLabel", true, false) as Label).text.contains("逃离"):
		_fail("Escape result was not shown in battle UI")
		return
	result_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "BetweenBattles":
		_fail("Postbattle roster scene did not open")
		return
	var next_button := current_scene.find_child("NextButton", true, false) as Button
	var card_row := current_scene.find_child("CardRow", true, false) as HBoxContainer
	if next_button == null or card_row == null or card_row.get_child_count() != 3 or not next_button.disabled:
		_fail("Environment card choices were not offered after battle")
		return
	(card_row.get_child(0) as Button).pressed.emit()
	if next_button.disabled:
		_fail("Selecting a card did not unlock the next battle")
		return
	next_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "Battle" or root.get_node("RunManager").run_state.battle_count != 1:
		_fail("Next battle did not preserve the current run")
		return
	print("STAGE4_CAPTURE_FLOW passed")
	quit(0)


func _fail(message: String) -> bool:
	push_error("STAGE4_CAPTURE_FLOW failed: " + message)
	quit(1)
	return false
