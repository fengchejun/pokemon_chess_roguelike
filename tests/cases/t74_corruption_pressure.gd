extends RefCounted

func run(t: TestContext) -> void:
	t.begin("战斗与区域黑化、全面占领和营地夺回")
	_timed(t)
	_growth_and_damage(t)
	_movement(t)
	_occupation(t)
	_camp_ui(t)
	_persistence(t)
	t.finish()

func _run_state(floor: int = 0) -> RunState:
	var run := RunState.new_run(7401)
	run.region_mode = true
	run.battle_index = floor * Balance.BATTLES_PER_FLOOR
	run.choose_floor_theme(String(run.offered_floor_themes[0]))
	var region = RegionState.create_floor(floor, run.current_theme())
	for node in region.nodes.values():
		node["unlocked"] = true
	region.active_node = "battle_1"
	run.region_data = region.to_dict()
	run.mark_deployed([1])
	return run

func _state(run: RunState = null) -> BattleState:
	if run == null:
		run = _run_state()
	var state := BattleState.new()
	state.node_kind = "battle"
	state.setup(TestScenario.make_map(TestScenario.plain_terrain(), Vector2i(5, 5)), {"enemies": [["rock_wild1", Vector2i(4, 3)], ["grass_wild1", Vector2i(5, 4)]]}, 7401, 0, run.build_deploy_units([1]), {}, {}, ["rock_wild1"])
	return state

func _darken(state: BattleState) -> void:
	state.round = 8
	state.settle_round()

func _timed(t: TestContext) -> void:
	var state := _state()
	state.round = 7
	state.settle_round()
	t.check(not state.corruption_active, "第七轮末未黑化")
	var enemy := state.unit_by_uid(100)
	var before: int = enemy.max_hp
	enemy.hp = before / 2
	enemy.moved = true
	enemy.skill_used = true
	state.unit_by_uid(101).hp = 0
	var player_hp: int = state.unit_by_uid(1).hp
	_darken(state)
	t.check(state.timed_corruption_triggered and enemy.corrupted, "第八轮末黑化并记录占领事件")
	t.eq(enemy.max_hp, ceili(before * 11 / 10.0), "最大生命增加10%")
	t.eq(enemy.hp, roundi(float(before / 2) * enemy.max_hp / before), "按当前生命比例调整，不回满")
	t.check(enemy.moved and enemy.skill_used, "黑化不刷新行动")
	t.eq(state.unit_by_uid(101).hp, 0, "黑化不复活敌人")
	t.eq(state.unit_by_uid(1).hp, player_hp, "不影响我方生命")
	t.check(not state.trainer().corrupted, "训练家不黑化")
	t.check(not state.storm_strikes.is_empty(), "第八轮末仍预告天雷")
	var dark_max: int = enemy.max_hp
	state._trigger_timed_corruption()
	enemy.set_corrupted(true)
	t.eq(enemy.max_hp, dark_max, "重复结算不叠加生命")
	state.kill_unit(enemy, "击杀黑化初始敌人", "player", 1)
	t.eq(state.enemy_kills.back()["xp_reward"], 0, "黑化初始敌人也无击杀经验")
	t.eq(state.unit_by_uid(1).combat_xp, 0, "原出战成员不获得黑化击杀经验")
	t.eq(state.trainer().combat_xp, 0, "训练家也不获得黑化击杀经验")
	state.round = 9
	state.nest["pending_waves"] = 1
	state._try_spawn_wave()
	t.check(state.units.back().corrupted, "黑化后新出生增援同样黑化")
	var summon := state.summon_tree(state.units.back(), Vector2i(6, 6))
	t.check(summon != null and summon.corrupted, "黑化节点敌方新召唤物也黑化")
	var capture := _state()
	capture.capture_options["capture_field_join"] = true
	_darken(capture)
	capture.on_captured(capture.unit_by_uid(100), "rock_wild1", 5)
	t.check(not capture.unit_by_uid(100).corrupted, "捕获加入我方后去除黑化")
	t.check(capture.unit_by_uid(1).combat_xp > 0, "黑化只取消击杀经验，捕获经验保留")

func _growth_and_damage(t: TestContext) -> void:
	var state := _state()
	var enemy := state.unit_by_uid(100)
	enemy.skills = ["rock_break"]
	var opts := {"skill_direct": true, "no_element": true, "skill_id": "rock_break"}
	t.eq(state.calculate_damage(enemy, state.trainer(), 10, opts), 10, "普通敌人技能不再承受70%减益")
	enemy.max_hp = 50
	enemy.hp = 25
	enemy.set_corrupted(true)
	t.eq(enemy.max_hp, 55, "50生命精确变55，不因浮点误差变56")
	t.eq(state.calculate_damage(enemy, state.trainer(), 10, opts), 11, "黑化技能按完整基础伤害提升10%")
	t.eq(state.calculate_damage(enemy, state.trainer(), 5, {"no_element": true, "collision": true}), 5, "碰撞伤害不获得技能威力加成")
	state.unit_by_uid(1).cell = Vector2i(3, 3)
	var target := {"type": "unit", "unit": 1, "cell": Vector2i(3, 3)}
	var preview := state.preview_skill(enemy, "rock_break", target)
	var actual := SkillResolver.apply(state, enemy, "rock_break", target, false)
	t.eq(actual["hits"], preview["hits"], "黑化技能预览与真实执行一致")
	state.corruption_active = true
	state.set_enemy_level_bonus(1)
	var maximum: int = enemy.max_hp
	state.set_enemy_level_bonus(1)
	t.eq(enemy.max_hp, maximum, "等级与黑化叠加后重复同步不会膨胀")
	var base := MonsterProgression.max_hp(enemy.species_id, enemy.enemy_level)
	t.eq(enemy.max_hp, ceili(base * 11 / 10.0), "等级生命之后再加黑化10%")
	var inspired := _state()
	_darken(inspired)
	var ally := inspired.unit_by_uid(100)
	inspired._grant_inspiration(ally)
	t.eq(ally.max_hp, ceili((SpeciesDB.hp_of(ally.species_id) + Balance.INSPIRATION_HP_BONUS) * 11 / 10.0), "黑化与首领鼓舞正确组合")

func _movement(t: TestContext) -> void:
	var run := _run_state()
	var region = run.get_region()
	region.visits = 7
	region.active_node = "camp"
	region.record_entry("battle_1")
	t.check(not region.support_triggered, "八次移动不再自动占领")
	region.complete_visit()
	region.visits = 10
	run.region_data = region.to_dict()
	run.enter_region_node("battle_1")
	t.check(run.get_region().corrupted, "第十一次移动触发全图黑化")
	t.eq(run.invasion_level_bonus, 1, "保留第十一次移动等级+1")
	t.check(run.battle_config()["corrupted"], "后续战斗配置含全图黑化")
	run.cancel_region_entry()
	t.eq(run.get_region().visits, 10, "取消预览回退移动")
	t.check(not run.get_region().corrupted, "取消预览回退本次全图黑化")
	t.eq(run.invasion_level_bonus, 0, "取消预览回退本次等级增长")
	run.enter_region_node("battle_1")
	region = run.get_region()
	region.complete_visit()
	run.region_data = region.to_dict()
	run.battle_index = 6
	run.region_data.clear()
	t.check(not run.get_region().corrupted, "进入下一层黑化结束")
	t.eq(run.invasion_level_bonus, 1, "旧的区域等级增长仍跨层保留")

func _occupation(t: TestContext) -> void:
	var run := _run_state(2)
	var region = run.get_region()
	region.nodes["battle_2"]["cleared"] = true
	region.nodes["battle_2"]["mode"] = "event"
	run.region_data = region.to_dict()
	var state := _state(run)
	state.nest["hp"] = 7
	_darken(state)
	run.sync_from_battle(state)
	region = run.get_region()
	for id in region.nodes:
		if id != "boss":
			t.eq(region.node_mode(id), "battle", "全面占领包含营地和已清理节点")
	t.check(region.nodes["battle_1"]["corrupted"], "本场黑化记入本节点至离层")
	t.check(not region.corrupted, "本场超时不会提前让所有其他节点黑化")
	t.check(not run.rest_with_food({"basic": 3})["ok"], "营地被占期间不能回复")
	region.nodes["camp"]["mode"] = "camp"
	region.camp_invaded = false
	run.region_data = region.to_dict()
	run.sync_from_battle(state)
	t.eq(run.get_region().node_mode("camp"), "camp", "重复同步同一场不重复占领夺回的营地")
	region = run.get_region()
	state.end_battle("escape")
	region.store_battle("battle_1", state)
	var resumed: BattleState = region.resume_node("battle_1", run.build_deploy_units([1]), {"enemies": [], "reinforce": ["rock_wild1"]})
	t.eq(resumed.nest["hp"], 7, "当前战斗不因占领重置巢穴损伤")
	t.check(resumed.corruption_active and resumed.alive_units("enemy").all(func(u): return u.corrupted), "重访保留本节点黑化并影响新驻军")
	t.check(not resumed.timed_corruption_triggered, "新一场重新计时")
	region.active_node = "battle_1"
	run.region_data = region.to_dict()
	_darken(resumed)
	run.sync_from_battle(resumed)
	t.eq(run.get_region().node_mode("camp"), "battle", "另一场再拖满八轮可重新占领营地")

func _camp_ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = _run_state()
	var region = app.run.get_region()
	region.occupy_all()
	region.visits = 10
	app.run.region_data = region.to_dict()
	app.enter_region_node("camp")
	t.eq(app.current_screen.name, "PrepScreen", "被占营地进入战斗整备预览")
	var preview = app.current_screen
	t.check(preview.deploy_enemies.all(func(u): return u.corrupted), "全图黑化在实际预览中可见")
	preview._on_start()
	var state: BattleState = app.current_screen.state
	t.check(state.alive_units("enemy").all(func(u): return u.corrupted), "正式开战与预览黑化一致")
	app.current_screen.playback.finish_all()
	app.current_screen.viewed_enemy_uid = state.alive_units("enemy")[0].uid
	app.current_screen.refresh_all()
	t.check(app.current_screen.unit_body.text.contains("黑化"), "敌人详情显示黑化与零经验")
	for enemy in state.alive_units("enemy"):
		enemy.hp = 0
	state.damage_nest(int(state.nest["hp"]), "player")
	state.end_battle("victory")
	app.finish_battle(state)
	t.eq(app.run.get_region().node_mode("camp"), "camp", "营地清场恢复营地模式")
	t.check(not app.run.get_region().camp_invaded, "营地占领标记解除")
	var visits: int = app.run.get_region().visits
	app.run.pending_reward_choices = 0
	app.current_screen._show_next_step()
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "CampScreen", "夺回结算后直接进入营地，无需再走一次")
	t.check(app.current_screen.find_child("CampFeedback", true, false).text.contains("已夺回"), "营地提示已恢复服务")
	t.eq(app.run.get_region().visits, visits, "夺回开放回复不额外计区域移动")
	app.run.trainer_hp = 1
	app.run.food_inventory["basic"] = 3
	t.eq(app.current_screen.name, "CampScreen", "夺回营地后实际打开回复界面")
	app.current_screen.find_child("Campfire", true, false).pressed.emit()
	var rest = app.current_screen.find_child("CampRestButton", true, false)
	t.check(rest != null and not rest.disabled, "夺回后可以使用原有食物回复")
	if rest != null:
		rest.pressed.emit()
	t.eq(app.run.trainer_hp, app.run.trainer_max_hp(), "夺回后食物回复实际生效")
	app.free()

func _persistence(t: TestContext) -> void:
	var state := _state()
	_darken(state)
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state)).clone()
	t.eq(restored.unit_by_uid(100).max_hp, state.unit_by_uid(100).max_hp, "克隆读档不重复增加生命")
	t.check(restored.corruption_active and restored.unit_by_uid(100).corrupted, "克隆读档保留黑化")
	var old := BattleSnapshot.save_state(_state())
	old["version"] = 5
	old["fields"]["round"] = BattleSnapshot.encode(9)
	var migrated := BattleSnapshot.load_state(old)
	t.check(migrated.corruption_active, "旧进行中超八轮快照兼容新黑化规则")
	var region := RegionState.create_floor(0, "rock")
	region.visits = 11
	region.corrupted = true
	var reload := RegionState.from_dict(region.to_dict())
	t.check(reload.corrupted, "区域黑化存读档保留")
	region.nodes["battle_1"]["snapshot"] = BattleSnapshot.save_state(_state())
	var old_enemy_hp: int = _state().unit_by_uid(100).max_hp
	var cached := region.load_battle("battle_1")
	t.check(cached.unit_by_uid(100).corrupted, "已保存节点也受全图黑化影响")
	t.eq(cached.unit_by_uid(100).max_hp, ceili(old_enemy_hp * 11 / 10.0), "旧节点加载全图黑化只加一次")
	var run := _run_state()
	run.in_battle = true
	run.battle_snapshot = old
	var data := run.to_dict()
	data["version"] = 14
	var path := "res://.test_t74_legacy.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	t.check(file != null, "旧版区域档案可写入测试路径")
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "真实v14文件仍可读取")
	if loaded != null:
		t.check(BattleSnapshot.load_state(loaded.battle_snapshot).corruption_active, "旧文件超八轮战斗加载后黑化")
	SaveSystem.delete_save(path)
