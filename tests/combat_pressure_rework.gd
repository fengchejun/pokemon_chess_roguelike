extends SceneTree

const TerrainManager = preload("res://scripts/terrain_manager.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_water_and_burning():
		return
	if not _test_fire_and_water_skills():
		return
	if not _test_rock_and_nest():
		return
	if not _test_reward_and_aggro():
		return
	await _test_ui()


func _test_water_and_burning() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var water: CombatUnit = state.unit_by_id("ally_water")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	state.terrain.ground[Vector2i(3, 3)] = "shallow_water"
	enemy.cell = Vector2i(3, 3)
	state.phase = "enemy_move"
	if not state.enemy_move(enemy, Vector2i(4, 3)):
		return _fail("Shallow water slowed enemy before settlement")
	enemy.cell = Vector2i(3, 3)
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	state.turn_number += 1
	enemy.move_points = state.effective_move_range(enemy)
	if not enemy.wet or enemy.move_points != 2 or state.enemy_move_cells(enemy).is_empty() or not state.enemy_move(enemy, Vector2i(4, 3)):
		return _fail("Wet debuff did not reduce enemy movement by one after settlement")
	enemy.cell = Vector2i(3, 3)
	state.unit_by_id("wild_b").cell = Vector2i(4, 4)
	if not state.enemy_move(state.unit_by_id("wild_b"), Vector2i(4, 3)):
		return _fail("Water enemy was slowed in shallow water")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 3)
	state.terrain.ground[Vector2i(4, 3)] = "deep_water"
	if state.try_player_move(fire.unit_id, Vector2i(4, 3)) or not fire.is_alive() or fire.move_points == 0 or state.can_undo_move():
		return _fail("Voluntary deep-water move was accepted or consumed resources")
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(3, 3)
	fire.cell = Vector2i(1, 2)
	TurnTestHelper.advance_to_player(state, "ally_water")
	if not state.try_player_move(water.unit_id, Vector2i(4, 3)) or not water.is_alive():
		return _fail("Water monster did not survive deep water")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(3, 3)
	state.terrain.ground[Vector2i(3, 3)] = "grass"
	state.terrain.ground[Vector2i(4, 3)] = "grass"
	state.terrain.objects[Vector2i(5, 3)] = TerrainManager.make_plant()
	if not state.terrain.ignite_plant(Vector2i(3, 3)) or state.terrain.is_burning(Vector2i(4, 3)) or state.terrain.is_burning(Vector2i(5, 3)):
		return _fail("Connected flammables ignited instantly")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if not water.burned or water.hp != water.max_hp or not state.terrain.is_flammable(Vector2i(3, 3)) or not state.terrain.is_burning(Vector2i(4, 3)) or state.terrain.is_burning(Vector2i(5, 3)):
		return _fail("First burning settlement spread too far or destroyed early")
	state.turn_number += 1
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if water.hp != water.max_hp - 1 or state.terrain.is_flammable(Vector2i(3, 3)) or not state.terrain.is_burning(Vector2i(5, 3)):
		return _fail("Second burning settlement or debuff tick was wrong")
	state.terrain.ground[Vector2i(4, 3)] = "shallow_water"
	state.phase = "player"
	water.move_points = 3
	TurnTestHelper.advance_to_player(state, "ally_water")
	if not state.try_player_move(water.unit_id, Vector2i(4, 3)) or water.burned:
		return _fail("Entering water did not clear burning debuff")
	return true


func _test_fire_and_water_skills() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	fire.cell = Vector2i(1, 0)
	enemy.cell = Vector2i(4, 0)
	if state.can_use_skill(fire, "fire_burst", Vector2i(2, 0)) or not state.can_use_skill(fire, "fire_burst", enemy.cell) or EnvironmentResolver.skill_area(state, "fire_burst", enemy.cell).size() != 1:
		return _fail("Fire blind spot or occupied-center collapse failed")
	state.terrain.objects[Vector2i(2, 0)] = TerrainManager.make_rock()
	if state.can_use_skill(fire, "fire_burst", enemy.cell) or state.projected_skill_impact(fire, "fire_burst", enemy.cell) != Vector2i(-1, -1):
		return _fail("Adjacent obstacle did not activate fire blind spot")
	state.terrain.add_steam(fire.cell)
	if state.can_use_skill(fire, "fire_burst", enemy.cell):
		return _fail("Fog failed to suppress fire skill")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(1, 0)
	var splash_a: CombatUnit = state.unit_by_id("wild_a")
	var splash_b: CombatUnit = state.unit_by_id("wild_b")
	splash_a.cell = Vector2i(4, 1)
	splash_b.cell = Vector2i(5, 0)
	state.terrain.ground.erase(Vector2i(4, 1))
	if EnvironmentResolver.skill_area(state, "fire_burst", Vector2i(4, 0)).size() != 4 or not state.try_use_skill(fire.unit_id, "fire_burst", Vector2i(4, 0)) or splash_a.hp != splash_a.max_hp - 1 or splash_b.hp != splash_b.max_hp - 1:
		return _fail("Empty-center fire cross did not affect its neighboring cells")
	state = BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.cell = Vector2i(1, 3)
	state.unit_by_id("ally_rock").cell = Vector2i(0, 0)
	enemy = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(6, 3)
	if state.projected_skill_impact(water, "water_flow", enemy.cell) != Vector2i(5, 3):
		return _fail("Rock did not intercept long-range water flow")
	enemy.cell = Vector2i(4, 3)
	TurnTestHelper.advance_to_player(state, "ally_water")
	if not state.try_use_skill(water.unit_id, "water_flow", enemy.cell) or enemy.cell != Vector2i(4, 3) or enemy.hp != enemy.max_hp - 2 or state.terrain.object_at(Vector2i(5, 3)).get("hp", 0) != 1 or state.terrain.is_shallow_water(enemy.cell) or not enemy.wet:
		return _fail("Water flow collision or direct wet failed")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(1, 0)
	enemy = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 0)
	enemy.wet = true
	enemy.move_points = 0
	enemy.skill_points = 0
	state.terrain.ground[Vector2i(4, 0)] = "deep_water"
	TurnTestHelper.advance_to_player(state, "ally_water")
	if not state.try_use_skill(water.unit_id, "water_flow", enemy.cell) or enemy.is_alive():
		return _fail("Water push into deep water did not drown target")
	return true


func _test_rock_and_nest() -> bool:
	var state := BattleState.new()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 4)
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 4)
	enemy.wet = true
	enemy.move_points = 0
	enemy.skill_points = 0
	TurnTestHelper.advance_to_player(state, "ally_rock")
	if not state.try_use_skill(rock.unit_id, "rock_create", Vector2i(3, 4)) or enemy.hp != enemy.max_hp - 2 or not state.terrain.blocks_move(Vector2i(3, 3)) or not state.terrain.blocks_move(Vector2i(3, 5)) or state.terrain.object_at(Vector2i(5, 4)).get("type", "") != "plant":
		return _fail("Directional three-cell rock wall failed")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.unit_by_id("trainer").hp = 99
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("wild_b").move_points = 0
	if not TurnTestHelper.finish_round(state) or state.turn_number != 2 or state.unit_by_id("nest_2_1") == null:
		return _fail("Nest did not spawn at round two start")
	TurnTestHelper.finish_round(state)
	state.terrain.objects[Vector2i(6, 1)] = TerrainManager.make_rock()
	state.terrain.objects[Vector2i(6, 1)]["hp"] = 99
	TurnTestHelper.finish_round(state)
	if state.unit_by_id("nest_4_2") != null:
		return _fail("Blocked nest exit still produced enemy")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	for unit in state.units:
		if unit.team == "enemy":
			unit.hp = 0
	state._check_outcome()
	if state.outcome != "victory" or state.nest["hp"] != 3:
		return _fail("Living nest incorrectly blocked victory")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(5, 2), "exit": Vector2i(6, 2), "hp": 3}
	if not state.try_use_skill("ally_fire", "fire_burst", Vector2i(5, 2)) or state.nest["hp"] != 2:
		return _fail("Damage skill did not harm nest")
	state.hit_cell(Vector2i(5, 2), 2, "测试")
	if state.nest["hp"] != 0:
		return _fail("Nest did not break at zero durability")
	TurnTestHelper.finish_round(state)
	if state.turn_number != 2 or state.spawned_count != 0:
		return _fail("Destroyed nest still spawned an enemy")
	return true


func _test_reward_and_aggro() -> bool:
	var state := BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	state.reward_cell = water.cell
	state.reward_state = "ground"
	state.terrain.ground[water.cell] = "grass"
	state.terrain.ignite_plant(water.cell)
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if state.reward_state != "carried" or not water.burned:
		return _fail("Reward was not picked before environmental damage")
	state.apply_environment_damage(water, water.hp, "测试")
	if state.reward_state != "destroyed":
		return _fail("Carrier death did not destroy reward")
	state = BattleState.new()
	state.reward_cell = Vector2i(4, 3)
	state.reward_state = "ground"
	state.hit_cell(state.reward_cell, 1, "测试")
	if state.reward_state != "destroyed":
		return _fail("Unpicked reward survived damage")
	state = BattleState.new()
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.reward_state = "carried"
	state.reward_carrier_id = "ally_fire"
	state.unit_by_id("wild_a").cell = Vector2i(4, 2)
	state.unit_by_id("trainer").cell = Vector2i(4, 0)
	state.finish_player_turn()
	if state.unit_by_id("ally_fire").hp != state.unit_by_id("ally_fire").max_hp - 2 or state.unit_by_id("trainer").hp != state.unit_by_id("trainer").max_hp:
		return _fail("Enemy did not prioritize a hittable reward carrier")
	var run := RunState.new()
	state = BattleState.new(run)
	state.reward_state = "carried"
	state.reward_carrier_id = "ally_water"
	state.outcome = "victory"
	var reward: Dictionary = run.apply_battle_result(state)
	if not reward.get("bonus_card", false) or not run.pending_bonus_card or run.offered_environment_cards.size() != 3:
		return _fail("Surviving carrier did not grant a second card choice")
	var first_card: String = run.offered_environment_cards[0]
	if not run.choose_environment_card(first_card) or not run.bonus_choice_active or run.offered_environment_cards.size() != 3 or run.can_start_battle():
		return _fail("First card choice did not lead to bonus choice")
	var second_card: String = run.offered_environment_cards[0]
	if not run.choose_environment_card(second_card) or run.environment_cards.size() != 2 or not run.can_start_battle():
		return _fail("Bonus card choice did not finish reward flow")
	return true


func _test_ui() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene did not open")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	battle.set("state", state)
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 4)
	TurnTestHelper.advance_to_player(state, "ally_rock")
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var environment_label := battle.find_child("EnvironmentLabel", true, false) as Label
	if board == null or environment_label == null:
		_fail("New battle UI controls are missing")
		return
	board.cell_pressed.emit(rock.cell)
	var skill_button := battle.find_child("SkillButton_rock_create", true, false) as Button
	if skill_button == null:
		_fail("Rock skill button is missing")
		return
	skill_button.pressed.emit()
	if board.action_mode != "skill:rock_create" or not environment_label.text.contains("巢穴"):
		_fail("Rock creation or nest information was not available in UI")
		return
	board.cell_pressed.emit(Vector2i(4, 3))
	if rock.skill_points != 0 or not state.terrain.blocks_move(Vector2i(4, 3)) or not environment_label.text.contains("岩 3"):
		_fail("Clicking a direction did not create the temporary wall or refresh terrain counts")
		return
	print("COMBAT_PRESSURE_REWORK passed")
	quit(0)


func _fail(message: String) -> bool:
	push_error("COMBAT_PRESSURE_REWORK failed: " + message)
	quit(1)
	return false
