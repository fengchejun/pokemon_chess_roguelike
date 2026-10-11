extends SceneTree

const MonsterCatalog = preload("res://scripts/monster_catalog.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_catalog_and_starters() or not _test_electric() or not _test_grass() or not _test_ice() or not _test_control_edges() or not _test_wind() or not _test_capture_statuses() or not _test_enemy_wind_order():
		return
	if change_scene_to_file("res://scenes/starter_selection.tscn") != OK:
		_fail("Starter selection scene failed to load")
		return
	await process_frame
	await process_frame
	var scene: Node = current_scene
	if scene.name != "StarterSelection" or not (scene.find_child("*", true, false) is Control):
		_fail("Starter selection UI did not render")
		return
	for species_id in ["electric", "grass", "ice"]:
		scene.call("_toggle", species_id)
	scene.call("_confirm")
	await process_frame
	await process_frame
	var live_run: RunState = root.get_node("RunManager").get("run_state")
	if current_scene == null or current_scene.name != "Battle" or live_run.active_records().size() != 3:
		_fail("Selected starters did not enter battle")
		return
	print("SEVEN_ELEMENTS passed")
	quit(0)


func _test_catalog_and_starters() -> bool:
	if MonsterCatalog.SPECIES.size() != 7 or MonsterCatalog.SPECIES["water"]["skills"].has("electric_arc") or not MonsterCatalog.SPECIES["electric"]["skills"].has("electric_arc"):
		return _fail("Water and electric species were not separated")
	var run := RunState.new()
	if run.set_starters(["fire", "fire", "rock"]) or not run.set_starters(["electric", "grass", "ice"]) or run.roster.size() != 3 or run.active_records().size() != 3:
		return _fail("Three distinct starter selection failed")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 31
	b.seed = 31
	for index in 12:
		if MonsterCatalog.pick_region_enemy("wetland", a) != MonsterCatalog.pick_region_enemy("wetland", b):
			return _fail("Region species draw was not deterministic")
	return true


func _test_electric() -> bool:
	var state := _state_with(["electric", "grass", "rock"])
	var caster: CombatUnit = state.unit_by_id("ally_electric")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(4, 2)
	victim.max_hp = 10
	victim.hp = 10
	if not state.try_use_skill(caster.unit_id, "lightning", victim.cell) or victim.hp != 8 or not victim.shocked:
		return _fail("First lightning failed to damage and shock")
	state._expire_turn_statuses()
	if not victim.shocked:
		return _fail("Single shock did not persist until the next shock")
	caster.skill_points = 1
	if not state.try_use_skill(caster.unit_id, "lightning", victim.cell) or victim.hp != 6 or victim.shocked or victim.paralyzed_skip_round != 1:
		return _fail("Second lightning failed to paralyze")
	state.phase = "enemy_attack"
	if state.can_act_now(victim):
		return _fail("Paralyzed enemy could still act")
	state = _state_with(["electric", "grass", "rock"])
	caster = state.unit_by_id("ally_electric")
	caster.cell = Vector2i(2, 2)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(3, 1)
	var land_victim: CombatUnit = state.unit_by_id("wild_b")
	land_victim.cell = Vector2i(2, 1)
	land_victim.wet = true
	if not state.try_use_skill(caster.unit_id, "electric_arc", Vector2i(3, 2)) or victim.hp != victim.max_hp - 1 or land_victim.hp != land_victim.max_hp - 1:
		return _fail("Discharge missed connected water or adjacent wet land")
	return true


func _test_grass() -> bool:
	var state := _state_with(["grass", "water", "rock"])
	var caster: CombatUnit = state.unit_by_id("ally_grass")
	caster.cell = Vector2i(2, 3)
	var victim: CombatUnit = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	state.terrain.ground[Vector2i(3, 3)] = "shallow_water"
	if not state.try_use_skill(caster.unit_id, "wild_vines", Vector2i(3, 3)) or not state.terrain.is_vine(Vector2i(3, 3)) or not state.terrain.is_vine(victim.cell) or victim.rooted_skip_round != 1:
		return _fail("Vines did not form under units and over shallow water")
	state.phase = "enemy_move"
	if not state.enemy_move_cells(victim).is_empty() or not state.can_act_now(victim):
		return _fail("Vines failed to block movement while preserving skill action")
	state.phase = "player"
	if not state.terrain.ignite_plant(Vector2i(3, 3)):
		return _fail("Vine on shallow water could not burn")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if not state.terrain.is_vine(Vector2i(3, 3)) or not state.terrain.is_burning(Vector2i(4, 3)):
		return _fail("Vine fire did not spread one step after settlement")
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if not state.terrain.is_shallow_water(Vector2i(3, 3)):
		return _fail("Burned vine did not reveal underlying shallow water")
	state = _state_with(["grass", "water", "rock"])
	caster = state.unit_by_id("ally_grass")
	caster.cell = Vector2i(2, 3)
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.hp = 4
	caster.hp = 3
	if not state.try_use_skill(caster.unit_id, "herbal_heal", caster.cell) or trainer.hp != 5 or caster.hp != 4:
		return _fail("Herbal heal did not restore allies in 3x3")
	return true


func _test_ice() -> bool:
	var state := _state_with(["ice", "fire", "rock"])
	var caster: CombatUnit = state.unit_by_id("ally_ice")
	caster.cell = Vector2i(2, 3)
	state.terrain.ground[Vector2i(4, 3)] = "collapsed"
	state.terrain.ground[Vector2i(5, 3)] = "deep_water"
	state.terrain.objects.erase(Vector2i(5, 3))
	if not state.try_use_skill(caster.unit_id, "frozen_ground", Vector2i(3, 3)) or not state.terrain.is_ice(Vector2i(4, 3)) or not state.terrain.is_ice(Vector2i(5, 3)):
		return _fail("Ice did not bridge pit and deep water")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(1, 3)
	if not state.try_use_skill(fire.unit_id, "fire_burst", victim.cell) or victim.is_alive() or not state.terrain.is_collapsed(victim.cell):
		return _fail("Fire did not melt ice and expose lethal pit")
	state = _state_with(["ice", "fire", "rock"])
	caster = state.unit_by_id("ally_ice")
	caster.cell = Vector2i(2, 3)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	if not state.try_use_skill(caster.unit_id, "freeze_ray", victim.cell) or not victim.frozen:
		return _fail("Freeze ray did not freeze first enemy")
	var old_hp: int = victim.hp
	if state.hit_cell(victim.cell, 1, "测试命中") or victim.hp != old_hp or victim.frozen or victim.frozen_skip_round != 1:
		return _fail("Frozen shield did not cancel first hit while retaining action lock")
	state.phase = "enemy_attack"
	if state.can_act_now(victim):
		return _fail("Thawed enemy did not skip its promised action")
	state._expire_turn_statuses()
	state.turn_number = 2
	if not state.can_act_now(victim):
		return _fail("Frozen action lock lasted more than one eligible phase")
	state = _state_with(["ice", "fire", "rock"])
	caster = state.unit_by_id("ally_ice")
	caster.cell = Vector2i(2, 3)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	if not state.try_use_skill(caster.unit_id, "freeze_ray", victim.cell):
		return _fail("Freeze ray failed in persistence scenario")
	state.phase = "enemy_attack"
	for round_number in [1, 2, 3]:
		state.turn_number = round_number
		if state.can_act_now(victim):
			return _fail("Frozen target acted in round %d" % round_number)
		state._expire_turn_statuses()
		if not victim.frozen:
			return _fail("Freeze expired without a hit in round %d" % round_number)
	victim.acted_round = 3
	old_hp = victim.hp
	if state.hit_cell(victim.cell, 1, "测试解冻") or victim.hp != old_hp or victim.frozen or victim.frozen_skip_round != 4:
		return _fail("Late thaw failed to retain the next action lock")
	state.turn_number = 4
	if state.can_act_now(victim):
		return _fail("Late thaw did not skip the next action")
	state._expire_turn_statuses()
	state.turn_number = 5
	if not state.can_act_now(victim):
		return _fail("Late thaw action lock did not expire")
	var vine_cell := Vector2i(3, 2)
	state.terrain.set_vine(vine_cell)
	state.terrain.ignite_plant(vine_cell)
	if not state.terrain.set_ice(vine_cell) or state.terrain.is_burning(vine_cell) or not state.terrain.melt_ice(vine_cell) or not state.terrain.is_vine(vine_cell) or state.terrain.is_burning(vine_cell):
		return _fail("Ice did not preserve vine while extinguishing its flame")
	return true


func _test_wind() -> bool:
	var state := _state_with(["wind", "fire", "rock"])
	var wind: CombatUnit = state.unit_by_id("ally_wind")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	wind.cell = Vector2i(2, 3)
	fire.cell = Vector2i(4, 3)
	if not state.try_use_skill(wind.unit_id, "tailwind", Vector2i(3, 3)) or state.effective_move_range(fire) != fire.base_move + 2 or fire.move_points != fire.base_move + 2:
		return _fail("Tailwind did not grant current-round movement")
	state._expire_turn_statuses()
	if state.effective_move_range(fire) != fire.base_move:
		return _fail("Tailwind did not expire")
	state = _state_with(["wind", "fire", "rock"])
	wind = state.unit_by_id("ally_wind")
	fire = state.unit_by_id("ally_fire")
	wind.cell = Vector2i(2, 3)
	fire.cell = Vector2i(3, 3)
	fire.skill_points = 0
	if not state.try_use_skill(wind.unit_id, "double_cast", fire.cell) or fire.skill_points != 1 or fire.double_cast_round != 1:
		return _fail("Double cast did not restore an extra cast after first use")
	return true


func _test_control_edges() -> bool:
	var state := _state_with(["ice", "water", "rock"])
	var ice: CombatUnit = state.unit_by_id("ally_ice")
	ice.cell = Vector2i(2, 3)
	var blocker: CombatUnit = state.unit_by_id("ally_water")
	blocker.cell = Vector2i(3, 3)
	var victim: CombatUnit = state.unit_by_id("wild_a")
	victim.cell = Vector2i(4, 3)
	if state.can_use_skill(ice, "freeze_ray", victim.cell):
		return _fail("Freeze ray crossed a friendly blocker")
	blocker.cell = Vector2i(0, 0)
	state.terrain.objects[Vector2i(3, 3)] = TerrainManager.make_rock()
	if state.can_use_skill(ice, "freeze_ray", victim.cell):
		return _fail("Freeze ray crossed a rock")
	state.terrain.objects.erase(Vector2i(3, 3))
	if not state.can_use_skill(ice, "freeze_ray", victim.cell):
		return _fail("Clear freeze ray was rejected")
	state = _state_with(["ice", "water", "rock"])
	var water: CombatUnit = state.unit_by_id("ally_water")
	water.cell = Vector2i(2, 3)
	victim = state.unit_by_id("wild_a")
	victim.cell = Vector2i(3, 3)
	state.apply_freeze(victim)
	var original_hp: int = victim.hp
	if not state.try_use_skill(water.unit_id, "water_flow", victim.cell) or victim.hp != original_hp or victim.cell != Vector2i(3, 3) or victim.wet or victim.frozen:
		return _fail("Frozen shield failed to cancel push, damage and wet")
	state = _state_with(["grass", "water", "rock"])
	var grass: CombatUnit = state.unit_by_id("ally_grass")
	grass.cell = Vector2i(2, 3)
	state.terrain.objects[Vector2i(3, 3)] = TerrainManager.make_rock()
	if not state.try_use_skill(grass.unit_id, "wild_vines", Vector2i(3, 3)) or state.terrain.is_vine(Vector2i(3, 3)) or not state.terrain.is_vine(Vector2i(4, 3)):
		return _fail("Vine placement failed to skip obstacle independently")
	return true


func _test_capture_statuses() -> bool:
	var state := BattleState.new()
	var victim: CombatUnit = state.unit_by_id("wild_a")
	victim.hp = 2
	for status in ["shocked", "frozen", "rooted"]:
		victim.shocked = status == "shocked"
		victim.frozen = status == "frozen"
		victim.rooted_skip_round = 1 if status == "rooted" else 0
		if state.capture_chance(victim) != 1.0:
			return _fail("New debuff did not improve capture: " + status)
	state._apply_reward_buff(victim, "debuff_immune")
	if victim.has_debuff():
		return _fail("Debuff immunity did not cleanse new statuses")
	return true


func _test_enemy_wind_order() -> bool:
	var state := BattleState.new()
	var wind: CombatUnit = state.unit_by_id("wild_c")
	wind.element_type = "wind"
	wind.skill_ids.assign(["tailwind", "double_cast"])
	wind.display_name = "测试风怪"
	state.unit_by_id("trainer").hp = 99
	state.finish_player_turn()
	var wind_index := -1
	var fire_index := -1
	for index in state.events.size():
		if state.events[index].contains("测试风怪 开始行动"):
			wind_index = index
		if state.events[index].contains("野生火系怪物 开始行动"):
			fire_index = index
	if wind_index < 0 or fire_index < 0 or wind_index >= fire_index:
		return _fail("Enemy wind did not act before the deployment-order enemies")
	var supported := false
	for event in state.events:
		if event.contains("本轮可额外施放一次技能") or event.contains("本轮移动力 +2"):
			supported = true
	if not supported:
		return _fail("Enemy wind acted first but did not support a teammate")
	return true


func _state_with(starters: Array[String]) -> BattleState:
	var run := RunState.new()
	run.set_starters(starters)
	return BattleState.new(run)


func _fail(message: String) -> bool:
	push_error("SEVEN_ELEMENTS failed: " + message)
	quit(1)
	return false
