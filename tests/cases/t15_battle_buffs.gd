extends RefCounted


func run(t: TestContext) -> void:
	t.begin("战场奖励 Buff")
	_t_claims(t)
	_t_flight_and_defense(t)
	_t_skill_buffs(t)
	t.finish()


func _t_claims(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var fire := state.unit_by_uid(1)
	fire.cell = state.reward["cell"]
	state.phase = BattleState.PHASE_ENEMY
	state.end_enemy_phase()
	t.eq(state.phase, BattleState.PHASE_REWARD, "我方守点在敌方阶段结束后暂停结算")
	t.eq(state.reward["state"], "pending", "奖励等待我方二选一")
	var options: Array = state.reward["options"]
	t.eq(options.size(), 2, "提供两个不同 Buff")
	t.check(options[0] != options[1], "两个选项不重复")
	t.eq(options, BattleBuffDB.offer(fire, state.run_seed, state.battle_index), "同一种子选项稳定")
	t.eq(state.round, 1, "选择前不进入下一回合")
	t.eq(state.resolve_reward_choice("invalid"), false, "不能选择未提供的 Buff")
	var chosen := String(options[0])
	t.check(state.resolve_reward_choice(chosen), "选择有效 Buff 继续结算")
	t.eq(state.reward["state"], "claimed", "一次领取后奖励格消失")
	t.check(fire.has_buff(chosen), "Buff 附于实际守点单位")
	t.eq(TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]]).unit_by_uid(1).battle_buffs.size(), 0, "下一场新单位不继承本场 Buff")
	t.eq(state.resolve_reward_choice(chosen), false, "奖励不可重复领取")
	var enemy_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 4)]])
	enemy_state.reward["cell"] = Vector2i(6, 4)
	enemy_state.begin_enemy_phase()
	t.eq(enemy_state.reward["state"], "claimed", "敌人守到我方阶段结束自动领取")
	t.check(not enemy_state.unit_by_uid(100).battle_buffs.is_empty(), "敌方领取的 Buff 当即生效")
	var enemy_repeat := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 4)]])
	enemy_repeat.reward["cell"] = Vector2i(6, 4)
	enemy_repeat.begin_enemy_phase()
	t.eq(enemy_state.reward["buff_id"], enemy_repeat.reward["buff_id"], "敌方自动选择可由本场种子复现")
	var damage_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	damage_state.reward["cell"] = Vector2i(4, 3)
	damage_state.unit_by_uid(1).cell = Vector2i(0, 3)
	SkillResolver.apply(damage_state, damage_state.unit_by_uid(1), "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.eq(damage_state.reward["state"], "destroyed", "空奖励格被火球伤害摧毁")
	var final_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	final_state.unit_by_uid(1).cell = final_state.reward["cell"]
	final_state.round = Balance.MAX_ROUNDS
	final_state.phase = BattleState.PHASE_ENEMY
	final_state.end_enemy_phase()
	t.eq(final_state.reward["state"], "map", "第六回合敌方结束后不再发放 Buff")
	var trainer := CombatUnit.make("trainer", "player", 5)
	t.eq(BattleBuffDB.eligible(trainer).size(), 4, "训练家只抽到四种通用 Buff")


func _t_flight_and_defense(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 1), TerrainDB.OBSTACLE],
		[Vector2i(3, 1), TerrainDB.DEEP],
		[Vector2i(4, 1), TerrainDB.PIT],
	])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], terrain)
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 1)
	t.eq(state.move_options(fire).has(Vector2i(4, 1)), false, "地面单位无法三步越障进入深坑")
	fire.battle_buffs["flight"] = true
	t.check(state.move_options(fire).has(Vector2i(4, 1)), "飞行三步越障与深水并能停在深坑")
	t.check(state.move_unit(fire, Vector2i(4, 1)), "飞行实际移动与预览一致")
	t.check(fire.is_alive(), "飞行停在深坑不坠落")
	var occupied := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var flyer_path := occupied.unit_by_uid(1)
	flyer_path.cell = Vector2i(1, 3)
	flyer_path.battle_buffs["flight"] = true
	t.check(occupied.move_options(flyer_path).has(Vector2i(3, 3)), "飞行可越过敌方占用格")
	t.eq(occupied.move_options(flyer_path).has(Vector2i(2, 3)), false, "飞行仍不能停在占用格")
	var push_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(3, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.PIT]]))
	var flyer := push_state.unit_by_uid(100)
	flyer.battle_buffs["flight"] = true
	PushResolver.push(push_state, flyer, Vector2i(1, 0), 1, 0, "测试")
	t.eq(flyer.cell, Vector2i(4, 3), "飞行被推入深坑仍能停留")
	t.check(flyer.is_alive(), "飞行推击落点免疫坠落")
	var immune := CombatUnit.make("fire_starter", "player", 8)
	immune.burn_ticks = 2
	immune.slow_ticks = 2
	var immune_state := TestScenario.make_state([], [["rock_wild1", Vector2i(6, 6)]])
	immune_state.units.append(immune)
	immune_state.reward = {"state": "pending", "cell": Vector2i(5, 5), "owner_uid": immune.uid, "options": ["status_immune", "move_plus"], "buff_id": ""}
	immune_state.phase = BattleState.PHASE_REWARD
	t.check(immune_state.resolve_reward_choice("status_immune"), "免疫 Buff 可正常领取")
	t.eq(immune.burn_ticks + immune.slow_ticks, 0, "取得免疫立即清除灼烧浸湿")
	immune_state.apply_burn(immune, null)
	immune_state.apply_slow(immune)
	t.eq(immune.burn_ticks + immune.slow_ticks, 0, "免疫期间不可重新获得对应状态")
	var faster := CombatUnit.make("wind_starter", "player", 9)
	var base_move := faster.effective_move()
	faster.battle_buffs["move_plus"] = true
	t.eq(faster.effective_move(), base_move + 1, "移动 Buff 使实际移动上限 +1")
	var guard_state := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(3, 3)]])
	var attacker := guard_state.unit_by_uid(1)
	var guarded := guard_state.unit_by_uid(100)
	guarded.battle_buffs["direct_guard"] = true
	var before := guarded.hp
	guard_state.damage_unit(attacker, guarded, 2, {"element": "rock", "cause": "技能"})
	t.eq(guarded.hp, before - 1, "技能直接伤害减免一")
	guard_state.damage_unit(null, guarded, 1, {"no_element": true, "cause": "碰撞"})
	t.eq(guarded.hp, before - 2, "碰撞伤害不被减免")
	guard_state.damage_unit(attacker, guarded, 1, {"element": "rock", "conductive": true})
	t.eq(guarded.hp, before - 3, "导电伤害不被减免")


func _t_skill_buffs(t: TestContext) -> void:
	var fire_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)]])
	var fire := fire_state.unit_by_uid(1)
	fire.cell = Vector2i(0, 3)
	fire.battle_buffs["fire_burst"] = true
	SkillResolver.apply(fire_state, fire, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}, false)
	t.check(fire_state.unit_by_uid(100).burn_ticks > 0, "强化火球外围附灼烧")
	var charge_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(1, 3)]])
	var charger := charge_state.unit_by_uid(1)
	charger.cell = Vector2i(0, 3)
	charger.battle_buffs["flame_charge"] = true
	var hp := charge_state.unit_by_uid(100).hp
	SkillResolver.apply(charge_state, charger, "flame_charge", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.eq(charge_state.unit_by_uid(100).hp, hp - 1, "强化冲锋沿途直伤一")
	var water_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var water := water_state.unit_by_uid(1)
	water.cell = Vector2i(0, 3)
	water.battle_buffs["water_flow"] = true
	SkillResolver.apply(water_state, water, "water_flow", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.eq(water_state.unit_by_uid(100).cell, Vector2i(4, 3), "强化水流击退两格")
	var rain_state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var rain := rain_state.unit_by_uid(1)
	rain.cell = Vector2i(0, 3)
	rain.battle_buffs["rain_call"] = true
	SkillResolver.apply(rain_state, rain, "rain_call", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(rain_state.unit_by_uid(100).slow_ticks > 0, "强化造雨立即浸湿单位")
	var electric_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.WATER], [Vector2i(3, 3), TerrainDB.WATER]])
	var electric_state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)]], electric_terrain)
	var electric := electric_state.unit_by_uid(1)
	electric.cell = Vector2i(1, 3)
	electric.battle_buffs["electric_arc"] = true
	SkillResolver.apply(electric_state, electric, "electric_arc", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(electric_state.unit_by_uid(100).slow_ticks > 0, "强化放电命中附浸湿")
	var rock_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.FRAGILE]])
	var break_state := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 6)]], rock_terrain)
	var breaker := break_state.unit_by_uid(1)
	breaker.cell = Vector2i(0, 3)
	breaker.battle_buffs["rock_break"] = true
	var break_entry := {"type": "cell", "cell": Vector2i(2, 3)}
	t.check(break_state.skill_targets(breaker, "rock_break").has(break_entry), "强化碎岩可瞄准易碎地块")
	SkillResolver.apply(break_state, breaker, "rock_break", break_entry, false)
	t.eq(break_state.terrain_at(Vector2i(2, 3)), TerrainDB.PIT, "强化碎岩击碎地面")
	var push_state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(3, 3)]])
	var pusher := push_state.unit_by_uid(1)
	pusher.cell = Vector2i(2, 3)
	pusher.battle_buffs["rock_push"] = true
	SkillResolver.apply(push_state, pusher, "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}, false)
	t.eq(push_state.unit_by_uid(100).cell, Vector2i(5, 3), "强化推击两格")
	var push_preview_state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(3, 3)]])
	push_preview_state.unit_by_uid(1).cell = Vector2i(2, 3)
	push_preview_state.unit_by_uid(1).battle_buffs["rock_push"] = true
	var preview := push_preview_state.preview_skill(push_preview_state.unit_by_uid(1), "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)})
	t.eq(preview["hits"][0]["push"]["to"], Vector2i(5, 3), "强化推击预览与实战同为两格")
	var wall_state := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 6)]])
	var waller := wall_state.unit_by_uid(1)
	waller.cell = Vector2i(2, 3)
	waller.battle_buffs["rock_create"] = true
	SkillResolver.apply(wall_state, waller, "rock_create", {"type": "dir", "dir": Vector2i(0, -1), "cell": Vector2i(2, 2)}, false)
	t.eq(int(wall_state.obstacle_expire_round.get(Vector2i(2, 2), -1)), wall_state.round + 1, "强化造岩多维持一轮")
