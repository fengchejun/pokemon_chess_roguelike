extends RefCounted

func run(t: TestContext) -> void:
	t.begin("固定等级差样本与敌人等级经验收益")
	for enemy_level in range(1, 11):
		var state := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(5, 3)]])
		var enemy := state.unit_by_uid(100)
		enemy.enemy_level = enemy_level
		state.kill_unit(enemy, "固定样本", "player", 1)
		t.eq(state.unit_by_uid(1).combat_xp, 1 + ceili(enemy_level / 2.0), "敌人等级影响击杀经验")
		t.eq(state.unit_by_uid(2).combat_xp, maxi(1, floori((1 + ceili(enemy_level / 2.0)) / 2.0)), "队友取得普通击杀奖励的一半")
		var boss := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(5, 3)]])
		boss.unit_by_uid(100).enemy_level = enemy_level
		boss.unit_by_uid(100).is_boss = true
		boss.kill_unit(boss.unit_by_uid(100), "首领固定样本", "player", 1)
		t.eq(boss.unit_by_uid(1).combat_xp, MonsterProgression.enemy_xp_reward(enemy_level, true), "首领额外二经验只给击杀者")
		t.eq(boss.unit_by_uid(2).combat_xp, MonsterProgression.enemy_participation_xp(enemy_level), "首领其他参与者仍用普通奖励的一半")
	var samples := []
	for pair in [[3, 1], [3, 3], [3, 5], [3, 7], [7, 7], [10, 10]]:
		var sample := _duel(pair[0], pair[1])
		samples.append(sample)
		print("BALANCE_SAMPLE ", JSON.stringify(sample))
	t.check(samples[0]["won"] and samples[1]["won"], "同级和低级基础样本可胜")
	t.check(not samples[2]["won"] and not samples[3]["won"], "低两至四级的裸装样本不能只靠对攻越级")
	t.finish()

func _duel(player_level: int, enemy_level: int) -> Dictionary:
	# Controlled damage benchmark: same species, no relics, no upgrades, no terrain,
	# no movement or storm. It measures HP pacing, not full tactical encounter balance.
	var state := TestScenario.make_state(["fire_starter"], [["fire_starter", Vector2i(3, 3)]])
	var player := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	player.cell = Vector2i(2, 3)
	player.combat_level = player_level
	player.combat_xp = MonsterProgression.threshold_for_level(player_level)
	player.max_hp = MonsterProgression.max_hp(player.species_id, player_level)
	player.hp = player.max_hp
	enemy.enemy_level = enemy_level
	enemy.max_hp = MonsterProgression.max_hp(enemy.species_id, enemy_level)
	enemy.hp = enemy.max_hp
	var rounds := 0
	while player.is_alive() and enemy.is_alive() and rounds < 30:
		rounds += 1
		SkillResolver.apply(state, player, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": enemy.cell}, false)
		if enemy.is_alive():
			SkillResolver.apply(state, enemy, "flame_jet", {"type": "dir", "dir": Vector2i.LEFT, "cell": player.cell}, false)
	return {"player_level": player_level, "enemy_level": enemy_level, "rounds": rounds, "won": player.is_alive(), "player_hp": player.hp, "enemy_hp": enemy.hp}
