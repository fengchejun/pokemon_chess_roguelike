extends RefCounted
const CampMap = preload("res://scripts/run/camp_map.gd")

func run(t: TestContext) -> void:
	t.begin("营地共享战场、预设地形与永久设施损毁")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8102)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	var screen = app.current_screen
	var state: BattleState = screen.state
	t.check(state.is_free_exploration() and state.is_camp_map, "和平营地使用非战斗节点规则")
	t.check(state.terrain.any(func(value): return value != TerrainDB.PLAIN and value != TerrainDB.OBSTACLE), "营地包含自然地形")
	var fire := Vector2i(3, 3)
	var storage := Vector2i(6, 3)
	t.eq(state.obstacle_durability[fire], 2, "篝火初始2耐久")
	t.eq(state.obstacle_durability[storage], 5, "仓库初始5耐久")
	var caster := state.unit_by_uid(1)
	caster.skills = ["rain_call", "ice_shard", "rock_break"]
	caster.cell = Vector2i(2, 2)
	state.terrain[GridSpec.index(caster.cell)] = TerrainDB.PLAIN
	state.obstacle_durability.erase(caster.cell)
	var target := Vector2i(2, 3)
	state.terrain[GridSpec.index(target)] = TerrainDB.PLAIN
	state.obstacle_durability.erase(target)
	t.check(state.cast_skill(caster, "rain_call", {"type": "cell", "cell": target}).get("ok", false), "和平营地可实际施放造雨")
	t.eq(state.terrain_at(target), TerrainDB.WATER, "造雨实际改变营地地形")
	t.eq(state.obstacle_durability[fire], 2, "造雨不覆盖设施")
	# 自建岩障与藤蔓也必须跨离场保留。
	var fortification := Vector2i(4, 5)
	state.place_temp_obstacle(fortification, TerrainDB.PLAIN, state.round + 1)
	var vines := Vector2i(5, 5)
	state.set_terrain(vines, TerrainDB.PLAIN)
	state.place_temp_vines(vines)
	t.check(state.cast_skill(caster, "ice_shard", {"type": "cell", "cell": fire}).get("ok", false), "普通直伤招式可真实命中篝火")
	t.eq(state.obstacle_durability[fire], 1, "普通命中只扣1耐久")
	var preview := state.clone()
	preview.damage_obstacle(fire, 1, "player")
	t.check(not state.camp_facilities["fire"]["destroyed"], "克隆预览不会损毁真实设施")
	t.check(app.run.camp_service_available("fire"), "尚存篝火可服务")
	state.damage_obstacle(fire, 1, "enemy")
	state.damage_obstacle(storage, 1, "enemy")
	app.sync_and_save(state)
	t.check(not app.run.camp_service_available("fire"), "敌军毁坏篝火后即时禁用恢复")
	t.check(not app.run.rest_with_food({"basic": 3}).get("ok", false), "不能绕过UI使用已毁篝火")
	var prepared := state.terrain.duplicate()
	var facilities := state.camp_facilities.duplicate(true)
	t.check(app.save_battle_and_return(state), "和平营地可保存并返回主菜单")
	t.check(app.run.battle_snapshot.is_empty(), "保存和平营地不伪装成进行中的战斗")
	var path := "res://.test_shared_camp_continue.json"
	SaveSystem.save_run(app.run, path)
	app.continue_run(path)
	t.eq(app.current_screen.name, "CampScreen", "继续游戏仍进入营地场景")
	t.eq(app.current_screen.state.terrain, prepared, "返回主菜单并继续保留布置地形")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	app.leave_camp()
	t.check(app.run.battle_snapshot.is_empty(), "离开和平营地不残留活动战斗快照")
	app.run = RunState.from_dict(app.run.to_dict())
	var region = app.run.get_region()
	region.visits = 7
	app.run.region_data = region.to_dict()
	app.enter_region_node("camp")
	t.eq(app.current_screen.name, "PrepScreen", "第八次移动入侵营地进入战前整备")
	t.eq(app.current_screen.map["terrain"], prepared, "入侵预览与提前布置的地图完全一致")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var invaded: BattleState = app.current_screen.state
	t.check(invaded.is_camp_map and invaded.alive_enemy_count() > 0, "实际入侵发生在营地战场")
	t.eq(invaded.terrain_at(target), TerrainDB.WATER, "入侵沿用造雨结果")
	t.eq(invaded.terrain_at(fortification), TerrainDB.OBSTACLE, "入侵保留自建岩障")
	t.eq(invaded.terrain_at(vines), TerrainDB.VINES, "入侵保留预设藤蔓")
	t.eq(invaded.camp_facilities, facilities, "入侵继承设施损毁状态")
	t.eq(invaded.obstacle_durability[storage], 4, "仓库受损耐久跨离场保留")
	# 实际碎岩沿用破障规则，一次摧毁余下仓库耐久。
	caster = invaded.unit_by_uid(1)
	caster.skills = ["rock_break"]
	caster.cell = Vector2i(6, 2)
	invaded.terrain[GridSpec.index(caster.cell)] = TerrainDB.PLAIN
	invaded.obstacle_durability.erase(caster.cell)
	caster.skill_used = false
	t.check(invaded.cast_skill(caster, "rock_break", {"type": "cell", "cell": storage}).get("ok", false), "碎岩可以真实攻击仓库")
	t.check(invaded.camp_facilities["storage"]["destroyed"], "碎岩特殊破障规则摧毁仓库")
	for enemy in invaded.alive_units("enemy"):
		enemy.hp = 0
	invaded.stop_nests()
	invaded.end_battle("victory")
	app.finish_battle(invaded)
	while app.run.pending_reward_choices > 0: app.run.skip_reward_choice()
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "CampScreen", "夺回后返回同一营地")
	t.check(not app.run.camp_service_available("fire") and not app.run.camp_service_available("storage"), "夺回不修复已毁设施")
	app.run.storage.append(app.run._make_record("water_starter", 8))
	t.check(not app.run.camp_swap(1, int(app.run.storage[0]["uid"])), "被毁仓库无法通过接口交换")
	app.run.pending_captures.append(app.run._make_record("fire_starter", 8))
	t.check(not app.run.capture_to_storage(), "被毁仓库不接收新捕获")
	t.eq(app.run.pending_captures.size(), 1, "拒绝入库不吞掉待处理捕获")
	t.check(not app.run.release_storage(int(app.run.storage[0]["uid"])), "无法绕过已毁仓库取出留守成员")
	while app.run.carried.size() < Balance.CARRIED_LIMIT:
		app.run.carried.append(app.run._make_record("grass_starter", 8))
	app.run.settlement_pending = true
	var settlement = load("res://scripts/ui/settlement_screen.gd").new()
	app._switch(settlement)
	var discard: Button = settlement.find_child("DiscardCaptureDestroyedStorage", true, false)
	t.check(discard != null, "背包满且仓库已毁时提供明确处理入口")
	discard.pressed.emit()
	t.check(app.run.pending_captures.is_empty(), "玩家主动放弃后可以继续结算")
	app.run = RunState.from_dict(app.run.to_dict())
	t.check(not app.run.camp_service_available("fire") and not app.run.camp_service_available("storage"), "损毁状态保存读档后仍生效")
	app.run.battle_index = 6
	app.run.region_data = {}
	app.run.refresh_theme_offers()
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var next := CampMap.ensure(app.run)
	t.eq(next.obstacle_durability[fire], 2, "下一层重新生成篝火")
	t.eq(next.obstacle_durability[storage], 5, "下一层重新生成仓库")
	app.free()
	t.finish()
