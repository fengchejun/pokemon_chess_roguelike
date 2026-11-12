extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")
const Loot = preload("res://scripts/run/battle_loot.gd")

func fixture() -> RunState:
	var run := RunState.new_run(94001)
	run.region_mode = true
	run.options["exploration_v2"] = true
	run.floor_themes = ["grass"]
	var region := Flow.generate(0, "grass", run.seed)
	region.active_node = "battle_1"
	run.region_data = region.to_dict()
	run.mark_deployed([1])
	return run

func state_for(role: String = "battle") -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(5, 3)]])
	state.node_kind = "battle"
	state.exploration_v2 = true
	state.exploration_role = role
	state.stop_nests()
	return state

func win(state: BattleState) -> void:
	state.kill_unit(state.unit_by_uid(100), "测试胜利", "player", 1)
	state.check_battle_end()

func run(t: TestContext) -> void:
	t.begin("战斗直接胜利、无撤退区与逐项领奖")
	var run := fixture()
	var map := MapGenerator.generate(run.seed, 0)
	Flow.prepare_map(run, map)
	map["chests"] = {Vector2i(5,3): "common"}
	map["battle_loot_generated"] = true
	Flow.prepare_battle_loot(run, map)
	t.check(map["chests"].is_empty(), "旧预览和新预览都移除战斗宝箱")
	t.check(map["reward"]["state"] == "absent", "战斗不放奖励点")
	for role in ["starter", "battle", "elite", "group", "recapture", "boss", "hunt"]:
		var state := state_for(role)
		if role in ["boss", "hunt"]:
			state.node_kind = "boss"
		t.check(not state.uses_extraction() and not state.can_escape() and not state.leave_node(true), "战斗禁止所有主动撤离 " + role)
		state.end_battle("escape")
		t.check(not state.ended, "底层不能绕过撤退限制 " + role)
		win(state)
		t.check(state.ended and state.end_reason == "victory", "清场立即胜利 " + role)
		t.check(not GridSpec.is_inside(state.boss_portal_cell), "无需走传送门 " + role)
	var old := state_for()
	old.extraction_cells = Balance.DEPLOY_AREA.duplicate()
	old.chests = {Vector2i(5,3): "common"}
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(old))
	t.check(restored.extraction_cells.is_empty() and restored.chests.is_empty(), "旧战场读档取消撤退区与额外宝箱")
	for role in ["capture", "treasure"]:
		var event := state_for(role)
		t.check(event.leave_node() and event.end_reason == "explored", "捕捉与解谜仍可离开 " + role)
	var state := state_for()
	win(state)
	var before := run.essence
	var relics := run.relic_stacks.duplicate()
	var outcome := run.settle_battle(state)
	t.check(run.has_pending_battle_loot(), "胜利生成待领取奖励")
	t.eq(run.essence, before, "选择前原质不入账")
	t.eq(run.relic_stacks, relics, "选择前遗物不入账")
	var saved := run.to_dict()
	var saved_offers := run.pending_battle_loot.duplicate(true)
	run.settle_battle(state)
	t.eq(run.pending_battle_loot, saved_offers, "重复战斗结算不重复生成")
	run = RunState.from_dict(saved)
	t.eq(run.pending_battle_loot, saved_offers, "未领取奖励固定存档")
	for i in run.pending_battle_loot.size():
		var take: bool = run.pending_battle_loot[i]["kind"] == "essence"
		t.check(run.resolve_battle_loot(i, take), "原质领取，其他放弃")
		t.check(not run.resolve_battle_loot(i, true), "已处理奖励不能重复领取")
	t.check(run.essence > before and run.relic_stacks == relics, "只拿原质不拿遗物")
	t.check(not run.has_pending_battle_loot(), "处理完成可以继续")
	var failed := fixture()
	state = state_for()
	state.end_battle("forced_retreat")
	failed.settle_battle(state)
	t.check(failed.pending_battle_loot.is_empty(), "失败不生成胜利奖励")
	var high := fixture()
	high.pending_battle_loot = Loot.preview(high, "high", "test-high")
	high.settlement_pending = true
	for i in high.pending_battle_loot.size():
		if high.pending_battle_loot[i]["kind"] == "legendary":
			t.check(high.resolve_battle_loot(i, true), "传奇三选一可选择领取")
	var rare_before := high.relic_stacks.duplicate()
	t.check(high.skip_reward_choice(), "传奇三选一可以跳过")
	t.eq(high.relic_stacks, rare_before, "跳过遗物不自动发放")
	t.check(not high.skip_reward_choice(), "跳过不能重复扣次")
	_ui(t)
	t.finish()

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = fixture()
	var state := state_for()
	win(state)
	app.finish_battle(state)
	t.eq(app.current_screen.name, "SettlementScreen", "真实入口直接打开战后奖励")
	var screen = app.current_screen
	for i in app.run.pending_battle_loot.size():
		var button_name := "TakeBattleLoot_%d" % i if app.run.pending_battle_loot[i]["kind"] == "essence" else "SkipBattleLoot_%d" % i
		screen.find_child(button_name, true, false).pressed.emit()
	t.check(not app.run.has_pending_battle_loot() and app.run.relic_stacks.is_empty(), "按钮支持只领取原质")
	app.free()
