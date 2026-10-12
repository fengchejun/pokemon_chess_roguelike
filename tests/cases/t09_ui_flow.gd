extends RefCounted

## 界面冒烟：主菜单 → 编队 → 地图预览 → 战斗 → 结算 → 下一场


func run(t: TestContext) -> void:
	t.begin("界面流程")
	var main_script = load("res://scripts/main.gd")
	t.check(main_script != null, "主脚本可加载")
	if main_script == null:
		t.finish()
		return
	var app = main_script.new()
	t.tree.root.add_child(app)
	t.check(app.current_screen != null, "初始界面存在")
	if app.current_screen != null:
		t.eq(app.current_screen.name, "MenuScreen", "主菜单加载")
	var new_button: Button = app.current_screen.find_child("NewRunButton", true, false)
	t.check(new_button != null, "新的一局按钮存在")
	if new_button == null:
		t.finish()
		return
	new_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "进入编队界面")
	t.check(app.run != null and app.run.carried.size() == 5, "本局初始队伍建立")
	var low_hp_option: CheckBox = app.current_screen.find_child("CaptureLowHpOption", true, false)
	var field_join_option: CheckBox = app.current_screen.find_child("CaptureFieldJoinOption", true, false)
	t.check(low_hp_option != null and field_join_option != null, "捕获两项设置在整备页可见")
	if low_hp_option != null and field_join_option != null:
		t.eq(low_hp_option.button_pressed, false, "低血量选项默认关闭")
		t.eq(field_join_option.button_pressed, false, "原地转阵营选项默认关闭")
		low_hp_option.button_pressed = true
		field_join_option.button_pressed = true
		t.eq(bool(app.run.options.get("capture_low_hp", false)), true, "整备页低血量设置写入本局")
		t.eq(bool(app.run.options.get("capture_field_join", false)), true, "整备页原地转阵营设置写入本局")
	var preview_button: Button = app.current_screen.find_child("PreviewButton", true, false)
	t.check(preview_button != null, "前往预览按钮存在")
	preview_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "开局未选择宝可梦时不能进入地图预览")
	var deploy_1: CheckBox = app.current_screen.find_child("Deploy_1", true, false)
	var deploy_2: CheckBox = app.current_screen.find_child("Deploy_2", true, false)
	var deploy_3: CheckBox = app.current_screen.find_child("Deploy_3", true, false)
	t.check(deploy_1 != null and deploy_2 != null and deploy_3 != null, "编成行存在")
	t.eq(deploy_1.button_pressed or deploy_2.button_pressed or deploy_3.button_pressed, false, "初始出战选择为空")
	deploy_1.button_pressed = true
	deploy_2.button_pressed = true
	deploy_3.button_pressed = true
	var prep_screen = app.current_screen
	t.eq(prep_screen.deploy_selection.size(), 3, "已选定三只出战宝可梦")
	preview_button.pressed.emit()
	t.eq(app.current_screen.name, "PreviewScreen", "选定宝可梦后进入地图预览")
	# 环境卡：仅在地图预览界面五选二
	var forest_toggle: Button = app.current_screen.find_child("CardToggle_forest", true, false)
	var ridge_toggle: Button = app.current_screen.find_child("CardToggle_ridge", true, false)
	t.check(forest_toggle != null and ridge_toggle != null, "预览界面有环境卡选择")
	t.eq(app.run.cards.size(), Balance.CARDS_PER_BATTLE, "默认已选 2 张")
	ridge_toggle.button_pressed = true
	ridge_toggle.pressed.emit()
	t.eq(app.run.cards.has("ridge"), false, "已选满 2 张时不能再选")
	t.eq(app.run.cards.size(), Balance.CARDS_PER_BATTLE, "选择数量仍为 2")
	forest_toggle.button_pressed = false
	forest_toggle.pressed.emit()
	t.eq(app.run.cards.size(), Balance.CARDS_PER_BATTLE - 1, "可以取消已选卡")
	var start_button: Button = app.current_screen.find_child("StartBattleButton", true, false)
	t.check(start_button != null, "开始战斗按钮存在")
	start_button.pressed.emit()
	t.eq(app.current_screen.name, "PreviewScreen", "未选满 2 张时不能开战")
	# 返回整备：保留出战编成
	var back_button: Button = app.current_screen.find_child("BackButton", true, false)
	t.check(back_button != null, "预览界面有返回按钮")
	back_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "返回整备界面")
	t.check(app.current_screen.find_child("CardToggle_stream", true, false) == null, "整备界面不再出现环境卡界面")
	deploy_1 = app.current_screen.find_child("Deploy_1", true, false)
	deploy_2 = app.current_screen.find_child("Deploy_2", true, false)
	deploy_3 = app.current_screen.find_child("Deploy_3", true, false)
	t.eq(deploy_1.button_pressed and deploy_2.button_pressed and deploy_3.button_pressed, true, "返回时保留出战编成")
	preview_button = app.current_screen.find_child("PreviewButton", true, false)
	preview_button.pressed.emit()
	t.eq(app.current_screen.name, "PreviewScreen", "重新进入地图预览")
	forest_toggle = app.current_screen.find_child("CardToggle_forest", true, false)
	forest_toggle.button_pressed = true
	forest_toggle.pressed.emit()
	t.eq(app.run.cards.size(), Balance.CARDS_PER_BATTLE, "重新选满 2 张")
	start_button = app.current_screen.find_child("StartBattleButton", true, false)
	start_button.pressed.emit()
	t.eq(app.current_screen.name, "BattleScreen", "进入战斗")
	var battle_screen = app.current_screen
	t.check(battle_screen.state != null, "战斗状态已建立")
	t.check(battle_screen.find_child("EvacuateButton", true, false) == null, "战斗界面不再有主动撤离按钮")
	if battle_screen.state == null:
		t.finish()
		return
	var state: BattleState = battle_screen.state
	t.eq(bool(state.capture_options.get("capture_low_hp", false)), true, "低血量设置传入战斗")
	t.eq(bool(state.capture_options.get("capture_field_join", false)), true, "原地转阵营设置传入战斗")
	t.check(not state.has_method("evacuate"), "战斗状态不再提供主动撤离接口")
	var unit: CombatUnit = state.unit_by_uid(1)
	t.check(unit != null and unit.is_alive(), "出战单位在场")
	if unit != null:
		battle_screen.select_unit(unit.uid)
		var from_cell := unit.cell
		var options: Dictionary = battle_screen.state.move_options(unit)
		var dest := Vector2i(-1, -1)
		for cell in options:
			dest = cell
			break
		t.check(dest != Vector2i(-1, -1), "存在可移动格")
		var moved: bool = battle_screen.do_move(dest)
		t.eq(moved, true, "点击移动执行成功")
		t.eq(unit.cell, dest, "移动位置正确")
		t.eq(battle_screen.do_undo(), true, "撤回移动成功")
		t.eq(unit.cell, from_cell, "撤回后回位")
	# 清场 → 结算
	for enemy in state.alive_units("enemy"):
		state.kill_unit(enemy, "测试清场", "player")
	battle_screen.refresh_all()
	battle_screen.report_end_now()
	t.eq(app.current_screen.name, "SettlementScreen", "进入战后结算")
	var settlement = app.current_screen
	var continue_button: Button = settlement.find_child("ContinueButton", true, false)
	t.check(continue_button != null, "结算继续按钮存在")
	if continue_button == null:
		t.finish()
		return
	if settlement.upgrade_pending:
		for child in settlement.choice_box.get_children():
			if child is Button:
				(child as Button).pressed.emit()
				break
	# 回归：连续两次捕获 —— 第一条入队后仍带 uid，第二条触发处理界面不崩溃
	app.run.pending_captures.append({"species_id": "fire_wild1", "hp": 4})
	app.run.pending_captures.append({"species_id": "water_wild1", "hp": 3})
	settlement._show_next_step()
	t.eq(app.run.carried.size(), Balance.CARRIED_LIMIT, "第一条捕获直接入队")
	t.check(app.run.carried[5].has("uid"), "入队记录带 uid")
	var capture_choice_btn: Button = settlement.find_child("CaptureToStorageButton", true, false)
	t.check(capture_choice_btn != null, "第二条捕获触发处理界面（不崩溃）")
	capture_choice_btn.pressed.emit()
	t.eq(app.run.storage.size(), 1, "第二条放入仓库")
	t.eq(app.run.pending_captures.size(), 0, "捕获处理完成")
	t.eq(continue_button.disabled, false, "无待处理事项可直接继续")
	var index_before: int = app.run.battle_index
	continue_button.pressed.emit()
	t.eq(app.run.battle_index, index_before + 1, "进入下一场")
	t.eq(app.current_screen.name, "PrepScreen", "回到整备界面")
	t.eq(app.run.carried.size(), 6, "名单为 6（含新捕获）")
	t.eq(app.run.storage.size(), 1, "仓库有 1 只（放入的捕获）")
	# 第二场：验证战后恢复与直达整备
	app.show_preview([1, 2, 3])
	var preview2 = app.current_screen
	var start2: Button = preview2.find_child("StartBattleButton", true, false)
	t.check(start2 != null, "第二场预览开始按钮存在")
	start2.pressed.emit()
	var battle2 = app.current_screen
	t.eq(battle2.name, "BattleScreen", "第二场进入战斗")
	t.eq(app.run.carried.size(), 6, "名单不受出战选择影响")
	for enemy in battle2.state.alive_units("enemy"):
		battle2.state.kill_unit(enemy, "测试清场", "player")
	battle2.refresh_all()
	battle2.report_end_now()
	var settlement2 = app.current_screen
	t.eq(settlement2.name, "SettlementScreen", "第二场进入结算")
	# 结算中的捕获处理：名单满员时提供「替换 / 放入仓库」选项
	t.eq(app.run.carried.size(), Balance.CARRIED_LIMIT, "名单已满（6）")
	var storage_before: int = app.run.storage.size()
	app.run.pending_captures.append({"species_id": "water_wild1", "hp": 3})
	settlement2._show_next_step()
	var settle_continue_btn: Button = settlement2.find_child("ContinueButton", true, false)
	t.eq(settle_continue_btn.disabled, true, "捕获待处理时不能继续")
	var to_storage_button: Button = settlement2.find_child("CaptureToStorageButton", true, false)
	t.check(to_storage_button != null, "名单满时提供「放入仓库」选项")
	to_storage_button.pressed.emit()
	t.eq(app.run.pending_captures.size(), 0, "捕获处理完成")
	t.eq(app.run.storage.size(), storage_before + 1, "捕获进入仓库")
	if settlement2.upgrade_pending:
		for child in settlement2.choice_box.get_children():
			if child is Button:
				(child as Button).pressed.emit()
				break
	var settle_continue: Button = settlement2.find_child("ContinueButton", true, false)
	t.eq(settle_continue.disabled, false, "第二场结算可以继续")
	app.run.trainer_hp = 1
	settle_continue.pressed.emit()
	t.eq(app.current_screen.name, "SupplyScreen", "完成两场后进入补给点")
	t.eq(app.run.battle_index, 2, "已进入第三场准备")
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	var supply_amount := maxi(1, roundi(float(trainer_max) * Balance.SUPPLY_TRAINER_RECOVERY_RATIO))
	t.eq(app.run.trainer_hp, 1 + supply_amount, "补给点：训练家恢复 50%% 上限")
	var leave_supply: Button = app.current_screen.find_child("LeaveSupplyButton", true, false)
	t.check(leave_supply != null, "补给界面有继续出发按钮")
	leave_supply.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "离开补给点进入整备")
	t.eq(app.run.pending_supply, false, "补给待办已完成")
	# 本局结束界面
	app.run.battle_index = Balance.BATTLES_PER_RUN
	app.show_run_end()
	t.eq(app.current_screen.name, "RunEndScreen", "本局结束界面加载")
	t.finish()
