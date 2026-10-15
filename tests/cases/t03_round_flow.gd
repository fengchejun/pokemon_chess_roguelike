extends RefCounted

## 回合结构：灼烧、定身、减速、巢穴增援、拾取、临时障碍与结束条件


func run(t: TestContext) -> void:
	t.begin("回合流程")
	_t_burn(t)
	_t_burn_cleared_by_water(t)
	_t_root_and_slow(t)
	_t_wet_phase_boundaries(t)
	_t_ice_slide_into_water(t)
	_t_vines_next_move(t)
	_t_burning_vines_release(t)
	_t_haste_next_move(t)
	_t_nest_spawn(t)
	_t_pickups(t)
	_t_temp_obstacle_expiry(t)
	_t_forced_retreat(t)
	_t_escape_round8(t)
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


func _t_wet_phase_boundaries(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(4, 3), TerrainDB.WATER],
		[Vector2i(1, 3), TerrainDB.WATER],
	])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], terrain)
	var enemy := state.unit_by_uid(100)
	t.eq(enemy.slow_ticks, 0, "浅水敌人在我方行动期间尚未获得浸湿")
	var forecast := state.forecast()
	var actions := state.begin_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(enemy, "water"), 1, "我方阶段结束后，浅水中的敌人获得水附着")
	t.eq(enemy.effective_move(), enemy.move_points, "水附着整轮末才转浸湿，敌方本阶段尚未减速")
	t.eq(actions, forecast, "预告按阶段交接时的水附着规划")
	enemy.cell = Vector2i(5, 3)
	state.end_enemy_phase()
	t.eq(enemy.slow_ticks, 1, "敌人离水后仍由已获得的水附着在整轮末转为浸湿")
	var player := state.unit_by_uid(1)
	player.cell = Vector2i(1, 3)
	state.phase = BattleState.PHASE_ENEMY
	state.end_enemy_phase()
	t.eq(player.slow_ticks, 1, "敌方阶段结束后，浅水中的我方获得下次行动的浸湿")
	t.eq(player.effective_move(), player.move_points - 1, "我方下一次移动减少一格")
	player.cell = Vector2i(2, 3)
	state.phase = BattleState.PHASE_ENEMY
	state.end_enemy_phase()
	t.eq(player.slow_ticks, 0, "我方离水并完成下一次行动后解除浸湿")
	var water_state := TestScenario.make_state(["water_starter"], [["water_wild1", Vector2i(4, 3)]], terrain)
	water_state.unit_by_uid(1).cell = Vector2i(1, 3)
	water_state.begin_enemy_phase()
	t.eq(water_state.unit_by_uid(100).slow_ticks, 0, "水系敌人免疫浅水浸湿")
	water_state.end_enemy_phase()
	t.eq(water_state.unit_by_uid(1).slow_ticks, 0, "水系我方免疫浅水浸湿")


func _t_ice_slide_into_water(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.ICE],
		[Vector2i(3, 3), TerrainDB.WATER],
	])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	t.check(state.move_unit(fire, Vector2i(2, 3)), "走上冰面准备滑入浅水")
	state.phase = BattleState.PHASE_ENEMY
	state.end_enemy_phase()
	t.eq(fire.cell, Vector2i(3, 3), "整轮末从冰面滑入浅水")
	t.eq(fire.slow_ticks, 0, "冰面滑行晚于阶段检查，滑入水后尚未附着")
	t.eq(fire.effective_move(), fire.move_points, "滑入水后的减速等下一次阶段结束和整轮转化")
	var immune := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var water := immune.unit_by_uid(1)
	water.cell = Vector2i(1, 3)
	immune.move_unit(water, Vector2i(2, 3))
	immune.phase = BattleState.PHASE_ENEMY
	immune.end_enemy_phase()
	t.eq(water.slow_ticks, 0, "水系滑入浅水仍免疫浸湿")


func _t_vines_next_move(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.VINES],
	])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	t.check(state.move_unit(fire, Vector2i(2, 3)), "后来踩进藤蔓格")
	t.eq(fire.vine_ticks, 2, "已用掉本轮移动，束缚保留到下次机会")
	t.check(state.undo_last_move(), "踏入藤蔓的移动可撤回")
	t.eq(fire.vine_ticks, 0, "撤回恢复束缚状态")
	t.check(state.move_unit(fire, Vector2i(2, 3)), "再次走入藤蔓")
	state.begin_enemy_phase()
	t.eq(fire.vine_ticks, 1, "我方阶段结束后仍束缚下一次移动")
	state.end_enemy_phase()
	t.eq(fire.can_move_now(), false, "下一轮我方不能移动，但仍可施法")
	t.eq(fire.can_act_skill(), true, "藤蔓不禁止技能")
	state.begin_enemy_phase()
	t.eq(fire.vine_ticks, 0, "被束缚的一次行动结束后解除，不会因仍在藤蔓上永久定身")
	var create := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var grass := create.unit_by_uid(1)
	grass.cell = Vector2i(2, 3)
	create.set_terrain(Vector2i(3, 3), TerrainDB.VINES)
	t.eq(create.unit_by_uid(100).vine_ticks, 1, "藤蔓在尚未行动的敌人脚下生成，阻止本次敌方移动")
	create.begin_enemy_phase()
	t.eq(create.unit_by_uid(100).can_move_now(), false, "敌方阶段开始时束缚仍有效")
	create.end_enemy_phase()
	t.eq(create.unit_by_uid(100).vine_ticks, 0, "敌人行动阶段结束后束缚解除")
	var pushed := TestScenario.make_state([], [["rock_wild1", Vector2i(3, 3)]], terrain)
	var pushed_enemy := pushed.unit_by_uid(100)
	pushed.set_terrain(Vector2i(4, 3), TerrainDB.VINES)
	PushResolver.push(pushed, pushed_enemy, Vector2i.RIGHT, 1, 0, "测试推击", "player")
	t.eq(pushed_enemy.cell, Vector2i(4, 3), "强制位移能进入藤蔓")
	t.eq(pushed_enemy.vine_ticks, 1, "被推到藤蔓上的敌人本次移动受阻")
	var flying := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var flyer := flying.unit_by_uid(1)
	flyer.cell = Vector2i(2, 3)
	flyer.battle_buffs["flight"] = true
	flying.apply_vine_on_landing(flyer)
	t.eq(flyer.vine_ticks, 0, "飞行单位不受藤蔓格束缚")


func _t_burning_vines_release(t: TestContext) -> void:
	var cell := Vector2i(2, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.VINES]])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	state.ignite(cell)
	state.burning_cells[cell] = 1
	state.begin_enemy_phase()
	PushResolver.push(state, fire, Vector2i.RIGHT, 1, 0, "测试推击", "enemy")
	t.eq(fire.cell, cell, "我方阶段后被推入即将烧尽的藤蔓")
	t.eq(fire.vine_ticks, 1, "敌方阶段踩入藤蔓会束缚下次移动")
	state.end_enemy_phase()
	t.eq(state.terrain_at(cell), TerrainDB.PLAIN, "完整回合结算后藤蔓烧尽")
	t.eq(fire.vine_ticks, 0, "藤蔓烧尽时立即解除脚下束缚")
	t.check(fire.can_move_now(), "藤蔓烧尽后的下一轮可正常移动")


func _t_haste_next_move(t: TestContext) -> void:
	var state := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var fire := state.unit_by_uid(2)
	fire.cell = Vector2i(2, 3)
	state.apply_haste(fire)
	t.eq(fire.haste_ticks, 1, "尚未移动的友军获得本次移动加速")
	t.eq(fire.effective_move(), fire.move_points + 2, "加速立即增加移动距离")
	state.begin_enemy_phase()
	t.eq(fire.haste_ticks, 0, "本次我方移动机会结束后加速解除")
	var after_move := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var later := after_move.unit_by_uid(2)
	later.moved = true
	after_move.apply_haste(later)
	t.eq(later.haste_ticks, 2, "已经移动的友军把加速留给下一次机会")
	after_move.begin_enemy_phase()
	t.eq(later.haste_ticks, 1, "本轮结束前保留下次加速")
	after_move.end_enemy_phase()
	t.eq(later.effective_move(), later.move_points + 2, "下一轮我方可以使用加速移动")
	after_move.begin_enemy_phase()
	t.eq(later.haste_ticks, 0, "加速只覆盖下一次移动机会")


func _t_nest_spawn(t: TestContext) -> void:
	for battle_round in range(1, Balance.MAX_ROUNDS + 1):
		t.eq(Balance.nest_wave_due(battle_round), battle_round in [2, 4, 6], "8 回合制仅第 2、4、6 回合新增产怪计划：%d" % battle_round)
		t.eq(Balance.nest_warning_due(battle_round), battle_round in [1, 3, 5], "产怪前一回合显示预警：%d" % battle_round)
	var state := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["fire_wild1"])
	t.eq(state.alive_enemy_count(), 1, "初始 1 只野生")
	state.start_round()
	t.eq(state.round, 2, "进入第 2 回合")
	t.eq(state.alive_enemy_count(), 2, "第 2 回合巢穴生成 1 只")
	var spawned := _newest_enemy(state)
	t.check(spawned != null, "找到生成单位")
	if spawned != null:
		t.eq(spawned.fresh_spawn, true, "新生成单位本回合不能再次行动")
		t.check(not spawned.moved and spawned.cell == state.nest["exits"][0], "新生成单位在出口待机且本轮不能移动")
		spawned.cell = Vector2i(5, 7)
		state.start_round()
		t.eq(state.alive_enemy_count(), 2, "第 3 回合不产怪")
		state.start_round()
		t.eq(state.alive_enemy_count(), 3, "第 4 回合再生成 1 只")
		var fourth_spawn := _newest_enemy(state)
		fourth_spawn.cell = Vector2i(4, 7)
		state.start_round()
		t.eq(state.alive_enemy_count(), 3, "第 5 回合只预警，不新增怪")
		state.start_round()
		t.eq(state.alive_enemy_count(), 4, "第 6 回合生成第三只增援")
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
	var queued := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["fire_wild1"])
	var gate := CombatUnit.make("water_starter", "player", 901)
	gate.cell = queued.nest["exits"][0]
	queued.units.append(gate)
	for _turn in range(2, 7):
		queued.start_round()
	t.eq(queued.round, 6, "堵口持续到第 6 回合")
	t.eq(int(queued.nest["pending_waves"]), 3, "第 2、4、6 回合的三次产怪均排队保留")
	t.eq(queued.alive_enemy_count(), 1, "堵口期间没有怪物穿过出口")
	gate.cell = Vector2i(0, 0)
	queued.start_round()
	t.eq(int(queued.nest["pending_waves"]), 2, "第 7 回合出口空出后只补产一只")
	queued.units.back().cell = Vector2i(4, 7)
	queued.start_round()
	t.eq(int(queued.nest["pending_waves"]), 1, "第 8 回合不新增波次，但继续补产队列中的一只")


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
	state.begin_enemy_phase()
	t.eq(state.reward["state"], "guarding", "己方在奖励格结束行动，开始守点")
	state.end_enemy_phase()
	t.eq(state.reward["state"], "carried", "敌方阶段结束后由守点者持有奖励")
	t.eq(state.reward_owner().uid, fire.uid, "奖励记录实际守点者")
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


func _t_escape_round8(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["fire_wild1", Vector2i(5, 7)]])
	state.round = Balance.MAX_ROUNDS - 1
	state.settle_round()
	t.check(not state.ended, "第 7 回合结算后战斗继续")
	state.round = Balance.MAX_ROUNDS
	state.settle_round()
	t.eq(state.end_reason, "escape", "第 8 回合结算后野生逃离")


func _t_victory(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(2, 3)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	fire.skills.append("fire_seed") # 兼容招式不在现行装备表，显式装备用于旧规则回归。
	state.unit_by_uid(100).hp = 2
	state.cast_skill(fire, "fire_seed", {"type": "cell", "cell": Vector2i(2, 3)})
	t.eq(state.unit_by_uid(100).hp <= 0, true, "火种击败野生")
	t.eq(state.end_reason, "victory", "全部敌人被击败立即胜利")
	t.eq(state.battle_exp(), 2, "击败获得 2 经验")
