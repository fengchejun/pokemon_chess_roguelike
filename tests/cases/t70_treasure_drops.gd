extends RefCounted

func run(t: TestContext) -> void:
	t.begin("随机宝箱、多奖励点与携带者巢穴掉落")
	_generation(t)
	_chests(t)
	_drops(t)
	_settle(t)
	_persist(t)
	_ui(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(5, 3)]])
	state.node_kind = "battle"
	state.reward = {"state": "absent", "cell": Vector2i(-1, -1), "owner_uid": -1, "guard_uid": -1}
	state.unit_by_uid(1).cell = Vector2i(1, 3)
	state.unit_by_uid(1).skills = ["rock_break"]
	return state

func _chest(state: BattleState, cell: Vector2i) -> void:
	state.set_terrain(cell, TerrainDB.OBSTACLE)
	state.chests[cell] = 1
	state.obstacle_durability[cell] = 1
	state.natural_essence_cells.erase(cell)

func _generation(t: TestContext) -> void:
	var battle_count := 0
	var event_count := 0
	var double_count := 0
	var carrier_count := 0
	for seed_value in range(200):
		for mode in ["battle", "event"]:
			var map := TestScenario.make_map(TestScenario.plain_terrain())
			var cfg := {"enemies": [["rock_wild1", Vector2i(6, 1)], ["rock_wild1", Vector2i(6, 2)], ["rock_wild1", Vector2i(6, 3)]], "boss_index": -1}
			MapGenerator.populate_treasure(map, cfg, seed_value, 0, mode, "test")
			t.eq(map["reward"]["state"], "absent", "新生成地图没有固定奖励点")
			t.check(map["chests"].size() <= 2, "宝箱最多两个")
			if not map["chests"].is_empty():
				if mode == "battle": battle_count += 1
				else: event_count += 1
			if map["chests"].size() == 2: double_count += 1
			if mode == "battle" and int(map["carrier_uid"]) >= 100: carrier_count += 1
			if mode == "event": t.eq(map["carrier_uid"], -1, "收集区不生成敌方携带者")
			var before := map.duplicate(true)
			MapGenerator.populate_treasure(map, cfg, seed_value + 1, 1, mode)
			t.eq(map, before, "刷新不会重新抽宝箱或携带者")
	t.check(battle_count > 45 and battle_count < 115, "战斗宝箱概率抽样在合理范围")
	t.check(event_count > battle_count and event_count > 105 and event_count < 175, "非战斗节点更常出现宝箱")
	t.check(double_count > 15 and carrier_count > 25, "可出现双宝箱及初始携带者")

func _chests(t: TestContext) -> void:
	var cell := Vector2i(3, 3)
	var state := _state()
	_chest(state, cell)
	t.check(not state.move_options(state.unit_by_uid(1)).has(cell), "地面不能站上宝箱")
	state.unit_by_uid(1).battle_buffs["flight"] = true
	t.check(not state.move_options(state.unit_by_uid(1)).has(cell), "飞行也不能停在宝箱")
	state.set_terrain(cell, TerrainDB.WATER)
	t.eq(state.terrain_at(cell), TerrainDB.OBSTACLE, "宝箱不被地形覆盖")
	var preview := state.preview_skill(state.unit_by_uid(1), "rock_break", {"type": "cell", "cell": cell})
	t.check(state.is_chest_cell(cell), "破箱预览不提前消耗宝箱")
	SkillResolver.apply(state, state.unit_by_uid(1), "rock_break", {"type": "cell", "cell": cell}, false)
	t.check(not state.is_chest_cell(cell), "一次碎岩破箱")
	t.eq(state.all_rewards().filter(func(p): return p.get("state") == "map").size(), 1, "破箱原格出现一个奖励点")
	t.eq(state.reward["cell"], cell, "掉落位置是宝箱原格")
	t.eq(preview["obstacles_damaged"][0]["damage"], 1, "宝箱只有1耐久")
	state.damage_obstacle(cell, 100, "player")
	t.eq(state.all_rewards().size(), 1, "重复攻击不重复掉落")
	state.damage_reward_at(cell)
	t.eq(state.reward["state"], "map", "奖励点不被攻击摧毁")
	var area := _state()
	_chest(area, cell)
	SkillResolver.resolve_channel(area, area.unit_by_uid(1), "fire_burst", [cell])
	t.eq(area.reward["state"], "map", "破箱同一次范围技能不会毁掉新掉落")
	var lightning := _state()
	lightning.node_kind = "event"
	lightning.unit_by_uid(100).hp = 0
	lightning.stop_nests()
	lightning.unit_by_uid(1).skills = ["lightning"]
	_chest(lightning, cell)
	t.check(not SkillResolver.targets(lightning, lightning.unit_by_uid(1), "lightning").is_empty(), "收集区只有宝箱时打雷仍有合法目标")
	SkillResolver.apply(lightning, lightning.unit_by_uid(1), "lightning", {"type": "cell", "cell": lightning.unit_by_uid(1).cell}, false)
	t.check(lightning.chests.is_empty() and lightning.reward["state"] == "map", "收集区打雷可正常开箱并保留奖励点")
	var collision := _state()
	_chest(collision, cell)
	collision.unit_by_uid(100).cell = Vector2i(2, 3)
	PushResolver.push(collision, collision.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试")
	t.check(collision.is_chest_cell(cell), "碰撞不损伤宝箱")
	var push := _state()
	_chest(push, Vector2i(2, 3))
	SkillResolver.apply(push, push.unit_by_uid(1), "rock_push", {"type": "cell", "cell": Vector2i(2, 3)}, false)
	t.check(not push.is_chest_cell(Vector2i(2, 3)) and push.reward["cell"] == Vector2i(2, 3), "推击直接开箱而不是搬运宝箱")

func _drops(t: TestContext) -> void:
	var state := _state()
	var enemy := state.unit_by_uid(100)
	enemy.reward_carrier = true
	state.kill_unit(enemy, "测试", "player", 1)
	t.eq(state.reward["cell"], Vector2i(5, 3), "击杀携带者在死亡格掉落")
	state.kill_unit(enemy, "重复", "player", 1)
	t.eq(state.all_rewards().size(), 1, "同一携带者不重复掉落")
	for kind in [TerrainDB.DEEP, TerrainDB.PIT, TerrainDB.LAVA]:
		var fatal := _state()
		fatal.unit_by_uid(100).reward_carrier = true
		fatal.set_terrain(Vector2i(6, 3), kind)
		PushResolver.push(fatal, fatal.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "推落", "player", 1)
		t.check(fatal.all_rewards().all(func(p): return p.get("state") == "absent"), "推下危险格不生成奖励点")
	var captured := _state()
	captured.unit_by_uid(100).reward_carrier = true
	captured.on_captured(captured.unit_by_uid(100), "rock_wild1", 1)
	t.check(not captured.unit_by_uid(100).reward_carrier and captured.reward["state"] == "absent", "捕获不触发击杀掉落")
	var nest := _state()
	var cell: Vector2i = nest.nest["cell"]
	nest.damage_nest(30, "player", cell)
	t.eq(nest.reward["cell"], cell, "拆巢原格生成奖励点")
	t.eq(nest.reward["state"], "map", "拆巢不自动取得奖励")
	var boss_state := _state()
	boss_state.node_kind = "boss"
	boss_state.boss_uid = 100
	boss_state.unit_by_uid(100).is_boss = true
	var boss_cell: Vector2i = boss_state.unit_by_uid(100).cell
	boss_state.add_reward_point(boss_cell, "nest:portal-test")
	boss_state.kill_unit(boss_state.unit_by_uid(100), "测试", "player", 1)
	boss_state.check_battle_end()
	t.check(boss_state.boss_portal_cell != boss_cell and GridSpec.is_inside(boss_state.boss_portal_cell), "传送门避开奖励点原格")
	t.check(not boss_state.is_interaction_cell(boss_cell), "首领倒下后奖励点仍可站立拾取")
	var run := RunState.new_run(7070)
	var unpicked := _state()
	unpicked.end_battle("victory")
	t.eq(run.settle_battle(unpicked)["reward_points_earned"], 0, "清场没有未持有点数的额外经验")

func _settle(t: TestContext) -> void:
	var state := _state()
	var cell := Vector2i(3, 3)
	state.add_reward_point(cell, "chest:one")
	state.add_reward_point(cell, "enemy:one")
	state.add_reward_point(cell, "enemy:one")
	t.eq(state.all_rewards().size(), 2, "多个来源同格可共存，来源去重")
	state.unit_by_uid(1).cell = cell
	state._begin_reward_guard()
	state._finish_reward_guard()
	t.check(state.all_rewards().all(func(p): return p.get("state") == "carried"), "同一单位可拾取多个奖励点")
	state.end_battle("escape")
	var run := RunState.new_run(7071)
	run.mark_deployed([1])
	var result := run.settle_battle(state)
	t.eq(result["reward_points_earned"], 2, "保住两个奖励点获得两点额外经验")
	var xp_after := int(run.record_by_uid(1)["xp"])
	run.settle_battle(state)
	t.eq(int(run.record_by_uid(1)["xp"]), xp_after, "重复结算不重复发放奖励经验")
	var dead := _state()
	dead.add_reward_point(cell, "test")
	dead.unit_by_uid(1).cell = cell
	dead._begin_reward_guard()
	dead._finish_reward_guard()
	dead.kill_unit(dead.unit_by_uid(1), "测试")
	dead.end_battle("escape")
	t.eq(RunState.new_run(7072).settle_battle(dead)["reward_points_earned"], 0, "持有者倒下失去奖励")

func _persist(t: TestContext) -> void:
	var state := _state()
	_chest(state, Vector2i(3, 3))
	state.add_reward_point(Vector2i(4, 3), "enemy:old")
	state.unit_by_uid(100).reward_carrier = true
	var old := BattleSnapshot.save_state(state)
	old["fields"].erase("extra_rewards")
	old["fields"]["reward"] = BattleSnapshot.encode({"state": "map", "cell": Vector2i(6, 4)})
	t.eq(BattleSnapshot.load_state(old).reward["state"], "absent", "旧档未领取的固定奖励点移除")
	old["fields"]["reward"] = BattleSnapshot.encode({"state": "carried", "cell": Vector2i(6, 4), "owner_uid": 1})
	t.eq(BattleSnapshot.load_state(old).reward["state"], "carried", "旧档已取得的奖励保留")
	var copy := BattleSnapshot.load_state(BattleSnapshot.save_state(state)).clone()
	t.eq(copy.chests, state.chests, "存读档和克隆保留宝箱")
	t.check(copy.unit_by_uid(100).reward_carrier, "存读档和克隆保留携带者")
	t.eq(copy.all_rewards(), state.all_rewards(), "存读档保留多个奖励点")
	copy.damage_obstacle(Vector2i(3, 3), 1, "player")
	copy.end_battle("escape")
	var region := RegionState.create_floor(0, "grass")
	region.store_battle("battle_1", copy)
	var resumed := region.resume_node("battle_1", [], {})
	t.check(resumed.chests.is_empty(), "已开宝箱重访不再生成")
	t.eq(resumed.all_rewards().filter(func(p): return p.get("state") == "map").size(), 2, "离场留下的奖励点重访保留")
	t.check(resumed.unit_by_uid(100).reward_carrier, "初始携带者身份重访保持")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(7073)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state()
	_chest(screen.state, Vector2i(3, 3))
	screen.state.unit_by_uid(100).reward_carrier = true
	app._switch(screen)
	screen.playback.finish_all()
	screen.refresh_all()
	screen._show_terrain(Vector2i(3, 3))
	t.check(screen.terrain_label.text.contains("宝箱") and screen.terrain_label.text.contains("耐久1"), "宝箱说明显示实体与耐久")
	t.eq(screen.board.chests.size(), 1, "棋盘绘制宝箱")
	screen.state.add_reward_point(Vector2i(4, 3), "one")
	screen.state.add_reward_point(Vector2i(4, 4), "two")
	screen.playback.finish_all()
	screen.refresh_all()
	t.eq(screen.board.extra_rewards.size(), 1, "棋盘显示多个独立奖励点")
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	region.active_node = "battle_1"
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	var preview = app.current_screen
	var boxes: Dictionary = preview.map["chests"].duplicate()
	var carriers: Array = preview.deploy_enemies.filter(func(u): return u.reward_carrier).map(func(u): return u.uid)
	t.eq(preview.map["reward"]["state"], "absent", "正式整备页没有固定奖励点")
	preview._on_start()
	var battle: BattleState = app.current_screen.state
	t.eq(battle.chests, boxes, "正式开战宝箱与预览一致")
	t.eq(battle.alive_units("enemy").filter(func(u): return u.reward_carrier).map(func(u): return u.uid), carriers, "正式开战携带者与预览一致")
	app.free()
