extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const BattleBuffSystem = preload("res://scripts/battle_buff_system.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_reward_timing() or not _test_buffs_and_flight() or not _test_nest_and_rounds() or not _test_skill_upgrades():
		return
	print("BATTLE_BUFF_ROUNDS passed")
	quit(0)


func _test_reward_timing() -> bool:
	var run := RunState.new()
	run.run_seed = 41
	var state := BattleState.new(run)
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	state.reward_cell = fire.cell
	state.reward_state = "ground"
	state.unit_by_id("trainer").hp = 99
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	if not state.finish_player_turn() or state.phase != "reward_choice" or state.reward_choices.size() != 2 or state.reward_choices[0] == state.reward_choices[1]:
		return _fail("Player reward was not offered after enemy phase")
	var first_choice: String = state.reward_choices[0]
	if not state.choose_reward_buff(first_choice) or fire.battle_buff != first_choice or state.turn_number != 2 or state.reward_state != "claimed":
		return _fail("Chosen buff was not applied before next round")
	if state.reward_choices.size() != 0 or state.choose_reward_buff(first_choice):
		return _fail("Reward was claimed twice")
	state.outcome = "victory"
	run.apply_battle_result(state)
	var next_battle := BattleState.new(run)
	for next_unit in next_battle.units:
		if next_unit.battle_buff != "" or next_unit.flying or next_unit.upgraded_skill_id != "":
			return _fail("Combat buff leaked into the next battle")
	var same_run := RunState.new()
	same_run.run_seed = 41
	var same_state := BattleState.new(same_run)
	same_state.reward_cell = same_state.unit_by_id("ally_fire").cell
	same_state.reward_state = "ground"
	if BattleBuffSystem.offer(same_state.unit_by_id("ally_fire"), same_state.buff_rng)[0] != first_choice:
		return _fail("Buff offer seed was not reproducible")
	state = BattleState.new()
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	state.reward_cell = enemy.cell
	state.reward_state = "ground"
	state.unit_by_id("trainer").hp = 99
	if not state.finish_player_turn() or state.reward_state != "claimed" or enemy.battle_buff == "":
		return _fail("Enemy did not auto-select at player phase end")
	state = BattleState.new()
	enemy = state.unit_by_id("wild_a")
	state.reward_cell = enemy.cell + Vector2i.LEFT
	state.reward_state = "ground"
	if EnemyAI.new().plan_move(state, enemy).back() != state.reward_cell:
		return _fail("Enemy did not actively move onto reachable reward")
	return true


func _test_buffs_and_flight() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	state._apply_reward_buff(trainer, "move_plus")
	if state.effective_move_range(trainer) != 4:
		return _fail("Movement buff did not add one tile")
	var water: CombatUnit = state.unit_by_id("ally_water")
	state.apply_skill_burn(water)
	state.apply_skill_wet(water)
	state._apply_reward_buff(water, "debuff_immune")
	if water.burned or water.wet:
		return _fail("Debuff immunity did not cleanse statuses")
	state.apply_skill_burn(water)
	state.apply_skill_wet(water)
	if water.burned or water.wet:
		return _fail("Debuff immunity did not prevent new statuses")
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	state._apply_reward_buff(rock, "direct_guard")
	var old_hp: int = rock.hp
	state._apply_damage(rock, 2, "技能", true)
	state._apply_damage(rock, 1, "碰撞")
	if rock.hp != old_hp - 2:
		return _fail("Direct guard reduced non-skill damage")
	state = BattleState.new()
	trainer = state.unit_by_id("trainer")
	state._apply_reward_buff(trainer, "flying")
	var pit := Vector2i(0, 3)
	var obstacle := Vector2i(0, 4)
	state.terrain.ground[pit] = "collapsed"
	state.terrain.objects[obstacle] = TerrainManager.make_rock()
	if not state.can_enter_voluntarily(trainer, pit) or not state.can_traverse_voluntarily(trainer, obstacle):
		return _fail("Flying did not bypass lethal ground or obstacle")
	trainer.cell = pit
	state._apply_entry_effects(trainer)
	if not trainer.is_alive() or state.can_enter_voluntarily(trainer, obstacle):
		return _fail("Flying landing or obstacle endpoint was incorrect")
	state.terrain.burning[pit] = 2
	state.begin_environment_resolution()
	EnvironmentResolver.settle_round(state)
	state.end_environment_resolution()
	if trainer.burned or trainer.wet:
		return _fail("Flying unit received ground fire or water effects")
	state = BattleState.new()
	trainer = state.unit_by_id("trainer")
	state._apply_reward_buff(trainer, "flying")
	state.terrain.objects[Vector2i(3, 3)] = TerrainManager.make_rock()
	var route: Array[Vector2i] = state.get_move_path(trainer, Vector2i(4, 3))
	if route != [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)] or not state.try_player_move(trainer.unit_id, Vector2i(4, 3)) or trainer.cell != Vector2i(4, 3):
		return _fail("Flying preview and movement did not cross unit and rock")
	state = BattleState.new()
	rock = state.unit_by_id("ally_rock")
	var guarded: CombatUnit = state.unit_by_id("wild_a")
	rock.cell = Vector2i(2, 3)
	guarded.cell = Vector2i(3, 3)
	state.terrain.objects[Vector2i(4, 3)] = TerrainManager.make_rock()
	state._apply_reward_buff(guarded, "direct_guard")
	old_hp = guarded.hp
	if not state.try_use_skill(rock.unit_id, "rock_push", guarded.cell) or guarded.hp != old_hp - 2:
		return _fail("Push guard did not separate reduced direct hit from collision")
	return true


func _test_nest_and_rounds() -> bool:
	var state := BattleState.new()
	state.nest = {"cell": Vector2i(5, 1), "exit": Vector2i(6, 1), "hp": 1}
	state.hit_cell(Vector2i(5, 1), 1, "测试")
	if state.outcome != "victory" or not state.unit_by_id("wild_a").is_alive():
		return _fail("Destroying nest did not win with live enemies")
	state = BattleState.new()
	state.turn_number = CombatConfig.MAX_PLAYER_ROUNDS
	state.reward_cell = state.unit_by_id("ally_fire").cell
	state.reward_state = "ground"
	state.unit_by_id("trainer").hp = 99
	for enemy in state.units:
		if enemy.team == "enemy":
			enemy.move_points = 0
			enemy.skill_points = 0
	if CombatConfig.MAX_PLAYER_ROUNDS != 6 or not state.finish_player_turn() or state.outcome != "escape" or state.reward_state != "expired":
		return _fail("Round six did not escape without late player reward")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.turn_number = 6
	state._start_round()
	if state.spawned_count != 0:
		return _fail("Nest spawned after its two scheduled rounds")
	return true


func _test_skill_upgrades() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	if not BattleBuffSystem.candidates(fire).has("skill_upgrade:fire_burst"):
		return _fail("Fire skill upgrade missing from candidates")
	state._apply_reward_buff(fire, "skill_upgrade:flame_charge")
	if fire.upgraded_skill_id != "flame_charge":
		return _fail("Skill upgrade not assigned")
	state = BattleState.new()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	state._apply_reward_buff(rock, "skill_upgrade:rock_break")
	rock.cell = Vector2i(4, 3)
	state.terrain.ground[Vector2i(4, 4)] = "fragile"
	if not state.try_use_skill(rock.unit_id, "rock_break", Vector2i(4, 4)) or not state.terrain.is_collapsed(Vector2i(4, 4)):
		return _fail("Upgraded rock break did not collapse fragile ground")
	return true


func _fail(message: String) -> bool:
	push_error("BATTLE_BUFF_ROUNDS failed: " + message)
	quit(1)
	return false
