extends RefCounted


func run(t: TestContext) -> void:
	t.begin("战后奖励三选一与背包")
	_test_offer_and_claim(t)
	_test_inventory_roundtrip(t)
	_test_legacy_migration(t)
	_test_monster_growth_in_battle(t)
	_test_settlement_resume(t)
	t.finish()


func _test_offer_and_claim(t: TestContext) -> void:
	var run_state := RunState.new_run(20261014)
	run_state.pending_reward_choices = 2
	var first: Array = run_state.reward_choices()
	t.eq(first.size(), 3, "每次奖励提供三个选项")
	t.eq(first, run_state.reward_choices(), "相同种子、场次和选择序号给出稳定选项")
	var unique := {}
	for reward_id in first:
		var id := String(reward_id)
		unique[id] = true
		t.check(RewardDB.is_consumable(id), "奖励池仅含可留存的消耗卡：%s" % id)
		t.check(RewardDB.name_of(id) != id and RewardDB.description_of(id) != "", "每项奖励有可读名称与说明")
	t.eq(unique.size(), 3, "同一次三选一不会出现重复项目")
	t.eq(run_state.choose_reward("upgrade:team_move"), false, "不能越过经验系统从战后池领取局内强化")
	t.eq(run_state.choose_reward("position:not_real"), false, "奖励列表之外的项目不能领取")
	var chosen := String(first[0])
	t.eq(run_state.choose_reward(chosen), true, "从三个选项中领取一项")
	t.eq(run_state.reward_inventory, [chosen], "消耗卡进入本局背包")
	t.eq(run_state.pending_reward_choices, 1, "领取后仅扣除一次待选机会")
	t.eq(run_state.reward_choice_index, 1, "下一次奖励使用新的选择序号")
	var second: Array = run_state.reward_choices()
	t.eq(second, RunState.from_dict(run_state.to_dict()).reward_choices(), "读档后续选项保持可复现")
	t.check(run_state.choose_reward(String(second[0])), "可领取第二次奖励")
	t.eq(run_state.reward_inventory.size(), 2, "两次选择可累计两张卡")
	t.eq(run_state.pending_reward_choices, 0, "待领次数归零")
	t.eq(run_state.choose_reward(String(second[0])), false, "次数归零后不能重复领取")


func _test_inventory_roundtrip(t: TestContext) -> void:
	var run_state := RunState.new_run(20261015)
	run_state.reward_inventory = ["position:forest", "map:water", RewardDB.MOD_ITEM]
	run_state.select_reward_item("position:forest")
	run_state.pending_reward_choices = 1
	run_state.reward_choice_index = 3
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.reward_inventory, run_state.reward_inventory, "背包顺序与种类在本局存档中保留")
	t.eq(restored.selected_reward_item, "position:forest", "战前所选消耗卡在本局存档中保留")
	t.eq(restored.pending_reward_choices, 1, "尚未领取的奖励选择次数保留")
	t.eq(restored.reward_choice_index, 3, "奖励随机序号保留，防止反复读档刷新选项")
	var previous_inventory: Array = restored.reward_inventory.duplicate()
	t.eq(restored.select_reward_item(""), true, "可选择下一场不使用卡")
	t.eq(restored.consume_selected_reward_item(), "", "不使用卡时开战不消耗背包")
	t.eq(restored.reward_inventory, previous_inventory, "未使用的所有卡留在本局背包")


func _test_legacy_migration(t: TestContext) -> void:
	var old := RunState.new_run(20261016).to_dict()
	old["cards"] = ["stream", "forest"]
	old["environment_deck"] = ["water", "electric"]
	old["environment_reward_pending"] = true
	old["options"]["card_mode"] = "environment"
	var restored := RunState.from_dict(old)
	t.eq(restored.cards, [], "旧版免费站位卡全部清除")
	t.eq(restored.environment_deck, [], "旧版常驻地貌卡全部清除")
	t.eq(restored.environment_reward_pending, false, "旧版待领地貌卡不再保留")
	t.eq(restored.reward_inventory, [], "旧卡不会折算成新消耗卡")
	t.eq(restored.options.has("card_mode"), false, "旧环境模式开关移除")


func _test_monster_growth_in_battle(t: TestContext) -> void:
	var selected := [
		{"id": 41, "species_id": "fire_starter", "affinity": 7, "xp": 10, "level": 3},
		{"id": 42, "species_id": "water_starter", "affinity": 2},
		{"id": 43, "species_id": "grass_starter", "affinity": 0},
	]
	var run_state := RunState.new_run(20261017, selected)
	var fire := run_state.record_by_uid(1)
	t.eq(int(fire["level"]), 1, "新局怪物等级重置，即使旧收藏带有等级字段")
	t.eq(int(fire["xp"]), 0, "新局怪物经验重置，即使旧收藏带有经验字段")
	t.eq(int(fire["affinity"]), 7, "永久亲密度从收藏继承")
	t.eq(int(fire["hp"]), SpeciesDB.hp_of("fire_starter"), "新局按初始等级满血开始")
	var deployed := run_state.build_deploy_units([1])
	t.eq((deployed[1] as CombatUnit).max_hp, SpeciesDB.hp_of("fire_starter"), "新局部署不继承上局等级生命")
	MonsterProgression.award_xp(fire, 10)
	t.eq(int(fire["level"]), 3, "本局获得经验后升到三级")
	t.eq((run_state.build_deploy_units([1])[1] as CombatUnit).max_hp, SpeciesDB.hp_of("fire_starter") + 1, "本局奇数级生命成长进入部署单位")
	var battle := TestScenario.make_state(["fire_starter"], [])
	run_state.mark_deployed([1])
	battle.unit_by_uid(1).hp = 2
	battle.end_battle("victory")
	run_state.sync_from_battle(battle)
	run_state.settle_battle(battle)
	t.eq(int(run_state.record_by_uid(1)["hp"]), 2 + RunState.recovery_amount(SpeciesDB.hp_of("fire_starter") + 1), "战后恢复按本局成长后的生命上限计算")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(int(restored.record_by_uid(1)["xp"]), 10, "本局读档保留本局怪物经验")
	t.eq(int(restored.record_by_uid(1)["level"]), 3, "本局读档保留本局怪物等级")
	t.eq(int(restored.record_by_uid(1)["affinity"]), 8, "本局读档保留出战后增长的永久亲密度")
	t.eq((restored.build_deploy_units([1])[1] as CombatUnit).max_hp, SpeciesDB.hp_of("fire_starter") + 1, "读档后的部署仍有本局成长生命上限")


func _test_settlement_resume(t: TestContext) -> void:
	var run_state := RunState.new_run(20261018)
	var battle := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	run_state.mark_deployed([1])
	battle.kill_unit(battle.unit_by_uid(100), "测试击败", "player")
	battle.check_battle_end()
	run_state.sync_from_battle(battle)
	run_state.settle_battle(battle)
	t.eq(run_state.settlement_pending, true, "战后有待处理结算标记")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.pending_reward_choices, 1, "读档仍有一次待领奖励")
	t.eq(restored.last_settlement.get("reason", ""), "victory", "结算摘要可从本局存档恢复")
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = restored
	app.pending_settlement = {"battle": null, "outcome": restored.last_settlement.duplicate(true)}
	app.battle_settled = true
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	t.eq(app.current_screen.name, "SettlementScreen", "没有内存中的 BattleState 仍能恢复结算界面")
	var offered: Array = restored.reward_choices()
	var id := String(offered[0])
	var choice: Button = app.current_screen.find_child("RewardChoice_%s" % id.replace(":", "_"), true, false)
	t.check(choice != null, "恢复后的结算界面仍可领取三选一")
	if choice != null:
		choice.pressed.emit()
		t.eq(restored.reward_inventory, [id], "恢复后领取的消耗卡进入背包")
		var next: Button = app.current_screen.find_child("ContinueButton", true, false)
		t.check(next != null and not next.disabled, "领取后可继续下一场")
		if next != null:
			next.pressed.emit()
			t.eq(restored.battle_index, 1, "恢复结算不会重打一场或重复发奖")
			t.eq(restored.settlement_pending, false, "进入下一场后结算待办清除")
	app.queue_free()
