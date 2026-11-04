extends RefCounted

func run(t: TestContext) -> void:
	t.begin("敌人低优先级疏通巢穴出生格")
	_obstacles(t)
	_terrain(t)
	_priority(t)
	t.finish()

func _state(kind: int = TerrainDB.OBSTACLE, pool: Array = ["rock_wild1"]) -> BattleState:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(5, 3), kind]])
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(5, 2)]], terrain, {}, {}, pool)
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(5, 4)
	state.trainer().cell = Vector2i(0, 0)
	state.unit_by_uid(1).cell = Vector2i(0, 1)
	state.unit_by_uid(100).skills = ["rock_break"]
	state.unit_by_uid(100).moved = true
	return state

func _action(state: BattleState) -> Dictionary:
	for action in EnemyAI.plan(state):
		if int(action["uid"]) == 100:
			return action
	return {}

func _execute(state: BattleState) -> Array:
	var actions := state.begin_enemy_phase()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
	return actions

func _obstacles(t: TestContext) -> void:
	for kind in [TerrainDB.OBSTACLE, TerrainDB.TREE]:
		var state := _state(kind)
		var signature := state._signature()
		var action := _action(state)
		t.check(action.get("nest_spawn_repair", false), "攻击不到玩家时疏通出生格障碍")
		t.eq(state._signature(), signature, "清路规划不改变实战状态")
		t.eq(action.get("skill", {}).get("id", ""), "rock_break", "只使用已有碎岩技能")
		_execute(state)
		t.eq(state.terrain_at(Vector2i(5, 3)), TerrainDB.PLAIN, "实战拆除出生格障碍")
		t.eq(state.nest["hp"], 30, "清理不伤及己方巢穴")
		state.nest["pending_waves"] = 1
		state._try_spawn_wave()
		t.eq(state.units.back().cell, Vector2i(5, 3), "清出的出生格实际用于补产增援")
	var trade := _state()
	var worse := trade.clone()
	worse.damage_obstacle(Vector2i(5, 3), 2)
	worse.place_temp_obstacle(Vector2i(6, 4), TerrainDB.PLAIN, 4)
	t.check(EnemyAI._nest_spawn_repair_score(trade, worse, 100) <= 0, "不能为清一个出生格又堵住另一个出生格")
	var partial := _state()
	partial.unit_by_uid(100).skills = ["ice_shard"]
	t.check(_action(partial).get("nest_spawn_repair", false), "普通伤害可先削一层必要障碍耐久")
	_execute(partial)
	t.eq(partial.obstacle_durability[Vector2i(5, 3)], 1, "实战首击削减耐久")
	var unrelated := _state()
	unrelated.nest["cell"] = Vector2i(7, 6)
	t.check(_action(unrelated).get("skill", {}).is_empty(), "不借产怪清理名义攻击无关障碍")
	var stopped := _state()
	stopped.stop_nests()
	t.check(_action(stopped).get("skill", {}).is_empty(), "巢穴摧毁后停止清理出生格")
	var empty_pool := _state(TerrainDB.OBSTACLE, [])
	t.check(_action(empty_pool).get("skill", {}).is_empty(), "没有增援池不做产怪工程")

func _terrain(t: TestContext) -> void:
	for kind in [TerrainDB.PIT, TerrainDB.DEEP, TerrainDB.LAVA]:
		for skill in ["frozen_ground", "wild_vines"]:
			var state := _state(kind)
			state.unit_by_uid(100).skills = [skill]
			var action := _action(state)
			t.check(action.get("nest_spawn_repair", false), "%s会修复不可出生地形%s" % [skill, kind])
			_execute(state)
			t.check(TerrainDB.can_stand(state.terrain_at(Vector2i(5, 3)), "rock"), "实战修复后岩系增援能站立")
			t.eq(state.terrain_at(state.nest["cell"]), TerrainDB.PLAIN, "修复地形不覆盖巢穴")
			state.nest["pending_waves"] = 1
			state._try_spawn_wave()
			t.eq(state.units.back().cell, Vector2i(5, 3), "修复后的危险格实际可出生")
	var water := _state(TerrainDB.DEEP, ["water_wild1"])
	water.unit_by_uid(100).skills = ["frozen_ground"]
	t.check(_action(water).get("skill", {}).is_empty(), "深水已适合水系增援时不做无效改造")
	var incapable := _state(TerrainDB.LAVA)
	incapable.unit_by_uid(100).skills = ["rain_call"]
	t.check(not _action(incapable).get("nest_spawn_repair", false), "造雨无法改变岩浆时不虚假施法清理")
	var channel := _state()
	channel.unit_by_uid(100).skills = ["tsunami"]
	t.check(_action(channel).get("nest_spawn_repair", false), "可用安全蓄力技能清除障碍")
	_execute(channel)
	t.check(not channel.pending_casts.is_empty(), "实际蓄力宣告遵循正常吟唱时序")
	channel.end_enemy_phase()
	_execute(channel)
	t.eq(channel.obstacle_durability[Vector2i(5, 3)], 1, "下一敌方阶段蓄力落下削减必要障碍耐久")
	var unsafe := _state()
	unsafe.unit_by_uid(100).skills = ["fire_burst"]
	unsafe.unit_by_uid(100).cell = Vector2i(5, 1)
	t.check(not _action(unsafe).get("nest_spawn_repair", false), "蓄力范围会伤到己巢时不为清路冒险")

func _priority(t: TestContext) -> void:
	var attack := _state()
	attack.unit_by_uid(1).cell = Vector2i(4, 2)
	var action := _action(attack)
	t.check(not action.get("nest_spawn_repair", false) and not action.get("skill", {}).is_empty(), "能攻击玩家时优先攻击")
	var guard := _state()
	guard.nest["hp"] = 1
	guard.unit_by_uid(100).cell = Vector2i(6, 4)
	guard.unit_by_uid(1).cell = Vector2i(3, 4)
	guard.unit_by_uid(1).skills = ["rock_break"]
	guard.unit_by_uid(100).skills = ["ice_shard"]
	guard.unit_by_uid(1).cell = Vector2i(2, 4)
	# 射程三格内没有有效攻击，但玩家仍处在残血巢穴附近。
	t.check(_action(guard).has("guard"), "需要保护巢穴时守护优先于产怪清路")
