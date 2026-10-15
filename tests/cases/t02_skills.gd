extends RefCounted

## 技能总表逐条验证


func run(t: TestContext) -> void:
	t.begin("技能")
	_t_fire_seed_hit(t)
	_t_fire_seed_splash(t)
	_t_flame_charge(t)
	_t_water_flow(t)
	_t_rain_dance(t)
	_t_discharge_root(t)
	_t_volt_step(t)
	_t_seed_sow(t)
	_t_drain(t)
	_t_push_collision(t)
	_t_rock_smash(t)
	_t_rock_create(t)
	_t_attr_modifier(t)
	t.finish()


func _t_fire_seed_hit(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["grass_wild1", Vector2i(4, 3)]])
	var fire := CombatUnit.make("fire_starter", "player", 50)
	state.units.append(fire)
	fire.cell = Vector2i(0, 3)
	var entry := {"type": "cell", "cell": Vector2i(4, 3)}
	var result := SkillResolver.apply(state, fire, "fire_seed", entry, false)
	t.check(bool(result["ok"]), "火种施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - 2, "属性克制停用后，火种中心造成基础 2 伤")
	t.eq(wild.burn_ticks, Balance.BURN_TICKS, "命中附加灼烧")


func _t_fire_seed_splash(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["grass_wild1", Vector2i(4, 2)]])
	var fire := CombatUnit.make("fire_starter", "player", 50)
	state.units.append(fire)
	fire.cell = Vector2i(0, 3)
	var entry := {"type": "cell", "cell": Vector2i(4, 3)}
	var result := SkillResolver.apply(state, fire, "fire_seed", entry, false)
	t.check(bool(result["ok"]), "火种打空施放成功")
	t.eq(result["hits"].size(), 1, "溅射命中 1 个单位")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - 1, "属性克制停用后，火种溅射造成基础 1 伤")
	t.eq(wild.burn_ticks, 0, "溅射不附加灼烧")


func _t_flame_charge(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.DEEP],
	])
	var state := TestScenario.make_state([], [["water_wild1", Vector2i(1, 3)]], terrain)
	var fire := CombatUnit.make("fire_starter", "player", 50)
	state.units.append(fire)
	fire.cell = Vector2i(0, 3)
	var entry := {"type": "cell", "cell": Vector2i(2, 3)}
	var result := SkillResolver.apply(state, fire, "flame_charge", entry, false)
	t.check(bool(result["ok"]), "闪焰冲锋施放成功")
	t.check(bool(result["self_death"]), "落点为深水死亡")
	t.eq(fire.hp, 0, "冲锋者死亡")
	t.eq(state.deaths.size(), 1, "倒下写入战损记录")
	# 跨过水面单位获得灼烧
	var terrain2 := TestScenario.plain_terrain()
	var state2 := TestScenario.make_state([], [["grass_wild1", Vector2i(1, 3)]], terrain2)
	var fire2 := CombatUnit.make("fire_starter", "player", 50)
	state2.units.append(fire2)
	fire2.cell = Vector2i(0, 3)
	var result2 := SkillResolver.apply(state2, fire2, "flame_charge", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(bool(result2["ok"]), "闪焰冲锋跨过单位")
	t.eq(state2.unit_by_uid(100).burn_ticks, Balance.BURN_TICKS, "被跨过的非火系单位灼烧")
	t.eq(fire2.cell, Vector2i(2, 3), "冲锋后位置更新")


func _t_water_flow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var water_mon := CombatUnit.make("water_starter", "player", 50)
	state.units.append(water_mon)
	water_mon.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, water_mon, "water_flow", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(bool(result["ok"]), "水流施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("rock_wild1") - 1, "水流不受克制影响：1 伤害")
	t.eq(wild.cell, Vector2i(3, 3), "命中后击退 1 格")
	t.eq(wild.slow_ticks, 2, "命中后减速")
	# 命中障碍在前方造水
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
	])
	var state2 := TestScenario.make_state([], [], terrain)
	var water_mon2 := CombatUnit.make("water_starter", "player", 50)
	state2.units.append(water_mon2)
	water_mon2.cell = Vector2i(0, 3)
	var result2 := SkillResolver.apply(state2, water_mon2, "water_flow", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(bool(result2["ok"]), "水流击中障碍")
	t.eq(state2.terrain_at(Vector2i(1, 3)), TerrainDB.WATER, "障碍前一格生成水面")
	t.eq(state2.terrain_at(Vector2i(2, 3)), TerrainDB.OBSTACLE, "障碍本身不变化")
	# 命中空地造水
	var state3 := TestScenario.make_state([], [])
	var water_mon3 := CombatUnit.make("water_starter", "player", 50)
	state3.units.append(water_mon3)
	water_mon3.cell = Vector2i(0, 3)
	SkillResolver.apply(state3, water_mon3, "water_flow", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.eq(state3.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "射到空地生成水面")


func _t_rain_dance(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(3, 2), TerrainDB.GRASS],
		[Vector2i(4, 4), TerrainDB.OBSTACLE],
		[Vector2i(2, 4), TerrainDB.LAVA],
	])
	var state := TestScenario.make_state([], [], terrain)
	var water_mon := CombatUnit.make("water_starter", "player", 50)
	state.units.append(water_mon)
	water_mon.cell = Vector2i(1, 3)
	var result := SkillResolver.apply(state, water_mon, "rain_dance", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.check(bool(result["ok"]), "造雨术施放成功")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.WATER, "草丛变水面")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.OBSTACLE, "跳过障碍")
	t.eq(state.terrain_at(Vector2i(2, 4)), TerrainDB.LAVA, "跳过熔岩")
	t.eq(state.terrain_at(Vector2i(2, 3)), TerrainDB.WATER, "平地变水面")


func _t_discharge_root(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["water_wild1", Vector2i(2, 3)]])
	var pika := CombatUnit.make("electric_starter", "player", 50)
	state.units.append(pika)
	pika.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, pika, "discharge", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}, false)
	t.check(bool(result["ok"]), "放电施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("water_wild1") - 2, "放电造成基础 2 伤")
	t.eq(wild.root_pending, true, "命中附加定身")


func _t_volt_step(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
	])
	var state := TestScenario.make_state([], [], terrain)
	var pika := CombatUnit.make("electric_starter", "player", 50)
	state.units.append(pika)
	pika.cell = Vector2i(0, 3)
	var entries := SkillResolver.targets(state, pika, "volt_step")
	var blocked := false
	var allowed := false
	for entry in entries:
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(2, 3):
			blocked = true
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(3, 3) or entry.get("cell", Vector2i(-1, -1)) == Vector2i(3, 4):
			allowed = true
	t.eq(blocked, false, "不能落在障碍上")
	t.eq(allowed, false, "不能穿过障碍绕到 3 格")
	var result := SkillResolver.apply(state, pika, "volt_step", {"type": "cell", "cell": Vector2i(1, 4)}, false)
	t.check(bool(result["ok"]), "电光步施放成功")
	t.eq(pika.cell, Vector2i(1, 4), "瞬移位置更新")


func _t_seed_sow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [])
	var grass_mon := CombatUnit.make("grass_starter", "player", 50)
	state.units.append(grass_mon)
	grass_mon.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, grass_mon, "seed_sow", {"type": "cell", "cell": Vector2i(3, 3)}, false)
	t.check(bool(result["ok"]), "播种施放成功")
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.GRASS, "平地生成草丛")


func _t_drain(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var grass_mon := CombatUnit.make("grass_starter", "player", 50)
	state.units.append(grass_mon)
	grass_mon.cell = Vector2i(0, 3)
	grass_mon.hp = 3
	var result := SkillResolver.apply(state, grass_mon, "drain", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}, false)
	t.check(bool(result["ok"]), "吸取施放成功")
	t.eq(state.unit_by_uid(100).hp, SpeciesDB.hp_of("rock_wild1") - 1, "吸取造成基础 1 伤")
	t.eq(grass_mon.hp, 4, "自身回复 1 生命")


func _t_push_collision(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["water_wild1", Vector2i(3, 3)]])
	var rock := CombatUnit.make("rock_starter", "player", 50)
	state.units.append(rock)
	rock.cell = Vector2i(2, 3)
	var result := SkillResolver.apply(state, rock, "push", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}, false)
	t.check(bool(result["ok"]), "推击施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("water_wild1") - 2, "推击 2 伤害（无克制关系）")
	t.eq(wild.cell, Vector2i(4, 3), "推开 1 格")
	# 推入障碍：碰撞加伤
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(4, 3), TerrainDB.OBSTACLE],
	])
	var state2 := TestScenario.make_state([], [["water_wild1", Vector2i(3, 3)]], terrain)
	var rock2 := CombatUnit.make("rock_starter", "player", 50)
	state2.units.append(rock2)
	rock2.cell = Vector2i(2, 3)
	SkillResolver.apply(state2, rock2, "push", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}, false)
	var wild2 := state2.unit_by_uid(100)
	t.eq(wild2.hp, SpeciesDB.hp_of("water_wild1") - 3, "碰撞追加 1 伤害")
	t.eq(wild2.cell, Vector2i(3, 3), "被障碍挡住")
	t.eq(state2.obstacle_durability.get(Vector2i(4, 3), 0), 1, "障碍耐久 −1")


func _t_rock_smash(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
	])
	var state := TestScenario.make_state([], [], terrain)
	var rock := CombatUnit.make("rock_starter", "player", 50)
	state.units.append(rock)
	rock.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, rock, "rock_smash", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(bool(result["ok"]), "碎岩施放成功")
	t.eq(state.obstacle_durability.get(Vector2i(2, 3), 0), 0, "障碍被破坏")
	t.eq(state.terrain_at(Vector2i(2, 3)), TerrainDB.PLAIN, "破坏后变平地")


func _t_rock_create(t: TestContext) -> void:
	var state := TestScenario.make_state([], [])
	var rock := CombatUnit.make("rock_starter", "player", 50)
	state.units.append(rock)
	rock.cell = Vector2i(2, 3)
	var result := SkillResolver.apply(state, rock, "rock_create", {"type": "dir", "dir": Vector2i(0, -1), "cell": Vector2i(2, 2)}, false)
	t.check(bool(result["ok"]), "造岩施放成功")
	t.eq(state.terrain_at(Vector2i(1, 2)), TerrainDB.OBSTACLE, "横排左端生成障碍")
	t.eq(state.terrain_at(Vector2i(2, 2)), TerrainDB.OBSTACLE, "横排中端生成障碍")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.OBSTACLE, "横排右端生成障碍")
	t.eq(int(state.obstacle_expire_round.get(Vector2i(2, 2), -1)), state.round, "我方障碍本轮敌方阶段后消失")


func _t_attr_modifier(t: TestContext) -> void:
	for pair in [["fire", "grass"], ["grass", "fire"], ["fire", "ice"], ["rock", "electric"], ["electric", "water"], ["water", "fire"]]:
		t.eq(Elements.modifier(pair[0], pair[1]), 0, "%s 对 %s 无属性修正" % pair)
	t.eq(Elements.modifier("fire", "fire"), 0, "同属性无修正")
	t.eq(Elements.modifier("", "fire"), 0, "无属性不参与克制")
	t.eq(Elements.counter_pairs().size(), 0, "对局不暴露克制配对")
