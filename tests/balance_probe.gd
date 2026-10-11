extends SceneTree

const MapGenerator = preload("res://scripts/map_generator.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var defeat := 0
	var escape := 0
	var victory := 0
	var total_spawned := 0
	var remaining_hp := 0
	for seed_value in range(1000, 1020):
		var run := RunState.new()
		run.run_seed = seed_value
		var layout: Dictionary = MapGenerator.generate("wetland", [], seed_value)
		var state := BattleState.new(run, layout)
		while state.outcome == "" and state.turn_number <= CombatConfig.MAX_PLAYER_ROUNDS:
			state.finish_player_turn()
			if state.phase == "reward_choice":
				state.choose_reward_buff(state.reward_choices[0])
		match state.outcome:
			"defeat": defeat += 1
			"escape": escape += 1
			"victory": victory += 1
		total_spawned += state.spawned_count
		remaining_hp += state.unit_by_id("trainer").hp
	print("BALANCE_PROBE idle20: defeat=", defeat, " escape=", escape, " victory=", victory, " spawned=", total_spawned, " trainer_hp_sum=", remaining_hp)
	var direct: Dictionary = _fixed_duel(false)
	var terrain: Dictionary = _fixed_duel(true)
	print("BALANCE_PROBE fixed duel: direct=", direct, " terrain=", terrain)
	quit(0)


func _fixed_duel(use_terrain: bool) -> Dictionary:
	var state := BattleState.new()
	state.unit_by_id("ally_fire").cell = Vector2i(0, 0)
	state.unit_by_id("ally_rock").cell = Vector2i(3, 1)
	state.unit_by_id("ally_water").cell = Vector2i(2, 3)
	state.unit_by_id("wild_a").cell = Vector2i(3, 3)
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.terrain.ground[Vector2i(3, 3)] = "shallow_water"
	state.terrain.ground[Vector2i(4, 3)] = "deep_water"
	state.reward_cell = Vector2i(2, 3)
	state.reward_state = "ground"
	while state.outcome == "" and state.turn_number <= CombatConfig.MAX_PLAYER_ROUNDS:
		if use_terrain:
			if state.turn_number == 1 and state.current_player_ids().has("ally_water"):
				state.try_use_skill("ally_water", "water_flow", Vector2i(3, 3))
		elif state.current_player_ids().has("ally_rock"):
			state.try_use_skill("ally_rock", "rock_break", Vector2i(3, 3))
		if state.outcome == "":
			state.finish_player_turn()
			if state.phase == "reward_choice":
				state.choose_reward_buff(state.reward_choices[0])
	return {"outcome": state.outcome, "turn": state.turn_number, "trainer_hp": state.unit_by_id("trainer").hp, "buff_claimed": state.reward_state == "claimed"}
