extends RefCounted


func run(t: TestContext) -> void:
	t.begin("战场奖励守点与旧 Buff 效果")
	_t_reward_credit(t)
	_t_flight_and_defense(t)
	_t_skill_buffs(t)
	t.finish()


func _t_reward_credit(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var fire := state.unit_by_uid(1)
	fire.cell = state.reward["cell"]
	t.eq(state.reward["state"], "map", "站上奖励点不会立即领取")
	state.begin_enemy_phase()
	t.eq(state.reward["state"], "guarding", "结束我方行动后开始守点")
	state.damage_unit(state.unit_by_uid(100), fire, 1, {"no_element": true, "cause": "测试"})
	t.check(fire.is_alive() and state.reward["state"] == "guarding", "守点者受伤但存活，奖励仍可领取")
	state.end_enemy_phase()
	t.eq(state.reward["state"], "carried", "敌方行动结束后由原守点者领取")
	t.eq(state.reward_owner().uid, fire.uid, "战场奖励记在守点者身上")
	t.eq(fire.battle_buffs.size(), 0, "奖励点不再立即提供本场 Buff")
	fire.cell = Vector2i(5, 4)
	state.end_battle("victory")
	t.check(state.reward_bonus_earned(), "领取后可以离开，存活到战斗结束即可获得额外选择次数")
	var early := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	early.unit_by_uid(1).cell = early.reward["cell"]
	early.end_battle("victory")
	t.check(not early.reward_bonus_earned(), "尚未守满敌方阶段时提前获胜不会领取")
	var interrupted := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var defender := interrupted.unit_by_uid(1)
	defender.cell = interrupted.reward["cell"]
	interrupted.begin_enemy_phase()
	defender.cell = Vector2i(5, 4)
	interrupted._refresh_reward_guard()
	defender.cell = interrupted.reward["cell"]
	interrupted.end_enemy_phase()
	t.eq(interrupted.reward["state"], "map", "被迫离开后即使回到格上，本轮守点仍告中断")
	var guard_death := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var guarding := guard_death.unit_by_uid(1)
	guarding.cell = guard_death.reward["cell"]
	guard_death.begin_enemy_phase()
	guard_death.damage_unit(guard_death.unit_by_uid(100), guarding, 99, {"no_element": true, "cause": "测试"})
	t.eq(guard_death.reward["state"], "destroyed", "守点者死亡则奖励被毁")
	var enemy_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 4)]])
	enemy_state.reward["cell"] = Vector2i(6, 4)
	enemy_state.begin_enemy_phase()
	t.eq(enemy_state.reward["state"], "map", "敌人占点只会阻挡，不领取我方奖励")
	var damage_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	damage_state.reward["cell"] = Vector2i(4, 3)
	damage_state.unit_by_uid(1).cell = Vector2i(0, 3)
	SkillResolver.resolve_channel(damage_state, damage_state.unit_by_uid(1), "fire_burst", [Vector2i(4, 3)])
	t.eq(damage_state.reward["state"], "destroyed", "空奖励格被火球伤害摧毁")
	var fallen := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var carrier := fallen.unit_by_uid(1)
	carrier.cell = fallen.reward["cell"]
	fallen.begin_enemy_phase()
	fallen.end_enemy_phase()
	fallen.damage_unit(fallen.unit_by_uid(100), carrier, 99, {"no_element": true, "cause": "测试"})
	t.eq(fallen.reward["state"], "lost", "持有者倒下则失去奖励")
	fallen.end_battle("victory")
	t.check(not fallen.reward_bonus_earned(), "持有者死亡不发额外战后奖励")
	var final_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	final_state.unit_by_uid(1).cell = final_state.reward["cell"]
	final_state.round = Balance.MAX_ROUNDS
	final_state.begin_enemy_phase()
	final_state.end_enemy_phase()
	t.eq(final_state.reward["state"], "carried", "第八回合敌方结束后仍可领取战后奖励")
	t.check(final_state.reward_bonus_earned(), "第八回合逃离结算也记录奖励")


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
	immune.battle_buffs["status_immune"] = true
	immune.burn_ticks = 0
	immune.slow_ticks = 0
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
	SkillResolver.resolve_channel(fire_state, fire, "fire_burst", [Vector2i(4, 3)])
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
