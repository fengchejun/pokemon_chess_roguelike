extends RefCounted

func run(t: TestContext) -> void:
	t.begin("敌人合理开路、保护巢穴与碎岩破障")
	_open_route(t)
	_real_blockage(t)
	_nests(t)
	_rock_break(t)
	t.finish()

func _open_route(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(6, 4), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(6, 5)]], terrain)
	state.trainer().cell = Vector2i(0, 0)
	state.unit_by_uid(100).skills = ["rock_break"]
	var signature := state._signature()
	var actions := EnemyAI.plan(state)
	t.eq(state._signature(), signature, "AI模拟不改变原战场")
	t.check(not actions.is_empty(), "无攻击目标时仍规划接近")
	for action in actions:
		t.check((action.get("skill", {}) as Dictionary).is_empty(), "有接敌路线时不攻击身旁障碍")
	t.check(not (actions[0].get("move_path", []) as Array).is_empty(), "优先向玩家移动")
	var wall := TestScenario.plain_terrain()
	for y in range(7):
		wall[GridSpec.index(Vector2i(4, y))] = TerrainDB.OBSTACLE
	var detour := TestScenario.make_state([], [["rock_wild1", Vector2i(5, 3)]], wall)
	detour.trainer().cell = Vector2i(2, 3)
	detour.unit_by_uid(100).skills = ["rock_break"]
	var sim := detour.clone()
	sim.damage_obstacle(Vector2i(4, 3), 2)
	t.eq(EnemyAI._route_opening_score(detour, sim, 100), 0, "绕行可达时缩短路径不奖励无谓破障")
	var on_nest := TestScenario.make_state([], [["rock_wild1", Vector2i(7, 7)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(6, 7), TerrainDB.OBSTACLE]]))
	on_nest.nest["pending_waves"] = 1
	on_nest.trainer().cell = Vector2i(0, 0)
	on_nest.unit_by_uid(100).skills = ["rock_break"]
	var clear := EnemyAI.plan(on_nest)
	t.check(not clear.is_empty() and not (clear[0]["move_path"] as Array).is_empty(), "仍能主动让出产怪巢穴")
	for action in clear:
		t.check((action["skill"] as Dictionary).is_empty(), "让巢移动奖励不会诱发无收益技能")

func _real_blockage(t: TestContext) -> void:
	var terrain := TestScenario.plain_terrain()
	for y in range(GridSpec.H):
		terrain[GridSpec.index(Vector2i(4, y))] = TerrainDB.OBSTACLE
	var state := TestScenario.make_state([], [["ice_wild1", Vector2i(5, 3)]], terrain)
	state.trainer().cell = Vector2i(1, 3)
	var actor := state.unit_by_uid(100)
	actor.element = "rock"
	actor.skills = ["ice_shard"]
	actor.moved = true
	var actions := EnemyAI.plan(state)
	t.check(not actions.is_empty() and not (actions[0]["skill"] as Dictionary).is_empty(), "真的被墙隔断时仍会开始拆两耐久岩障")
	if not actions.is_empty():
		var hits: Array = actions[0].get("meta", {}).get("obstacles_damaged", [])
		t.check(not hits.is_empty() and int(hits[0]["damage"]) == 1, "普通技能首击削减必要障碍耐久")
	var unrelated := TestScenario.make_state([], [["rock_wild1", Vector2i(6, 3)]], TestScenario.with_cells(terrain, [[Vector2i(6, 2), TerrainDB.OBSTACLE]]))
	unrelated.trainer().cell = Vector2i(1, 3)
	var sim := unrelated.clone()
	sim.damage_obstacle(Vector2i(6, 2), 1)
	t.eq(EnemyAI._route_opening_score(unrelated, sim, 100), 0, "被墙隔断也不奖励拆无关障碍")

func _nests(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["fire_wild1", Vector2i(7, 3)]])
	state.nest["cell"] = Vector2i(4, 3)
	state.trainer().cell = Vector2i(4, 2)
	var actor := state.unit_by_uid(100)
	actor.skills = ["fire_burst"]
	actor.moved = true
	var bad_entry := {"type": "cell", "cell": Vector2i(4, 2)}
	t.check(EnemyAI._channel_score(state, actor, "fire_burst", bad_entry) < 0, "蓄力火球排除能伤及己巢的落点")
	var actions := EnemyAI.plan(state)
	var projected := state.clone()
	for action in actions:
		EnemyAI._execute_on(projected, action)
	projected.round += 1
	projected._resolve_due_channels("enemy")
	t.eq(projected.nest["hp"], Balance.NEST_DURABILITY, "敌人实际计划与释放保全己方巢穴")
	var damaged := state.clone()
	damaged.damage_nest(1, "enemy")
	t.check(EnemyAI._harms_own_nest(state, damaged), "即时技能的己巢损伤也会被识别")
	state.trainer().cell = Vector2i(4, 1)
	t.check(EnemyAI._channel_score(state, actor, "fire_burst", {"type": "cell", "cell": Vector2i(4, 0)}) > 0, "敌人仍会攻击不会伤巢的玩家落点")

func _rock_break(t: TestContext) -> void:
	for side in ["player", "enemy"]:
		for kind in [TerrainDB.OBSTACLE, TerrainDB.TREE]:
			var cell := Vector2i(3, 3)
			var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(2, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, kind]]))
			var actor := state.unit_by_uid(1 if side == "player" else 100)
			if side == "player":
				actor.cell = Vector2i(2, 2)
			actor.skills = ["rock_break"]
			var entry := {"type": "cell", "cell": cell}
			var hp := int(state.obstacle_durability[cell])
			var preview := state.preview_skill(actor, "rock_break", entry)
			t.check(preview.get("ok", false), "敌我碎岩预览可选障碍")
			t.eq(preview["obstacles_damaged"][0]["damage"], hp, "预览显示完整破障耐久")
			t.eq(state.obstacle_durability[cell], hp, "预览不提前摧毁障碍")
			var actual := SkillResolver.apply(state, actor, "rock_break", entry, false)
			t.check(actual.get("ok", false) and not state.obstacle_durability.has(cell), "碎岩一次摧毁岩障或树木")
			t.eq(state.terrain_at(cell), TerrainDB.PLAIN, "破障恢复原地面")
	var nest_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 6)]])
	nest_state.nest["cell"] = Vector2i(3, 3)
	nest_state.unit_by_uid(1).cell = Vector2i(2, 3)
	var nest_hit := SkillResolver.apply(nest_state, nest_state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": Vector2i(3, 3)}, false)
	t.check(nest_hit.get("ok", false), "碎岩仍能攻击敌方巢穴")
	t.eq(nest_state.nest["hp"], 2, "巢穴不属于碎岩一击摧毁的障碍")
