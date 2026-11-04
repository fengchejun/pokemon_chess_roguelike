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
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - Elements.direct_damage(SkillDB.damage_of("fire_seed"), "fire", "grass"), "火种中心受火克草加伤")
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
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - Elements.direct_damage(int(SkillDB.get_def("fire_seed")["splash_damage"]), "fire", "grass"), "火种溅射也受属性克制")
	t.eq(wild.burn_ticks, 0, "溅射不附加灼烧")


func _t_flame_charge(t: TestContext) -> void:
	var entry := {"type": "cell", "cell": Vector2i(2, 3)}
	var hit_first := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(1, 3)]])
	var first_fire := hit_first.unit_by_uid(1)
	first_fire.cell = Vector2i(0, 3)
	t.check(hit_first.skill_targets(first_fire, "flame_charge").has(entry), "被占据的冲锋方向仍可选择")
	var preview := hit_first.preview_skill(first_fire, "flame_charge", entry)
	t.eq(preview["hits"][0]["damage"], Elements.direct_damage(SkillDB.damage_of("flame_charge"), "fire", "grass"), "撞击预览显示克制直伤")
	t.eq(preview["hits"][0]["push"]["to"], Vector2i(2, 3), "撞击预览显示一格击退")
	t.eq(first_fire.cell, Vector2i(0, 3), "冲锋预览不移动施法者")
	var first_result := SkillResolver.apply(hit_first, first_fire, "flame_charge", entry, false)
	t.check(bool(first_result["ok"]), "闪焰冲锋可以撞击第一格单位")
	t.eq(first_fire.cell, Vector2i(0, 3), "第一格撞击时施法者原地停下")
	t.eq(hit_first.unit_by_uid(100).cell, Vector2i(2, 3), "第一格单位被推开一格")
	t.eq(hit_first.unit_by_uid(100).hp, hit_first.unit_by_uid(100).max_hp - Elements.direct_damage(SkillDB.damage_of("flame_charge"), "fire", "grass"), "第一格单位受到克制冲锋直伤")
	t.eq(hit_first.unit_by_uid(100).burn_ticks, 0, "冲锋不再附加沿途灼烧")
	var hit_second := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var second_fire := hit_second.unit_by_uid(1)
	second_fire.cell = Vector2i(0, 3)
	SkillResolver.apply(hit_second, second_fire, "flame_charge", entry, false)
	t.eq(second_fire.cell, Vector2i(1, 3), "第二格撞击时停在目标前一格")
	t.eq(hit_second.unit_by_uid(100).cell, Vector2i(3, 3), "第二格单位被推开一格")
	var rock_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 3), TerrainDB.OBSTACLE]])
	var rock_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 7)]], rock_terrain)
	var rock_fire := rock_state.unit_by_uid(1)
	rock_fire.cell = Vector2i(0, 3)
	SkillResolver.apply(rock_state, rock_fire, "flame_charge", entry, false)
	t.eq(rock_fire.cell, Vector2i(0, 3), "冲锋撞到岩障不能穿越")
	t.eq(int(rock_state.obstacle_durability[Vector2i(1, 3)]), 1, "岩障耐久减少一")
	var tree_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.TREE]])
	var tree_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 7)]], tree_terrain)
	var tree_fire := tree_state.unit_by_uid(1)
	tree_fire.cell = Vector2i(0, 3)
	SkillResolver.apply(tree_state, tree_fire, "flame_charge", entry, false)
	t.eq(tree_fire.cell, Vector2i(1, 3), "第二格树木被撞后施法者停在前方")
	t.eq(tree_state.terrain_at(Vector2i(2, 3)), TerrainDB.PLAIN, "一耐久树木被冲锋摧毁")
	var nest_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(0, 0)]])
	var nest_fire := nest_state.unit_by_uid(1)
	nest_fire.cell = Vector2i(5, 7)
	var nest_entry := {"type": "cell", "cell": Vector2i(7, 7)}
	t.check(nest_state.skill_targets(nest_fire, "flame_charge").has(nest_entry), "巢穴格可以作为冲锋方向")
	SkillResolver.apply(nest_state, nest_fire, "flame_charge", nest_entry, false)
	t.eq(nest_fire.cell, Vector2i(6, 7), "冲锋停在巢穴前")
	t.eq(int(nest_state.nest["hp"]), 19, "冲锋按11点技能伤害扣除巢穴生命")
	var collision_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var collision_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(1, 3)]], collision_terrain)
	var collision_fire := collision_state.unit_by_uid(1)
	collision_fire.cell = Vector2i(0, 3)
	var collision_result := SkillResolver.apply(collision_state, collision_fire, "flame_charge", entry, false)
	t.eq(collision_state.unit_by_uid(100).cell, Vector2i(1, 3), "目标被后方障碍挡住时不发生重叠")
	t.eq(collision_state.unit_by_uid(100).hp, collision_state.unit_by_uid(100).max_hp - SkillDB.damage_of("flame_charge") - Balance.COLLISION_DAMAGE, "撞击直伤和推击碰撞伤害分别结算")
	t.eq(collision_result["hits"][0]["push"]["collisions"][0]["kind"], "obstacle", "冲锋沿用共用推击碰撞规则")
	var deep_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 3), TerrainDB.DEEP]])
	var deep_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 7)]], deep_terrain)
	var deep_fire := deep_state.unit_by_uid(1)
	deep_fire.cell = Vector2i(0, 3)
	var deep_result := SkillResolver.apply(deep_state, deep_fire, "flame_charge", entry, false)
	t.check(bool(deep_result["self_death"]), "冲锋途中进入深水立即死亡")
	t.eq(deep_fire.cell, Vector2i(1, 3), "死亡前不会穿过深水")
	t.eq(deep_state.deaths.size(), 1, "冲锋者倒下写入战损记录")
	var lethal_push_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.PIT]])
	var lethal_push := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(1, 3)]], lethal_push_terrain)
	var pusher := lethal_push.unit_by_uid(1)
	pusher.cell = Vector2i(0, 3)
	var lethal_result := SkillResolver.apply(lethal_push, pusher, "flame_charge", entry, false)
	t.check(bool(lethal_result["hits"][0]["push"]["death"]), "冲锋可将单位推入空深坑")
	t.eq(pusher.cell, Vector2i(0, 3), "推杀后冲锋者仍停在碰撞前")


func _t_water_flow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]])
	var water_mon := CombatUnit.make("water_starter", "player", 50)
	state.units.append(water_mon)
	water_mon.cell = Vector2i(0, 3)
	var result := SkillResolver.apply(state, water_mon, "water_flow", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(bool(result["ok"]), "水流施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("rock_wild1") - SkillDB.damage_of("water_flow"), "水炮不受克制影响")
	t.eq(wild.cell, Vector2i(3, 3), "命中后击退 1 格")
	t.eq(wild.slow_ticks, 0, "水炮命中不自动浸湿")
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
	t.eq(wild.hp, SpeciesDB.hp_of("water_wild1") - Elements.direct_damage(SkillDB.damage_of("discharge"), "electric", "water"), "放电受电克水加伤")
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
	t.eq(state.unit_by_uid(100).hp, SpeciesDB.hp_of("rock_wild1") - Elements.direct_damage(SkillDB.damage_of("drain"), "grass", "rock"), "吸取受草克岩加伤")
	t.eq(grass_mon.hp, 3 + Balance.DRAIN_HEAL, "自身回复配置的生命")


func _t_push_collision(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["water_wild1", Vector2i(3, 3)]])
	var rock := CombatUnit.make("rock_starter", "player", 50)
	state.units.append(rock)
	rock.cell = Vector2i(2, 3)
	var result := SkillResolver.apply(state, rock, "push", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}, false)
	t.check(bool(result["ok"]), "推击施放成功")
	var wild := state.unit_by_uid(100)
	t.eq(wild.hp, SpeciesDB.hp_of("water_wild1") - SkillDB.damage_of("push"), "推击造成配置的直伤")
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
	t.eq(wild2.hp, SpeciesDB.hp_of("water_wild1") - SkillDB.damage_of("push") - Balance.COLLISION_DAMAGE, "碰撞追加配置的伤害")
	t.eq(wild2.cell, Vector2i(3, 3), "被障碍挡住")
	t.eq(state2.obstacle_durability.get(Vector2i(4, 3), 0), Balance.OBSTACLE_DURABILITY, "单位被推撞障碍不扣耐久")


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
	t.eq(state.obstacle_durability.get(Vector2i(2, 3), 0), 0, "旧碎岩兼容入口也直接破障")
	t.eq(state.terrain_at(Vector2i(2, 3)), TerrainDB.PLAIN, "破障后通路立即恢复")


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
	for pair in [["fire", "grass", 1], ["grass", "fire", -1], ["fire", "water", -1], ["rock", "electric", 1], ["electric", "water", 1], ["water", "fire", 1]]:
		t.eq(Elements.modifier(pair[0], pair[1]), pair[2], "%s 对 %s 的五系克制关系" % [pair[0], pair[1]])
	t.eq(Elements.modifier("fire", "fire"), 0, "同属性无修正")
	t.eq(Elements.modifier("", "fire"), 0, "无属性不参与克制")
	t.eq(Elements.LIST.size(), 5, "当前只有五种独立属性")
	t.eq(Elements.counter_pairs().size(), 5, "五属性单环各有一条克制边")
	t.eq(SpeciesDB.element_of("ice_starter"), "water", "冰物种归水系")
	t.eq(SpeciesDB.element_of("wind_starter"), "electric", "风物种归电系")
	t.eq(SkillDB.element_of("ice_shard"), "water", "冰技能归水系")
	t.eq(SkillDB.element_of("tailwind"), "electric", "风技能归电系")
	t.eq(Elements.direct_damage(20, "fire", "grass"), 25, "克制直伤乘 1.25")
	t.eq(Elements.direct_damage(20, "fire", "water"), 15, "被克直伤乘 0.75")
