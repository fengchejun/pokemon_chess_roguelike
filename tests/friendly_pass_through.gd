extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_ally_corridor():
		return
	if not _test_enemy_and_terrain_still_block():
		return
	print("FRIENDLY_PASS_THROUGH passed")
	quit(0)


func _test_ally_corridor() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	var start: Vector2i = trainer.cell
	var occupied: Vector2i = rock.cell
	var destination := Vector2i(3, 3)
	if state.can_player_move(trainer, occupied) or state.try_player_move(trainer.unit_id, occupied) or trainer.move_points != 3:
		return _fail("Occupied ally cell was accepted as a destination")
	var route: Array[Vector2i] = state.get_move_path(trainer, destination)
	if route != [occupied, destination]:
		return _fail("Shortest player route did not pass through the ally")
	if not state.try_player_move(trainer.unit_id, destination) or trainer.cell != destination or rock.cell != occupied or state.unit_at(occupied) != rock:
		return _fail("Player movement did not pass through ally without ending in overlap")
	if trainer.move_points != 0 or state.try_player_move(trainer.unit_id, Vector2i(4, 3)):
		return _fail("One-move limit changed after passing through ally")
	if not state.undo_last_move() or trainer.cell != start or rock.cell != occupied or trainer.move_points != 3:
		return _fail("Undo did not restore movement through ally")
	return true


func _test_enemy_and_terrain_still_block() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	rock.cell = Vector2i(5, 7)
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(2, 3)
	if not state.get_move_path(trainer, Vector2i(3, 3)).is_empty():
		return _fail("Player route passed through an enemy")
	state = BattleState.new()
	trainer = state.unit_by_id("trainer")
	state.terrain.ground[Vector2i(2, 3)] = "collapsed"
	if not state.get_move_path(trainer, Vector2i(3, 3)).is_empty():
		return _fail("Player route passed through a pit occupied by an ally")
	state = BattleState.new()
	enemy = state.unit_by_id("wild_a")
	var other_enemy: CombatUnit = state.unit_by_id("wild_b")
	enemy.cell = Vector2i(5, 0)
	other_enemy.cell = Vector2i(4, 0)
	if state.enemy_move_cells(enemy).has(Vector2i(3, 0)):
		return _fail("Enemy incorrectly passed through another enemy")
	return true


func _fail(message: String) -> bool:
	push_error("FRIENDLY_PASS_THROUGH failed: " + message)
	quit(1)
	return false
