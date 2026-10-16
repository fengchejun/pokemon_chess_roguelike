extends RefCounted


func run(t: TestContext) -> void:
	t.begin("直伤破障与敌方开路")
	_unit_skills(t)
	_area_skills(t)
	_rock_create(t)
	_enemy_opens_route(t)
	_enemy_bridges_lethal_ground(t)
	_enemy_clears_exit(t)
	t.finish()


func _unit_skills(t: TestContext) -> void:
	var cell := Vector2i(3, 3)
	for pair in [["ice_starter", "ice_shard"], ["rock_starter", "rock_push"], ["grass_wild1", "drain"]]:
		var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.OBSTACLE]])
		var state := TestScenario.make_state([], [[pair[0], Vector2i(2, 3)]], terrain)
		var caster := state.unit_by_uid(100)
		if not caster.skills.has(pair[1]):
			caster.skills.append(pair[1])
		var entry := {"type": "cell", "cell": cell}
		t.check(state.skill_targets(caster, pair[1]).has(entry), "%s 可以选岩障" % pair[1])
		var preview := state.preview_skill(caster, pair[1], entry)
		t.eq(int(state.obstacle_durability[cell]), 2, "%s 预览不扣耐久" % pair[1])
		t.eq(int(preview.get("obstacles_damaged", [{}])[0].get("damage", -1)), 1, "%s 预览只扣一点" % pair[1])
		var result := SkillResolver.apply(state, caster, pair[1], entry, false)
		t.check(bool(result.get("ok", false)), "%s 实际施放成功" % pair[1])
		t.eq(int(state.obstacle_durability[cell]), 1, "%s 对岩障只扣一点" % pair[1])


func _area_skills(t: TestContext) -> void:
	var cell := Vector2i(3, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]], terrain)
	var caster := state.unit_by_uid(100)
	caster.skills.append("rock_slide")
	var summary := SkillResolver.resolve_channel(state, caster, "rock_slide", [cell])
	t.eq(int(state.obstacle_durability[cell]), 1, "岩崩落点高伤仍只扣一点耐久")
	t.eq(int(summary["obstacles_damaged"][0]["damage"]), 1, "岩崩范围预览记录破障")
	var wave := TestScenario.make_state([], [["water_wild1", Vector2i(3, 2)]], terrain)
	var wave_caster := wave.unit_by_uid(100)
	wave_caster.skills.append("tsunami")
	SkillResolver.resolve_channel(wave, wave_caster, "tsunami", [cell])
	t.eq(int(wave.obstacle_durability[cell]), 1, "海啸既有范围内的障碍受击")


func _rock_create(t: TestContext) -> void:
	var cell := Vector2i(3, 2)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(2, 3)]], terrain)
	var caster := state.unit_by_uid(100)
	var entry := {"type": "dir", "dir": Vector2i(0, -1), "cell": Vector2i(2, 2)}
	var result := SkillResolver.apply(state, caster, "rock_create", entry, false)
	t.check(bool(result.get("ok", false)), "造岩可作用于已有障碍")
	t.eq(int(state.obstacle_durability[cell]), 1, "造岩对已有岩障扣一耐久且不叠岩")


func _enemy_opens_route(t: TestContext) -> void:
	var terrain := TestScenario.plain_terrain()
	for y in range(GridSpec.H):
		terrain[GridSpec.index(Vector2i(4, y))] = TerrainDB.OBSTACLE
	terrain[GridSpec.index(Vector2i(4, 3))] = TerrainDB.TREE
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(5, 3)]], terrain)
	state.trainer().cell = Vector2i(2, 3)
	var actions := EnemyAI.plan(state)
	t.check(not actions.is_empty(), "被墙隔开的敌人会规划行动")
	var opened := false
	for action in actions:
		for obstacle in action.get("meta", {}).get("obstacles_damaged", []):
			if obstacle.get("cell", Vector2i(-1, -1)) == Vector2i(4, 3) and bool(obstacle.get("destroyed", false)):
				opened = true
	t.check(opened, "敌人会用合适的直伤技能打破能接通路线的树木")


func _enemy_bridges_lethal_ground(t: TestContext) -> void:
	var terrain := TestScenario.plain_terrain()
	for y in range(GridSpec.H):
		terrain[GridSpec.index(Vector2i(4, y))] = TerrainDB.DEEP
	var state := TestScenario.make_state([], [["ice_wild1", Vector2i(5, 3)]], terrain)
	state.trainer().cell = Vector2i(2, 3)
	var actions := EnemyAI.plan(state)
	var bridged := false
	for action in actions:
		if String(action.get("skill", {}).get("id", "")) != "frozen_ground":
			continue
		for change in action.get("meta", {}).get("terrain_changes", []):
			if change.get("cell", Vector2i(-1, -1)) == Vector2i(4, 3) and int(change.get("to", -1)) == TerrainDB.ICE:
				bridged = true
	t.check(bridged, "冰系敌人在深水隔断时会以冰封大地开路")


func _enemy_clears_exit(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(6, 7)]])
	state.nest["pending_waves"] = 1
	state.trainer().cell = Vector2i(0, 0)
	var actions := EnemyAI.plan(state)
	t.check(not actions.is_empty(), "巢穴积压增援时守口敌人仍规划行动")
	if not actions.is_empty():
		t.check(not (actions[0].get("move_path", []) as Array).is_empty(), "可移动时守口敌人主动让出出口")
