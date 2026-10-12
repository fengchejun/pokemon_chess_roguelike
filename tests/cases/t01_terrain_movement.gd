extends RefCounted

## ① 地形六类与通行、② 移动消耗与撤回


func run(t: TestContext) -> void:
	t.begin("地形与移动")
	_t_cost_model(t)
	_t_deep_water(t)
	_t_grass_conceal(t)
	_t_move_and_undo(t)
	t.finish()


func _t_cost_model(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(1, 3), TerrainDB.WATER],
	])
	var state := TestScenario.make_state(["fire_starter", "water_starter"], [], terrain)
	var fire := state.unit_by_uid(1)
	var water_mon := state.unit_by_uid(2)
	fire.cell = Vector2i(0, 3)
	water_mon.cell = Vector2i(0, 4)
	var fire_options := PathFinder.stop_cells(state, fire)
	t.check(not fire_options.has(Vector2i(3, 3)), "非水系穿越水面少走一格：3 格外不可达")
	t.check(fire_options.has(Vector2i(2, 3)), "非水系进入水面后可到 2 格（3-1）")
	var water_options := PathFinder.stop_cells(state, water_mon)
	t.check(water_options.has(Vector2i(3, 4)), "水系移动不受水面影响")


func _t_deep_water(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(1, 3), TerrainDB.DEEP],
		[Vector2i(1, 4), TerrainDB.LAVA],
	])
	var state := TestScenario.make_state(["water_starter", "fire_starter"], [], terrain)
	var water_mon := state.unit_by_uid(1)
	var fire := state.unit_by_uid(2)
	water_mon.cell = Vector2i(0, 3)
	fire.cell = Vector2i(0, 4)
	t.check(PathFinder.stop_cells(state, water_mon).has(Vector2i(1, 3)), "水系可以停在深水（可进入）")
	water_mon.cell = Vector2i(0, 2)
	var options := PathFinder.reachable(state, water_mon)
	t.check(options.has(Vector2i(1, 2)) and options.has(Vector2i(2, 2)), "水系可穿过深水")
	t.check(not PathFinder.reachable(state, fire).has(Vector2i(1, 4)), "熔岩不可进入")
	var push_test := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]], terrain)
	var wild := push_test.unit_by_uid(100)
	wild.cell = Vector2i(2, 3)
	var result := PushResolver.push(push_test, wild, Vector2i(-1, 0), 1, 0, "测试推击", "player")
	t.check(bool(result["death"]), "推入致死地形立即死亡")
	t.eq(wild.hp, 0, "致死地形死亡后生命为 0")


func _t_grass_conceal(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(3, 3), TerrainDB.GRASS],
	])
	var state := TestScenario.make_state([], [["electric_wild1", Vector2i(3, 3)]], terrain)
	var wild := state.unit_by_uid(100)
	wild.cell = Vector2i(3, 3)
	var pika := CombatUnit.make("electric_starter", "player", 50)
	state.units.append(pika)
	pika.cell = Vector2i(0, 3)
	var far_entries := SkillResolver.targets(state, pika, "discharge")
	var found_far := false
	for entry in far_entries:
		if int(entry.get("unit", -1)) == 100:
			found_far = true
	t.eq(found_far, false, "草丛中的单位不能被 3 格外的放电选中")
	pika.cell = Vector2i(1, 3)
	var near_entries := SkillResolver.targets(state, pika, "discharge")
	var found_near := false
	for entry in near_entries:
		if int(entry.get("unit", -1)) == 100:
			found_near = true
	t.eq(found_near, true, "2 格内可以选中草丛目标")
	pika.cell = Vector2i(0, 5)
	# 射线不受隐蔽影响：火种可以打中草丛里的单位
	var fire_mon := CombatUnit.make("fire_starter", "player", 51)
	state.units.append(fire_mon)
	fire_mon.cell = Vector2i(0, 3)
	var ray_entries := SkillResolver.targets(state, fire_mon, "fire_seed")
	var ray_hits := false
	for entry in ray_entries:
		if entry.get("cell", Vector2i(-1, -1)) == Vector2i(3, 3):
			ray_hits = true
	t.eq(ray_hits, true, "射线技能不受草丛隐蔽限制")


func _t_move_and_undo(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	var before := fire.cell
	t.check(state.move_unit(fire, Vector2i(3, 3)), "合法移动成功")
	t.eq(fire.cell, Vector2i(3, 3), "移动后位置更新")
	t.check(state.undo_last_move(), "可以撤回移动")
	t.eq(fire.cell, before, "撤回后回到原位")
	t.check(state.move_unit(fire, Vector2i(2, 3)), "再次移动成功")
	state.commit_actions()
	t.eq(state.can_undo(), false, "提交后不能再撤回")
