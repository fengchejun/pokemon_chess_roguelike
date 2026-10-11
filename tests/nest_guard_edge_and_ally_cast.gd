extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_nest_guard():
		return
	if not _test_push_at_edge():
		return
	if not await _test_ally_cast_click():
		return
	print("NEST_GUARD_EDGE_ALLY_CAST passed")
	quit(0)


func _test_nest_guard() -> bool:
	var state := BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	var guard: CombatUnit = state.unit_by_id("wild_a")
	guard.cell = state.nest["exit"]
	if not state.nest_exit_guarded():
		return _fail("Enemy on the exit did not guard the nest")
	state.hit_cell(state.nest["cell"], 1, "测试攻击")
	if state.nest["hp"] != 3:
		return _fail("One damage reduced a guarded nest")
	state.hit_cell(state.nest["cell"], 2, "测试攻击")
	if state.nest["hp"] != 2:
		return _fail("Guarded nest did not reduce two damage to one")
	guard.team = "player"
	if state.nest_exit_guarded():
		return _fail("A player unit incorrectly guarded the nest")
	state.hit_cell(state.nest["cell"], 1, "测试攻击")
	if state.nest["hp"] != 1:
		return _fail("Nest defense remained after enemy changed sides")
	guard.cell = Vector2i(5, 1)
	state.hit_cell(state.nest["cell"], 1, "测试攻击")
	if state.nest["hp"] != 0 or state.outcome != "victory":
		return _fail("Unguarded nest did not take full damage and end battle")
	return true


func _test_push_at_edge() -> bool:
	var state := BattleState.new()
	state.terrain.objects.clear()
	state.unit_by_id("wild_c").hp = 0
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	var target: CombatUnit = state.unit_by_id("wild_a")
	rock.cell = Vector2i(6, 3)
	target.cell = Vector2i(7, 3)
	var preview: Dictionary = state.preview_skill_push(rock, "rock_push", target.cell)
	if preview.get("destination") != Vector2i(7, 3) or int(preview.get("collision_damage", -1)) != 0 or int(preview.get("target_damage", -1)) != 2:
		return _fail("Edge push preview still added collision damage")
	if not state.try_use_skill(rock.unit_id, "rock_push", target.cell) or target.hp != target.max_hp - 2 or target.cell != Vector2i(7, 3):
		return _fail("Rock push at the edge did not match its preview")
	state = BattleState.new()
	state.terrain.objects.clear()
	state.unit_by_id("wild_c").hp = 0
	var water: CombatUnit = state.unit_by_id("ally_water")
	target = state.unit_by_id("wild_a")
	water.cell = Vector2i(5, 3)
	water.upgraded_skill_id = "water_flow"
	target.cell = Vector2i(6, 3)
	preview = state.preview_skill_push(water, "water_flow", target.cell)
	if preview.get("destination") != Vector2i(7, 3) or int(preview.get("collision_damage", -1)) != 0:
		return _fail("Two-cell water push preview added edge collision damage")
	if not state.try_use_skill(water.unit_id, "water_flow", target.cell) or target.cell != Vector2i(7, 3) or target.hp != target.max_hp - 1:
		return _fail("Water push at the edge did not match its preview")
	return true


func _test_ally_cast_click() -> bool:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene could not open")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var board: BattleBoard = battle.find_child("BattleBoard", true, false)
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
	board.cell_pressed.emit(ally.cell)
	if rock.skill_points != 0 or ally.hp != ally.max_hp - 2 or battle.get("selected_unit_id") != rock.unit_id or battle.get("action_mode") != "move":
		return _fail("Clicking an allied rock-wall direction selected the ally instead of casting")
	state = BattleState.new()
	state.terrain.objects.clear()
	var water: CombatUnit = state.unit_by_id("ally_water")
	var trainer: CombatUnit = state.unit_by_id("trainer")
	water.cell = Vector2i(3, 3)
	trainer.cell = Vector2i(4, 3)
	battle.set("state", state)
	battle.set("selected_unit_id", water.unit_id)
	battle.set("action_mode", "skill:rain_call")
	battle.call("_refresh")
	board.cell_pressed.emit(trainer.cell)
	if water.skill_points != 0 or not state.terrain.is_shallow_water(trainer.cell) or battle.get("selected_unit_id") != water.unit_id:
		return _fail("Clicking an allied rain center did not cast")
	state = BattleState.new()
	state.terrain.objects.clear()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	water = state.unit_by_id("ally_water")
	battle.set("state", state)
	battle.set("selected_unit_id", fire.unit_id)
	battle.set("action_mode", "skill:fire_burst")
	battle.call("_refresh")
	board.cell_pressed.emit(water.cell)
	if fire.skill_points != 0 or water.hp != water.max_hp - 2 or battle.get("selected_unit_id") != fire.unit_id:
		return _fail("A valid allied fireball target switched selection instead of casting")
	return true


func _fail(message: String) -> bool:
	push_error("NEST_GUARD_EDGE_ALLY_CAST failed: " + message)
	quit(1)
	return false
