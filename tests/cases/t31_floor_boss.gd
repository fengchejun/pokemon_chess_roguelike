extends RefCounted


func run(t: TestContext) -> void:
	t.begin("三层主题、首领与永久首领之血")
	_themes_and_maps(t)
	_boundary_routing(t)
	_eighteen_battle_route(t)
	_enemy_levels_and_boss(t)
	_blood_and_save(t)
	t.finish()


func _themes_and_maps(t: TestContext) -> void:
	var run_state := RunState.new_run(31001)
	t.eq(BattleDB.count(), 18, "三层每层六战")
	for floor_index in 3:
		t.eq(run_state.floor_index(), floor_index, "当前楼层正确")
		t.check(run_state.needs_theme_choice(), "每层开始需选择主题")
		t.eq(run_state.offered_floor_themes.size(), 2, "每层提供两个主题")
		var offer: Array = run_state.offered_floor_themes.duplicate()
		t.eq(RunState.from_dict(run_state.to_dict()).offered_floor_themes, offer, "读档保持待选的两个主题")
		var theme_id := String(offer[0])
		t.check(not run_state.floor_themes.has(theme_id), "本局主题不会重复")
		t.check(run_state.choose_floor_theme(theme_id), "可选择本层候选主题")
		t.eq(run_state.current_theme(), theme_id, "主题写入本局状态")
		var restored := RunState.from_dict(run_state.to_dict())
		t.eq(restored.current_theme(), theme_id, "读档保持所选主题")
		for local_index in 6:
			var index := floor_index * 6 + local_index
			var cfg := BattleDB.config_for(index, run_state.seed, theme_id)
			t.eq(String(cfg["region"]), String(BattleDB.THEMES[theme_id]["name"]), "本层六战共享地形主题")
			t.eq((cfg["enemies"] as Array).size(), (BattleDB.CONFIGS[local_index]["enemies"] as Array).size(), "沿用该场敌人数和部署格")
			var themed_count := 0
			for pair in cfg["enemies"]:
				if SpeciesDB.element_of(String(pair[0])) == theme_id:
					themed_count += 1
			t.check(themed_count >= roundi((cfg["enemies"] as Array).size() * 0.6), "合并冰风后主题属性占比不少于原定六成")
			t.eq(int(cfg["boss_index"]) >= 0, local_index == 5, "每层第六战指定一位首领")
			var map := MapGenerator.generate(run_state.seed, index, 0, [], theme_id)
			t.eq(String(map["region"]), String(cfg["region"]), "地图与敌人使用同一主题")
			t.check(int(map["attempt"]) < 64, "主题地图通过可玩性校验")
			run_state.advance_battle()
		if floor_index < 2:
			t.eq(run_state.offered_floor_themes, BattleDB.theme_offers(run_state.seed, floor_index + 1, run_state.floor_themes), "下一层候选可复现")
	t.check(run_state.run_finished(), "第十八战后本局通关")


func _boundary_routing(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(31005)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	for next_floor in [1, 2]:
		app.run.battle_index = next_floor * Balance.BATTLES_PER_FLOOR - 1
		app.run.advance_battle()
		t.check(app.run.supply_due(), "第 6、12 战后补给到期")
		app.run.pending_supply = true
		app.show_supply()
		t.eq(app.current_screen.name, "SupplyScreen", "先进入补给界面")
		app.run.choose_supply_item(String(app.run.supply_choices()[0]))
		app.leave_supply()
		t.eq(app.current_screen.name, "FloorThemeScreen", "补给后进入新层主题选择")
		var theme_id := String(app.run.offered_floor_themes[0])
		var button: Button = app.current_screen.find_child("ChooseTheme_%s" % theme_id, true, false)
		t.check(button != null, "新层主题按钮存在")
		button.pressed.emit()
		t.eq(app.current_screen.name, "PrepScreen", "选完主题再进入整备")
	app.queue_free()


func _eighteen_battle_route(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(31006)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_prep()
	var started := Time.get_ticks_msec()
	for index in Balance.BATTLES_PER_RUN:
		t.eq(app.current_screen.name, "PrepScreen", "第 %d 战从整备开始" % (index + 1))
		app.show_preview([1, 2, 3])
		t.eq(app.current_screen.name, "PrepScreen", "第 %d 战在合并页可以预览" % (index + 1))
		var preview_map: Dictionary = app.current_screen.map.duplicate(true)
		app.begin_battle([1, 2, 3], preview_map)
		t.eq(app.current_screen.name, "BattleScreen", "第 %d 战可以启动" % (index + 1))
		var state: BattleState = app.current_screen.state
		# 只检查长流程：直接给战斗一个胜利结果，不将其计作战术试玩。
		state.end_battle("victory")
		app.finish_battle(state)
		t.eq(app.current_screen.name, "SettlementScreen", "第 %d 战进入结算" % (index + 1))
		while app.run.pending_reward_choices > 0:
			var choices: Array = app.run.reward_choices()
			t.check(not choices.is_empty(), "第 %d 战有可领取的消耗卡" % (index + 1))
			if choices.is_empty():
				break
			app.run.choose_reward(String(choices[0]))
		app.continue_after_settlement()
		if index == Balance.BATTLES_PER_RUN - 1:
			t.eq(app.current_screen.name, "RunEndScreen", "第十八战后进入明确结局")
			break
		if app.current_screen.name == "SupplyScreen":
			app.run.choose_supply_item(String(app.run.supply_choices()[0]))
			app.leave_supply()
		if app.current_screen.name == "FloorThemeScreen":
			var theme_id := String(app.run.offered_floor_themes[0])
			app.run.choose_floor_theme(theme_id)
			app.show_prep()
	t.eq(app.run.battle_index, Balance.BATTLES_PER_RUN, "完整流程推进十八场")
	print("EIGHTEEN_BATTLE_ROUTE_MS %d" % (Time.get_ticks_msec() - started))
	app.queue_free()


func _enemy_levels_and_boss(t: TestContext) -> void:
	var seed_value := 31002
	for theme_id in BattleDB.THEME_IDS:
		for floor_index in 3:
			var cfg_for_theme := BattleDB.config_for(floor_index * 6 + 5, seed_value, String(theme_id))
			var enemy_index := 0
			for pair in cfg_for_theme["enemies"]:
				t.eq(BattleDB.enemy_upgrade_ids(seed_value, floor_index * 6 + 5, enemy_index, String(pair[0])).size(), 0, "Lv1/3/5 的普通敌人没有提前强化")
				enemy_index += 1
			for species_id in cfg_for_theme["reinforce"]:
				t.eq(BattleDB.enemy_upgrade_ids(seed_value, floor_index * 6 + 5, 100 + enemy_index, String(species_id)).size(), 0, "Lv1/3/5 的增援没有提前强化")
				enemy_index += 1
	for species_id in SpeciesDB.SPECIES:
		if species_id == "trainer" or species_id == "tree_summon":
			continue
		for level in [1, 2, 4, 6, 8, 10]:
			var skills := BattleDB.enemy_skills_for_level(String(species_id), level)
			t.eq(skills.size(), BattleDB.enemy_skill_count(level), "敌人各等级拥有规定数量的技能")
			var upgrades := BattleDB.enemy_upgrade_ids_at_level(seed_value, 0, 0, String(species_id), level)
			t.eq(upgrades.size(), clampi((level - 4) / 2, 0, 3), "Lv6/8/10 各增加一次技能强化")
			var unique_upgrades := {}
			for upgrade_id in upgrades:
				var required_skill := String(RunState.upgrade_info(String(upgrade_id)).get("requires_skill", ""))
				t.check(skills.has(required_skill), "敌人只强化已装备技能")
				unique_upgrades[upgrade_id] = true
			t.eq(upgrades.size(), unique_upgrades.size(), "同一技能不会重复强化")
	var water_skills := BattleDB.enemy_skills_for_level("water_wild1", 4)
	t.eq(water_skills[2], "trial_water_1", "水系以同属性可学招式补齐第三招")
	for floor_index in 3:
		var index := floor_index * 6 + 5
		var cfg := BattleDB.config_for(index, seed_value, "fire")
		var state := _state_for(cfg, seed_value, index)
		var boss := state.unit_by_uid(state.boss_uid)
		t.check(boss != null and boss.is_boss, "首领在初始敌人中选出")
		for enemy_index in (cfg["enemies"] as Array).size():
			var unit := state.unit_by_uid(100 + enemy_index)
			t.eq(unit.enemy_level, 1 + floor_index * 2 + (1 if unit.is_boss else 0), "普通敌人 Lv1/3/5，首领高一级")
			t.eq(unit.max_hp, MonsterProgression.max_hp(unit.species_id, unit.enemy_level) + (Balance.BOSS_HP_BONUS if unit.is_boss else 0), "等级与首领生命叠加正确")
			t.eq(unit.skills, BattleDB.enemy_skills_for_level(unit.species_id, unit.enemy_level), "实际技能与等级相符")
			t.eq(unit.upgrades, BattleDB.enemy_upgrade_values(seed_value, index, enemy_index, unit.species_id, unit.is_boss), "技能强化与关卡配置一致")
			t.eq(unit.upgrades.size(), 1 if floor_index == 2 and unit.is_boss else 0, "当前十八战仅第三层首领达到强化等级")
		if floor_index != 2:
			continue
		var knockout := _state_for(cfg, seed_value, index)
		var knockout_boss := knockout.unit_by_uid(knockout.boss_uid)
		knockout.damage_unit(null, knockout_boss, knockout_boss.hp, {"no_element": true, "cause": "测试一击击倒"})
		t.check(not knockout.inspiration_triggered, "首领被一击击倒不会发动鼓舞")
		var ally := state.unit_by_uid(100 if boss.uid != 100 else 101)
		var before_hp := ally.hp
		var before_max := ally.max_hp
		var before_move := ally.effective_move()
		boss.hp = boss.max_hp / 2 + 1
		state.damage_unit(null, boss, 1, {"no_element": true, "cause": "测试触发"})
		t.check(state.inspiration_triggered, "首领半血且存活时触发鼓舞")
		t.eq([ally.hp, ally.max_hp, ally.effective_move()], [before_hp + Balance.INSPIRATION_HP_BONUS, before_max + Balance.INSPIRATION_HP_BONUS, before_move + 1], "鼓舞增加友军当前生命、上限和移动")
		state.damage_unit(null, boss, 1, {"no_element": true, "cause": "测试重复"})
		t.eq(ally.max_hp, before_max + Balance.INSPIRATION_HP_BONUS, "鼓舞只触发一次")
		boss.hp = boss.max_hp
		t.check(ally.inspired, "首领恢复后鼓舞仍在")
		state.nest["pending_waves"] = 1
		state._try_spawn_wave()
		var reinforcement := state.units.back() as CombatUnit
		t.check(reinforcement.inspired, "后出生增援也得到鼓舞")
		t.eq(reinforcement.enemy_level, 5, "增援继承当前楼层等级")
		t.eq(reinforcement.skills.size(), 3, "增援按当前等级装备三招")
		t.eq(reinforcement.upgrades.size(), 0, "Lv5 增援尚未达到强化等级")
		state.on_captured(boss, boss.species_id, 1)
		t.check(not boss.is_boss and boss.enemy_level == 1 and boss.upgrades.is_empty(), "捕获后首领恢复普通物种")
		t.check(ally.inspired and state.inspiration_triggered, "捕获首领不撤销已触发的敌方鼓舞")
		state.on_captured(ally, ally.species_id, 1)
		t.check(not ally.inspired, "被捕获的鼓舞友军转阵营时移除加成")


func _blood_and_save(t: TestContext) -> void:
	var run_state := RunState.new_run(31003)
	var profile := CollectionState.defaults()
	var cfg := BattleDB.config_for(5, run_state.seed, "water")
	var state := _state_for(cfg, run_state.seed, 5)
	var boss := state.unit_by_uid(state.boss_uid)
	state.on_captured(boss, boss.species_id, 1)
	state.end_battle("victory")
	var outcome := run_state.settle_battle(state)
	t.eq(int(outcome["boss_blood"]), 1, "捕获首领且清场获胜领取首领之血")
	run_state.battle_index = 5
	t.check(profile.credit_boss_capture(run_state, outcome), "首领之血写入永久收藏")
	t.eq(profile.boss_blood, 1, "永久资源数量正确")
	t.check(not profile.credit_boss_capture(run_state, outcome), "同一场不会重复入账")
	var path := "res://.test_boss_blood_profile.json"
	t.check(profile.save(path), "首领之血可保存")
	var reloaded := CollectionState.load_profile(path)
	t.eq(reloaded.boss_blood, 1, "读档保留首领之血")
	t.check(not reloaded.credit_boss_capture(run_state, outcome), "读档后仍能阻止重复入账")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var escaped := _state_for(cfg, run_state.seed, 5)
	escaped.on_captured(escaped.unit_by_uid(escaped.boss_uid), boss.species_id, 1)
	escaped.end_battle("escape")
	t.eq(int(RunState.new_run(31003).settle_battle(escaped)["boss_blood"]), 0, "捕获首领后超时逃离不发首领之血")
	var nest_win := _state_for(cfg, run_state.seed, 5)
	nest_win.on_captured(nest_win.unit_by_uid(nest_win.boss_uid), boss.species_id, 1)
	nest_win.nest["alive"] = false
	nest_win.end_battle("victory")
	t.eq(int(RunState.new_run(31003).settle_battle(nest_win)["boss_blood"]), 0, "捕获首领后毁巢速通不发首领之血")
	var failed := _state_for(cfg, run_state.seed, 5)
	var failed_boss := failed.unit_by_uid(failed.boss_uid)
	failed.on_captured(failed_boss, failed_boss.species_id, 1)
	failed.end_battle("forced_retreat")
	var failed_run := RunState.new_run(31004)
	failed_run.battle_index = 5
	var failed_outcome := failed_run.settle_battle(failed)
	t.eq(int(failed_outcome["boss_blood"]), 0, "训练家死亡时本场首领之血失效")


func _state_for(cfg: Dictionary, seed_value: int, battle_index: int) -> BattleState:
	var map := TestScenario.make_map(TestScenario.plain_terrain(), cfg["nest_cell"], Vector2i(3, 3))
	map["nest_exits"] = (cfg["nest_exits"] as Array).duplicate()
	var trainer := CombatUnit.make("trainer", "player", Balance.TRAINER_UID)
	var state := BattleState.new()
	state.setup(map, cfg, seed_value, battle_index, [trainer], {}, {}, cfg["reinforce"])
	return state
