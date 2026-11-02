extends RefCounted

func run(t: TestContext) -> void:
	t.begin("异常按所属方结算与层数")
	_boundaries(t)
	_water(t)
	_water_variants(t)
	_lethal_settlement(t)
	_stacks_and_controls(t)
	_parasite_snapshot(t)
	t.finish()

func _state() -> BattleState:
	return TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(6, 6)]])

func _boundaries(t: TestContext) -> void:
	var state := _state()
	var player := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	state.apply_burn(player, enemy)
	state.apply_burn(enemy, player)
	var php := player.hp
	var ehp := enemy.hp
	state.begin_enemy_phase()
	t.eq(player.hp, php - Balance.BURN_DAMAGE, "我方结束只结算我方灼烧")
	t.eq(enemy.hp, ehp, "敌人未行动前不提前扣灼烧")
	state.end_enemy_phase()
	t.eq(player.hp, php - Balance.BURN_DAMAGE, "敌方结束不重复伤害我方")
	t.eq(enemy.hp, ehp - Balance.BURN_DAMAGE, "敌方结束只结算敌方")
	t.eq(player.burn_ticks, 1, "我方每整轮只减一层")
	t.eq(enemy.burn_ticks, 1, "敌方每整轮只减一层")
	state.settle_round()
	t.eq(player.hp, php - Balance.BURN_DAMAGE, "环境结算不重复伤害")
	state.begin_enemy_phase()
	state.end_enemy_phase()
	t.eq(player.burn_ticks + enemy.burn_ticks, 0, "两次各自行动后层数归零")

func _water(t: TestContext) -> void:
	var state := _state()
	var unit := state.unit_by_uid(1)
	unit.cell = Vector2i(1, 3)
	state.set_terrain(Vector2i(2, 3), TerrainDB.WATER)
	state.apply_burn(unit, state.unit_by_uid(100))
	var hp := unit.hp
	t.check(state.move_unit(unit, Vector2i(3, 3)), "移动经过水格再离开")
	t.eq(unit.burn_ticks, 2, "经过水格不灭火")
	state.begin_enemy_phase()
	t.eq(unit.hp, hp - Balance.BURN_DAMAGE, "终点在陆地仍受伤")
	state.end_enemy_phase()
	t.check(state.move_unit(unit, Vector2i(2, 3)), "下一回合停在水格")
	t.eq(unit.burn_ticks, 1, "停水后也要等结算")
	state.begin_enemy_phase()
	t.eq(unit.burn_ticks, 0, "所属方结束在水中灭火")
	t.eq(unit.hp, hp - Balance.BURN_DAMAGE, "水格净化先于伤害")
	var pushed := _state()
	var target := pushed.unit_by_uid(100)
	target.cell = Vector2i(3, 3)
	pushed.set_terrain(Vector2i(4, 3), TerrainDB.WATER)
	pushed.apply_burn(target, pushed.unit_by_uid(1))
	PushResolver.push(pushed, target, Vector2i(1, 0), 1, 0, "测试推击")
	t.eq(target.burn_ticks, 2, "被推入水不提前灭火")

func _stacks_and_controls(t: TestContext) -> void:
	var state := _state()
	var target := state.unit_by_uid(100)
	for index in range(5):
		state.apply_burn(target, state.unit_by_uid(1))
		state.apply_slow(target)
	t.eq(target.burn_ticks, Balance.STATUS_MAX_STACKS, "重复灼烧封顶")
	t.eq(target.slow_ticks, Balance.STATUS_MAX_STACKS, "浸湿重复施加封顶")
	var hp := target.hp
	state.begin_enemy_phase()
	t.eq(target.slow_ticks, 4, "对方结束不衰减浸湿")
	state.end_enemy_phase()
	t.eq(hp - target.hp, Balance.BURN_DAMAGE, "叠层只延时不提高伤害")
	t.eq(target.slow_ticks, 3, "所属方结束浸湿减一层")
	var control := _state()
	var player := control.unit_by_uid(1)
	player.paralyzed_ticks = 1
	player.frozen = true
	control.start_round()
	t.check(player.frozen and player.paralyzed_ticks == 1, "新整轮不提前解除控制")
	control.begin_enemy_phase()
	t.check(not player.frozen and player.paralyzed_ticks == 0, "所属方结束解除控制")

func _parasite_snapshot(t: TestContext) -> void:
	var state := _state()
	var target := state.unit_by_uid(100)
	target.parasite_ticks = 2
	target.parasite_source_uid = 1
	target.parasite_source_side = "player"
	var clone := state.clone()
	t.eq(clone.unit_by_uid(100).parasite_ticks, 2, "预览克隆保留寄生层数")
	var saved := BattleSnapshot.save_state(state)
	var loaded := BattleSnapshot.load_state(saved)
	t.eq(loaded.unit_by_uid(100).parasite_ticks, 2, "读档保留寄生层数")
	var old_unit: Dictionary = saved["units"][saved["units"].size() - 1]
	old_unit.erase("parasite_ticks")
	var legacy := BattleSnapshot.load_state(saved)
	t.eq(legacy.unit_by_uid(100).parasite_ticks, 2, "旧寄生快照补初始层数")
	state._finish_status_effects("player")
	t.eq(target.parasite_ticks, 2, "来源方结束不消耗寄生")
	state._finish_status_effects("enemy")
	t.eq(target.parasite_ticks, 1, "目标方结束消耗寄生层数")
	state._finish_status_effects("enemy")
	t.eq(target.parasite_source_uid, -1, "寄生层数耗尽解除来源")

func _water_variants(t: TestContext) -> void:
	var state := _state()
	var enemy := state.unit_by_uid(100)
	enemy.cell = Vector2i(3, 3)
	state.set_terrain(Vector2i(4, 3), TerrainDB.WATER)
	state.apply_burn(enemy, state.unit_by_uid(1))
	state.phase = BattleState.PHASE_ENEMY
	state._pending_actions = [{"uid": enemy.uid, "move_path": [Vector2i(4, 3)], "skill": {}}]
	state._pending_index = 0
	state.step_enemy_phase()
	t.eq(enemy.burn_ticks, 2, "真实敌人移动入水不立即净化")
	state.end_enemy_phase()
	t.eq(enemy.burn_ticks, 0, "敌人同样在本方结束于水中净化")
	var rain := _state()
	var player := rain.unit_by_uid(1)
	player.cell = Vector2i(2, 3)
	rain.apply_burn(player, rain.unit_by_uid(100))
	SkillResolver._convert_to_water(rain, player.cell, {"terrain_changes": []})
	t.eq(player.burn_ticks, 2, "原地生成水面也不能提前灭火")
	player.battle_buffs["flight"] = true
	var hp := player.hp
	rain.begin_enemy_phase()
	t.eq(player.hp, hp - Balance.BURN_DAMAGE, "飞行单位不获得水格净化")

func _lethal_settlement(t: TestContext) -> void:
	var state := _state()
	var trainer := state.trainer()
	trainer.hp = Balance.BURN_DAMAGE
	state.apply_burn(trainer, state.unit_by_uid(100))
	var actions := state.begin_enemy_phase()
	t.check(state.ended, "我方末灼烧击倒训练家立即结束战斗")
	t.eq(actions.size(), 0, "结算致败后不再规划敌方行动")
