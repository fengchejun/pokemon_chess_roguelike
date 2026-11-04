extends RefCounted

func run(t: TestContext) -> void:
	t.begin("首领半血回巢、庇护与破巢出场")
	_transition(t)
	_immunity_and_pause(t)
	_release_and_capture(t)
	_bypass(t)
	_area_and_occupied_exit(t)
	_save(t)
	_node_and_ui(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["fire_starter", "grass_starter"], [["rock_wild1", Vector2i(4, 3)], ["grass_wild1", Vector2i(6, 3)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "boss"
	state.boss_uid = 100
	var boss := state.unit_by_uid(100)
	boss.is_boss = true
	boss.max_hp = 60
	boss.hp = 60
	state.nest["cell"] = Vector2i(4, 2)
	return state

func _retreat(state: BattleState) -> void:
	var boss := state.unit_by_uid(state.boss_uid)
	state.damage_unit(null, boss, 31, {"no_element": true})

func _break_nest(state: BattleState) -> void:
	state.damage_nest(int(state.nest["hp"]), "player")

func _transition(t: TestContext) -> void:
	var state := _state()
	var boss := state.unit_by_uid(100)
	var old_cell := boss.cell
	state.begin_channel(boss, "rock_slide", [Vector2i(1, 3)])
	_retreat(state)
	t.eq(boss.hp, 29, "越过半血的伤害完整扣除而非锁血")
	t.check(state.boss_retreat_used and boss.sheltered, "首次半血进入庇护")
	t.check(state.inspiration_triggered and state.unit_by_uid(101).inspired, "回巢同时鼓舞守卫")
	t.eq(state.unit_at(old_cell), null, "回巢后原位置不占格")
	t.eq(state.unit_at(state.nest["cell"]), null, "庇护首领不覆盖巢穴")
	t.check(not state.nest_covered(), "主巢穴可被拆除")
	t.eq(state.alive_enemy_count(), 2, "庇护首领仍计入存活敌人")
	t.check(not state.alive_units("enemy").has(boss), "庇护首领不作为在场目标")
	t.check(not boss.can_move_now() and not boss.can_act_skill(), "庇护不能行动")
	t.check(state.pending_casts.is_empty(), "回巢中断首领吟唱")
	t.check(not state.check_battle_end() and not state.is_free_exploration(), "回巢不触发胜利或自由探索")
	var actions := EnemyAI.plan(state)
	t.check(actions.all(func(a): return int(a["uid"]) != boss.uid), "AI不给庇护首领规划行动")

func _immunity_and_pause(t: TestContext) -> void:
	var state := _state()
	var boss := state.unit_by_uid(100)
	_retreat(state)
	boss.burn_ticks = 3
	boss.slow_ticks = 2
	boss.shock_ticks = 2
	boss.paralyzed_ticks = 1
	boss.frozen = true
	boss.root_pending = true
	boss.haste_ticks = 1
	boss.parasite_ticks = 2
	boss.parasite_source_uid = 2
	boss.parasite_source_side = "player"
	var hp := boss.hp
	var result := state.damage_unit(state.unit_by_uid(1), boss, 999, {"no_element": true})
	t.eq(result["amount"], 0, "巢内免疫直接与间接伤害")
	state.kill_unit(boss, "测试致死地形")
	t.eq(boss.hp, hp, "巢内不能被地形处死")
	state._finish_status_effects("enemy")
	state._finish_movement_effects("enemy")
	state.reinforcement_pool = []
	state.start_round()
	t.eq([boss.hp, boss.burn_ticks, boss.slow_ticks, boss.shock_ticks, boss.parasite_ticks, boss.haste_ticks], [hp, 3, 2, 2, 2, 1], "庇护期间所有持续计数暂停")
	t.check(boss.frozen and boss.paralyzed_ticks == 1 and boss.root_pending, "控制状态不提前消退或转化")
	state.trainer().cell = boss.cell + Vector2i(-1, 0)
	t.check(not CaptureSystem.can_attempt(state, state.trainer(), boss), "无法捕获庇护首领")
	state.on_captured(boss, boss.species_id, 1)
	t.check(state.captured.is_empty(), "底层捕获入口也拒绝庇护首领")
	var entries := SkillResolver.targets(state, state.unit_by_uid(2), "leech_seed")
	t.check(entries.all(func(e): return int(e.get("unit", -1)) != boss.uid), "单位型技能不显示庇护首领")

func _release_and_capture(t: TestContext) -> void:
	var state := _state()
	var boss := state.unit_by_uid(100)
	_retreat(state)
	var hp := boss.hp
	_break_nest(state)
	t.check(not boss.sheltered and not state.nest["alive"], "破巢解除庇护")
	t.eq(boss.cell, state.nest["cell"], "空置主巢穴原位出场")
	t.eq(boss.hp, hp, "出巢不回血")
	t.check(not state.check_battle_end(), "拆巢后仍需击败或捕获首领")
	state.damage_unit(null, boss, 1, {"no_element": true})
	t.eq(boss.hp, hp - 1, "出巢可继续造成伤害")
	boss.hp = boss.max_hp
	state.nest["alive"] = true
	state.damage_unit(null, boss, 40, {"no_element": true})
	t.check(not boss.sheltered, "即使恢复后再次半血也不重复回巢")
	state.nest["alive"] = false
	state.trainer().cell = boss.cell + Vector2i(-1, 0)
	var captured := state.capture_attempt(state.trainer(), boss, 0.0)
	t.check(captured.get("success", false), "破巢后恢复捕获")
	t.check(GridSpec.is_inside(state.boss_portal_cell), "捕获后生成传送门")
	state.end_battle("victory")
	var outcome := RunState.new_run(4242).settle_battle(state)
	t.eq(outcome["boss_blood"], 1, "破巢后捕获获胜仍有首领之血")

func _bypass(t: TestContext) -> void:
	var state := _state()
	_break_nest(state)
	_retreat(state)
	t.check(not state.unit_by_uid(100).sheltered, "提前拆巢阻止庇护")
	t.check(state.inspiration_triggered, "提前拆巢不取消半血鼓舞")
	var lethal := _state()
	lethal.damage_unit(null, lethal.unit_by_uid(100), 999, {"no_element": true})
	t.check(not lethal.boss_retreat_used and not lethal.inspiration_triggered, "一击击败不强行锁血转阶段")
	lethal.check_battle_end()
	t.check(GridSpec.is_inside(lethal.boss_portal_cell), "爆发击杀正常进入胜利流程")

func _area_and_occupied_exit(t: TestContext) -> void:
	var state := _state()
	_retreat(state)
	var boss := state.unit_by_uid(100)
	var hp := boss.hp
	state.nest["hp"] = 1
	var summary := SkillResolver.resolve_channel(state, state.unit_by_uid(1), "fire_burst", [state.nest["cell"]])
	t.check(not boss.sheltered, "范围技破巢后正常出场")
	t.eq(boss.hp, hp, "拆巢同一次范围技不穿透首领")
	t.check((summary["hits"] as Array).all(func(h): return h["uid"] != boss.uid), "该次技能命中列表不含出巢首领")
	var blocked := _state()
	_retreat(blocked)
	var guard := blocked.unit_by_uid(101)
	guard.cell = blocked.nest["cell"]
	blocked.nest["alive"] = false
	blocked.set_terrain(Vector2i(4, 1), TerrainDB.LAVA)
	blocked.try_release_boss()
	var emerged := blocked.unit_by_uid(100)
	t.check(not emerged.sheltered and emerged.cell != guard.cell, "原格被占时选择附近空格，不挤占守卫")
	t.check(blocked.terrain_at(emerged.cell) != TerrainDB.LAVA, "出场避开致死地形")

func _save(t: TestContext) -> void:
	var state := _state()
	_retreat(state)
	var clone := state.clone()
	t.check(clone.boss_retreat_used and clone.sheltered_boss() != null, "预览克隆保留阶段")
	var snapshot := BattleSnapshot.save_state(state)
	var restored := BattleSnapshot.load_state(snapshot)
	t.check(restored.boss_retreat_used and restored.sheltered_boss() != null, "战斗读档保持庇护")
	_break_nest(restored)
	t.check(restored.sheltered_boss() == null, "读档后仍能破巢解锁")
	var legacy := snapshot.duplicate(true)
	legacy["fields"].erase("boss_retreat_used")
	for member in legacy["units"]:
		member.erase("sheltered")
	legacy["fields"]["nest"] = BattleSnapshot.encode(state.nest.duplicate(true))
	var old := BattleSnapshot.load_state(legacy)
	t.check(old != null and old.sheltered_boss() == null, "无阶段字段的旧快照可正常读取")

func _node_and_ui(t: TestContext) -> void:
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
	app.current_screen._on_start()
	var screen = app.current_screen
	var state: BattleState = screen.state
	var boss := state.unit_by_uid(state.boss_uid)
	var half_hit := ceili(boss.max_hp / 2.0)
	state.damage_unit(null, boss, half_hit, {"no_element": true})
	screen.playback.finish_all()
	screen.refresh_all()
	t.check(screen.objective_label.text.contains("首领已回巢"), "目标面板明确要求破巢")
	t.check(screen.board.nest.get("boss_sheltered", false), "棋盘标记首领庇护巢穴")
	var shown: CombatUnit = screen.board.units.filter(func(u): return u.uid == boss.uid)[0]
	t.check(not shown.is_on_board(), "展示快照不把巢内首领画成占格单位")
	screen._show_terrain(state.nest["cell"])
	t.check(screen.terrain_label.text.contains("首领正在巢内庇护"), "巢穴详情解释庇护与拆巢")
	var old_hp := boss.hp
	state.start_round()
	t.eq(boss.hp, old_hp, "正常首领属性下增援阶段不改变巢内血量")
	region = app.run.get_region()
	region.store_battle("boss", state)
	var loaded: BattleState = region.load_battle("boss")
	t.check(loaded.sheltered_boss() != null, "节点持久化记录庇护阶段")
	var resumed: BattleState = region.resume_node("boss", [], app.run.battle_config())
	t.check(resumed.sheltered_boss() == null and not resumed.boss_retreat_used, "撤退后重进按满血重置回巢机会")
	t.eq(resumed.unit_by_uid(resumed.boss_uid).hp, resumed.unit_by_uid(resumed.boss_uid).max_hp, "重进首领与现有规则一致恢复满血")
	app.free()
