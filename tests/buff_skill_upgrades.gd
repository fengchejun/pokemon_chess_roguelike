extends SceneTree

const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_fire() or not _test_water() or not _test_rock():
		return
	print("BUFF_SKILL_UPGRADES passed")
	quit(0)


func _test_fire() -> bool:
	var state := BattleState.new()
	var caster: CombatUnit = state.unit_by_id("ally_fire")
	var victim: CombatUnit = state.unit_by_id("wild_b")
	caster.cell = Vector2i(2, 3)
	victim.cell = Vector2i(4, 4)
	state.terrain.ground.erase(victim.cell)
	state._apply_reward_buff(caster, "skill_upgrade:fire_burst")
	if not state.try_use_skill(caster.unit_id, "fire_burst", Vector2i(4, 3)) or victim.hp != victim.max_hp - 1 or not victim.burned:
		return _fail("Upgraded fire burst did not burn outer target")
	state = BattleState.new()
	caster = state.unit_by_id("ally_fire")
	victim = state.unit_by_id("wild_b")
	caster.cell = Vector2i(2, 3)
	victim.cell = Vector2i(3, 3)
	state._apply_reward_buff(caster, "skill_upgrade:flame_charge")
	if not state.try_use_skill(caster.unit_id, "flame_charge", Vector2i(4, 3)) or caster.cell != Vector2i(4, 3) or victim.hp != victim.max_hp - 1 or not victim.burned:
		return _fail("Upgraded flame charge did not damage and burn crossed unit")
	return true


func _test_water() -> bool:
	var state := BattleState.new()
	var caster: CombatUnit = state.unit_by_id("ally_water")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(3, 2)
	state._apply_reward_buff(caster, "skill_upgrade:water_flow")
	if not state.try_use_skill(caster.unit_id, "water_flow", victim.cell) or victim.cell != Vector2i(5, 2):
		return _fail("Upgraded water flow did not push two cells")
	state = BattleState.new()
	caster = state.unit_by_id("wild_b")
	victim = state.unit_by_id("ally_fire")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(3, 2)
	state._apply_reward_buff(caster, "skill_upgrade:water_flow")
	state.phase = "enemy_attack"
	if not state.try_use_skill(caster.unit_id, "water_flow", victim.cell) or victim.cell != Vector2i(5, 2):
		return _fail("Enemy upgraded water flow did not share player rules")
	state = BattleState.new()
	caster = state.unit_by_id("ally_water")
	victim = state.unit_by_id("wild_a")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(4, 4)
	state._apply_reward_buff(caster, "skill_upgrade:rain_call")
	if not state.try_use_skill(caster.unit_id, "rain_call", Vector2i(4, 4)) or not victim.wet or not state.terrain.is_shallow_water(victim.cell):
		return _fail("Upgraded rain did not immediately wet its target")
	state = BattleState.new()
	caster = state.unit_by_id("ally_water")
	victim = state.unit_by_id("wild_a")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(3, 2)
	state._apply_reward_buff(caster, "skill_upgrade:electric_arc")
	if not state.try_use_skill(caster.unit_id, "electric_arc", victim.cell) or not victim.wet:
		return _fail("Upgraded electric arc did not wet conductive target")
	return true


func _test_rock() -> bool:
	var state := BattleState.new()
	var caster: CombatUnit = state.unit_by_id("ally_rock")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	caster.cell = Vector2i(2, 2)
	victim.cell = Vector2i(3, 2)
	state._apply_reward_buff(caster, "skill_upgrade:rock_push")
	if not state.try_use_skill(caster.unit_id, "rock_push", victim.cell) or victim.cell != Vector2i(5, 2):
		return _fail("Upgraded rock push did not push two cells")
	state = BattleState.new()
	caster = state.unit_by_id("ally_rock")
	caster.cell = Vector2i(2, 2)
	state._apply_reward_buff(caster, "skill_upgrade:rock_break")
	state.terrain.ground[Vector2i(2, 4)] = "fragile"
	if not state.try_use_skill(caster.unit_id, "rock_break", Vector2i(2, 4)) or not state.terrain.is_collapsed(Vector2i(2, 4)):
		return _fail("Upgraded rock break did not collapse fragile ground")
	state = BattleState.new()
	caster = state.unit_by_id("ally_rock")
	caster.cell = Vector2i(2, 2)
	state._apply_reward_buff(caster, "skill_upgrade:rock_create")
	var wall_cell := Vector2i(3, 2)
	if not state.try_use_skill(caster.unit_id, "rock_create", wall_cell) or int(state.terrain.object_at(wall_cell).get("expire_after_enemy_round", 0)) != 2:
		return _fail("Upgraded rock wall expiry was not extended")
	state.unit_by_id("trainer").hp = 99
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	state.finish_player_turn()
	if not state.terrain.blocks_move(wall_cell):
		return _fail("Upgraded rock wall expired after first enemy phase")
	return true


func _fail(message: String) -> bool:
	push_error("BUFF_SKILL_UPGRADES failed: " + message)
	quit(1)
	return false
