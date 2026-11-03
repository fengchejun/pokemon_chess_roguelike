extends RefCounted


func _new_app(t: TestContext, seed: int):
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(seed)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_camp()
	app.leave_camp()
	return app


func _start(app, id: String):
	app.enter_region_node(id)
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	return app.current_screen.state


func _timeout(app, battle: BattleState) -> void:
	var was_free := battle.is_free_exploration()
	battle.round = 8
	if was_free:
		battle.end_battle("explored")
	else:
		battle.end_enemy_phase()
	app.finish_battle(battle)
	app.continue_after_settlement()
	if was_free:
		var region = app.run.get_region()
		region.visits = 8
		region._apply_pressure()
		app.run.region_data = region.to_dict()


func run(t: TestContext) -> void:
	t.begin("驻军补充、场景复用与首领增援")
	var app = _new_app(t, 71)
	var first: BattleState = _start(app, "battle_1")
	t.eq(first.alive_enemy_count(), 3, "普通节点首访三名驻军")
	var dead_uid: int = first.alive_units("enemy")[0].uid
	first.unit_by_uid(dead_uid).hp = 0
	first.nest["hp"] = 2
	_timeout(app, first)
	var second: BattleState = _start(app, "battle_1")
	t.eq(second.alive_enemy_count(), 4, "首次超时后补足四名")
	t.check(not second.unit_by_uid(dead_uid).is_alive(), "已死亡身份不复活")
	t.eq(second.nest["hp"], 2, "巢穴耐久保留")
	var second_dead: int = second.alive_units("enemy")[0].uid
	second.unit_by_uid(second_dead).hp = 0
	_timeout(app, second)
	var third: BattleState = _start(app, "battle_1")
	t.eq(third.alive_enemy_count(), 4, "反复超时仍只补足四名")
	t.check(not third.unit_by_uid(second_dead).is_alive(), "第二次击杀的身份也不复活")
	t.check(third.next_enemy_uid > second.next_enemy_uid, "补兵使用新身份")
	app.queue_free()
	var collect_app = _new_app(t, 72)
	var gathering: BattleState = _start(collect_app, "event_1")
	t.eq(gathering.alive_enemy_count(), 0, "原生收集区初次没有驻军")
	var terrain_before := gathering.terrain.duplicate()
	gathering.food_cells.append(Vector2i(4, 3))
	_timeout(collect_app, gathering)
	t.eq(collect_app.run.get_region().node_mode("event_1"), "battle", "原生收集区全面占领后改战斗")
	var reoccupied: BattleState = _start(collect_app, "event_1")
	t.eq(reoccupied.alive_enemy_count(), 3, "新驻军恰为三名")
	t.check(reoccupied.nest["alive"], "新巢穴启用")
	t.eq(reoccupied.terrain, terrain_before, "场景地形未重生成")
	t.check(reoccupied.food_cells.has(Vector2i(4, 3)), "未拾取物保留")
	collect_app.queue_free()
	var clear_app = _new_app(t, 75)
	var clearing: BattleState = _start(clear_app, "battle_1")
	for enemy in clearing.alive_units("enemy"):
		enemy.hp = 0
	clearing.nest["alive"] = false
	clearing.end_battle("victory")
	clear_app.finish_battle(clearing)
	while clear_app.run.pending_reward_choices > 0:
		clear_app.run.choose_reward(String(clear_app.run.reward_choices()[0]))
	clear_app.continue_after_settlement()
	t.eq(clear_app.run.get_region().node_mode("battle_1"), "event", "普通战斗真正清空后成为收集区")
	t.check(clear_app.run.get_region().nodes["battle_1"]["reward_claimed"], "首次清场奖励已记账")
	var cleared_visit: BattleState = _start(clear_app, "battle_1")
	t.eq(cleared_visit.alive_enemy_count(), 0, "已清场重访无敌人")
	var old_terrain := cleared_visit.terrain.duplicate()
	cleared_visit.food_cells.append(Vector2i(4, 3))
	_timeout(clear_app, cleared_visit)
	t.eq(clear_app.run.get_region().node_mode("battle_1"), "battle", "已清场收集区全面占领后重新被占据")
	var new_garrison: BattleState = _start(clear_app, "battle_1")
	t.eq(new_garrison.alive_enemy_count(), 3, "已清场区域生成三名新驻军")
	t.check(new_garrison.nest["alive"], "先前摧毁的巢穴被新驻军重建")
	t.eq(new_garrison.terrain, old_terrain, "已清场区域地形保持原样")
	t.check(new_garrison.food_cells.has(Vector2i(4, 3)), "已清场区域未拾取物保持")
	t.check(clear_app.run.get_region().nodes["battle_1"]["reward_claimed"], "新驻军不重置首次清场奖励账目")
	clear_app.queue_free()
	var boss_app = _new_app(t, 73)
	var region = boss_app.run.get_region()
	region.nodes["boss"]["unlocked"] = true
	boss_app.run.region_data = region.to_dict()
	var boss_battle: BattleState = _start(boss_app, "boss")
	t.eq(boss_battle.alive_enemy_count(), 3, "支援前首领区共三名含首领")
	t.check(boss_battle.unit_by_uid(boss_battle.boss_uid).is_boss, "三名中包含首领")
	var boss := boss_battle.unit_by_uid(boss_battle.boss_uid)
	var boss_cell := boss.cell
	var pushed := PushResolver.push(boss_battle, boss, Vector2i.LEFT, 1, 0, "测试")
	t.check(bool(pushed["blocked"]) and boss.cell == boss_cell, "首领不会被推动")
	boss.hp = 0
	boss_battle.check_battle_end()
	t.check(not boss_battle.ended and boss_battle.boss_portal_cell == boss_cell, "击败首领出现传送门并保留战场")
	t.eq(boss_battle.alive_enemy_count(), 0, "剩余敌人撤离")
	t.check(not boss_battle.nest["alive"] and int(boss_battle.nest["pending_waves"]) == 0, "巢穴停止产兵")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(boss_battle))
	t.eq(restored.boss_portal_cell, boss_cell, "传送门随战斗快照保存")
	restored.round = 8
	restored.end_enemy_phase()
	t.check(not restored.ended, "击败首领后不再受八回合限制")
	var portal_neighbor: Vector2i = GridSpec.neighbors4(boss_cell)[0]
	boss_battle.set_terrain(portal_neighbor, TerrainDB.PLAIN)
	boss_battle.trainer().cell = portal_neighbor
	boss_app.current_screen._on_board_clicked(boss_cell)
	t.eq(boss_battle.end_reason, "victory", "点击传送门才开始胜利结算")
	boss_app.current_screen.report_end_now()
	t.check(boss_app.run.get_region().nodes["boss"]["cleared"], "使用传送门后的结算记录首领完成")
	var abandoned: Dictionary = boss_app.run._make_record("fire_starter")
	boss_app.run.carried.append(abandoned)
	boss_app.collection.absorb_run(boss_app.run)
	boss_app.run.carried.erase(abandoned)
	boss_app.run.storage.append(abandoned)
	var previous_collection_id := int(boss_app.collection.owned[0]["id"])
	var prior_owned: Dictionary = boss_app.run._make_record("water_starter")
	prior_owned["collection_id"] = previous_collection_id
	boss_app.run.storage.append(prior_owned)
	var abandoned_source := "run:%d:%d" % [boss_app.run.seed, int(abandoned["uid"])]
	while boss_app.run.pending_reward_choices > 0:
		boss_app.run.choose_reward(String(boss_app.run.reward_choices()[0]))
	boss_app.continue_after_settlement()
	t.check(boss_app.run.storage.is_empty(), "进入下一层后丢弃营地留守成员")
	t.check(boss_app.collection.owned.all(func(entry): return String(entry.get("source", "")) != abandoned_source), "本局留守成员不进入永久收藏")
	t.check(not boss_app.collection.record_by_id(previous_collection_id).is_empty(), "已有永久收藏不会因留守被删除")
	boss_app.queue_free()
	var support_app = _new_app(t, 74)
	region = support_app.run.get_region()
	region.nodes["boss"]["unlocked"] = true
	for index in range(14):
		region.record_entry("camp")
		region.complete_visit()
	support_app.run.region_data = region.to_dict()
	support_app.run.invasion_level_bonus = region.boss_level_bonus
	var reinforced: BattleState = _start(support_app, "boss")
	t.eq(reinforced.alive_enemy_count(), 5, "支援后首领区共五名含首领")
	t.eq(reinforced.unit_by_uid(reinforced.boss_uid).enemy_level, 1 + 1 + 2, "首领按第 14 次移动获得两级加成")
	t.eq(reinforced.boss_power_percent, 0, "旧百分比强化不再生效")
	var save_path := "res://.test_pressure_v10.json"
	t.check(SaveSystem.save_run(support_app.run, save_path), "v10 保存首领战")
	var loaded := SaveSystem.load_run(save_path)
	t.check(loaded != null and loaded.get_region().boss_level_bonus == 2, "v10 读回等级阶段")
	t.eq(loaded.battle_snapshot.get("units", []).size(), reinforced.units.size(), "首领驻军快照不会重复生成")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	reinforced.round = 8
	reinforced.end_enemy_phase()
	t.check(not reinforced.ended and not reinforced.storm_strikes.is_empty(), "支援后首领战第8回合继续并预告天雷")
	reinforced.damage_unit(null, reinforced.trainer(), 999, {"no_element": true})
	support_app.finish_battle(reinforced)
	t.check(support_app.run.run_failed and support_app.current_screen.name == "RunEndScreen", "首领战训练家阵亡仍终止本局")
	support_app.queue_free()
	t.finish()
