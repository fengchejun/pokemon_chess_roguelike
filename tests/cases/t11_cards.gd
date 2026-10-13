extends RefCounted

## 环境卡（v2.2 站位增益）：水域穿行、草丛伏击、障碍掩体、
## 必死格邻位庇护、平地机动、熔脉火伤、卡池规则


func run(t: TestContext) -> void:
	t.begin("环境卡效果")
	_t_water_ignore(t)
	_t_water_range(t)
	_t_grass_duel(t)
	_t_obstacle_cover(t)
	_t_push_bonus(t)
	_t_hazard_guards(t)
	_t_fire_bonus(t)
	_t_card_selection(t)
	t.finish()


func _t_water_ignore(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(1, 3), TerrainDB.WATER],
	])
	var state := TestScenario.make_state(["fire_starter"], [], terrain, {"water_ignore": 1})
	state.trainer().cell = Vector2i(0, 7)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	t.check(PathFinder.stop_cells(state, fire).has(Vector2i(3, 3)), "溪流：我方非水系穿水不减速（可达 3 格）")
	fire.cell = Vector2i(1, 3)
	state.settle_round()
	t.eq(fire.slow_ticks, 0, "溪流：我方留在浅水不获得浸湿")
	var state2 := TestScenario.make_state([], [["rock_wild1", Vector2i(0, 3)]], terrain, {"water_ignore": 1})
	state2.trainer().cell = Vector2i(0, 7)
	var enemy := state2.unit_by_uid(100)
	enemy.cell = Vector2i(0, 3)
	enemy.cell = Vector2i(1, 3)
	state2.settle_round()
	t.eq(enemy.slow_ticks, 2, "溪流：敌方留在浅水于回合结算获得浸湿")


func _t_water_range(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["water_wild1", Vector2i(6, 3)]], [], {"water_range": 1})
	var player_water := state.unit_by_uid(1)
	player_water.cell = Vector2i(0, 2)
	var entries := SkillResolver.targets(state, player_water, "rain_dance")
	var found_far := false
	for entry in entries:
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(6, 2):
			found_far = true
	t.eq(found_far, true, "潮汐：我方可施放距离 +1 的落点（5→6）")
	var enemy_water := state.unit_by_uid(100)
	enemy_water.cell = Vector2i(6, 3)
	var enemy_entries := SkillResolver.targets(state, enemy_water, "rain_dance")
	var enemy_far := false
	var enemy_base := false
	for entry in enemy_entries:
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(0, 3):
			enemy_far = true
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(1, 3):
			enemy_base = true
	t.eq(enemy_far, false, "潮汐：敌方射程不受益（增益仅我方）")
	t.eq(enemy_base, true, "潮汐：敌方保持基础射程")
	t.eq(SkillResolver._range_bonus(state, player_water, "fire_seed"), 0, "潮汐不影响火系技能")


func _t_grass_duel(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.GRASS],
	])
	var effects := {"grass_reduction": 1, "grass_strike": 1}
	# 站在草丛中：受到的远程伤害 −1
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain, effects)
	var player := state.unit_by_uid(1)
	player.cell = Vector2i(2, 3)
	var hp_before := player.hp
	SkillResolver.apply(state, state.unit_by_uid(100), "rock_smash", {"type": "unit", "unit": player.uid, "cell": player.cell}, false)
	t.eq(player.hp, hp_before, "密林：草丛中的我方单位受远程伤害 −1（1 → 0）")
	var state2 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain)
	var player2 := state2.unit_by_uid(1)
	player2.cell = Vector2i(2, 3)
	SkillResolver.apply(state2, state2.unit_by_uid(100), "rock_smash", {"type": "unit", "unit": player2.uid, "cell": player2.cell}, false)
	t.eq(player2.hp, hp_before - 1, "对照：无卡时正常受到 1 点")
	# 站在草丛中：造成的直接伤害 +1
	var terrain3 := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(0, 3), TerrainDB.GRASS],
	])
	var state3 := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]], terrain3, effects)
	var fire := state3.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	SkillResolver.apply(state3, fire, "fire_seed", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(state3.unit_by_uid(100).hp, SpeciesDB.hp_of("grass_wild1") - 4, "密林：火种 2 + 火克草 1 + 草丛增伤 1")
	var state4 := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]], [], effects)
	var fire4 := state4.unit_by_uid(1)
	fire4.cell = Vector2i(0, 3)
	SkillResolver.apply(state4, fire4, "fire_seed", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(state4.unit_by_uid(100).hp, SpeciesDB.hp_of("grass_wild1") - 3, "密林：不在草丛时只有火克草 +1")
	# 敌方站在草丛中不享受增益
	var terrain5 := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(0, 3), TerrainDB.GRASS],
	])
	var state5 := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(0, 3)]], terrain5, effects)
	var victim := state5.unit_by_uid(1)
	victim.cell = Vector2i(1, 3)
	SkillResolver.apply(state5, state5.unit_by_uid(100), "drain", {"type": "unit", "unit": victim.uid, "cell": victim.cell}, false)
	t.eq(victim.hp, SpeciesDB.hp_of("fire_starter") - 1, "密林：敌方在草丛中不享受 +1")


func _t_obstacle_cover(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(3, 3), TerrainDB.OBSTACLE],
	])
	var effects := {"obstacle_cover": 1}
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain, effects)
	var player := state.unit_by_uid(1)
	player.cell = Vector2i(2, 3)
	var hp_before := player.hp
	SkillResolver.apply(state, state.unit_by_uid(100), "rock_smash", {"type": "unit", "unit": player.uid, "cell": player.cell}, false)
	t.eq(player.hp, hp_before, "岩脊：紧邻障碍的我方单位受远程伤害 −1（1 → 0）")
	var state2 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain)
	var player2 := state2.unit_by_uid(1)
	player2.cell = Vector2i(2, 3)
	SkillResolver.apply(state2, state2.unit_by_uid(100), "rock_smash", {"type": "unit", "unit": player2.uid, "cell": player2.cell}, false)
	t.eq(player2.hp, hp_before - 1, "对照：无卡时正常受到 1 点")
	# 不紧邻障碍时没有掩体（即便拥有岩脊）
	var state3 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain, effects)
	var player3 := state3.unit_by_uid(1)
	player3.cell = Vector2i(2, 5)
	var enemy3 := state3.unit_by_uid(100)
	enemy3.cell = Vector2i(1, 5)
	var hp3 := player3.hp
	SkillResolver.apply(state3, enemy3, "rock_smash", {"type": "unit", "unit": player3.uid, "cell": player3.cell}, false)
	t.eq(player3.hp, hp3 - 1, "岩脊：不紧邻障碍时无减伤")


func _t_push_bonus(t: TestContext) -> void:
	var effects := {"push_damage": 1}
	# 紧邻障碍推击：伤害 +1
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 2), TerrainDB.OBSTACLE],
	])
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(3, 3)]], terrain, effects)
	var rock := state.unit_by_uid(1)
	rock.cell = Vector2i(2, 3)
	var wild := state.unit_by_uid(100)
	SkillResolver.apply(state, rock, "push", {"type": "unit", "unit": wild.uid, "cell": wild.cell}, false)
	t.eq(wild.hp, SpeciesDB.hp_of("water_wild1") - 3, "岩脊：借石发力，推击伤害 +1（2 → 3）")
	t.eq(wild.cell, Vector2i(4, 3), "岩脊：推击位移照常")
	# 不紧邻障碍：无加成
	var state2 := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(3, 3)]], terrain, effects)
	var rock2 := state2.unit_by_uid(1)
	rock2.cell = Vector2i(2, 5)
	var wild2 := state2.unit_by_uid(100)
	wild2.cell = Vector2i(3, 5)
	SkillResolver.apply(state2, rock2, "push", {"type": "unit", "unit": wild2.uid, "cell": wild2.cell}, false)
	t.eq(wild2.hp, SpeciesDB.hp_of("water_wild1") - 2, "岩脊：不紧邻障碍时推击无加成")
	# 敌方推击不享受（且敌方也不算入场）
	var state3 := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain, effects)
	var fire := state3.unit_by_uid(1)
	fire.cell = Vector2i(2, 3)
	var enemy := state3.unit_by_uid(100)
	SkillResolver.apply(state3, enemy, "push", {"type": "unit", "unit": fire.uid, "cell": fire.cell}, false)
	t.eq(fire.hp, SpeciesDB.hp_of("fire_starter") - 2, "岩脊：敌方推击无加成（2 点）")
	t.eq(fire.cell, Vector2i(3, 3), "岩脊：敌方推击位移照常")


func _t_hazard_guards(t: TestContext) -> void:
	# 潮汐：紧邻深水免疫强制位移
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 2), TerrainDB.DEEP],
	])
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain, {"deep_guard": 1})
	var player := state.unit_by_uid(1)
	player.cell = Vector2i(2, 3)
	var hp_before := player.hp
	SkillResolver.apply(state, state.unit_by_uid(100), "push", {"type": "unit", "unit": player.uid, "cell": player.cell}, false)
	t.eq(player.cell, Vector2i(2, 3), "潮汐：紧邻深水时不会被推离")
	t.eq(player.hp, hp_before - 2, "潮汐：伤害照常结算（2 点）")
	var state2 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain)
	var player2 := state2.unit_by_uid(1)
	player2.cell = Vector2i(2, 3)
	SkillResolver.apply(state2, state2.unit_by_uid(100), "push", {"type": "unit", "unit": player2.uid, "cell": player2.cell}, false)
	t.eq(player2.cell, Vector2i(3, 3), "对照：无卡时会被推离")
	# 熔脉：紧邻熔岩免疫强制位移
	var terrain3 := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 2), TerrainDB.LAVA],
	])
	var state3 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], terrain3, {"lava_guard": 1})
	var player3 := state3.unit_by_uid(1)
	player3.cell = Vector2i(2, 3)
	SkillResolver.apply(state3, state3.unit_by_uid(100), "push", {"type": "unit", "unit": player3.uid, "cell": player3.cell}, false)
	t.eq(player3.cell, Vector2i(2, 3), "熔脉：紧邻熔岩时不会被推离")
	# 不紧邻致死地形时庇护不生效
	var state4 := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(1, 3)]], [], {"deep_guard": 1, "lava_guard": 1})
	var player4 := state4.unit_by_uid(1)
	player4.cell = Vector2i(2, 3)
	SkillResolver.apply(state4, state4.unit_by_uid(100), "push", {"type": "unit", "unit": player4.uid, "cell": player4.cell}, false)
	t.eq(player4.cell, Vector2i(3, 3), "庇护只在紧邻时生效")
	# 敌方不受庇护：推到深水仍会淘汰
	var terrain5 := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(3, 3), TerrainDB.DEEP],
	])
	var state5 := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(2, 3)]], terrain5, {"deep_guard": 1})
	var rock := state5.unit_by_uid(1)
	rock.cell = Vector2i(1, 3)
	SkillResolver.apply(state5, rock, "push", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}, false)
	t.eq(state5.unit_by_uid(100).hp, 0, "庇护仅对我方生效：敌方仍会被推入致死地形")


func _t_fire_bonus(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], [], {"fire_bonus": 1})
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	SkillResolver.apply(state, fire, "fire_seed", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(state.unit_by_uid(100).hp, SpeciesDB.hp_of("rock_wild1") - 3, "熔脉：我方火系技能 +1 伤害（2+1=3）")
	var state2 := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(4, 3)]], [], {"fire_bonus": 1})
	state2.trainer().cell = Vector2i(0, 7)
	var target := state2.unit_by_uid(1)
	target.cell = Vector2i(0, 3)
	SkillResolver.apply(state2, state2.unit_by_uid(100), "fire_seed", {"type": "cell", "cell": Vector2i(0, 3)}, false)
	t.eq(target.hp, SpeciesDB.hp_of("water_starter") - 1, "熔脉：敌方火系无加成（逆克制后最低 1）")


func _t_card_selection(t: TestContext) -> void:
	var run := RunState.new_run(999)
	t.eq(run.cards.size(), Balance.CARDS_PER_BATTLE, "开局默认已选 2 张出战卡")
	for card_id in run.cards:
		t.check(CardDB.CARDS.has(String(card_id)), "所选卡有效：%s" % card_id)
	t.eq(run.effects(), CardDB.active_effects(run.cards), "实际生效与所选一致")
	run.cards = ["magma", "tide"]
	t.eq(int(run.effects().get("fire_bonus", 0)), 1, "换卡后火系 +1 生效")
	t.eq(int(run.effects().get("lava_guard", 0)), 1, "换卡后熔脉庇护生效")
	var data := run.to_dict()
	data["cards"] = ["stream", "forest", "ridge", "magma"]
	var loaded := RunState.from_dict(data)
	t.eq(loaded.cards.size(), Balance.CARDS_PER_BATTLE, "读档后出战卡固定为 2 张")
	t.eq(loaded.cards.has("ridge"), false, "超出的选择被裁掉")
	var data2 := run.to_dict()
	data2["cards"] = ["not_a_card"]
	var loaded2 := RunState.from_dict(data2)
	t.eq(loaded2.cards.size(), Balance.CARDS_PER_BATTLE, "非法卡名回退补齐为 2 张")
