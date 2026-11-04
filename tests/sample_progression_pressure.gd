extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var rows: Array = []
	for curve in ["legacy", "current"]:
		for pair in [[1,1],[1,5],[3,5],[5,5],[5,7],[7,7],[10,10]]:
			for count in [1,3]:
				var enemies: Array = []
				for i in range(count): enemies.append(["rock_wild1",Vector2i(5,i+2)])
				var state := TestScenario.make_state(["rock_starter","rock_starter","rock_starter"],enemies)
				state.node_kind = "battle"
				state.experience_recipients.clear()
				for unit in state.units:
					if unit.is_trainer: continue
					unit.combat_level = pair[0] if unit.side == "player" else pair[1]
					unit.max_hp = MonsterProgression.max_hp(unit.species_id,unit.combat_level) if curve == "current" else SpeciesDB.hp_of(unit.species_id) + int((unit.combat_level - 1) / 2) * 10
					unit.hp = unit.max_hp
				var turns := 0
				while turns < 40:
					var players := state.alive_units("player").filter(func(u): return not u.is_trainer)
					if players.is_empty() or state.alive_units("enemy").is_empty(): break
					turns += 1
					for actor in players:
						var targets := state.alive_units("enemy")
						if targets.is_empty(): break
						state.damage_unit(actor,targets[0],10,{"element":"rock","skill_direct":true,"skill_id":"rock_break","cause":"固定集火样本"})
					for actor in state.alive_units("enemy"):
						var targets := state.alive_units("player").filter(func(u): return not u.is_trainer)
						if targets.is_empty(): break
						state.damage_unit(actor,targets[0],10,{"element":"rock","skill_direct":true,"skill_id":"rock_break","cause":"固定集火样本"})
				var won := state.alive_units("enemy").is_empty()
				rows.append({"curve":curve,"player_level":pair[0],"enemy_level":pair[1],"enemies":count,"rounds":turns,"player_won":won,"remaining_players":state.alive_units("player").filter(func(u):return not u.is_trainer).size()})
	DirAccess.make_dir_recursive_absolute("res://outputs/progression_mentor_20261104")
	var file := FileAccess.open("res://outputs/progression_mentor_20261104/balance_samples.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"固定双方集火交换伤害；无移动、遗物、强化、地形击杀及天雷，非完整AI胜率测试","samples":rows},"  "))
	for row in rows: print(row)
	quit(0)
