extends SceneTree

## 固定种子敌方回合性能样本：区分规划与实际执行耗时。
## 用法：godot --headless --path . --script res://tests/profile_enemy_phase.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for index in [0, 5, 6, 11, 12, 17]:
		var theme := String(BattleDB.THEME_IDS[int(index / 6)])
		var cfg := BattleDB.config_for(index, 31001, theme)
		var map := MapGenerator.generate(31001, index, 0, [], theme)
		var units: Array = [
			CombatUnit.make("trainer", "player", Balance.TRAINER_UID),
			CombatUnit.make("fire_starter", "player", 1),
			CombatUnit.make("water_starter", "player", 2),
			CombatUnit.make("rock_starter", "player", 3),
		]
		var state := BattleState.new()
		state.setup(map, cfg, 31001, index, units, {}, {}, cfg["reinforce"])
		var started := Time.get_ticks_usec()
		var actions := state.begin_enemy_phase()
		var planning_ms := float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		while not state.enemy_phase_finished():
			state.step_enemy_phase()
		var execution_ms := float(Time.get_ticks_usec() - started) / 1000.0
		print("PROFILE battle=%d enemies=%d actions=%d plan_ms=%.1f execute_ms=%.1f" % [index + 1, (cfg["enemies"] as Array).size(), actions.size(), planning_ms, execution_ms])
	quit(0)
