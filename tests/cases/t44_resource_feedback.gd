extends RefCounted

func run(t: TestContext) -> void:
	t.begin("经验与原质即时提示")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	app.leave_camp()
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var screen = app.current_screen
	var battle: BattleState = screen.state
	var events: Array = []
	battle.feedback.connect(func(e): events.append(e))
	battle.unit_by_uid(3).hp = 0
	var foes := battle.alive_units("enemy")
	var cell: Vector2i = foes[0].cell
	battle.kill_unit(foes[0], "收益验证", "player", 1)
	var xp := events.filter(func(e): return e["kind"] == "experience")
	t.eq(xp.size(), 3, "共享经验提示两名存活出战者与训练家")
	for event in xp:
		t.eq(event["value"], app.run.battle_kill_xp_for(battle, event["uid"]), "经验数字与本场经验增量一致")
		t.eq(event["cell"], battle.unit_by_uid(event["uid"]).cell, "经验显示在受益单位旁")
	var essence := events.filter(func(e): return e["kind"] == "essence")
	t.eq(essence.size(), 1, "击败敌人原质仅提示一次")
	t.eq(essence[0]["cell"], cell, "原质显示在掉落来源格")
	t.eq(essence[0]["value"], 3, "普通敌人原质为3")
	events.clear()
	screen.refresh_all()
	app.sync_and_save(battle)
	t.eq(events.size(), 0, "刷新和同步不重复显示资源收益")
	battle.earn_essence("enemy:%d" % foes[0].uid, 3, cell)
	t.eq(events.size(), 0, "重复领取不重复提示")
	battle.kill_unit(foes[1], "环境击杀")
	t.eq(events.filter(func(e): return e["kind"] in ["experience", "essence"]).size(), 0, "无归属环境击杀不虚构收益")
	events.clear()
	var obstacle_cell := Vector2i(4, 4)
	battle.set_terrain(obstacle_cell, TerrainDB.OBSTACLE)
	battle.obstacle_durability[obstacle_cell] = 1
	battle.natural_essence_cells.append(obstacle_cell)
	battle.damage_obstacle(obstacle_cell, 5, "player")
	t.eq(events.back()["text"], "原质 +1", "天然障碍破坏提示原质")
	t.eq(events.back()["cell"], obstacle_cell, "障碍收益使用障碍位置")
	var before := battle.essence_earned
	battle.earn_essence("nest_test", 8, Vector2i(7, 7))
	t.eq(battle.essence_earned - before, 8, "提示不改变资源数值")
	t.eq(events.back()["text"], "原质 +8", "原质8显示正确")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(battle))
	var restored_events: Array = []
	restored.feedback.connect(func(e): restored_events.append(e))
	restored.enable_feedback()
	restored.earn_essence("nest_test", 8, Vector2i(7, 7))
	t.eq(restored_events.size(), 0, "读取存档后已领取资源不重播")
	var clone := battle.clone()
	clone.earn_essence("preview_only", 8, cell)
	t.eq(events.back()["text"], "原质 +8", "模拟副本不泄露资源提示")
	app.queue_free()
	t.finish()
