extends SceneTree

const EnemyAI = preload("res://scripts/enemy_ai.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_movement_values_and_paths():
		return
	if not _test_ray_interception():
		return
	if not _test_birth_move():
		return
	await _test_preview()


func _test_preview() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle scene did not open for ray preview")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	state.terrain.objects[Vector2i(3, 2)] = TerrainManager.make_plant()
	battle.set("state", state)
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	board.cell_pressed.emit(state.unit_by_id("ally_fire").cell)
	var skill_button := battle.find_child("SkillButton_fire_burst", true, false) as Button
	if skill_button == null:
		_fail("Fire skill button is missing")
		return
	skill_button.pressed.emit()
	board.cell_hovered.emit(Vector2i(6, 2))
	if board.action_mode != "skill:fire_burst" or not preview.text.contains("被 (4, 3) 遮挡"):
		_fail("Ray preview did not report the actual first impact cell")
		return
	print("ENEMY_APPROACH_LOS passed")
	quit(0)


func _test_movement_values_and_paths() -> bool:
	var state := BattleState.new()
	for pair in [["ally_fire", "wild_a", 3], ["ally_water", "wild_b", 3], ["ally_rock", "wild_c", 2]]:
		if state.unit_by_id(pair[0]).base_move != pair[2] or state.unit_by_id(pair[1]).base_move != pair[2]:
			return _fail("Same-species move values differ")
	if state.unit_by_id("trainer").base_move != 3 or state.unit_by_id("wild_c").cell != Vector2i(6, 3):
		return _fail("Trainer or forward rock deployment is wrong")
	var ally_rock: CombatUnit = state.unit_by_id("ally_rock")
	ally_rock.wet = true
	if state.effective_move_range(ally_rock) != 1 or state.effective_move_range(state.unit_by_id("wild_a")) != 3:
		return _fail("Wet or species movement limit is wrong")
	var rock: CombatUnit = state.unit_by_id("wild_c")
	var route: Array[Vector2i] = EnemyAI.new().plan_move(state, rock)
	if route.is_empty() or route.size() > 2 or route.has(Vector2i(5, 3)):
		return _fail("Rock did not plan a legal detour around its blocking rock")
	state = BattleState.new()
	var fire: CombatUnit = state.unit_by_id("wild_a")
	state.unit_by_id("trainer").cell = Vector2i(1, 2)
	state.unit_by_id("ally_fire").cell = Vector2i(0, 2)
	if not EnemyAI.new().plan_move(state, fire).is_empty():
		return _fail("Ranged fire moved despite a clear line")
	state.terrain.objects[Vector2i(4, 2)] = TerrainManager.make_plant()
	if EnemyAI.new().plan_move(state, fire).is_empty():
		return _fail("Blocked ranged fire did not seek a new firing line")
	state = BattleState.new()
	rock = state.unit_by_id("wild_c")
	state.terrain.objects.erase(Vector2i(5, 3))
	for unit in state.units:
		if unit.team == "player" and unit.unit_id != "trainer":
			unit.cell = Vector2i(0, 7 - state.units.find(unit))
	var forward: Array[Vector2i] = EnemyAI.new().plan_move(state, rock)
	if forward.is_empty() or forward[0] != Vector2i(5, 3):
		return _fail("Rock did not advance toward the trainer despite a range-two skill")
	return true


func _test_ray_interception() -> bool:
	var state := BattleState.new()
	var target: CombatUnit = state.unit_by_id("wild_a")
	state.terrain.objects[Vector2i(3, 2)] = TerrainManager.make_plant()
	if state.projected_skill_impact(state.unit_by_id("ally_fire"), "fire_burst", target.cell) != Vector2i(3, 2) or not state.try_use_skill("ally_fire", "fire_burst", target.cell):
		return _fail("Tree did not intercept fire")
	if target.hp != target.max_hp or state.terrain.object_at(Vector2i(3, 2)).get("hp") != 1 or not state.terrain.is_burning(Vector2i(3, 2)):
		return _fail("Fire did not damage and ignite the intercepted tree")
	state = BattleState.new()
	state.unit_by_id("ally_rock").cell = Vector2i(3, 2)
	if state.projected_skill_impact(state.unit_by_id("ally_fire"), "fire_burst", Vector2i(6, 2)) != Vector2i(3, 2):
		return _fail("Friendly unit did not intercept fire")
	state = BattleState.new()
	state.terrain.objects[Vector2i(3, 4)] = TerrainManager.make_rock()
	var water: CombatUnit = state.unit_by_id("ally_water")
	var impact: Vector2i = state.projected_skill_impact(water, "water_flow", Vector2i(6, 4))
	if impact != Vector2i(3, 4):
		return _fail("Rock did not intercept water")
	if not TurnTestHelper.advance_to_player(state, water.unit_id) or not state.try_use_skill(water.unit_id, "water_flow", Vector2i(6, 4)) or state.terrain.object_at(impact).get("hp") != 1:
		return _fail("Water did not damage its first blocking rock")
	for skill_id in ["fire_burst", "water_flow"]:
		for blocker in ["tree", "rock", "nest", "ally", "enemy"]:
			state = BattleState.new()
			var caster: CombatUnit = state.unit_by_id("ally_fire") if skill_id == "fire_burst" else state.unit_by_id("ally_water")
			caster.cell = Vector2i(1, 2) if skill_id == "fire_burst" else Vector2i(1, 4)
			var barrier: Vector2i = Vector2i(3, caster.cell.y)
			var intended: Vector2i = Vector2i(6, caster.cell.y)
			match blocker:
				"tree": state.terrain.objects[barrier] = TerrainManager.make_plant()
				"rock": state.terrain.objects[barrier] = TerrainManager.make_rock()
				"nest": state.nest = {"cell": barrier, "exit": barrier + Vector2i.LEFT, "hp": 3}
				"ally": state.unit_by_id("ally_rock").cell = barrier
				"enemy": state.unit_by_id("wild_c").cell = barrier
			if state.projected_skill_impact(caster, skill_id, intended) != barrier:
				return _fail("Ray failed to stop at first blocker: %s / %s" % [skill_id, blocker])
			if blocker in ["tree", "rock", "nest"]:
				var old_hp: int = int(state.nest["hp"]) if blocker == "nest" else int(state.terrain.object_at(barrier)["hp"])
				if skill_id == "water_flow" and not TurnTestHelper.advance_to_player(state, caster.unit_id):
					return _fail("Water caster never became active")
				if not state.try_use_skill(caster.unit_id, skill_id, intended):
					return _fail("Intercepted skill could not cast: %s / %s" % [skill_id, blocker])
				var new_hp: int = int(state.nest["hp"]) if blocker == "nest" else int(state.terrain.object_at(barrier).get("hp", 0))
				if new_hp != old_hp - 1:
					return _fail("First obstacle did not lose one durability: %s / %s" % [skill_id, blocker])
	state = BattleState.new()
	state.terrain.objects[Vector2i(2, 2)] = TerrainManager.make_plant()
	if state.projected_skill_impact(state.unit_by_id("ally_fire"), "fire_burst", Vector2i(6, 2)) != Vector2i(-1, -1):
		return _fail("Adjacent first blocker did not enforce the fire blind spot")
	return true


func _test_birth_move() -> bool:
	var state := BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.unit_by_id("trainer").hp = 99
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("wild_b").move_points = 0
	if not TurnTestHelper.finish_round(state) or state.turn_number != 2:
		return _fail("Could not reach first nest spawn")
	var newborn: CombatUnit = state.unit_by_id("nest_2_1")
	if newborn == null or newborn.cell == Vector2i(6, 1) or newborn.skill_points != 0 or newborn.eligible_round != 3:
		return _fail("Newborn did not move once without gaining a skill action: %s events=%s" % [str({"cell": newborn.cell, "skill": newborn.skill_points, "eligible": newborn.eligible_round}) if newborn != null else "missing", str(state.events.slice(maxi(0, state.events.size() - 8)))])
	return true


func _fail(message: String) -> bool:
	push_error("ENEMY_APPROACH_LOS failed: " + message)
	quit(1)
	return false
