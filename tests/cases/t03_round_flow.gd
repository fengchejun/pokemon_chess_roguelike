extends RefCounted

## 回合结构：灼烧、定身、减速、巢穴增援、拾取、临时障碍与结束条件


func run(t: TestContext) -> void:
	t.begin("回合流程")
	_t_burn(t)
	_t_burn_cleared_by_water(t)
	_t_root_and_slow(t)
	_t_nest_spawn(t)
	_t_pickups(t)
	_t_temp_obstacle_expiry(t)
	_t_forced_retreat(t)
	_t_escape_round4(t)
	_t_victory(t)
	t.finish()


func _t_burn(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["grass_wild1", Vector2i(4, 3)]])
	var fire := CombatUnit.make("fire_starter", "player", 50)
	state.units.append(fire)
	fire.cell = Vector2i(0, 3)
	var wild := state.unit_by_uid(100)
	state.apply_burn(wild, fire)
	t.eq(wild.burn_ticks, 2, "灼烧初始 2 回合")
	state.settle_round()
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - 1, "第一次结算 1 伤害")
	t.eq(wild.burn_ticks, 1, "灼烧剩余 1 回合")
	state.settle_round()
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1") - 2, "第二次结算 1 伤害")
	t.eq(wild.burn_ticks, 0, "灼烧结束")
	# 火系免疫
	var state2 := TestScenario.make_state([], [["fire_wild1", Vector2i(4, 3)]])
	var fire2 := CombatUnit.make("fire_starter", "player", 50)
	state2.units.append(fire2)
	fire2.cell = Vector2i(0, 3)
	state2.apply_burn(state2.unit_by_uid(100), fire2)
	t.eq(state2.unit_by_uid(100).burn_ticks, 0, "火系免疫灼烧")


func _t_burn_cleared_by_water(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.WATER],
	])
	var state := TestScenario.make_state([], [["grass_wild1", Vector2i(4, 3)]], terrain)
	var fire := CombatUnit.make("fire_starter", "player", 50)
	state.units.append(fire)
	fire.cell = Vector2i(0, 3)
	var wild := state.unit_by_uid(100)
	state.apply_burn(wild, fire)
	wild.cell = Vector2i(2, 3)
	state.settle_round()
	t.eq(wild.burn_ticks, 0, "进入水面解除灼烧")
	t.eq(wild.hp, SpeciesDB.hp_of("grass_wild1"), "解除后不再受到灼烧伤害")


func _t_root_and_slow(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(4, 3)]])
	var wild := state.unit_by_uid(100)
	state.apply_root(wild)
	t.eq(wild.root_pending, true, "定身标记生效")
	state.start_round()
	t.eq(wild.move_cancelled, true, "定身取消下一次移动")
	t.eq(wild.root_pending, false, "定身已消耗")
	state.start_round()
	t.eq(wild.move_cancelled, false, "一轮后定身解除")
	# 减速
	state.apply_slow(wild)
	t.eq(wild.slow_ticks, 2, "减速已挂载")
	t.eq(wild.effective_move(), wild.move_points - 1, "减速使移动上限 −1")
	state.settle_round()
	t.eq(wild.slow_ticks, 1, "缓慢衰减")
	state.settle_round()
	t.eq(wild.slow_ticks, 0, "1 回合后解除")


func _t_nest_spawn(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["fire_wild1"])
	t.eq(state.alive_enemy_count(), 1, "初始 1 只野生")
	state.start_round()
	t.eq(state.round, 2, "进入第 2 回合")
	t.eq(state.alive_enemy_count(), 2, "第 2 回合巢穴生成 1 只")
	var spawned := _newest_enemy(state)
	t.check(spawned != null, "找到生成单位")
	if spawned != null:
		t.eq(spawned.fresh_spawn, true, "新生成单位本回合在洞口待机")
		spawned.cell = Vector2i(5, 7)
		state.start_round()
		t.eq(state.alive_enemy_count(), 2, "第 3 回合不产怪")
		state.start_round()
		t.eq(state.alive_enemy_count(), 3, "第 4 回合再生成 1 只")
	# 摧毁巢穴后停止
	var state2 := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["fire_wild1"])
	state2.nest["hp"] = 1
	state2.damage_nest(2)
	t.eq(state2.nest["alive"], false, "巢穴被摧毁")
	state2.start_round()
	t.eq(state2.alive_enemy_count(), 1, "摧毁后不再生成")
	# 出口被占：生成被阻止
	var state3 := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["fire_wild1"])
	var nest_cell: Vector2i = state3.nest["cell"]
	var exits: Array = state3.nest["exits"]
	for cell in exits:
		var blocker := CombatUnit.make("fire_wild1", "enemy", 900 + exits.find(cell))
		blocker.cell = cell
		state3.units.append(blocker)
	var ring := GridSpec.neighbors8(nest_cell)
	for cell in ring:
		var blocker2 := CombatUnit.make("fire_wild1", "enemy", 950 + ring.find(cell))
		blocker2.cell = cell
		state3.units.append(blocker2)
	var before := state3.alive_enemy_count()
	state3.start_round()
	t.eq(state3.alive_enemy_count(), before, "出口与相邻格全被占时生成被阻止")


func _newest_enemy(state: BattleState) -> CombatUnit:
	var newest: CombatUnit = null
	for unit in state.units:
		if unit.side == "enemy":
			newest = unit
	return newest


func _t_pickups(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [])
	var fire := state.unit_by_uid(1)
	fire.cell = state.reward["cell"]
	state.settle_round()
	t.eq(state.reward["state"], "carried", "停留在奖励格拾取奖励")
	t.eq(state.carrier_uid(), fire.uid, "拾取者成为携带者")
	state.kill_unit(fire, "测试死亡", "enemy")
	t.eq(state.reward["state"], "dropped", "携带者阵亡奖励掉落")
	var water_mon := CombatUnit.make("water_starter", "player", 2)
	state.units.append(water_mon)
	water_mon.cell = state.reward["cell"]
	state.settle_round()
	t.eq(state.reward["state"], "carried", "掉落奖励可以再次拾取")
	t.eq(state.carrier_uid(), water_mon.uid, "新携带者生效")
	# 恢复果实
	var fruits_state := TestScenario.make_state(["fire_starter"], [])
	var fmon := fruits_state.unit_by_uid(1)
	fmon.hp = 2
	fruits_state.fruits.append(Vector2i(1, 1))
	fmon.cell = Vector2i(1, 1)
	fruits_state.settle_round()
	t.eq(fmon.hp, 4, "拾取恢复果实回复 2 生命")
	t.eq(fruits_state.fruits.size(), 0, "果实被消耗")
	# 踩上即拾取；撤销移动时连同果实一起回滚
	var move_state := TestScenario.make_state(["fire_starter"], [])
	move_state.trainer().cell = Vector2i(0, 7)
	var mmon := move_state.unit_by_uid(1)
	mmon.cell = Vector2i(0, 3)
	mmon.hp = 2
	move_state.fruits.append(Vector2i(2, 3))
	t.eq(move_state.move_unit(mmon, Vector2i(2, 3)), true, "移动到果实格")
	t.eq(mmon.hp, 4, "踩上即拾取并回复 2 生命")
	t.eq(move_state.fruits.size(), 0, "果实立即被消耗")
	t.eq(move_state.undo_last_move(), true, "撤回移动")
	t.eq(mmon.hp, 2, "撤回后回复被回滚")
	t.eq(move_state.fruits.size(), 1, "撤回后果实回到原位")
	t.eq(move_state.fruits[0], Vector2i(2, 3), "果实位置正确")
	# 满血踩上也同样消耗（拾取即拾取）
	mmon.hp = SpeciesDB.hp_of("fire_starter")
	move_state.move_unit(mmon, Vector2i(2, 3))
	t.eq(mmon.hp, SpeciesDB.hp_of("fire_starter"), "满血拾取不回血")
	t.eq(move_state.fruits.size(), 0, "满血拾取同样消耗果实")


func _t_temp_obstacle_expiry(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [])
	var rock := state.unit_by_uid(1)
	rock.cell = Vector2i(2, 3)
	SkillResolver.apply(state, rock, "rock_create", {"type": "dir", "dir": Vector2i(0, -1), "cell": Vector2i(2, 2)}, false)
	t.eq(state.terrain_at(Vector2i(2, 2)), TerrainDB.OBSTACLE, "临时障碍生成")
	state.settle_round()
	t.eq(state.terrain_at(Vector2i(2, 2)), TerrainDB.PLAIN, "本轮敌方阶段后消失")


func _t_forced_retreat(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["fire_wild1", Vector2i(5, 3)]])
	var trainer := state.trainer()
	var enemy := state.unit_by_uid(100)
	state.damage_unit(enemy, trainer, 99, {"cause": "测试", "no_element": true})
	t.eq(state.end_reason, "forced_retreat", "训练家倒下触发强制撤退")
	t.eq(trainer.hp, 1, "训练家以 1 生命保留")
	t.eq(state.battle_exp(), 0, "强制撤退不结算本场经验")


func _t_escape_round4(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["fire_wild1", Vector2i(5, 7)]])
	state.round = Balance.MAX_ROUNDS
	state.settle_round()
	t.eq(state.end_reason, "escape", "第 4 回合结算后野生逃离")


func _t_victory(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(2, 3)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	state.unit_by_uid(100).hp = 2
	state.cast_skill(fire, "fire_seed", {"type": "cell", "cell": Vector2i(2, 3)})
	t.eq(state.unit_by_uid(100).hp <= 0, true, "火种击败野生")
	t.eq(state.end_reason, "victory", "全部敌人被击败立即胜利")
	t.eq(state.battle_exp(), 2, "击败获得 2 经验")
