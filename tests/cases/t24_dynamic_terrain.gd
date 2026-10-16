extends RefCounted


func run(t: TestContext) -> void:
	t.begin("临时藤蔓、冰面扩张与雾气")
	_vines_and_expiry(t)
	_vines_burning_and_replacement(t)
	_ice_growth(t)
	_steam_overlay(t)
	t.finish()


func _vines_and_expiry(t: TestContext) -> void:
	var deep := Vector2i(3, 3)
	var pit := Vector2i(4, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[deep, TerrainDB.DEEP], [pit, TerrainDB.PIT], [Vector2i(3, 2), TerrainDB.WATER]])
	var state := TestScenario.make_state(["grass_starter", "fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var grass := state.unit_by_uid(1)
	grass.cell = Vector2i(2, 3)
	var walker := state.unit_by_uid(2)
	walker.cell = Vector2i(2, 4)
	var result := SkillResolver.apply(state, grass, "wild_vines", {"type": "dir", "dir": Vector2i(1, 0), "cell": deep}, false)
	t.check(bool(result.get("ok", false)), "藤蔓技能可覆盖深水与深坑")
	t.eq(state.terrain_at(deep), TerrainDB.VINES, "深水暂时变为可站立藤蔓")
	t.eq(state.terrain_at(pit), TerrainDB.VINES, "深坑暂时变为可站立藤蔓")
	t.eq(int(state.vine_origin[deep]), TerrainDB.DEEP, "保存深水底层")
	t.eq(int(state.vine_origin[pit]), TerrainDB.PIT, "保存深坑底层")
	t.eq(int(state.vine_expire_round[deep]), 2, "下一轮末到期")
	t.check(state.move_options(walker).has(deep), "覆盖深水的藤蔓成为合法主动移动终点")
	t.check(state.move_unit(walker, deep), "地面单位可走上深水藤蔓桥")
	state.settle_round()
	t.eq(state.terrain_at(deep), TerrainDB.VINES, "生成当轮末藤蔓仍在")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.WATER, "藤蔓不会向水面自行扩张")
	state.round = 2
	state.settle_round()
	t.eq(state.terrain_at(deep), TerrainDB.DEEP, "到期恢复深水")
	t.eq(state.terrain_at(pit), TerrainDB.PIT, "到期恢复深坑")
	t.eq(walker.hp, 0, "非水系地面单位站在恢复的深水上立即倒下")
	t.check(state.vine_expire_round.is_empty() and state.vine_origin.is_empty(), "到期清除藤蔓元数据")

	var water_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var water := water_state.unit_by_uid(1)
	water_state.place_temp_vines(deep)
	water.cell = deep
	water_state.round = 2
	water_state.settle_round()
	t.check(water.is_alive() and water_state.terrain_at(deep) == TerrainDB.DEEP, "水系在恢复的深水上存活")

	var flying_state := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var flyer := flying_state.unit_by_uid(1)
	flyer.battle_buffs["flight"] = true
	flying_state.place_temp_vines(pit)
	flyer.cell = pit
	flying_state.round = 2
	flying_state.settle_round()
	t.check(flyer.is_alive() and flying_state.terrain_at(pit) == TerrainDB.PIT, "飞行单位在恢复的深坑上存活")

	var trainer_state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	trainer_state.place_temp_vines(pit)
	trainer_state.unit_by_uid(Balance.TRAINER_UID).cell = pit
	trainer_state.round = 2
	trainer_state.settle_round()
	t.eq(trainer_state.end_reason, "forced_retreat", "训练家脚下恢复深坑后强制撤退")


func _vines_burning_and_replacement(t: TestContext) -> void:
	var pit := Vector2i(3, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[pit, TerrainDB.PIT]])
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	state.place_temp_vines(pit)
	state.ignite(pit)
	state.burning_cells[pit] = 1
	state.settle_round()
	t.eq(state.terrain_at(pit), TerrainDB.PIT, "燃烧提前毁藤蔓时恢复深坑而非平地")
	t.check(not state.vine_expire_round.has(pit), "烧毁后不再重复到期")
	state.place_temp_vines(pit)
	state.set_terrain(pit, TerrainDB.ICE)
	state.round = 2
	state.settle_round()
	t.eq(state.terrain_at(pit), TerrainDB.ICE, "其他技能改写藤蔓后不再恢复旧底层")
	t.check(not state.vine_origin.has(pit), "改写后底层记录清除")


func _ice_growth(t: TestContext) -> void:
	var ice := Vector2i(2, 3)
	var first := Vector2i(3, 3)
	var second := Vector2i(4, 3)
	var line := TestScenario.with_cells(TestScenario.plain_terrain(), [[ice, TerrainDB.ICE], [first, TerrainDB.WATER], [second, TerrainDB.DEEP]])
	var state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(6, 6)]], line, {}, {}, [], 73)
	var other := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(6, 6)]], line, {}, {}, [], 73)
	var spawn_before := state.spawn_rng.state
	var capture_before := state.capture_rng.state
	var preview := state.clone()
	preview.settle_round()
	t.eq(state.terrain_at(first), TerrainDB.WATER, "克隆战场扩冰不修改正式战场")
	state.settle_round()
	other.settle_round()
	t.eq(state.terrain_at(first), TerrainDB.ICE, "冰面可扩张到相邻浅水")
	t.eq(state.terrain_at(second), TerrainDB.DEEP, "本轮新冰不继续扩张")
	t.eq(state.terrain, other.terrain, "相同种子产生相同冰面")
	t.eq(state.terrain, preview.terrain, "预览克隆与正式结算一致")
	t.eq(state.spawn_rng.state, spawn_before, "冰面随机数不改变产怪随机数")
	t.eq(state.capture_rng.state, capture_before, "冰面随机数不改变捕获随机数")
	state.round = 2
	state.settle_round()
	t.eq(state.terrain_at(second), TerrainDB.ICE, "下一轮新冰可扩张到深水")

	var branching := TestScenario.with_cells(TestScenario.plain_terrain(), [[ice, TerrainDB.ICE], [Vector2i(1, 3), TerrainDB.WATER], [first, TerrainDB.DEEP]])
	var branch_state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(6, 6)]], branching)
	branch_state.settle_round()
	var frozen_count := int(branch_state.terrain_at(Vector2i(1, 3)) == TerrainDB.ICE) + int(branch_state.terrain_at(first) == TerrainDB.ICE)
	t.eq(frozen_count, 1, "一块冰面在一轮中只冻结一个邻接水格")


func _steam_overlay(t: TestContext) -> void:
	var cell := Vector2i(3, 3)
	var state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.add_steam(cell)
	for value in [TerrainDB.WATER, TerrainDB.DEEP, TerrainDB.ICE, TerrainDB.VINES, TerrainDB.PIT]:
		state.set_terrain(cell, value)
		t.check(state.steam_cells.has(cell), "%s 不清除同格雾气" % TerrainDB.name_of(value))
	state.set_terrain(cell, TerrainDB.PLAIN)
	state.place_temp_obstacle(cell, TerrainDB.PLAIN, state.round + 1)
	t.check(not state.steam_cells.has(cell), "造岩短墙清除同格雾气")
	state.damage_obstacle(cell, Balance.OBSTACLE_DURABILITY)
	t.check(not state.steam_cells.has(cell), "短墙被破坏后雾气不会恢复")
	for blocker in [TerrainDB.OBSTACLE, TerrainDB.TREE]:
		state.add_steam(cell)
		state.set_terrain(cell, blocker)
		t.check(not state.steam_cells.has(cell), "%s 出现时清除雾气" % TerrainDB.name_of(blocker))
		state.add_steam(cell)
		t.check(not state.steam_cells.has(cell), "阻挡物上不能新生雾气")
		state.set_terrain(cell, TerrainDB.PLAIN)
	state.add_steam(cell)
	state.settle_round()
	t.eq(int(state.steam_cells.get(cell, 0)), 1, "雾气自然倒计时仍生效")
	state.round = 2
	state.settle_round()
	t.check(not state.steam_cells.has(cell), "雾气在第二次整轮结算后消散")
