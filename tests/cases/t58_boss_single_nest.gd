extends RefCounted

func run(t: TestContext) -> void:
	t.begin("首领节点单巢穴与旧档恢复")
	for index in [5, 11, 17]:
		for seed_value in range(5):
			var map := MapGenerator.generate(seed_value, index)
			t.eq(map["nest_cells"].size(), 1, "各层首领地图默认一个巢穴")
			t.check(MapGenerator._validate(map["terrain"], map["nest_cells"]), "首领主巢穴可达")
	var map := MapGenerator.generate(1234, 5, 0, [], "", 2)
	var state := BattleState.new()
	state.node_kind = "boss"
	var cfg := BattleDB.config_for(5)
	state.setup(map, cfg, 1234, 5, [], {}, {}, cfg.get("reinforce", []))
	t.eq(state.all_nests().size(), 1, "战斗初始化拒绝额外首领巢穴")
	var second := state.nest.duplicate(true)
	second["cell"] = Vector2i(7, 7)
	second["pending_waves"] = 2
	state.extra_nests = [second]
	state.nest["hp"] = 1
	state.nest["pending_waves"] = 1
	var snapshot := BattleSnapshot.save_state(state)
	var restored := BattleSnapshot.load_state(snapshot)
	t.eq(restored.all_nests().size(), 1, "旧首领快照移除额外巢穴")
	t.eq(restored.nest["cell"], state.nest["cell"], "保留主巢穴原位置")
	t.eq(restored.nest["hp"], 1, "保留主巢穴耐久")
	t.eq(restored.nest["pending_waves"], 1, "保留主巢穴积压增援")
	t.eq(restored.units.size(), state.units.size(), "不删除已生成敌人")
	state.nest["alive"] = false
	state.nest["hp"] = 0
	var destroyed := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.check(not destroyed.nest["alive"] and destroyed.extra_nests.is_empty(), "主巢穴已毁时不重新生成替代巢穴")
	state.node_kind = "battle"
	state.boss_uid = -1
	var ordinary := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(ordinary.all_nests().size(), 2, "普通节点已有多巢穴不受影响")
	_preview(t)
	t.finish()

func _preview(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	region.active_node = "boss"
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	var preview = app.current_screen
	t.eq(preview.map["nest_cells"].size(), 1, "首访预览只有一个巢穴")
	t.check(preview.board.extra_nests.is_empty(), "棋盘不绘制第二巢穴")
	preview._on_start()
	var battle: BattleState = app.current_screen.state
	t.eq(battle.all_nests().size(), 1, "从预览进入首领战仍是一个巢穴")
	var second := battle.nest.duplicate(true)
	second["cell"] = Vector2i(7, 7)
	battle.extra_nests = [second]
	battle.nest["hp"] = 2
	region = app.run.get_region()
	region.store_battle("boss", battle)
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	preview = app.current_screen
	t.eq(preview.map["nest_cells"].size(), 1, "旧双巢穴节点重访预览移除第二巢穴")
	t.eq(preview.board.nest["hp"], 2, "重访保留主巢穴损伤")
	preview._on_start()
	battle = app.current_screen.state
	t.eq(battle.all_nests().size(), 1, "重访战斗不会恢复第二巢穴")
	app.free()
