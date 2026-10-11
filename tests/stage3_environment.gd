extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_terrain_and_breaking():
		return
	if not _test_water_electric_and_steam():
		return
	if not _test_enemy_water_damage():
		return
	if not _test_fog_propagation_and_enemy_setup():
		return
	if not _test_reaction_batch():
		return
	if not _test_burning_and_push_collision():
		return
	await _test_skill_ui()


func _test_terrain_and_breaking() -> bool:
	var state := BattleState.new()
	if not state.terrain.is_water(Vector2i(3, 2)) or not state.terrain.is_fragile(Vector2i(4, 4)) or not state.terrain.blocks_move(Vector2i(5, 3)):
		return _fail("Initial terrain types are wrong")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(4, 3)
	if not state.can_use_skill(fire, "fire_burst", Vector2i(6, 3)) or state.projected_skill_impact(fire, "fire_burst", Vector2i(6, 3)) != Vector2i(6, 3):
		return _fail("Fireball could not pass the adjacent rock")
	fire.cell = Vector2i(3, 3)
	if not state.can_use_skill(fire, "fire_burst", Vector2i(6, 3)) or state.projected_skill_impact(fire, "fire_burst", Vector2i(6, 3)) != Vector2i(6, 3):
		return _fail("Fireball did not land beyond the blocking rock")
	fire.cell = Vector2i(1, 2)
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 3)
	if not TurnTestHelper.advance_to_player(state, "ally_rock") or state.can_player_move(rock, Vector2i(5, 3)) or not state.try_use_skill("ally_rock", "rock_break", Vector2i(5, 3)):
		return _fail("Rock obstacle or breaking skill failed")
	if state.terrain.blocks_move(Vector2i(5, 3)) or not state.can_enter_voluntarily(rock, Vector2i(5, 3)) or rock.move_points != 0:
		return _fail("Destroyed rock did not open a path")
	state = BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	var water_target: CombatUnit = state.unit_by_id("wild_a")
	water.cell = Vector2i(2, 4)
	water_target.cell = Vector2i(3, 4)
	water_target.move_points = 0
	water_target.skill_points = 0
	state.terrain.ground.erase(Vector2i(4, 4))
	if not TurnTestHelper.advance_to_player(state, "ally_water") or not state.try_use_skill("ally_water", "water_flow", Vector2i(3, 4)) or state.terrain.is_water(Vector2i(3, 4)) or not water_target.wet or water_target.hp != water_target.max_hp - 1:
		return _fail("Water skill did not deal one damage and apply wet without making water")
	return true


func _test_water_electric_and_steam() -> bool:
	var run := RunState.new()
	run.set_starters(["fire", "electric", "rock"])
	var state := BattleState.new(run)
	var water: CombatUnit = state.unit_by_id("ally_electric")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var first: CombatUnit = state.unit_by_id("wild_a")
	var second: CombatUnit = state.unit_by_id("wild_b")
	water.cell = Vector2i(2, 2)
	fire.cell = Vector2i(3, 2)
	first.cell = Vector2i(3, 1)
	second.cell = Vector2i(4, 2)
	first.wet = true
	first.move_points = 0
	first.skill_points = 0
	if not TurnTestHelper.advance_to_player(state, "ally_electric") or not state.try_use_skill("ally_electric", "electric_arc", Vector2i(3, 2)):
		return _fail("Electric skill could not hit connected water")
	if fire.hp != fire.max_hp - 1 or first.hp != first.max_hp - 1 or second.hp != second.max_hp - 1:
		return _fail("Connected water did not hit each unit exactly once")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(1, 2)
	if not state.try_use_skill("ally_fire", "fire_burst", Vector2i(3, 2)) or not state.terrain.is_steam(Vector2i(3, 2)):
		return _fail("Fire on water did not create steam")
	fire.cell = Vector2i(1, 2)
	fire.skill_points = 1
	if state.can_use_skill(fire, "fire_burst", Vector2i(3, 2)) or not state.can_use_skill(fire, "flame_jet", Vector2i(3, 2)):
		return _fail("Spent fireball became reusable or steam blocked flamethrower from outside")
	fire.cell = Vector2i(3, 2)
	if state.can_use_skill(fire, "flame_jet", Vector2i(5, 2)) or state.can_use_skill(fire, "flame_jet", Vector2i(4, 2)):
		return _fail("Fog failed to suppress flamethrower")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if not state.terrain.is_steam(Vector2i(3, 2)):
		return _fail("Steam ended after only one settlement")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if state.terrain.is_steam(Vector2i(3, 2)):
		return _fail("Steam did not expire after two settlements")
	return true


func _test_enemy_water_damage() -> bool:
	var state := BattleState.new()
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(4, 5)
	if not TurnTestHelper.finish_round(state) or trainer.hp != trainer.max_hp - 1 or state.terrain.is_shallow_water(Vector2i(4, 5)) or not trainer.wet or trainer.cell != Vector2i(3, 5):
		return _fail("Enemy water skill did not damage, push and wet trainer")
	return true


func _test_burning_and_push_collision() -> bool:
	var state := BattleState.new()
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	enemy = state.unit_by_id("wild_a")
	rock.cell = Vector2i(3, 3)
	enemy.cell = Vector2i(4, 3)
	enemy.move_points = 0
	enemy.skill_points = 0
	if not TurnTestHelper.advance_to_player(state, "ally_rock") or not state.try_use_skill("ally_rock", "rock_push", enemy.cell) or enemy.cell != Vector2i(4, 3) or state.terrain.object_at(Vector2i(5, 3)).get("hp", 0) != 1:
		return _fail("Push into rock did not stop and damage obstacle")
	return true


func _test_reaction_batch() -> bool:
	var run := RunState.new()
	run.set_starters(["fire", "electric", "rock"])
	var state := BattleState.new(run)
	state.unit_by_id("ally_electric").cell = Vector2i(2, 1)
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(3, 2)
	trainer.hp = 1
	var last_enemy: CombatUnit = state.unit_by_id("wild_a")
	last_enemy.cell = Vector2i(3, 1)
	last_enemy.hp = 1
	last_enemy.wet = true
	last_enemy.move_points = 0
	last_enemy.skill_points = 0
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	if not TurnTestHelper.advance_to_player(state, "ally_electric") or not state.try_use_skill("ally_electric", "electric_arc", Vector2i(3, 1)):
		return _fail("Batch fixture could not cast electric skill")
	if last_enemy.is_alive() or trainer.is_alive() or state.outcome != "defeat":
		return _fail("Reaction stopped after the first target ended combat")
	return true


func _test_fog_propagation_and_enemy_setup() -> bool:
	var state := BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.cell = Vector2i(3, 2)
	state.terrain.add_steam(water.cell)
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 1)
	enemy.wet = true
	enemy.move_points = 0
	enemy.skill_points = 0
	if not TurnTestHelper.advance_to_player(state, "ally_water") or state.try_use_skill("ally_water", "water_flow", Vector2i(4, 2)) or enemy.hp != enemy.max_hp or water.skill_points != 1:
		return _fail("Steam failed to block water skill without spending resources")
	state = BattleState.new()
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("ally_fire").cell = Vector2i(0, 2)
	state.unit_by_id("trainer").cell = Vector2i(1, 2)
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	state.terrain.add_steam(Vector2i(3, 2))
	state.unit_by_id("wild_a").wet = true
	state.unit_by_id("wild_a").move_points = 0
	TurnTestHelper.finish_round(state)
	if state.unit_by_id("trainer").hp != CombatConfig.TRAINER_HP:
		return _fail("Enemy cast beyond one cell while standing in steam")
	state = BattleState.new()
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("trainer").cell = Vector2i(4, 2)
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	state.terrain.add_steam(Vector2i(3, 2))
	state.unit_by_id("wild_a").wet = true
	state.unit_by_id("wild_a").move_points = 0
	TurnTestHelper.finish_round(state)
	if state.unit_by_id("trainer").hp != CombatConfig.TRAINER_HP:
		return _fail("Enemy fire skill bypassed the fog minimum-range lock")
	state = BattleState.new()
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("trainer").cell = Vector2i(0, 0)
	state.unit_by_id("wild_b").cell = Vector2i(5, 5)
	state.unit_by_id("wild_b").move_points = 0
	TurnTestHelper.finish_round(state)
	if state.terrain.ground.values().count("shallow_water") <= 3:
		return _fail("Enemy water monster did not prepare shallow water")
	state = BattleState.new()
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("trainer").cell = Vector2i(0, 0)
	state.unit_by_id("wild_c").cell = Vector2i(6, 3)
	state.unit_by_id("wild_c").move_points = 0
	TurnTestHelper.finish_round(state)
	if state.terrain.blocks_move(Vector2i(5, 3)):
		return _fail("Enemy rock monster did not clear a blocking rock")
	return true


func _test_skill_ui() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene could not load")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	battle.set("state", BattleState.new())
	battle.call("_refresh")
	var state: BattleState = battle.get("state")
	TurnTestHelper.advance_to_player(state, "ally_water")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	if board == null or preview == null:
		_fail("Skill controls are missing")
		return
	board.cell_pressed.emit(state.unit_by_id("ally_water").cell)
	var button := battle.find_child("SkillButton_water_flow", true, false) as Button
	if button == null:
		_fail("Water skill button is missing")
		return
	state.unit_by_id("ally_water").cell = Vector2i(2, 2)
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	button.pressed.emit()
	board.cell_hovered.emit(Vector2i(3, 2))
	if not button.text.contains("水流") or not preview.text.contains("造成 1 伤"):
		_fail("Water skill UI did not show new damage")
		return
	var electric_run := RunState.new()
	electric_run.set_starters(["fire", "electric", "rock"])
	state = BattleState.new(electric_run)
	battle.set("state", state)
	battle.set("selected_unit_id", "ally_electric")
	state.unit_by_id("ally_electric").cell = Vector2i(2, 2)
	state.unit_by_id("wild_a").cell = Vector2i(3, 2)
	battle.call("_refresh")
	button = battle.find_child("SkillButton_electric_arc", true, false) as Button
	if button == null:
		_fail("Electric monster skill button is missing")
		return
	button.pressed.emit()
	board.cell_hovered.emit(Vector2i(3, 2))
	if not button.text.contains("放电") or not preview.text.contains("影响 3 格"):
		_fail("Electric area preview is missing")
		return
	board.cell_pressed.emit(Vector2i(3, 2))
	if state.unit_by_id("wild_a").hp != CombatConfig.WILD_HP - CombatConfig.ELECTRIC_DAMAGE or state.unit_by_id("ally_electric").skill_points != 0:
		_fail("Skill click did not settle electric damage and cost")
		return
	print("STAGE3_ENVIRONMENT passed")
	quit(0)


func _fail(message: String) -> bool:
	push_error("STAGE3_ENVIRONMENT failed: " + message)
	quit(1)
	return false
