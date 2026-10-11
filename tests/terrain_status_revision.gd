extends SceneTree

const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_wet_timing():
		return
	if not _test_fire_wave():
		return
	if not _test_fragile_ground():
		return
	await _test_selection_and_preview()


func _test_wet_timing() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var water: CombatUnit = state.unit_by_id("ally_water")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	trainer.cell = Vector2i(3, 1)
	fire.cell = Vector2i(3, 2)
	water.cell = Vector2i(4, 2)
	enemy.cell = Vector2i(3, 3)
	enemy.skill_points = 0
	state.terrain.objects[Vector2i(3, 4)] = TerrainManager.make_rock()
	state.terrain.objects[Vector2i(4, 3)] = TerrainManager.make_rock()
	state.terrain.ground[enemy.cell] = "shallow_water"
	state.terrain.ground[trainer.cell] = "shallow_water"
	state.terrain.ground[fire.cell] = "shallow_water"
	if trainer.wet or fire.wet or enemy.wet or water.wet:
		return _fail("Water applied wet before the end-of-round settlement")
	if not TurnTestHelper.finish_round(state) or state.turn_number != 2 or not trainer.wet or not fire.wet or not enemy.wet or water.wet:
		return _fail("Settlement did not assign wet to non-water units only")
	if trainer.move_points != 2 or fire.move_points != 2 or water.move_points != 3 or state.effective_move_range(enemy) != 2 or enemy.skill_points != 1:
		return _fail("Wet did not reduce only next-round movement")
	enemy.eligible_round = 99
	if not TurnTestHelper.advance_to_player(state, "trainer") or not state.try_player_move("trainer", Vector2i(2, 1)) or not trainer.wet:
		return _fail("Wet disappeared immediately after leaving water")
	if not TurnTestHelper.finish_round(state) or state.turn_number != 3 or trainer.wet or trainer.move_points != 3 or not enemy.wet:
		return _fail("Wet did not expire on land or refresh in water")
	return true


func _test_fire_wave() -> bool:
	var state := BattleState.new()
	for x in range(3, 7):
		state.terrain.ground[Vector2i(x, 3)] = "grass"
	if not state.terrain.ignite_plant(Vector2i(3, 3)) or state.terrain.is_burning(Vector2i(4, 3)):
		return _fail("Ignition spread before settlement")
	_settle(state)
	if not state.terrain.is_burning(Vector2i(3, 3)) or not state.terrain.is_burning(Vector2i(4, 3)) or state.terrain.is_burning(Vector2i(5, 3)):
		return _fail("First fire wave spread farther than one cell")
	_settle(state)
	if state.terrain.is_flammable(Vector2i(3, 3)) or not state.terrain.is_burning(Vector2i(5, 3)) or state.terrain.is_burning(Vector2i(6, 3)):
		return _fail("Second fire wave or two-settlement destruction was wrong")
	_settle(state)
	if not state.terrain.is_burning(Vector2i(6, 3)):
		return _fail("Fire failed to move across the connected grass")
	_settle(state)
	_settle(state)
	if not state.terrain.burning.is_empty():
		return _fail("Fire failed to expire after a bounded number of settlements")
	state = BattleState.new()
	state.terrain.ground[Vector2i(3, 4)] = "grass"
	state.terrain.ground[Vector2i(4, 4)] = "grass"
	state.terrain.ignite_plant(Vector2i(3, 4))
	if not state.terrain.set_water(Vector2i(3, 4)) or state.terrain.is_burning(Vector2i(3, 4)):
		return _fail("Water did not extinguish fire")
	_settle(state)
	if state.terrain.is_burning(Vector2i(4, 4)):
		return _fail("Extinguished fire still spread")
	state = BattleState.new()
	state.unit_by_id("ally_water").cell = Vector2i(1, 4)
	state.terrain.objects[Vector2i(3, 4)] = TerrainManager.make_plant()
	state.terrain.ignite_plant(Vector2i(3, 4))
	TurnTestHelper.advance_to_player(state, "ally_water")
	if not state.try_use_skill("ally_water", "water_flow", Vector2i(3, 4)) or state.terrain.is_burning(Vector2i(3, 4)) or state.terrain.object_at(Vector2i(3, 4)).get("burning", true):
		return _fail("Water flow did not extinguish a burning plant")
	return true


func _test_fragile_ground() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var trainer: CombatUnit = state.unit_by_id("trainer")
	fire.cell = Vector2i(1, 3)
	trainer.cell = Vector2i(4, 4)
	state.unit_by_id("ally_rock").cell = Vector2i(0, 0)
	state.terrain.ground[trainer.cell] = "fragile"
	if not state.try_use_skill(fire.unit_id, "fire_burst", Vector2i(4, 3)) or not state.terrain.is_collapsed(trainer.cell) or trainer.is_alive():
		return _fail("Fireball splash should collapse fragile ground beneath trainer")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(1, 1)
	var victim: CombatUnit = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 1)
	state.terrain.ground[Vector2i(4, 2)] = "fragile"
	if not state.try_use_skill(fire.unit_id, "fire_burst", victim.cell) or not state.terrain.is_collapsed(victim.cell) or victim.is_alive() or not state.terrain.is_collapsed(Vector2i(4, 2)):
		return _fail("Occupied fireball center should collapse center and adjacent fragile ground")
	state = BattleState.new()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 4)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	state.terrain.ground[Vector2i(4, 3)] = "fragile"
	state.terrain.ground[Vector2i(3, 3)] = "fragile"
	TurnTestHelper.advance_to_player(state, "ally_rock")
	if not state.try_use_skill(rock.unit_id, "rock_create", Vector2i(4, 3)) or victim.is_alive() or not state.terrain.is_collapsed(Vector2i(4, 3)) or not state.terrain.is_collapsed(Vector2i(3, 3)) or not state.terrain.object_at(Vector2i(3, 3)).is_empty():
		return _fail("Rock creation did not collapse empty and occupied fragile cells")
	for skill_id in ["water_flow", "electric_arc", "rock_break"]:
		state = BattleState.new()
		state.terrain.ground[Vector2i(3, 3)] = "fragile"
		var caster: CombatUnit = state.unit_by_id("ally_rock") if skill_id == "rock_break" else state.unit_by_id("ally_water")
		caster.cell = Vector2i(2, 3)
		state.unit_by_id("wild_a").cell = Vector2i(3, 3)
		TurnTestHelper.advance_to_player(state, caster.unit_id)
		if not state.try_use_skill(caster.unit_id, skill_id, Vector2i(3, 3)) or not state.terrain.is_fragile(Vector2i(3, 3)):
			return _fail("Horizontal skill unexpectedly collapsed fragile ground: " + skill_id)
	state = BattleState.new()
	rock = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(2, 3)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(3, 3)
	victim.move_points = 0
	victim.skill_points = 0
	state.terrain.ground[Vector2i(4, 3)] = "fragile"
	TurnTestHelper.advance_to_player(state, "ally_rock")
	if not state.try_use_skill(rock.unit_id, "rock_push", victim.cell) or not state.terrain.is_fragile(victim.cell) or not victim.is_alive():
		return _fail("Sideways push unexpectedly collapsed fragile ground")
	state = BattleState.new()
	rock = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(2, 3)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(3, 3)
	victim.move_points = 0
	victim.skill_points = 0
	state.terrain.ground[Vector2i(4, 3)] = "collapsed"
	TurnTestHelper.advance_to_player(state, "ally_rock")
	if not state.try_use_skill(rock.unit_id, "rock_push", victim.cell) or victim.is_alive():
		return _fail("Pushing a ground unit into a permanent pit did not kill it")
	state = BattleState.new()
	rock = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 4)
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(4, 3)
	state.terrain.ground[fire.cell] = "fragile"
	state._apply_reward_buff(fire, "flying")
	TurnTestHelper.advance_to_player(state, "ally_rock")
	if not state.try_use_skill(rock.unit_id, "rock_create", Vector2i(4, 3)) or not fire.is_alive():
		return _fail("Flying unit died when fragile ground collapsed")
	return true


func _test_selection_and_preview() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle UI could not open")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	battle.set("state", state)
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	board.cell_pressed.emit(state.unit_by_id("ally_fire").cell)
	var fire_button := battle.find_child("SkillButton_fire_burst", true, false) as Button
	if fire_button == null:
		_fail("Fire skill button is missing")
		return
	fire_button.pressed.emit()
	board.cell_hovered.emit(Vector2i(4, 2))
	if board.action_mode != "skill:fire_burst" or not preview.text.contains("将塌陷"):
		_fail("Fireball preview did not show fragile collapse")
		return
	var cancel_aim := InputEventKey.new()
	cancel_aim.pressed = true
	cancel_aim.keycode = KEY_ESCAPE
	battle.call("_unhandled_input", cancel_aim)
	board.cell_pressed.emit(state.unit_by_id("ally_water").cell)
	if board.selected_unit_id != "ally_water" or board.action_mode != "move":
		_fail("Canceling aim did not allow selecting another ally")
		return
	board.cell_pressed.emit(state.unit_by_id("ally_rock").cell)
	TurnTestHelper.advance_to_player(state, "ally_rock")
	battle.call("_refresh")
	var rock_button := battle.find_child("SkillButton_rock_create", true, false) as Button
	rock_button.pressed.emit()
	board.cell_pressed.emit(state.unit_by_id("ally_rock").cell + Vector2i.UP)
	if state.unit_by_id("ally_rock").skill_points != 0:
		_fail("Clicking a direction did not cast rock creation")
		return
	print("TERRAIN_STATUS_REVISION passed")
	quit(0)


func _settle(state: BattleState) -> void:
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()


func _fail(message: String) -> bool:
	push_error("TERRAIN_STATUS_REVISION failed: " + message)
	quit(1)
	return false
