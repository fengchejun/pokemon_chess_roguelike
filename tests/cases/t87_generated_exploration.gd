extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")

func distances(region: RegionState, excluded: String = "") -> Dictionary:
	var reached := {"camp": 0}
	var queue := ["camp"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for other in region.nodes[id]["links"]:
			if other != excluded and not reached.has(other):
				reached[other] = reached[id] + 1
				queue.append(other)
	return reached

func can_reach_chest(terrain: Array, element: String, break_rocks: bool) -> bool:
	var queue := [Vector2i(1, 3)]
	var seen := {queue[0]: true}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == Vector2i(6, 3):
			return true
		for next in GridSpec.neighbors4(cell):
			var tile: int = terrain[GridSpec.index(next)]
			if not seen.has(next) and (TerrainDB.can_stand(tile, element) or (break_rocks and tile in [TerrainDB.OBSTACLE, TerrainDB.ROCK_MOUNTAIN])):
				seen[next] = true
				queue.append(next)
	return false

func run(t: TestContext) -> void:
	t.begin("三层随机区域、委托与宝箱谜题")
	var layouts := {}
	var tiers := {}
	for seed_value in range(1, 61):
		for floor in 3:
			var region := Flow.generate(floor, "fire", seed_value)
			var nodes := region.nodes
			t.check(nodes.size() in [14, 15], "4×4 只生成14或15个实际节点")
			t.eq(nodes.values().filter(func(n): return n["role"] == "item_shop").size(), 1, "每层一个道具商店")
			t.eq(nodes.values().filter(func(n): return n["role"] == "skill_shop").size(), 1, "每层一个技能商店")
			t.eq(nodes.values().filter(func(n): return n["role"] == "capture").size(), 1, "每层一个野生栖息地")
			t.eq(nodes.values().filter(func(n): return n["role"] == "elite").size(), 1, "每层一个精英战")
			t.eq(nodes.values().filter(func(n): return n["role"] == "battle").size(), nodes.size() - 9, "空出的名额换成普通战斗")
			t.eq(nodes.values().filter(func(n): return n["role"] == "group").size(), 1, "每层群体事件不重复")
			t.check(not nodes.values().any(func(n): return n["role"] == "empty"), "没有可进入的空节点")
			t.eq(distances(region).size(), nodes.size(), "全图连通")
			var reachable := distances(region, "battle_5")
			t.check(reachable.get("boss", 99) <= Balance.EXPLORATION_ACTIONS, "不交付委托也能在行动预算内到达Boss")
			t.check(reachable.get("event_2", 99) <= Balance.EXPLORATION_ACTIONS and reachable.get("shop_2", 99) <= Balance.EXPLORATION_ACTIONS and reachable.has("battle_2"), "两家商店与捕捉点不依赖交付")
			var positions := {}
			var valid := true
			var geometry: Array = []
			for id in nodes:
				var cell := Flow.position(id, nodes[id])
				if positions.has(cell) or cell.x not in range(4) or cell.y not in range(4):
					valid = false
				positions[cell] = true
				for other in nodes[id]["links"]:
					var next := Flow.position(other, nodes[other])
					if GridSpec.manhattan(cell, next) != 1 or not nodes[other]["links"].has(id):
						valid = false
					geometry.append("%s>%s" % [str(cell), str(next)])
			t.check(valid, "节点坐标唯一，连线双向且只连接正交邻格")
			geometry.sort()
			layouts[str(geometry)] = true
			tiers[nodes["battle_5"]["commission"]["tier"]] = true
	t.check(layouts.size() > 100, "不同种子和楼层生成多样的实际路网")
	t.eq(tiers.size(), 3, "三档委托均能生成")
	var sample := Flow.generate(1, "water", 321)
	t.eq(Flow.generate(1, "water", 321).to_dict(), sample.to_dict(), "同种子同层可复现")
	t.eq(RegionState.from_dict(sample.to_dict()).to_dict(), sample.to_dict(), "拓扑、任务和谜题可存档")

	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	var run_state: RunState = app.run
	run_state.battle_index = Balance.BATTLES_PER_FLOOR
	run_state.floor_themes = ["fire"]
	run_state.refresh_theme_offers()
	var save_path := "user://.test_map_transition_%d.json" % OS.get_process_id()
	SaveSystem.save_run(run_state, save_path)
	app.continue_run(save_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	run_state = app.run
	t.check(run_state.region_data.is_empty() and app.current_screen.name == "FloorThemeScreen", "选主题前续档不会提前生成楼层")
	var chosen_theme := String(run_state.offered_floor_themes[0])
	t.check(run_state.choose_floor_theme(chosen_theme) and run_state.get_region().theme == chosen_theme, "选定主题后按实际主题生成地图")
	var boss_region: RegionState = run_state.get_region()
	boss_region.nodes["boss"]["unlocked"] = true
	run_state.region_data = boss_region.to_dict()
	app.enter_region_node("boss")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var boss_battle: BattleState = app.current_screen.state
	for enemy in boss_battle.alive_units("enemy"):
		enemy.hp = 0
	t.check(not boss_battle.check_battle_end() and not GridSpec.is_inside(boss_battle.boss_portal_cell), "普通 Boss 战仍需清除存活的巢穴")
	boss_battle.stop_nests()
	boss_battle.phase = BattleState.PHASE_ENEMY
	var final_round := boss_battle.round
	boss_battle.end_enemy_phase()
	t.check(boss_battle.ended and boss_battle.end_reason == "victory", "普通 Boss 在环境清场后立即胜利")
	t.check(boss_battle.phase == BattleState.PHASE_ENDED and boss_battle.round == final_round, "胜利后回合立即结束")
	t.check(not run_state.get_region().invaded, "提前打 Boss 未触发入侵")
	t.check(boss_battle.chests.is_empty(), "首领战取消额外宝箱")
	app.finish_battle(boss_battle)
	t.check(run_state.has_pending_battle_loot(), "高级战利品等待选择领取")
	for i in run_state.pending_battle_loot.size(): run_state.resolve_battle_loot(i, true)
	t.check(run_state.pending_reward_choices == 1, "领取后进入新版遗物三选一")
	var paid := run_state.essence
	run_state.settle_battle(boss_battle)
	t.eq(run_state.essence, paid, "重复结算不会再发高级奖励")
	while run_state.pending_reward_choices > 0:
		t.check(run_state.skip_reward_choice(), "提前过层可放弃遗物")
	app.continue_after_settlement()
	t.eq(run_state.floor_index(), 2, "提前过层进入下一层")
	run_state.floor_themes = ["fire", "water", "grass"]
	for floor in 3:
		run_state.battle_index = floor * Balance.BATTLES_PER_FLOOR
		run_state.region_data = {}
		var region = run_state.get_region()
		t.eq(region.flow_version, 2, "正常入口三层都生成新版地图")
		for id in ["battle_1", "combat_1"]:
			region.active_node = id
			run_state.region_data = region.to_dict()
			var cfg := run_state.battle_config()
			t.eq(cfg["enemies"].size() - int(not String(cfg["carrier_tier"]).is_empty()), 3 + floor, "普通战斗按层生成3、4、5名基础敌人")
		region.visits = Balance.EXPLORATION_ACTIONS
		run_state.region_data = region.to_dict()
		app.show_region()
		region = run_state.get_region()
		t.check(region.invaded and not region.nodes.has("hunt"), "三层均在行动耗尽后切换入侵")
		t.eq(run_state.floor_index(), floor, "入侵保留当前楼层")
		t.eq(region.nodes.values().filter(func(node): return node.get("invasion_carrier", false)).size(), 4, "全面失守时每层恰有四处军需")
		while not region.can_enter_after_invasion("boss"):
			var frontier: Array = region.nodes.keys().filter(func(id): return region.nodes[id].get("occupied", false) and region.can_enter_after_invasion(id))
			t.check(not frontier.is_empty(), "全线失守仍有可夺回的前线")
			if frontier.is_empty():
				break
			var id: String = frontier[0]
			region.nodes[id]["occupied"] = false
			region.nodes[id]["passable"] = true
		t.check(region.can_enter_after_invasion("boss"), "夺回路径能到达 Boss")


	run_state.battle_index = 0
	run_state.region_data = {}
	var region = run_state.get_region()
	region.active_node = "battle_4"
	for variant in 4:
		region.nodes["battle_4"]["puzzle"] = variant
		run_state.region_data = region.to_dict()
		var map := MapGenerator.generate(run_state.seed, 0)
		Flow.prepare_map(run_state, map)
		t.check(map["chests"].has(Vector2i(6, 3)), "各结构均生成可拾取的宝箱")
		var terrain: Array = map["terrain"]
		if variant == 0:
			t.eq(terrain.count(TerrainDB.ROCK_MOUNTAIN), 4, "隔水藏珍保留四座岩山")
			t.check(not can_reach_chest(terrain, "fire", true) and not can_reach_chest(terrain, "water", false) and can_reach_chest(terrain, "water", true), "隔水藏珍需过河并打开岩山")
		elif variant == 1:
			t.check(not can_reach_chest(terrain, "fire", false) and can_reach_chest(terrain, "fire", true), "岩垒需破障才可进入")
		elif variant == 2:
			t.check(not can_reach_chest(terrain, "fire", false), "断桥缺口挡住普通地面移动")
			var caster := CombatUnit.make("ice_starter", "player", 1)
			var state := BattleState.new()
			state.node_kind = "event"
			state.setup(map, {"enemies": []}, run_state.seed, 0, [caster], {}, {}, [])
			Flow.prepare_state(run_state, state)
			t.check(state.move_unit(caster, Vector2i(2, 4)), "施法者可走到断桥入口")
			t.check(not state.move_options(caster).has(Vector2i(5, 4)), "普通移动入口无法直接到对岸")
			var entry := {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(3, 4)}
			t.check(state.cast_skill(caster, "frozen_ground", entry).get("ok", false), "可以用冰封大地补桥")
			t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.ICE, "断桥缺口被铺成冰面")
			t.check(state.move_unit(caster, Vector2i(5, 4)), "补桥后可通过普通移动抵达对岸")
		else:
			t.check(can_reach_chest(terrain, "fire", false), "熔沟保留可通行的绕路")

	region.active_node = "battle_5"
	var required := {"tier": 3, "species": "fire_wild1", "element": "fire", "skill": "flame_jet"}
	region.nodes["battle_5"]["commission"] = required
	run_state.region_data = region.to_dict()
	var candidate := run_state._make_record("fire_wild1", 12)
	candidate["equipped_skills"] = ["fire_burst"]
	t.check(Flow.request_matches({"tier": 1, "element": "fire"}, candidate), "一档按属性匹配")
	t.check(Flow.request_matches({"tier": 2, "species": "fire_wild1"}, candidate), "二档按物种匹配")
	run_state.storage.append(candidate)
	app._switch(load("res://scripts/ui/exploration_node_screen.gd").new())
	var before := run_state.essence
	app.current_screen.deliver(candidate["uid"])
	t.eq(run_state.essence, before, "仓库成员不能交付")
	run_state.storage.erase(candidate)
	run_state.carried.append(candidate)
	app.current_screen.deliver(candidate["uid"])
	t.eq(run_state.essence, before, "会招式但未装备时不能交付")
	candidate["equipped_skills"] = ["flame_jet"]
	app.current_screen.deliver(candidate["uid"])
	t.eq(run_state.essence, before + 48, "装备指定招式后按三档结算")
	t.check(not run_state.carried.has(candidate), "交付成员从随身队伍离开")
	app.free()
	t.finish()
