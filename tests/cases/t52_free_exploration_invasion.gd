extends RefCounted
func run(t: TestContext) -> void:
	t.begin("胜后自由探索与跨层入侵")
	var state := TestScenario.make_state(["fire_starter", "grass_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.node_kind = "battle"
	state.round = 8
	state.unit_by_uid(100).hp = 0
	t.check(state.is_free_exploration(), "清场后即使巢穴未毁也解锁区域")
	state.nest["alive"] = false
	state.unit_by_uid(1).skill_used = true
	state.unit_by_uid(1).moved = true
	state.check_battle_end()
	t.check(state.is_free_exploration() and state.can_leave_node(), "清场并毁巢仍进入自由探索")
	t.check(not state.ended and not state.unit_by_uid(1).skill_used, "停留地图恢复行动")
	var nest_only := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	nest_only.node_kind = "battle"
	nest_only.nest["hp"] = 1
	nest_only.damage_nest(1, "player")
	t.check(nest_only.alive_enemy_count() > 0 and not nest_only.has_live_nests(), "仅摧毁巢穴时敌人仍存活")
	t.check(nest_only.battle_objective_met() and nest_only.can_leave_node(), "破坏巢穴也可单独解锁区域")
	state.end_enemy_phase()
	t.eq(state.round, 8, "自由探索不增加回合")
	t.check(not state.ended, "第八回合胜利不强制逃离")
	state._pending_actions = [{"uid": 100}]
	state._pending_index = 0
	t.check(state.enemy_phase_finished(), "清场后不等待残留敌方动作")
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 2)
	var destination := Vector2i(6, 2)
	t.check(state.move_unit(caster, destination), "自由探索一次走到远格")
	t.check(state.move_unit(caster, Vector2i(1, 2)), "可立即再次移动")
	state.set_terrain(Vector2i(3, 2), TerrainDB.TREE)
	state.obstacle_durability[Vector2i(3, 2)] = 1
	var cast := state.cast_skill(caster, "fire_burst", {"type": "cell", "cell": Vector2i(3, 2)})
	t.check(bool(cast.get("ok", false)), "战外吟唱可施放")
	t.check(not state.obstacle_durability.has(Vector2i(3, 2)), "吟唱即时产生效果")
	t.check(state.pending_casts.is_empty() and caster.channel_lock_round < 0 and not caster.skill_used, "吟唱无等待和行动代价")
	var healer := state.unit_by_uid(2)
	for skill in ["herbal_heal", "drain", "leech_seed"]:
		t.check(SkillResolver.targets(state, healer, skill).is_empty(), "战外禁用含回复技能 " + skill)
	var reloaded := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.check(reloaded.is_free_exploration(), "读档保留自由探索")
	t.eq(reloaded.round, 8, "读档保持胜利回合")
	for boundary in [7, 10, 13]:
		var region := RegionState.create_floor(0, "grass")
		region.visits = boundary
		region.support_triggered = boundary > 7
		region.boss_level_bonus = 1 if boundary == 13 else 0
		region.nodes["boss"]["unlocked"] = true
		region.record_entry("boss")
		t.eq(region.boss_level_bonus, 1 if boundary == 13 else 0, "临界进入首领不触发升级")
		t.eq(region.support_triggered, boundary > 7, "临界进入首领不触发占领")
	var run_state := RunState.new_run(52030)
	run_state.region_mode = true
	run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
	var region = run_state.get_region()
	region.visits = 10
	region.support_triggered = true
	run_state.region_data = region.to_dict()
	t.check(run_state.enter_region_node("camp"), "第十一次可进入营地")
	t.eq(run_state.get_region().node_mode("camp"), "battle", "进场前营地已转战斗")
	t.eq(run_state.invasion_level_bonus, 1, "全局等级加一")
	t.check(not bool(run_state.rest_with_food({}).get("ok", false)), "被占领的营地不能休整")
	run_state.cancel_region_entry()
	t.eq(run_state.invasion_level_bonus, 0, "取消进场退回该次压力")
	t.eq(run_state.get_region().visits, 10, "取消计数回退")
	run_state.enter_region_node("camp")
	region = run_state.get_region()
	region.complete_visit()
	run_state.region_data = region.to_dict()
	for i in range(3):
		run_state.enter_region_node("camp")
		region = run_state.get_region()
		region.complete_visit()
		run_state.region_data = region.to_dict()
	t.eq(run_state.invasion_level_bonus, 2, "再拖延三次继续升级")
	var loaded := RunState.from_dict(run_state.to_dict())
	t.eq(loaded.invasion_level_bonus, 2, "整局累计等级存读档")
	loaded.region_data = {}
	loaded.battle_index = 6
	region = loaded.get_region()
	region.record_entry("battle_1")
	loaded.region_data = region.to_dict()
	t.eq(loaded.battle_config().get("enemy_level_bonus", 0), 2, "下一层普通敌人继承加成")
	state.set_enemy_level_bonus(2)
	state.add_garrison(1, ["rock_wild1"], [Vector2i(6, 5)])
	t.eq(state.alive_units("enemy")[0].enemy_level, 3, "后生成驻军继承等级")
	t.finish()
