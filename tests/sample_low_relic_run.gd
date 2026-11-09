extends SceneTree

## 固定种子的无遗物自动战术试玩。实际走移动/施法/敌方行动/结算，不直接清场。
## 用法：Godot --headless --path . --script res://tests/sample_low_relic_run.gd

var nest_focus := false
var trace_actions := false
var capture_mode := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if not args.is_empty() else 31001
	nest_focus = args.size() > 1 and String(args[1]) == "nest"
	trace_actions = args.has("trace")
	capture_mode = args.has("capture")
	var run := RunState.new_run(seed_value, [
		{"id": 1, "species_id": "fire_starter", "starting_skill_id": "flame_jet"},
		{"id": 2, "species_id": "water_starter", "starting_skill_id": "water_flow"},
		{"id": 3, "species_id": "rock_starter", "starting_skill_id": "rock_break"},
	])
	if capture_mode:
		run.options["capture_low_hp"] = true
	run.choose_floor_theme("grass" if run.offered_floor_themes.has("grass") else String(run.offered_floor_themes[0]))
	var started := Time.get_ticks_msec()
	for battle_index in Balance.BATTLES_PER_FLOOR:
		var cfg := BattleDB.config_for(battle_index, run.seed, run.current_theme())
		var map := MapGenerator.generate(run.seed, battle_index, 0, [], run.current_theme())
		var deployed: Array = []
		for record in run.carried:
			if int(record["hp"]) > 0:
				deployed.append(int(record["uid"]))
			if deployed.size() >= 3:
				break
		if deployed.is_empty():
			print("LOW_RELIC_RUN STOP no_survivors battle=%d" % (battle_index + 1))
			break
		run.mark_deployed(deployed)
		var state := BattleState.new()
		state.setup(map, cfg, run.seed, battle_index, run.build_deploy_units(deployed), {}, {}, cfg.get("reinforce", []), run.options, run.relic_stacks)
		var received_damage := 0
		while not state.ended and state.round <= Balance.MAX_ROUNDS:
			if trace_actions and battle_index == 5:
				print("TRACE round=%d nest=%d enemies=%d trainer=%d" % [state.round, int(state.nest.get("hp", 0)), state.alive_enemy_count(), state.trainer().hp])
			if capture_mode:
				_try_capture(state)
			for unit in state.units:
				if state.ended:
					break
				if unit.side != "player" or unit.is_trainer or not unit.is_alive():
					continue
				_play_unit(state, unit)
			if not state.ended:
				_move_trainer_to_safety(state)
			if state.ended:
				break
			state.begin_enemy_phase()
			while not state.enemy_phase_finished() and not state.ended:
				var before_step := _team_hp(state)
				state.step_enemy_phase()
				received_damage += maxi(0, before_step - _team_hp(state))
			if not state.ended:
				var before_settle := _team_hp(state)
				state.end_enemy_phase()
				received_damage += maxi(0, before_settle - _team_hp(state))
		var boss := state.unit_by_uid(state.boss_uid)
		print("LOW_RELIC_BATTLE %s" % JSON.stringify({"battle": battle_index + 1, "theme": run.current_theme(), "rounds": state.round, "reason": state.end_reason, "damage_taken": received_damage, "player_deaths": state.deaths.size(), "captures": state.captured.size(), "enemy_left": state.alive_enemy_count(), "boss_alive": boss != null and boss.is_alive(), "nest_alive": bool(state.nest.get("alive", false)), "relics": run.relic_stacks}))
		if state.end_reason == "forced_retreat":
			break
		run.sync_from_battle(state)
		run.settle_battle(state)
		while not run.pending_captures.is_empty():
			if not run.capture_join_team():
				if not run.capture_to_storage():
					break
		while not run.pending_monster_levels().is_empty():
			var level_entry: Dictionary = run.pending_monster_levels()[0]
			var uid := int(level_entry["uid"])
			var level := int(level_entry["level"])
			var options := run.available_monster_upgrades(uid)
			if not options.is_empty():
				run.take_monster_level_choice(uid, level, String(options[0]))
			else:
				var skills := run.available_new_skills(uid)
				if not skills.is_empty():
					run.learn_monster_skill(uid, level, String(skills[0]))
				else:
					break
		while run.pending_reward_choices > 0:
			if run.discard_unavailable_reward_choices() <= 0:
				break
		run.advance_battle()
		if run.supply_due():
			run.pending_supply = true
			run.apply_supply_recovery()
			run.choose_supply_item(String(run.supply_choices()[0]))
			run.pending_supply = false
	print("LOW_RELIC_RUN_ELAPSED_MS %d" % (Time.get_ticks_msec() - started))
	quit(0)


func _team_hp(state: BattleState) -> int:
	var total := 0
	for unit in state.units:
		if unit.side == "player":
			total += maxi(0, unit.hp)
	return total


func _play_unit(state: BattleState, unit: CombatUnit) -> void:
	var destinations: Array = [unit.cell]
	if state.can_move_unit_now(unit):
		destinations.append_array(state.move_options(unit).keys())
	var best := {"score": -9999.0, "dest": unit.cell, "skill": "", "entry": {}}
	for dest in destinations:
		var sim := state.clone()
		var actor := sim.unit_by_uid(unit.uid)
		if dest != unit.cell and not sim.move_unit(actor, dest):
			continue
		var distance := 99
		for enemy in sim.alive_units("enemy"):
			distance = mini(distance, GridSpec.manhattan(dest, enemy.cell))
		if nest_focus and bool(sim.nest.get("alive", false)):
			distance = mini(distance, GridSpec.manhattan(dest, sim.nest["cell"]))
		var move_score := -float(distance) * 0.25
		if move_score > float(best["score"]):
			best = {"score": move_score, "dest": dest, "skill": "", "entry": {}}
		for skill_id in actor.skills:
			for entry in sim.skill_targets(actor, String(skill_id)):
				var preview := sim.preview_skill(actor, String(skill_id), entry)
				if not bool(preview.get("ok", false)):
					continue
				var score := move_score
				for hit in preview.get("hits", []):
					var target := sim.unit_by_uid(int(hit.get("uid", -1)))
					if target != null and target.side == "enemy":
						score += float(hit.get("damage", 0)) + (22.0 if bool(hit.get("killed", false)) else 0.0)
						if hit.get("push") != null:
							for collision in hit["push"].get("collisions", []):
								score += float(collision.get("target_damage", 0))
				if nest_focus:
					for obstacle in preview.get("obstacles_damaged", []):
						score += 12.0 if bool(obstacle.get("destroyed", false)) else 5.0
				if String(preview.get("text", "")).contains("巢穴") or entry.get("type", "") == "nest":
					score += 120.0 if nest_focus else 45.0
				if score > float(best["score"]):
					best = {"score": score, "dest": dest, "skill": String(skill_id), "entry": entry}
	if best["dest"] != unit.cell:
		state.move_unit(unit, best["dest"])
	if String(best["skill"]) != "":
		state.cast_skill(unit, String(best["skill"]), best["entry"])
	if trace_actions and state.battle_index == 5:
		print("TRACE unit=%s cell=%s skill=%s target=%s score=%.1f" % [unit.display_name, str(unit.cell), String(best["skill"]), str(best["entry"]), float(best["score"])])


func _move_trainer_to_safety(state: BattleState) -> void:
	var trainer := state.trainer()
	if trainer == null or not state.can_move_unit_now(trainer):
		return
	if capture_mode and _try_capture(state):
		return
	var best_cell := trainer.cell
	var best_score := -999
	for cell in [trainer.cell] + state.move_options(trainer).keys():
		var closest := 99
		for enemy in state.alive_units("enemy"):
			closest = mini(closest, GridSpec.manhattan(cell, enemy.cell))
		var score := closest * 10 - GridSpec.manhattan(cell, Vector2i(0, 0))
		if score > best_score:
			best_score = score
			best_cell = cell
	if best_cell != trainer.cell:
		state.move_unit(trainer, best_cell)


func _try_capture(state: BattleState) -> bool:
	var trainer := state.trainer()
	if trainer == null or trainer.capture_used or not state.can_move_unit_now(trainer):
		return false
	for enemy in state.alive_units("enemy"):
		if enemy.hp > Balance.CAPTURE_GUARANTEE_HP and (enemy.hp > Balance.CAPTURE_DEBUFF_GUARANTEE_HP or not CaptureSystem.has_debuff(enemy)):
			continue
		for cell in [trainer.cell] + state.move_options(trainer).keys():
			if maxi(absi(cell.x - enemy.cell.x), absi(cell.y - enemy.cell.y)) != 1:
				continue
			if cell == trainer.cell or state.move_unit(trainer, cell):
				var result := state.capture_attempt(trainer, enemy)
				if trace_actions and state.battle_index == 5:
					print("TRACE capture=%s target=%s" % [str(result), enemy.display_name])
				return bool(result.get("success", false))
	return false
