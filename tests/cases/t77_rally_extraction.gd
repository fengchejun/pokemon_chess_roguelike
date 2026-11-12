extends RefCounted
func run(t: TestContext) -> void:
	t.begin("撤退区永久取消与旧快照迁移")
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6,3)]])
	state.node_kind = "battle"
	t.check(state.extraction_cells.is_empty(), "新战场无撤退区")
	t.check(BattleState.extraction_area({"deploy_area": Balance.DEPLOY_AREA}).is_empty(), "部署格不再生成撤退区")
	state.extraction_cells = Balance.DEPLOY_AREA.duplicate()
	for cell in [Vector2i(0,3), Vector2i(1,5), Vector2i(3,3)]:
		state.trainer().cell = cell
		t.check(not state.can_escape() and not state.leave_node(true), "旧撤退格及区外均不能撤离")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.check(restored.extraction_cells.is_empty(), "旧快照读取清空撤退区")
	var board := BoardView.new()
	board.set_from_state(state)
	t.check(board.extraction_cells.is_empty(), "旧战场字段不绘制绿色框")
	board.free()
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1,2,3]))
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	region.nodes["battle_1"]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node("battle_1")
	app.show_preview([1,2,3])
	t.check(app.current_screen.board.extraction_cells.is_empty(), "战前预览无撤退区")
	app.current_screen._on_start()
	t.check(app.current_screen.state.extraction_cells.is_empty(), "正式战斗无撤退区")
	app.free()
	t.finish()
