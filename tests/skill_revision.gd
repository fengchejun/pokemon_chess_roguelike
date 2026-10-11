extends SceneTree

const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _fire_and_charge() or not _water_and_rain() or not _fog() or not _enemy_choices():
		quit(1)
		return
	if not await _rain_ally_target_ui():
		quit(1)
		return
	print("SKILL_REVISION passed")
	quit(0)


func _fire_and_charge() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var victim: CombatUnit = state.unit_by_id("wild_b")
	victim.cell = Vector2i(4, 2)
	state.terrain.ground[victim.cell] = "fragile"
	var fire_result: bool = state.try_use_skill(fire.unit_id, "fire_burst", victim.cell)
	if not fire_result or victim.hp != victim.max_hp - 2 or not victim.burned or state.terrain.is_collapsed(victim.cell):
		return _fail("Fire center damage, burn or fragile preservation")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if victim.hp != victim.max_hp - 2:
		return _fail("Direct burn damaged on its application settlement")
	state.turn_number += 1
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if victim.hp != victim.max_hp - 3:
		return _fail("Direct burn did not tick next settlement")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(2, 2)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	state.unit_by_id("wild_c").cell = Vector2i(7, 7)
	if not state.try_use_skill(fire.unit_id, "fire_burst", Vector2i(4, 2)) or victim.hp != victim.max_hp - 1 or victim.burned:
		return _fail("Fire splash should deal one damage without direct burn")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(2, 2)
	victim = state.unit_by_id("wild_b")
	victim.cell = Vector2i(3, 2)
	state.terrain.objects[Vector2i(3, 2)] = state.terrain.make_rock()
	if not state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(4, 2)) or fire.cell != Vector2i(4, 2) or not victim.burned or victim.hp != victim.max_hp or fire.move_points != fire.base_move:
		return _fail("Charge did not pass blocker, burn intermediate unit, and preserve move")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(2, 2)
	state.unit_by_id("wild_a").cell = Vector2i(2, 4)
	var old_skill: int = fire.skill_points
	if state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(2, 4)) or fire.skill_points != old_skill:
		return _fail("Occupied charge landing spent skill")
	state.terrain.ground[Vector2i(4, 2)] = "collapsed"
	if not state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(4, 2)) or fire.is_alive():
		return _fail("Charge landing on collapsed pit should kill caster")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(2, 2)
	state.terrain.ground[Vector2i(4, 2)] = "deep_water"
	if not state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(4, 2)) or fire.is_alive():
		return _fail("Charge landing on deep water should drown caster")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	var fire_victim: CombatUnit = state.unit_by_id("wild_a")
	fire_victim.cell = Vector2i(4, 2)
	if not state.try_use_skill(fire.unit_id, "fire_burst", fire_victim.cell) or fire_victim.hp != fire_victim.max_hp - 2 or fire_victim.burned:
		return _fail("Fire type should take direct fire damage but resist burn")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(2, 2)
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var target: Vector2i = fire.cell + direction * 2
		if not state.can_use_skill(fire, "flame_charge", target):
			return _fail("Charge direction was unexpectedly invalid: " + str(direction))
	if state.can_use_skill(fire, "flame_charge", Vector2i(4, 3)):
		return _fail("Diagonal charge was legal")
	return true


func _water_and_rain() -> bool:
	var state := BattleState.new()
	var water: CombatUnit = state.unit_by_id("ally_water")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	water.cell = Vector2i(2, 4)
	victim.cell = Vector2i(3, 4)
	if not state.try_use_skill(water.unit_id, "water_flow", victim.cell) or not victim.wet or state.terrain.is_water(Vector2i(3, 4)) or victim.hp != victim.max_hp - 1:
		return _fail("Water hit unit should wet and push without making water")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	state.turn_number += 1
	if state.effective_move_range(victim) != victim.base_move - 1:
		return _fail("Skill wet failed to reduce next-round movement")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if victim.wet:
		return _fail("Dry skill wet did not expire after affected round")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(2, 3)
	state.terrain.objects[Vector2i(4, 3)] = state.terrain.make_rock()
	state.terrain.ground.erase(Vector2i(3, 3))
	if not state.try_use_skill(water.unit_id, "water_flow", Vector2i(5, 3)) or not state.terrain.is_shallow_water(Vector2i(3, 3)):
		return _fail("Water did not form before remote obstacle")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(4, 3)
	if not state.try_use_skill(water.unit_id, "water_flow", Vector2i(5, 3)) or not state.terrain.is_shallow_water(water.cell):
		return _fail("Adjacent obstacle should form water under caster")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(2, 4)
	state.terrain.ground[Vector2i(4, 4)] = "fragile"
	state.terrain.ground[Vector2i(5, 5)] = "collapsed"
	state.terrain.ground[Vector2i(3, 5)] = "grass"
	state.terrain.ignite_plant(Vector2i(3, 5))
	if not state.try_use_skill(water.unit_id, "rain_call", Vector2i(4, 4)) or not state.terrain.is_shallow_water(Vector2i(4, 4)) or not state.terrain.is_shallow_water(Vector2i(3, 5)) or state.terrain.is_burning(Vector2i(3, 5)) or not state.terrain.is_collapsed(Vector2i(5, 5)) or state.terrain.object_at(Vector2i(5, 4)).is_empty():
		return _fail("Rain conversion, extinction or skipped cells")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(2, 5)
	var water_victim: CombatUnit = state.unit_by_id("wild_b")
	water_victim.cell = Vector2i(4, 5)
	if not state.try_use_skill(water.unit_id, "water_flow", water_victim.cell) or water_victim.wet:
		return _fail("Water type should resist direct wet")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(0, 0)
	if state.can_use_skill(water, "rain_call", Vector2i(3, 3)) or not state.can_use_skill(water, "rain_call", Vector2i(3, 2)) or EnvironmentResolver.skill_area(state, "rain_call", Vector2i(0, 0)).size() != 4:
		return _fail("Rain distance or board-edge clipping")
	if not state.try_use_skill(water.unit_id, "rain_call", Vector2i(0, 0)) or not state.terrain.is_shallow_water(water.cell) or water.wet:
		return _fail("Rain under caster should make water without immediate wet")
	state = BattleState.new()
	water = state.unit_by_id("ally_water")
	water.cell = Vector2i(1, 0)
	if not state.try_use_skill(water.unit_id, "water_flow", Vector2i(3, 0)) or not state.terrain.is_shallow_water(Vector2i(3, 0)):
		return _fail("Water flow empty target did not make shallow water")
	return true


func _fog() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	state.terrain.add_steam(fire.cell)
	for skill_id in fire.skill_ids:
		if state.can_use_skill(fire, skill_id, Vector2i(3, 2)):
			return _fail("Fog allowed fire skill")
	var previous: int = fire.skill_points
	if state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(3, 2)) or fire.skill_points != previous:
		return _fail("Fog spent skill point")
	var water: CombatUnit = state.unit_by_id("ally_water")
	state.terrain.add_steam(water.cell)
	if state.can_use_skill(water, "rain_call", water.cell) or state.can_use_skill(water, "water_flow", Vector2i(3, 4)):
		return _fail("Fog allowed water skill")
	return true


func _enemy_choices() -> bool:
	var state := BattleState.new()
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	var trainer: CombatUnit = state.unit_by_id("trainer")
	enemy.cell = Vector2i(4, 2)
	trainer.cell = Vector2i(3, 2)
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.phase = "enemy_attack"
	preload("res://scripts/enemy_ai.gd").new().attack_phase(state, [enemy.unit_id])
	if not trainer.burned or enemy.cell != Vector2i(2, 2):
		return _fail("Enemy failed to use safe charge on priority target")
	state = BattleState.new()
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	enemy = state.unit_by_id("wild_b")
	enemy.cell = Vector2i(5, 5)
	state.unit_by_id("trainer").cell = Vector2i(0, 0)
	state.phase = "enemy_attack"
	preload("res://scripts/enemy_ai.gd").new().attack_phase(state, [enemy.unit_id])
	if not state.events.back().contains("浅水") and not state.events.back().contains("造雨"):
		return _fail("Enemy failed to prepare water without a direct target")
	return true


func _rain_ally_target_ui() -> bool:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene failed to load")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	battle.set("state", state)
	battle.set("selected_unit_id", "ally_water")
	battle.set("action_mode", "skill:rain_call")
	var trainer_cell: Vector2i = state.unit_by_id("trainer").cell
	battle.call("_on_directed_skill_pressed", trainer_cell)
	if battle.get("selected_unit_id") != "ally_water" or not state.terrain.is_shallow_water(trainer_cell) or state.unit_by_id("ally_water").skill_points != 0:
		return _fail("Directed rain on allied center changed selection or failed to cast")
	return true


func _fail(message: String) -> bool:
	push_error("SKILL_REVISION failed: " + message)
	return false
