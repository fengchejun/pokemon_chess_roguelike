extends RefCounted


func run(t: TestContext) -> void:
	t.begin("新局区域完整流程")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	t.check(app.run.region_mode, "实际新局启用区域模式")
	var theme := String(app.run.offered_floor_themes[0])
	app.current_screen.find_child("ChooseTheme_" + theme, true, false).pressed.emit()
	t.eq(app.current_screen.name, "RegionScreen", "选择主题后进入区域路线")
	app.enter_region_node("camp")
	app.enter_region_node("event_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var event = app.current_screen
	t.eq(event.state.node_kind, "event", "非战斗节点进入自由收集")
	t.eq(event.state.alive_enemy_count(), 0, "非战斗节点不生成战斗敌人")
	t.check(not event.state.nest["alive"], "非战斗节点不保留活巢穴")
	event.state.end_battle("explored")
	app.finish_battle(event.state)
	t.eq(app.run.pending_reward_choices, 0, "反复探索空节点不发放战斗遗物")
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "RegionScreen", "收集结束返回路线")
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var combat = app.current_screen
	var foe: CombatUnit = combat.state.alive_units("enemy")[0]
	foe.hp -= 2
	var foe_uid := foe.uid
	var foe_cell := foe.cell
	combat.state.round = 8
	combat.state.end_enemy_phase()
	t.eq(combat.state.end_reason, "escape", "普通节点八回合返回")
	app.finish_battle(combat.state)
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "RegionScreen", "未清空节点结算后返回路线")
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var revisit = app.current_screen
	t.eq(revisit.state.unit_by_uid(foe_uid).hp, revisit.state.unit_by_uid(foe_uid).max_hp, "实际重访恢复敌人生命")
	t.eq(revisit.state.unit_by_uid(foe_uid).cell, foe_cell, "实际重访保留敌人站位")
	t.eq(revisit.state.round, 1, "重访重开回合")
	var resume_path := "res://.test_region_resume.json"
	app.sync_and_save(revisit.state)
	t.check(SaveSystem.save_run(app.run, resume_path), "区域战斗中快照写入临时存档")
	app.show_menu()
	app.continue_run(resume_path)
	t.eq(app.current_screen.name, "BattleScreen", "标题续战恢复当前节点战斗")
	t.eq(app.current_screen.state.node_kind, "battle", "续战保留节点规则")
	t.eq(app.current_screen.state.unit_by_uid(foe_uid).cell, foe_cell, "续战保留节点敌人站位")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(resume_path))
	t.check(app.run.get_region().visits >= 4, "各次非首领进入累计强化次数")
	app.run = RunState.new_run(77)
	app.run.region_mode = true
	for floor_number in range(3):
		app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
		app.show_region()
		for id in ["camp", "event_1", "battle_3", "battle_5", "boss"]:
			app.enter_region_node(id)
		app.show_preview([1, 2, 3])
		app.current_screen._on_start()
		var boss_screen = app.current_screen
		t.eq(boss_screen.state.boss_power_percent, 20, "每层四次非首领访问增加 20% 强化")
		var boss: CombatUnit = boss_screen.state.unit_by_uid(boss_screen.state.boss_uid)
		t.check(boss != null and boss.is_boss, "首领节点生成首领")
		var base_boss := CombatUnit.make(boss.species_id, "enemy", boss.uid)
		BattleDB.configure_enemy(base_boss, app.run.seed, app.run.battle_index, int(app.run.battle_config()["boss_index"]), true)
		t.eq(boss.max_hp, ceili(base_boss.max_hp * 1.2), "首领强化实际增加最大生命")
		boss.hp = 0
		boss_screen.state.check_battle_end()
		app.finish_battle(boss_screen.state)
		while app.run.pending_reward_choices > 0:
			app.run.choose_reward(String(app.run.reward_choices()[0]))
		app.continue_after_settlement()
		t.eq(app.current_screen.name, "RunEndScreen" if floor_number == 2 else "FloorThemeScreen", "首领击败后推进下一层或完成本局")
	app.queue_free()
	t.finish()
