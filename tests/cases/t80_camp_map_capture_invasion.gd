extends RefCounted

func run(t: TestContext) -> void:
	t.begin("营地地图、捕捉范围与八次移动入侵")
	var region := RegionState.create_floor(0, "grass")
	for i in range(1, 9):
		t.check(region.record_entry("camp"), "进入计数 %d" % i)
		t.eq(region.camp_invaded, i >= 8, "前七次营地安全，第八次入侵")
		region.complete_visit()
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8101)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.enter_region_node("camp")
	app.show_camp()
	var camp = app.current_screen
	t.eq(camp.board.units.size(), app.run.carried.size() + 1, "携带成员和训练师均在地图")
	var used := {}
	for unit in camp.camp_units:
		t.check(not used.has(unit.cell) and unit.cell not in [camp.FIRE_CELL, camp.STORAGE_CELL], "随机站位不重叠设施或成员")
		used[unit.cell] = true
	var destination: Vector2i = camp.board.movement_cells.keys()[0]
	var visits: int = app.run.get_region().visits
	camp._on_cell_clicked(destination)
	t.eq(camp._unit_at(destination).uid, Balance.TRAINER_UID, "训练师可移动到空格")
	t.eq(app.run.get_region().visits, visits, "营地格子移动不计区域移动")
	var positions: Dictionary = app.run.get_region().nodes["camp"]["map_positions"].duplicate(true)
	app.run = RunState.from_dict(app.run.to_dict())
	app.show_camp()
	t.eq(app.run.get_region().nodes["camp"]["map_positions"], positions, "读档重建地图保持站位")
	app.run.storage.append(app.run._make_record("water_starter", 8))
	var member_uid: int = app.run.carried[0]["uid"]
	var stored_uid: int = app.run.storage[0]["uid"]
	app.current_screen._on_cell_clicked(app.current_screen.STORAGE_CELL)
	app.current_screen.find_child("CampSwap_%d_%d" % [member_uid, stored_uid], true, false).pressed.emit()
	t.check(app.run.carried.any(func(r): return int(r["uid"]) == stored_uid), "仓库交换按钮实际生效")
	t.check(app.current_screen.camp_units.any(func(u): return u.uid == stored_uid), "新携带成员出现在地图")
	t.check(not app.current_screen.camp_units.any(func(u): return u.uid == member_uid), "留守成员只存仓库")
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(4, 4)]])
	state.trainer().cell = Vector2i(3, 3)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.selected_uid = Balance.TRAINER_UID
	screen._on_capture_pressed()
	t.eq(screen.board.area_cells.size(), 25, "捕捉范围含斜向完整5乘5格")
	t.check(screen.board.attack_cells.has(Vector2i(4, 4)), "合法目标单独高亮")
	state.node_kind = "event"
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 4)
	caster.skills = ["drain"]
	caster.hp = 1
	var hit := state.cast_skill(caster, "drain", {"type": "unit", "unit": 100, "cell": Vector2i(4, 4)})
	t.check(hit.get("ok", false) and caster.hp > 1, "自由探索允许吸取并真实回复")
	for skill in ["drain", "leech_seed", "furnace_fist"]:
		t.check(not state.recovery_skill_blocked(skill), "伤害回复技能战外放开 " + skill)
	for skill in ["herbal_heal", "first_aid", "antidote"]:
		t.check(state.recovery_skill_blocked(skill), "直接治疗仍禁用 " + skill)
	app.free()
	t.finish()
