extends RefCounted


func run(t: TestContext) -> void:
	t.begin("怪物本局成长与永久亲密度界面")
	_test_collection_prep_and_run_end(t)
	_test_ordered_settlement_choices(t)
	_test_stored_monster_upgrade_after_replacement(t)
	t.finish()


func _test_collection_prep_and_run_end(t: TestContext) -> void:
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.collection.record_by_id(1)["affinity"] = 7
	app.start_new_run()
	var collection_text := _all_label_text(app.current_screen)
	t.check(collection_text.contains("亲密度 7"), "开局收藏页显示永久亲密度")
	t.check(collection_text.contains("本局等级、经验与怪物强化在新局重置"), "收藏页说明本局成长不继承")
	for id in [1, 2, 3]:
		var choice: CheckBox = app.current_screen.find_child("Collection_%d" % id, true, false)
		choice.button_pressed = true
	var start: Button = app.current_screen.find_child("StartFromCollectionButton", true, false)
	start.pressed.emit()
	var fire: Dictionary = app.run.record_by_uid(1)
	t.eq(int(fire.get("affinity", 0)), 7, "开局继承永久亲密度")
	MonsterProgression.award_xp(fire, 10)
	fire["upgrades_taken"] = ["fireball_damage"]
	fire["upgrades"] = {"fireball_damage": 1}
	app.show_prep()
	var prep_text := _all_label_text(app.current_screen)
	t.check(prep_text.contains("本局 Lv.3") and prep_text.contains("经验 10/18"), "整备页显示怪物本局等级与经验")
	t.check(prep_text.contains("亲密度 7（永久"), "整备页区分永久亲密度")
	t.check(prep_text.contains("本局强化：炽烈火球"), "整备页显示该怪物的已选本局升级")
	app.show_run_end()
	var summary: Label = app.current_screen.find_child("RunEndSummary", true, false)
	t.check(summary != null, "结局页存在成长摘要")
	if summary != null:
		t.check(summary.text.contains("小火龙：本局 Lv.3 · 经验 10/18"), "结局页显示怪物本局等级经验")
		t.check(summary.text.contains("亲密度 7"), "结局页显示永久亲密度")
		t.check(summary.text.contains("本局强化：炽烈火球"), "结局页列出怪物已选升级")
	app.queue_free()


func _test_ordered_settlement_choices(t: TestContext) -> void:
	var run_state := RunState.new_run(20261019)
	MonsterProgression.award_xp(run_state.record_by_uid(1), 18)
	MonsterProgression.award_xp(run_state.record_by_uid(2), 4)
	run_state.pending_reward_choices = 1
	run_state.settlement_pending = true
	var pending: Array = run_state.pending_monster_levels()
	t.eq(pending.size(), 3, "跨级怪物和另一只怪物共有三项待选偶数级强化")
	t.eq([int(pending[0]["uid"]), int(pending[0]["level"])], [1, 2], "先处理较小 UID 的较低偶数级")
	t.eq([int(pending[1]["uid"]), int(pending[1]["level"])], [1, 4], "同一怪物按等级升序继续")
	t.eq([int(pending[2]["uid"]), int(pending[2]["level"])], [2, 2], "之后处理下一只怪物")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.pending_monster_levels().size(), pending.size(), "读档保留待处理升级顺序")
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = restored
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 0, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var continue_button: Button = app.current_screen.find_child("ContinueButton", true, false)
	t.check(continue_button != null and continue_button.disabled, "有怪物待选强化时不能继续")
	for expected in [[1, 2], [1, 4], [2, 2]]:
		var entry: Dictionary = app.run.pending_monster_levels()[0]
		t.eq([int(entry["uid"]), int(entry["level"])], expected, "战后界面按 UID 与等级顺序显示当前强化")
		var category: Button = app.current_screen.find_child("MonsterGrowth_enhance_%d_%d" % [int(entry["uid"]), int(entry["level"])], true, false)
		t.check(category != null, "当前怪物可选强化类别")
		if category == null:
			break
		category.pressed.emit()
		var id := String(app.run.available_monster_upgrades(int(entry["uid"]))[0])
		var skill_id := String(RunState.upgrade_info(id)["requires_skill"])
		var button: Button = app.current_screen.find_child("MonsterEnhance_%d_%d_%s" % [int(entry["uid"]), int(entry["level"]), skill_id], true, false)
		t.check(button != null, "当前怪物的具体招式按钮存在")
		if button == null:
			break
		button.pressed.emit()
		t.check((app.run.record_by_uid(int(entry["uid"])).get("upgrades_taken", []) as Array).has(id), "选择记录到对应怪物")
	t.eq(app.run.pending_monster_levels().size(), 0, "全部怪物强化已逐项处理")
	t.eq(app.run.pending_reward_choices, 1, "怪物升级完成后才进入战后卡牌选择")
	var reward_id := String(app.run.reward_choices()[0])
	var reward_button: Button = app.current_screen.find_child("RewardChoice_%s" % reward_id.replace(":", "_"), true, false)
	t.check(reward_button != null and continue_button.disabled, "战后卡牌仍需领取，不能跳过")
	if reward_button != null:
		reward_button.pressed.emit()
		t.eq(continue_button.disabled, false, "怪物强化和卡牌领取完毕后可继续")
	app.queue_free()


func _test_stored_monster_upgrade_after_replacement(t: TestContext) -> void:
	var run_state := RunState.new_run(20261020)
	var fire := run_state.record_by_uid(1)
	MonsterProgression.award_xp(fire, 4)
	var removed: Dictionary = run_state.carried.pop_front()
	run_state.storage.append(removed)
	t.check(run_state.record_by_uid(1).is_empty(), "捕获替换后，原出战怪不再被视为携带成员")
	t.check(not run_state.owned_record_by_uid(1).is_empty(), "原出战怪仍保存在仓库")
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = run_state
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 0, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var step: Label = app.current_screen.step_label
	t.check(step.text.contains("小火龙") and step.text.contains("Lv.2"), "仓库中的原出战怪仍显示正确升级对象")
	var category: Button = app.current_screen.find_child("MonsterGrowth_enhance_1_2", true, false)
	t.check(category != null, "仓库怪物可见强化类别")
	if category != null:
		category.pressed.emit()
	var choice_id := String(run_state.available_monster_upgrades(1)[0])
	var skill_id := String(RunState.upgrade_info(choice_id)["requires_skill"])
	var button: Button = app.current_screen.find_child("MonsterEnhance_1_2_%s" % skill_id, true, false)
	t.check(button != null, "仓库怪物仍可看到待领强化")
	if button != null:
		button.pressed.emit()
		t.check((run_state.owned_record_by_uid(1).get("upgrades_taken", []) as Array).has(choice_id), "领取结果写入仓库中的同一只怪物")
		t.eq(run_state.pending_monster_levels().size(), 0, "仓库怪物领取后不再阻塞结算")
	app.queue_free()


func _all_label_text(root: Node) -> String:
	var parts: Array = []
	if root is Label:
		parts.append((root as Label).text)
	for child in root.get_children():
		parts.append(_all_label_text(child))
	return "\n".join(parts)
