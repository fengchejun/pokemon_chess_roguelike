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
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	t.check(app.current_screen != null, "初始界面存在")
	if app.current_screen != null:
		t.eq(app.current_screen.name, "MenuScreen", "主菜单加载")
	t.eq(app.music_director.current_track, "title", "主菜单播放标题音乐")
	t.eq(MusicDirector.TRACK_PATHS["title"], "res://assets/audio/title.mp3", "标题音乐指向项目内音源")
	for track_path in MusicDirector.TRACK_PATHS.values():
		t.check(ResourceLoader.exists(String(track_path)), "背景音乐资源已导入：%s" % track_path)
	var new_button: Button = app.current_screen.find_child("NewRunButton", true, false)
	t.check(new_button != null, "新的一局按钮存在")
	if new_button == null:
		t.finish()
		return
	new_button.pressed.emit()
	t.eq(app.current_screen.name, "CollectionScreen", "进入跨局收藏选择")
	for id in [1, 2, 3]:
		var choice: CheckBox = app.current_screen.find_child("Collection_%d" % id, true, false)
		t.check(choice != null, "初始收藏可选 %d" % id)
		if choice != null:
			choice.button_pressed = true
	var collection_start: Button = app.current_screen.find_child("StartFromCollectionButton", true, false)
	t.check(collection_start != null and not collection_start.disabled, "选三只后可开始本局")
	collection_start.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "进入编队界面")
	t.eq(app.music_director.current_track, "prep", "整备页播放整备音乐")
	var music_player: MusicDirector = app.music_director
	t.check(app.run != null and app.run.carried.size() == 3, "本局由永久收藏选三只开局")
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
	t.check(app.music_director == music_player and app.music_director.current_track == "prep", "整备与预览共用持续播放的音乐")
	t.check(app.current_screen.find_child("CardToggle_forest", true, false) == null, "预览界面不再免费选择站位卡")
	t.eq(app.run.mod_points(), 0, "未使用工具时预览页没有免费改造次数")
	var start_button: Button = app.current_screen.find_child("StartBattleButton", true, false)
	t.check(start_button != null, "开始战斗按钮存在")
	# 返回整备：保留出战编成
	var back_button: Button = app.current_screen.find_child("BackButton", true, false)
	t.check(back_button != null, "预览界面有返回按钮")
	back_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "返回整备界面")
	t.check(app.current_screen.find_child("RewardItemOption", true, false) != null, "整备页有奖励背包选择")
	deploy_1 = app.current_screen.find_child("Deploy_1", true, false)
	deploy_2 = app.current_screen.find_child("Deploy_2", true, false)
	deploy_3 = app.current_screen.find_child("Deploy_3", true, false)
	t.eq(deploy_1.button_pressed and deploy_2.button_pressed and deploy_3.button_pressed, true, "返回时保留出战编成")
	preview_button = app.current_screen.find_child("PreviewButton", true, false)
	preview_button.pressed.emit()
	t.eq(app.current_screen.name, "PreviewScreen", "重新进入地图预览")
	start_button = app.current_screen.find_child("StartBattleButton", true, false)
	start_button.pressed.emit()
	t.eq(app.current_screen.name, "BattleScreen", "不使用消耗卡也能进入战斗")
	t.eq(app.music_director.current_track, "battle", "进入战斗切换战斗音乐")
	t.eq(MusicDirector.TRACK_PATHS["battle"], "res://assets/audio/battle.mp3", "战斗音乐指向项目内音源")
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
	state.reward["state"] = "carried"
	state.reward["owner_uid"] = unit.uid
	battle_screen.refresh_all()
	var reward_layer: Control = battle_screen.find_child("RewardChoiceLayer", true, false)
	t.check(reward_layer == null, "战场奖励不再打断战斗弹出 Buff 选择")
	t.check(battle_screen.status_label.text.contains("奖励已持有"), "战斗界面显示奖励持有状态")
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
	t.eq(app.music_director.current_track, "prep", "战斗结束切回战间整备音乐")
	var settlement = app.current_screen
	var continue_button: Button = settlement.find_child("ContinueButton", true, false)
	t.check(continue_button != null, "结算继续按钮存在")
	if continue_button == null:
		t.finish()
		return
	# 本局三只开局；补齐到五只，专门验证随后满员捕获处理。
	app.run.carried.append(app.run._make_record("ice_starter"))
	app.run.carried.append(app.run._make_record("wind_starter"))
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
	t.eq(continue_button.disabled, true, "捕获处理后仍需领取战后奖励")
	_claim_pending_monster_levels(t, app)
	_claim_pending_rewards(t, app)
	t.eq(continue_button.disabled, false, "奖励处理完成后可以继续")
	t.check(app.run.reward_inventory.size() >= 1, "三选一消耗卡已进入背包")
	var index_before: int = app.run.battle_index
	continue_button.pressed.emit()
	t.eq(app.run.battle_index, index_before + 1, "进入下一场")
	t.eq(app.current_screen.name, "PrepScreen", "回到整备界面")
	t.eq(app.run.carried.size(), 6, "名单为 6（含新捕获）")
	t.eq(app.run.storage.size(), 1, "仓库有 1 只（放入的捕获）")
	# 第二场：从背包选一张卡，开战后只消耗所选的一张。
	var selected_item := String(app.run.reward_inventory[0])
	var reward_selector: OptionButton = app.current_screen.find_child("RewardItemOption", true, false)
	t.check(reward_selector != null and reward_selector.item_count > 1, "下一场整备页列出背包卡")
	reward_selector.select(1)
	reward_selector.item_selected.emit(1)
	t.eq(app.run.selected_reward_item, selected_item, "战前选中一张已有消耗卡")
	var inventory_before_battle: int = app.run.reward_inventory.size()
	# 第二场：验证战后恢复与补给流程。
	app.show_preview([1, 2, 3])
	var preview2 = app.current_screen
	var start2: Button = preview2.find_child("StartBattleButton", true, false)
	t.check(start2 != null, "第二场预览开始按钮存在")
	start2.pressed.emit()
	var battle2 = app.current_screen
	t.eq(battle2.name, "BattleScreen", "第二场进入战斗")
	t.eq(app.run.reward_inventory.size(), inventory_before_battle - 1, "开战消耗且仅消耗一张选定卡")
	t.eq(app.run.selected_reward_item, "", "开战后已选卡清空")
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
	var settle_continue: Button = settlement2.find_child("ContinueButton", true, false)
	t.eq(settle_continue.disabled, true, "第二场结算先领取怪物升级和奖励")
	_claim_pending_monster_levels(t, app)
	_claim_pending_rewards(t, app)
	t.eq(settle_continue.disabled, false, "第二场奖励处理完可以继续")
	app.run.trainer_hp = 1
	settle_continue.pressed.emit()
	t.eq(app.current_screen.name, "SupplyScreen", "完成两场后进入补给点")
	t.eq(app.music_director.current_track, "prep", "补给页沿用整备音乐")
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
	app.show_menu()
	t.eq(app.music_director.current_track, "title", "返回开始界面恢复标题音乐")
	app.free()
	t.finish()


func _claim_pending_rewards(t: TestContext, app: Control) -> void:
	var count := 0
	while app.run.pending_reward_choices > 0 and count < 4:
		var choices: Array = app.run.reward_choices()
		t.eq(choices.size(), 3, "每次战后奖励展示三种选择")
		var id := String(choices[0])
		t.check(RewardDB.is_consumable(id), "战后池只给可留存的消耗卡")
		var reward_button: Button = app.current_screen.find_child("RewardChoice_%s" % id.replace(":", "_"), true, false)
		t.check(reward_button != null, "战后奖励按钮与待选项目一致")
		if reward_button == null:
			break
		var before: int = app.run.reward_inventory.size()
		reward_button.pressed.emit()
		t.eq(app.run.reward_inventory.size(), before + 1, "领取后卡加入本局背包")
		count += 1
	t.eq(app.run.pending_reward_choices, 0, "本场奖励选择全部处理完成")


func _claim_pending_monster_levels(t: TestContext, app: Control) -> void:
	var count := 0
	while not app.run.pending_monster_levels().is_empty() and count < 12:
		var before: Array = app.run.pending_monster_levels()
		var entry: Dictionary = before[0]
		var uid := int(entry["uid"])
		var level := int(entry["level"])
		var category: Button = app.current_screen.find_child("MonsterGrowth_enhance_%d_%d" % [uid, level], true, false)
		if category != null:
			category.pressed.emit()
		var choices: Array = app.run.available_monster_upgrades(uid)
		var id := String(choices[0]) if not choices.is_empty() else ""
		var skill_id := String(RunState.upgrade_info(id).get("requires_skill", ""))
		var button: Button = app.current_screen.find_child("MonsterEnhance_%d_%d_%s" % [uid, level, skill_id], true, false)
		t.check(button != null, "结算页先选类别再选具体招式")
		if button == null:
			break
		button.pressed.emit()
		t.eq(app.run.pending_monster_levels().size(), before.size() - 1, "领取一项后只移除当前怪物升级")
		t.check((app.run.record_by_uid(uid).get("upgrades_taken", []) as Array).has(id), "升级只记录到对应怪物")
		count += 1
	t.eq(app.run.pending_monster_levels().size(), 0, "本场怪物升级选择全部完成")
