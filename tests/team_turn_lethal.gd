extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_voluntary_entry():
		return
	if not _test_forced_entry_and_collapse():
		return
	print("TEAM_TURN_LETHAL passed")
	quit(0)


func _test_voluntary_entry() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 1)
	state.terrain.ground[Vector2i(4, 1)] = "deep_water"
	if state.can_player_move(fire, Vector2i(4, 1)) or not state.get_move_path(fire, Vector2i(5, 1)).is_empty() or state.try_player_move(fire.unit_id, Vector2i(4, 1)) or fire.move_points != 3 or fire.cell != Vector2i(3, 1):
		return _fail("Non-water ally entered deep water or crossed it within the move limit")
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.cell = Vector2i(3, 4)
	state.terrain.ground[Vector2i(4, 4)] = "deep_water"
	if not state.try_player_move(water.unit_id, Vector2i(4, 4)) or not water.is_alive() or water.cell != Vector2i(4, 4):
		return _fail("Water ally could not voluntarily enter deep water")
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(3, 6)
	state.terrain.ground[Vector2i(4, 6)] = "collapsed"
	if state.can_player_move(trainer, Vector2i(4, 6)) or state.try_player_move(trainer.unit_id, Vector2i(4, 6)) or trainer.move_points != 3:
		return _fail("Trainer entered a pit or lost movement on a rejected command")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 0)
	state.terrain.ground[Vector2i(4, 0)] = "deep_water"
	state.phase = "enemy_move"
	if state.enemy_move_cells(enemy).has(Vector2i(4, 0)) or state.enemy_move(enemy, Vector2i(4, 0)) or enemy.move_points != 3:
		return _fail("Non-water enemy entered deep water or spent its movement")
	var water_enemy: CombatUnit = state.unit_by_id("wild_b")
	water_enemy.cell = Vector2i(5, 5)
	state.terrain.ground[Vector2i(5, 6)] = "deep_water"
	if not state.enemy_move_cells(water_enemy).has(Vector2i(5, 6)) or not state.enemy_move(water_enemy, Vector2i(5, 6)) or not water_enemy.is_alive():
		return _fail("Water enemy could not voluntarily enter deep water")
	return true


func _test_forced_entry_and_collapse() -> bool:
	var state := BattleState.new()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(2, 3)
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 3)
	state.terrain.ground[Vector2i(4, 3)] = "collapsed"
	if not state.try_use_skill(rock.unit_id, "rock_push", enemy.cell) or enemy.is_alive():
		return _fail("Forced push into a pit did not kill the target")
	state = BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.cell = Vector2i(1, 0)
	enemy = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 0)
	state.terrain.ground[Vector2i(4, 0)] = "deep_water"
	if not state.try_use_skill(water.unit_id, "water_flow", enemy.cell) or enemy.is_alive():
		return _fail("Forced water push into deep water did not drown the target")
	state = BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(1, 0)
	enemy = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(4, 0)
	state.terrain.ground[enemy.cell] = "fragile"
	if not state.try_use_skill(fire.unit_id, "fire_burst", enemy.cell) or enemy.is_alive() or not state.terrain.is_collapsed(enemy.cell):
		return _fail("Fireball should collapse an occupied fragile tile")
	return true


func _fail(message: String) -> bool:
	push_error("TEAM_TURN_LETHAL failed: " + message)
	quit(1)
	return false
