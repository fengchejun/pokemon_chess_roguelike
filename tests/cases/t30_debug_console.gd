extends RefCounted

const DebugActions = preload("res://scripts/debug/debug_tools.gd")


func run(t: TestContext) -> void:
	t.begin("F7 测试控制台")
	_prep_actions(t)
	_battle_actions(t)
	_ui_toggle(t)
	t.finish()


func _prep_actions(t: TestContext) -> void:
	var run := RunState.new_run(321)
	var original_count := run.carried.size()
	var added := DebugActions.add_monster(run, "wind_wild1")
	t.check(bool(added.get("ok", false)), "调试怪物可加入携带队伍")
	t.eq(run.carried.size(), original_count + 1, "加入后人数正确")
	t.check(bool(run.carried.back().get("debug_spawned", false)), "调试怪物标记为非永久收藏")
	t.check(not bool(DebugActions.add_monster(run, "ice_wild1").get("ok", false)), "满 6 只时不会越过携带上限")
	var collection := CollectionState.defaults()
	var before := collection.owned.size()
	collection.absorb_run(run)
	t.eq(collection.owned.size(), before, "调试局整体不写入永久收藏")
	t.check(bool(RunState.from_dict(run.to_dict()).debug_tainted), "调试局标记随本局存档读取")
	var uid := int(run.carried[0]["uid"])
	t.check(bool(DebugActions.add_skill(run, uid, "ice_shard").get("ok", false)), "可跨属性学任意已配置技能")
	t.check((run.record_by_uid(uid)["known_skills"] as Array).has("ice_shard"), "新招进入招式库")
	t.check((run.record_by_uid(uid)["equipped_skills"] as Array).has("ice_shard"), "装备位有空时自动装备")
	t.check(not bool(DebugActions.add_skill(run, uid, "ice_shard").get("ok", false)), "重复学习被拒绝")
	var growth := DebugActions.add_xp(run, uid, 10)
	t.check(bool(growth.get("ok", false)), "可增加本局经验")
	t.eq(int(run.record_by_uid(uid)["level"]), 2, "经验使用真实升级阈值")
	t.eq(int(run.record_by_uid(uid)["xp"]), 10, "经验准确记入目标怪物")
	t.check(not run.pending_monster_levels().is_empty(), "偶数级强化仍可在正常结算流程领取")


func _battle_actions(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 2)
	target.element = ""
	caster.skills.append("ice_shard")
	t.check(bool(DebugActions.set_damage_bonus(state, "player", 2).get("ok", false)), "我方伤害可调")
	t.eq(int(state.clone().debug_skill_damage_bonus["player"]), 2, "克隆保留伤害覆盖")
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	var preview := state.preview_skill(caster, "ice_shard", entry)
	t.eq(int(preview["hits"][0]["damage"]), SkillDB.damage_of("ice_shard") + 2, "预览展示调整后的单体直伤")
	var hp_before := target.hp
	state.cast_skill(caster, "ice_shard", entry)
	t.eq(hp_before - target.hp, SkillDB.damage_of("ice_shard") + 2, "实际直伤与预览一致")
	t.check(bool(DebugActions.set_capture_percent(state, 100).get("ok", false)), "捕获率可设置为 100%")
	state.trainer().cell = Vector2i(2, 2)
	var captured := state.capture_attempt(state.trainer(), target, 0.99)
	t.check(bool(captured.get("success", false)), "100% 覆盖使高骰值捕获成功")
	var zero := TestScenario.make_state([], [["rock_wild1", Vector2i(3, 2)]])
	zero.trainer().cell = Vector2i(2, 2)
	DebugActions.set_capture_percent(zero, 0)
	t.eq(CaptureSystem.chance_percent(zero.unit_by_uid(100), false, zero.debug_capture_percent), 0, "界面成功率可显示 0% 覆盖")
	t.check(not bool(zero.capture_attempt(zero.trainer(), zero.unit_by_uid(100), 0.0).get("success", true)), "0% 覆盖不能捕获")
	var other := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 2)]])
	t.check(bool(DebugActions.heal_players(other).get("ok", false)), "存活友军可回满血")
	other.trainer().cell = Vector2i(2, 2)
	other.trainer().hp = 1
	DebugActions.heal_players(other)
	t.eq(other.trainer().hp, other.trainer().max_hp, "训练家生命回满")
	DebugActions.soften_enemies(other)
	t.eq(other.unit_by_uid(100).hp, 1, "敌人可调至 1 HP 用于捕获测试")
	DebugActions.win_battle(other)
	t.eq(other.end_reason, "victory", "一键获胜进入现有胜利结算")


func _ui_toggle(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(987)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_prep()
	var f7 := InputEventKey.new()
	f7.keycode = KEY_F7
	f7.pressed = true
	app._input(f7)
	t.check(app.debug_console != null and app.debug_console.visible, "整备页 F7 面板可打开")
	if app.debug_console != null:
		t.check(app.debug_console.monster_option != null and app.debug_console.skill_option != null, "整备面板有怪物与技能选择")
		app.debug_console._add_monster()
		t.eq(app.run.carried.size(), 6, "控制台按钮可实际添加怪物并刷新整备页")
		t.check(app.debug_console.visible, "整备刷新后控制台仍保持打开")
		app._input(f7)
		t.check(not app.debug_console.visible, "再次按 F7 关闭")
	app.begin_battle([int(app.run.carried[0]["uid"])], TestScenario.make_map(TestScenario.plain_terrain()))
	app.toggle_debug_console()
	t.check(app.debug_console.visible and app.debug_console.player_damage != null, "战斗页 F7 显示伤害调节")
	app.queue_free()
