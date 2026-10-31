extends RefCounted

func run(t: TestContext) -> void:
	t.begin("整备预览同页与局部装备刷新")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.options["capture_low_hp"] = true
	app.run.reward_inventory = [RewardDB.MOD_ITEM]
	app.run.carried.append(app.run._make_record("rock_starter"))
	var fainted: Dictionary = app.run._make_record("water_wild1")
	fainted["hp"] = 0
	app.run.carried.append(fainted)
	var record: Dictionary = app.run.record_by_uid(1)
	if not record["known_skills"].has("flame_jet"):
		record["known_skills"].append("flame_jet")
	app.show_prep()
	var screen = app.current_screen
	t.check(screen.find_child("TeamPreparationPanel", true, false) != null and screen.find_child("MapPreviewPanel", true, false) != null, "队伍与地图同时存在")
	t.check(screen.find_child("CaptureLowHpOption", true, false) == null and screen.find_child("PreviewButton", true, false) == null, "删除右侧捕获设置与中间跳转")
	t.check(app.run.options["capture_low_hp"], "删除设置界面不清除已有捕获选项")
	t.check(not screen.tools_scroll.visible, "改造工具默认收起")
	screen.find_child("PreviewToolsToggle", true, false).pressed.emit()
	t.check(screen.tools_scroll.visible, "工具可在同页展开")
	for uid in [1, 2, 3]:
		screen.check_boxes[uid].button_pressed = true
	screen.check_boxes[4].button_pressed = true
	t.eq(screen.deploy_selection, [1, 2, 3], "仍最多选择三只")
	t.check(not screen.check_boxes[4].button_pressed, "超额选择回退")
	t.check(screen.check_boxes[int(fainted["uid"])].disabled, "濒死成员不可选择")
	screen.card_selector.select(1)
	screen.card_use_button.pressed.emit()
	t.eq(app.run.reward_inventory.size(), 0, "工具立即消耗一次")
	var cell := Vector2i(-1, -1)
	for candidate in GridSpec.all_cells():
		if not MapGenerator.mod_protected(screen.map, candidate) and screen.map["terrain"][GridSpec.index(candidate)] == TerrainDB.PLAIN:
			cell = candidate
			break
	screen._set_mod_kind("water")
	screen._on_cell_clicked(cell)
	t.eq(screen.mod_used, 1, "同页地图改造可用")
	var terrain: Array = screen.map["terrain"].duplicate()
	var selector: OptionButton = screen.find_child("SkillSlot_1_0", true, false)
	for index in selector.item_count:
		if selector.get_item_metadata(index) == "flame_jet":
			selector.select(index)
			selector.item_selected.emit(index)
			break
	t.check(app.current_screen == screen, "换技能不重建整个页面")
	t.eq(record["equipped_skills"][0], "flame_jet", "实际装备所选技能")
	t.eq(screen.map["terrain"], terrain, "换技能保留已改造地图")
	t.eq(screen.deploy_selection, [1, 2, 3], "换技能保留出战选择")
	t.eq(screen.mod_used, 1, "换技能保留改造额度")
	t.eq(app.run.reward_inventory.size(), 0, "换技能不重复消耗道具")
	app.back_to_prep(screen.deploy_uids)
	screen = app.current_screen
	t.eq(screen.map["terrain"], terrain, "重开合并页保留本场地图")
	t.eq(screen.deploy_selection, [1, 2, 3], "重开合并页保留预设编成")
	screen._on_start()
	t.eq(app.current_screen.name, "BattleScreen", "同页直接开战")
	var battle: BattleState = app.current_screen.state
	t.eq(battle.unit_by_uid(1).skills[0], "flame_jet", "开战使用刚装备的技能")
	t.check(battle.unit_by_uid(4) == null, "未选择成员不会出战")
	t.eq(battle.terrain, terrain, "开战使用当前预览地图")
	t.eq(app.run.reward_inventory.size(), 0, "开战不二次扣除道具")
	app.queue_free()
	t.finish()
