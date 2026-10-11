extends SceneTree

const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_directions_and_edge():
		return
	if not _test_player_wall_expires_and_restores_ground():
		return
	if not _test_enemy_wall_waits_until_next_enemy_phase():
		return
	if not _test_enemy_chooses_wall():
		return
	if not await _test_click_on_ally():
		return
	print("TEMPORARY_ROCK_WALL passed")
	quit(0)


func _test_directions_and_edge() -> bool:
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for direction in directions:
		var state := BattleState.new()
		state.terrain.objects.clear()
		var rock: CombatUnit = state.unit_by_id("ally_rock")
		rock.cell = Vector2i(4, 4)
		var target: Vector2i = rock.cell + direction
		var sideways := Vector2i(-direction.y, direction.x)
		var expected: Array[Vector2i] = [target - sideways, target, target + sideways]
		if state.can_use_skill(rock, "rock_create", rock.cell) or state.can_use_skill(rock, "rock_create", rock.cell + Vector2i(1, 1)):
			return _fail("Self or diagonal rock target was accepted")
		if EnvironmentResolver.skill_area(state, "rock_create", target, rock.cell) != expected:
			return _fail("Rock wall did not run perpendicular to the chosen direction")
		if not state.try_use_skill(rock.unit_id, "rock_create", target):
			return _fail("Rock wall could not be cast in a cardinal direction")
		for cell in expected:
			if not state.terrain.blocks_move(cell) or int(state.terrain.object_at(cell).get("expire_after_enemy_round", -1)) != state.turn_number:
				return _fail("Three temporary rocks were not placed with the expected expiry")
	var edge_state := BattleState.new()
	edge_state.terrain.objects.clear()
	var edge_rock: CombatUnit = edge_state.unit_by_id("ally_rock")
	edge_rock.cell = Vector2i(0, 0)
	var edge_target := Vector2i(1, 0)
	if EnvironmentResolver.skill_area(edge_state, "rock_create", edge_target, edge_rock.cell) != [Vector2i(1, 0), Vector2i(1, 1)]:
		return _fail("Out-of-bounds part of the wall was not clipped")
	return true


func _test_player_wall_expires_and_restores_ground() -> bool:
	var state := BattleState.new()
	state.terrain.objects.clear()
	state.terrain.objects[Vector2i(0, 7)] = TerrainManager.make_rock()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(4, 4)
	state.terrain.ground[Vector2i(3, 3)] = "shallow_water"
	if not state.try_use_skill(rock.unit_id, "rock_create", Vector2i(4, 3)):
		return _fail("Player wall cast failed")
	if state.terrain.is_shallow_water(Vector2i(3, 3)) or not state.terrain.blocks_move(Vector2i(3, 3)):
		return _fail("Temporary rock did not cover underlying water")
	state.terrain.damage_object(Vector2i(4, 3), 2)
	if not state.terrain.object_at(Vector2i(4, 3)).is_empty():
		return _fail("Destroyed temporary rock was not removed")
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	if not state.finish_player_turn() or state.turn_number != 2:
		return _fail("Player wall fixture did not complete enemy phase")
	if not state.terrain.is_shallow_water(Vector2i(3, 3)) or not state.terrain.object_at(Vector2i(3, 3)).is_empty() or not state.terrain.object_at(Vector2i(5, 3)).is_empty() or state.terrain.object_at(Vector2i(0, 7)).get("type", "") != "rock":
		return _fail("Player wall did not disappear after enemy phase and restore terrain")
	return true


func _test_enemy_wall_waits_until_next_enemy_phase() -> bool:
	var state := BattleState.new()
	state.terrain.objects.clear()
	var rock: CombatUnit = state.unit_by_id("wild_c")
	rock.cell = Vector2i(4, 4)
	state.phase = "enemy_attack"
	if not state.try_use_skill(rock.unit_id, "rock_create", Vector2i(4, 3)):
		return _fail("Enemy wall cast failed")
	if int(state.terrain.object_at(Vector2i(4, 3)).get("expire_after_enemy_round", -1)) != 2:
		return _fail("Enemy wall expiry was not deferred to the following enemy phase")
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	state.phase = "player"
	if not state.finish_player_turn() or state.turn_number != 2 or not state.terrain.blocks_move(Vector2i(4, 3)):
		return _fail("Enemy wall disappeared before player could respond")
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	if not state.finish_player_turn() or not state.terrain.object_at(Vector2i(4, 3)).is_empty():
		return _fail("Enemy wall remained after the following enemy phase")
	return true


func _test_enemy_chooses_wall() -> bool:
	var state := BattleState.new()
	state.terrain.objects.clear()
	var rock: CombatUnit = state.unit_by_id("wild_c")
	rock.cell = Vector2i(4, 4)
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(3, 3)
	state.phase = "enemy_attack"
	EnemyAI.new().attack_phase(state, [rock.unit_id])
	var placed := false
	for object in state.terrain.objects.values():
		if object.has("expire_after_enemy_round"):
			placed = true
	if trainer.hp != trainer.max_hp - 2 or rock.skill_points != 0 or not placed:
		return _fail("Enemy AI did not use a directional wall to hit the trainer")
	return true


func _test_click_on_ally() -> bool:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle UI scene could not open")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	state.terrain.objects.clear()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	var ally: CombatUnit = state.unit_by_id("ally_fire")
	rock.cell = Vector2i(4, 4)
	ally.cell = Vector2i(4, 3)
	battle.set("state", state)
	battle.set("selected_unit_id", rock.unit_id)
	battle.set("action_mode", "skill:rock_create")
	battle.call("_refresh")
	var board: BattleBoard = battle.find_child("BattleBoard", true, false)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = board.get_cell_rect(ally.cell).get_center()
	board._gui_input(event)
	if rock.skill_points != 0 or ally.hp != ally.max_hp - 2 or battle.get("selected_unit_id") != rock.unit_id:
		return _fail("Clicking an allied direction did not cast without switching selection")
	return true


func _fail(message: String) -> bool:
	push_error("TEMPORARY_ROCK_WALL failed: " + message)
	quit(1)
	return false
