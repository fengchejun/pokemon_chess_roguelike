extends RefCounted


func run(t: TestContext) -> void:
	t.begin("多种子驻军站位与区域邻接")
	var layout := RegionState.create_floor(0, "grass")
	for id in RegionState.AREA_CELLS:
		for other in RegionState.AREA_CELLS:
			var a: Vector2i = RegionState.AREA_CELLS[id]
			var b: Vector2i = RegionState.AREA_CELLS[other]
			var shares_edge: bool = id != other and absi(a.x - b.x) + absi(a.y - b.y) == 1
			t.eq(layout.nodes[id]["links"].has(other), shares_edge, "节点连线与区域共享边一致")
	for seed in range(1, 21):
		var run_state := RunState.new_run(seed)
		run_state.region_mode = true
		run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
		var region = run_state.get_region()
		region.nodes["boss"]["unlocked"] = true
		run_state.region_data = region.to_dict()
		for id in ["battle_1", "boss"]:
			run_state.enter_region_node(id)
			var map := MapGenerator.generate(run_state.seed, run_state.battle_index, 0, [], run_state.current_theme())
			var cfg := run_state.place_region_enemies(run_state.battle_config(), map)
			var cells: Array = []
			for pair in cfg["enemies"]:
				t.check(GridSpec.is_inside(pair[1]) and not cells.has(pair[1]) and TerrainDB.can_stand(int(map["terrain"][GridSpec.index(pair[1])]), SpeciesDB.element_of(String(pair[0]))), "%s 种子 %d 敌军站位合法" % [id, seed])
				cells.append(pair[1])
			t.eq((cfg["enemies"] as Array).size(), 3, "%s 种子 %d 初始驻军三名" % [id, seed])
			run_state.cancel_region_entry()
		region = run_state.get_region()
		region.support_triggered = true
		region.nodes["boss"]["unlocked"] = true
		run_state.region_data = region.to_dict()
		run_state.enter_region_node("boss")
		var boss_map := MapGenerator.generate(run_state.seed, run_state.battle_index, 0, [], run_state.current_theme())
		var boss_cfg := run_state.place_region_enemies(run_state.battle_config(), boss_map)
		t.eq((boss_cfg["enemies"] as Array).size(), 5, "种子 %d 支援后首领区五名" % seed)
		var used: Array = []
		for pair in boss_cfg["enemies"]:
			t.check(GridSpec.is_inside(pair[1]) and not used.has(pair[1]), "种子 %d 首领增援站位不重叠" % seed)
			used.append(pair[1])
		run_state.cancel_region_entry()
		var event_map := MapGenerator.generate(run_state.seed, run_state.battle_index, 101, [], run_state.current_theme())
		var event_state := BattleState.new()
		event_state.setup(event_map, {"region": "探索区", "enemies": [], "boss_index": -1}, run_state.seed, run_state.battle_index, run_state.build_deploy_units([1, 2, 3]), {}, {}, [])
		event_state.node_kind = "battle"
		var pool: Array = BattleDB.config_for(run_state.battle_index, run_state.seed, run_state.current_theme())["reinforce"]
		t.eq(event_state.add_garrison(3, pool), 3, "种子 %d 探索区重驻能放下三名" % seed)
	t.finish()
