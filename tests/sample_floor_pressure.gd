extends SceneTree

## 固定种子的被动承压样本：三层各取首战和首领战。
## 用法：godot --headless --path . --script res://tests/sample_floor_pressure.gd
## 玩家不行动；输出仅用于观察敌方强度，不代表主动游玩平衡。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var run := RunState.new_run(31001)
	for floor_index in Balance.FLOORS_PER_RUN:
		run.battle_index = floor_index * Balance.BATTLES_PER_FLOOR
		run.refresh_theme_offers()
		run.choose_floor_theme(String(run.offered_floor_themes[0]))
		for local_value in [0, Balance.BATTLES_PER_FLOOR - 1]:
			var local_index := int(local_value)
			var index: int = floor_index * Balance.BATTLES_PER_FLOOR + local_index
			var cfg := BattleDB.config_for(index, run.seed, run.current_theme())
			var map := MapGenerator.generate(run.seed, index, 0, [], run.current_theme())
			var units: Array = [
				CombatUnit.make("trainer", "player", Balance.TRAINER_UID),
				CombatUnit.make("fire_starter", "player", 1),
				CombatUnit.make("water_starter", "player", 2),
				CombatUnit.make("rock_starter", "player", 3),
			]
			var state := BattleState.new()
			state.setup(map, cfg, run.seed, index, units, {}, {}, cfg["reinforce"])
			while not state.ended and state.round <= Balance.MAX_ROUNDS:
				state.begin_enemy_phase()
				while not state.enemy_phase_finished():
					state.step_enemy_phase()
				if not state.ended:
					state.end_enemy_phase()
			var surviving := 0
			var remaining_hp := 0
			for unit in state.alive_units("player"):
				surviving += 1
				remaining_hp += unit.hp
			print("PRESSURE %s" % JSON.stringify({
				"battle": index + 1,
				"theme": run.current_theme(),
				"boss": local_index == Balance.BATTLES_PER_FLOOR - 1,
				"rounds": state.round,
				"result": state.end_reason,
				"survivors": surviving,
				"remaining_hp": remaining_hp,
				"enemy_alive": state.alive_enemy_count(),
			}))
	print("PRESSURE_ELAPSED_MS %d" % (Time.get_ticks_msec() - started))
	quit(0)
