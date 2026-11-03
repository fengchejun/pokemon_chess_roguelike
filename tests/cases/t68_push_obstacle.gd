extends RefCounted

const SRC := Vector2i(2, 3)
const DST := Vector2i(3, 3)

func run(t: TestContext) -> void:
	t.begin("推击岩障、碰撞填坑与搬运记录")
	_move(t)
	_collision(t)
	_fill(t)
	_persistence(t)
	_ai(t)
	t.finish()

func _state(destination: int = TerrainDB.PLAIN) -> BattleState:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[SRC, TerrainDB.OBSTACLE], [DST, destination]])
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	state.node_kind = "battle"
	state.unit_by_uid(1).cell = Vector2i(1, 3)
	state.unit_by_uid(1).skills = ["rock_push"]
	state.trainer().cell = Vector2i(0, 0)
	return state

func _hit(state: BattleState, skill: String = "rock_push") -> Dictionary:
	return SkillResolver.apply(state, state.unit_by_uid(1), skill, {"type": "cell", "cell": SRC}, false)

func _move(t: TestContext) -> void:
	for skill in ["rock_push", "push"]:
		var state := _state(TerrainDB.WATER)
		state.unit_by_uid(1).skills = [skill]
		state.unit_by_uid(1).upgrades["push_distance"] = 3
		state.unit_by_uid(1).battle_buffs["rock_push"] = true
		var preview := state.preview_skill(state.unit_by_uid(1), skill, {"type": "cell", "cell": SRC})
		t.eq(state.obstacle_durability[SRC], 2, "预览不修改真实岩障耐久")
		var actual := _hit(state, skill)
		t.eq(actual["obstacle_push"], preview["obstacle_push"], "推岩预览与实际一致")
		t.eq(state.terrain_at(SRC), TerrainDB.PLAIN, "原格恢复底板")
		t.eq(state.terrain_at(DST), TerrainDB.OBSTACLE, "强化也只搬一格")
		t.eq(state.obstacle_durability[DST], 1, "先扣1耐久再移动")
		t.eq(state.essence_earned, 0, "搬运不奖励资源")
		state.damage_obstacle(DST, 1, "player")
		t.eq(state.terrain_at(DST), TerrainDB.WATER, "破坏恢复目标原地形")
		t.eq(state.essence_earned, 1, "搬运后破坏天然岩障给一次原质")
	var fragile_rock := _state(TerrainDB.PIT)
	fragile_rock.obstacle_durability[SRC] = 1
	var broken := _hit(fragile_rock)
	t.check(broken["obstacle_push"]["destroyed"] and not broken["obstacle_push"]["filled"], "1耐久岩障先破碎不能填坑")
	t.eq(fragile_rock.terrain_at(DST), TerrainDB.PIT, "原地破碎不改变前方坑")
	for kind in [TerrainDB.TREE, TerrainDB.OBSTACLE]:
		var state := _state(kind)
		var hp := int(state.obstacle_durability[DST])
		_hit(state)
		t.eq(state.obstacle_durability[SRC], 1, "被物体挡住仍扣自身耐久")
		t.eq(state.obstacle_durability[DST], hp, "前方物体不受碰撞损伤")
	var nest := _state()
	nest.nest["cell"] = DST
	_hit(nest)
	t.eq(nest.nest["hp"], 3, "推岩不伤前方巢穴")
	t.eq(nest.obstacle_durability[SRC], 1, "巢穴阻止岩障移动")
	var facility := _state()
	facility.boss_portal_cell = DST
	_hit(facility)
	t.eq(facility.obstacle_durability[SRC], 1, "设施阻止岩障移动")
	var edge := _state()
	edge.unit_by_uid(1).cell = Vector2i(6, 3)
	edge.set_terrain(Vector2i(7, 3), TerrainDB.OBSTACLE)
	edge.obstacle_durability[Vector2i(7, 3)] = 2
	PushResolver.push_obstacle(edge, edge.unit_by_uid(1), Vector2i(7, 3))
	t.eq(edge.obstacle_durability[Vector2i(7, 3)], 1, "边界阻挡但自身扣耐久")
	var other := _state()
	other.unit_by_uid(1).skills = ["water_flow"]
	_hit(other, "water_flow")
	t.eq(other.obstacle_durability[SRC], 1, "水炮仅原地损伤岩障")
	t.eq(other.terrain_at(DST), TerrainDB.PLAIN, "其他击退不能搬岩")
	var tree := _state()
	tree.set_terrain(SRC, TerrainDB.TREE)
	tree.obstacle_durability[SRC] = 1
	_hit(tree)
	t.eq(tree.terrain_at(SRC), TerrainDB.PLAIN, "推击树木仍按直接物体伤害破坏")
	t.eq(tree.terrain_at(DST), TerrainDB.PLAIN, "树木不会被搬运")
	var cast := _state()
	cast.cast_skill(cast.unit_by_uid(1), "rock_push", {"type": "cell", "cell": SRC})
	t.check(cast.unit_by_uid(1).skill_used and cast.unit_by_uid(1).moved, "推岩消耗正常技能移动机会")

func _collision(t: TestContext) -> void:
	for side in ["enemy", "player"]:
		var state := _state()
		var victim := state.unit_by_uid(100)
		victim.side = side
		victim.cell = DST
		var hp := victim.hp
		var result := _hit(state)
		t.eq(victim.hp, hp - Balance.COLLISION_DAMAGE, "岩障撞敌我单位都造成碰撞伤害")
		t.eq(victim.cell, DST, "被撞单位不被推动")
		t.eq(state.obstacle_durability[SRC], 1, "撞人后岩障不跟进")
		t.eq(result["hits"][0]["damage"], Balance.COLLISION_DAMAGE, "返回实际碰撞命中信息")
	var frozen := _state()
	frozen.unit_by_uid(100).cell = DST
	frozen.unit_by_uid(100).frozen = true
	var hp := frozen.unit_by_uid(100).hp
	_hit(frozen)
	t.eq(frozen.unit_by_uid(100).hp, hp, "冰冻沿用一次免伤")
	t.check(not frozen.unit_by_uid(100).frozen, "碰撞解除冰冻")
	var lethal := _state()
	lethal.unit_by_uid(100).cell = DST
	lethal.unit_by_uid(100).hp = 1
	_hit(lethal)
	t.eq(lethal.unit_by_uid(100).hp, 0, "碰撞可以击杀")
	t.eq(lethal.enemy_kills.back()["killer_uid"], 1, "碰撞击杀归属施法者")
	var bonus := _state()
	bonus.unit_by_uid(100).cell = DST
	bonus.effects["push_collision"] = 2
	bonus.relic_stacks["wall_crash"] = 1
	var before := bonus.unit_by_uid(100).hp
	_hit(bonus)
	t.eq(bonus.unit_by_uid(100).hp, before - 11, "沿用碰撞加成而非技能直伤克制")

func _fill(t: TestContext) -> void:
	for kind in [TerrainDB.DEEP, TerrainDB.LAVA, TerrainDB.PIT]:
		var state := _state(kind)
		var result := _hit(state)
		t.check(result["obstacle_push"]["filled"], "岩障填危险格")
		t.eq(state.terrain_at(DST), TerrainDB.FRAGILE, "危险格转为易碎格")
		t.eq(state.terrain_at(SRC), TerrainDB.PLAIN, "填坑后原岩障消失")
		t.check(not state.obstacle_durability.has(SRC), "不保留幽灵耐久")
		t.eq(state.essence_earned, 1, "填坑消耗天然岩障奖励一次原质")
		state.damage_obstacle(SRC, 2, "player")
		t.eq(state.essence_earned, 1, "填坑不重复奖励")
		var occupied := _state(kind)
		var victim := occupied.unit_by_uid(100)
		victim.cell = DST
		victim.battle_buffs["flight"] = true
		var hp := victim.hp
		_hit(occupied)
		t.eq(victim.hp, hp - Balance.COLLISION_DAMAGE, "危险格有单位先撞人")
		t.eq(occupied.terrain_at(DST), kind, "有单位不填危险格")
	var temp := _state(TerrainDB.PIT)
	temp.natural_essence_cells.erase(SRC)
	temp.obstacle_expire_round[SRC] = 2
	_hit(temp)
	temp.round = 5
	temp.settle_round()
	t.eq(temp.terrain_at(DST), TerrainDB.FRAGILE, "临时岩障填坑也是永久易碎格")
	t.eq(temp.essence_earned, 0, "临时岩障不新增资源")

func _persistence(t: TestContext) -> void:
	var state := _state(TerrainDB.GRASS)
	state.natural_essence_cells.erase(SRC)
	state.obstacle_origin[SRC] = TerrainDB.WATER
	state.obstacle_expire_round[SRC] = 3
	_hit(state)
	t.eq(state.terrain_at(SRC), TerrainDB.WATER, "搬走临时岩障恢复原格水面")
	t.eq(state.obstacle_expire_round[DST], 3, "到期时间不延长")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.clone().obstacle_expire_round[DST], 3, "克隆读档保留到期")
	restored.round = 3
	restored.settle_round()
	t.eq(restored.terrain_at(DST), TerrainDB.GRASS, "到期恢复目标底层")
	var natural := _state()
	natural.essence_claims["terrain:3:3"] = true
	_hit(natural)
	var saved := BattleSnapshot.load_state(BattleSnapshot.save_state(natural))
	t.eq(saved.clone().obstacle_reward_origins[DST], SRC, "保存克隆保留原质来源身份")
	saved.damage_obstacle(DST, 1, "player")
	t.eq(saved.essence_earned, 1, "目标格以前领过原质不吞掉搬来岩障的奖励")
	var claimed := _state()
	claimed.essence_claims["terrain:2:3"] = true
	_hit(claimed)
	claimed.damage_obstacle(DST, 1, "player")
	t.eq(claimed.essence_earned, 0, "搬运不能绕过来源重复领取限制")
	var legacy := BattleSnapshot.save_state(_state())
	legacy["fields"].erase("obstacle_reward_origins")
	var old := BattleSnapshot.load_state(legacy)
	_hit(old)
	old.damage_obstacle(DST, 1, "player")
	t.eq(old.essence_earned, 1, "旧档使用当前格作为来源")
	var effects := _state()
	effects.place_temp_vines(DST)
	effects.ignite(DST)
	effects.steam_cells[DST] = 2
	_hit(effects)
	t.check(not effects.vine_origin.has(DST) and not effects.burning_cells.has(DST) and not effects.burning_sources.has(DST) and not effects.steam_cells.has(DST), "覆盖清除藤蔓燃烧蒸汽记录")

func _ai(t: TestContext) -> void:
	var state := _state(TerrainDB.PIT)
	state.unit_by_uid(1).cell = Vector2i(0, 0)
	state.trainer().cell = Vector2i(0, 1)
	var actor := state.unit_by_uid(100)
	actor.cell = Vector2i(1, 3)
	actor.skills = ["rock_push"]
	actor.moved = true
	state.nest["cell"] = Vector2i(3, 4)
	state.reinforcement_pool = ["rock_wild1"]
	var plan := state.begin_enemy_phase()
	t.check(plan.any(func(a): return a.get("nest_spawn_repair", false)), "AI可低优先级用岩障填出生格坑")
	while not state.enemy_phase_finished():
		state.step_enemy_phase()
	t.eq(state.terrain_at(DST), TerrainDB.FRAGILE, "AI实际执行填坑")
	var collision := _state()
	collision.unit_by_uid(1).cell = DST
	collision.unit_by_uid(100).cell = Vector2i(1, 3)
	collision.unit_by_uid(100).skills = ["rock_push"]
	collision.unit_by_uid(100).moved = true
	t.check(EnemyAI.plan(collision).any(func(a): return a.get("meta", {}).get("obstacle_push", {}).get("hits", []).size() == 1), "AI识别推岩撞玩家收益")
