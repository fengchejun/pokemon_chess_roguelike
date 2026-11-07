extends RefCounted
const BattleSnapshot = preload("res://scripts/run/battle_snapshot.gd")

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
	app.run.region_mode = false # 此用例保留旧逐场流程覆盖；区域流程由 t36 验证。
	t.eq(app.current_screen.name, "FloorThemeScreen", "开局先选择本层主题")
	var first_theme := String(app.run.offered_floor_themes[0])
	var theme_button: Button = app.current_screen.find_child("ChooseTheme_%s" % first_theme, true, false)
	t.check(theme_button != null, "主题二选一按钮存在")
	theme_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "进入编队界面")
	t.eq(app.music_director.current_track, "prep", "整备页播放整备音乐")
	var music_player: MusicDirector = app.music_director
	t.check(app.run != null and app.run.carried.size() == 3, "本局由永久收藏选三只开局")
	t.check(app.current_screen.find_child("CaptureLowHpOption", true, false) == null and app.current_screen.find_child("CaptureFieldJoinOption", true, false) == null, "整备不再显示右侧捕获设置")
	t.check(app.current_screen.find_child("PreviewButton", true, false) == null, "不再需要前往预览的中间按钮")
	app.run.options["capture_low_hp"] = true
	app.run.options["capture_field_join"] = true
	var start_button: Button = app.current_screen.find_child("StartBattleButton", true, false)
	t.check(start_button != null, "合并页直接提供开始战斗")
	start_button.pressed.emit()
	t.eq(app.current_screen.name, "PrepScreen", "没有选择队伍不能开战")
	var deploy_1: CheckBox = app.current_screen.find_child("Deploy_1", true, false)
	var deploy_2: CheckBox = app.current_screen.find_child("Deploy_2", true, false)
	var deploy_3: CheckBox = app.current_screen.find_child("Deploy_3", true, false)
	t.eq(deploy_1.button_pressed or deploy_2.button_pressed or deploy_3.button_pressed, false, "初始出战选择为空")
	deploy_1.button_pressed = true
	deploy_2.button_pressed = true
	deploy_3.button_pressed = true
	t.eq(app.current_screen.deploy_selection.size(), 3, "在同页选择三只成员")
	t.check(app.current_screen.board != null and not app.current_screen.map.is_empty(), "同页始终有地图预览")
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
	t.check(battle_screen.action_panel.z_index > battle_screen.relic_panel.z_index, "行动窗口高于侧栏")
	state.pending_casts.append({"uid": 100, "side": "enemy", "skill_id": "rock_slide", "cells": [Vector2i(2, 3)], "due_round": state.round + 1})
	battle_screen.refresh_all()
	battle_screen._show_modal("战斗菜单", "层级验证")
	t.check(battle_screen.modal_layer.z_index > battle_screen.action_panel.z_index, "菜单高于行动窗口")
	battle_screen._close_modal()
	var has_channel_marker := false
	for marker in battle_screen.board.markers:
		if String(marker.get("text", "")) == "蓄":
			has_channel_marker = true
	t.check(has_channel_marker, "固定落点保留棋盘标记")
	state.pending_casts.clear()
	battle_screen.refresh_all()
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
	t.check(battle_screen.status_label.text.contains("我方持有 1"), "战斗界面显示奖励持有状态")
	if unit != null:
		battle_screen.select_unit(unit.uid)
		t.check(battle_screen.skill_box.find_child("ChooseSkillButton", true, false) != null, "选中后先显示技能类型入口")
		t.check(battle_screen.skill_box.find_child("SkillButton_fire_burst", true, false) == null, "具体技能初始不直接出现")
		t.check(battle_screen.board.movement_cells.is_empty(), "选中后尚未进入移动模式")
		battle_screen._on_choose_skill_pressed()
		t.check(battle_screen.skill_box.find_child("SkillButton_fire_burst", true, false) != null, "点击技能后才显示招式")
		battle_screen._return_to_main_actions()
		state.set_terrain(unit.cell, TerrainDB.VINES)
		battle_screen.playback.finish_all()
		battle_screen.refresh_all()
		t.check(battle_screen.unit_body.text.contains("禁锢 2 回合：不能普通移动"), "藤蔓施加禁锢且详情说明不禁止施法")
		t.eq(battle_screen._skill_phase_block_reason(unit), "", "藤蔓本身不禁用技能")
		state.add_steam(unit.cell)
		battle_screen.refresh_all()
		t.check(battle_screen.unit_body.text.contains("不可用（雾中禁用）"), "真正因雾无法施法时显示明确原因")
		state.steam_cells.erase(unit.cell)
		state.set_terrain(unit.cell, TerrainDB.PLAIN)
		unit.imprison_ticks = 0
		battle_screen.playback.finish_all()
		battle_screen.refresh_all()
		var original_skills := unit.skills.duplicate()
		unit.skills = ["tailwind"]
		battle_screen._on_skill_pressed("tailwind")
		t.eq(battle_screen.board.area_cells, SkillResolver.support_area(unit.cell, 2, true), "磁场加速瞄准显示自身周围区域")
		battle_screen._on_board_hovered(unit.cell)
		t.eq(battle_screen.board.area_cells, SkillResolver.support_area(unit.cell, 2, true), "磁场加速悬停范围与结算一致")
		unit.skills = ["earth_shake"]
		battle_screen._on_skill_pressed("earth_shake")
		battle_screen._on_board_hovered(unit.cell + Vector2i.RIGHT)
		t.eq(battle_screen.board.area_cells, SkillResolver.front_area_cells(unit.cell, Vector2i.RIGHT, 3), "撼地悬停显示蓄力锁定的三乘三范围")
		battle_screen._clear_aim()
		unit.skills = original_skills
		var from_cell := unit.cell
		var options: Dictionary = battle_screen.state.move_options(unit)
		var dest := Vector2i(-1, -1)
		for cell in options:
			dest = cell
			break
		t.check(dest != Vector2i(-1, -1), "存在可移动格")
		battle_screen._on_board_clicked(dest)
		t.eq(unit.cell, from_cell, "未选择移动指令时点击空格不会行走")
		t.check(not battle_screen.action_panel.visible, "点击空地关闭行动窗")
		battle_screen.select_unit(unit.uid)
		battle_screen._on_move_pressed()
		t.check(not battle_screen.action_panel.visible and not battle_screen.board.movement_cells.is_empty(), "移动指令收起浮窗并显示可移动格")
		battle_screen._cancel_action()
		t.check(battle_screen.action_panel.visible and battle_screen.board.movement_cells.is_empty(), "取消移动指令恢复行动窗并清除蓝色格")
		battle_screen._on_move_pressed()
		battle_screen._on_board_clicked(dest)
		t.eq(unit.cell, dest, "移动位置正确")
		battle_screen.playback.finish_all()
		t.check(battle_screen.action_panel.visible and battle_screen.action_mode == "main", "移动完成后重新显示主行动窗")
		var move_action: Button = battle_screen.skill_box.find_child("MoveActionButton", true, false)
		t.eq(move_action.text, "撤销移动", "移动后按钮变为撤销移动")
		t.check(not move_action.disabled, "撤销移动可用")
		t.eq(battle_screen.do_undo(), true, "撤回移动成功")
		t.eq(unit.cell, from_cell, "撤回后回位")
		battle_screen.select_unit(unit.uid)
		var stable_position: Vector2 = battle_screen.action_panel.position
		for cell in [Vector2i(0, 0), Vector2i(7, 7), Vector2i(3, 3)]:
			battle_screen.board.hover_cell = cell
			battle_screen._position_action_panel()
			t.eq(battle_screen.action_panel.position, stable_position, "悬停不改变行动窗位置")
		for mouse_button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			battle_screen.select_unit(unit.uid)
			var click := InputEventMouseButton.new()
			click.pressed = true
			click.button_index = mouse_button
			click.position = Vector2(-10, -10)
			battle_screen._input(click)
			t.check(not battle_screen.action_panel.visible, "左右键点击窗口外关闭")
		battle_screen.select_unit(unit.uid)
		var old_skills := unit.skills.duplicate()
		unit.skills = ["rain_call"]
		battle_screen._on_skill_pressed("rain_call")
		var entries: Array = battle_screen.aim_entries
		if entries.size() > 1:
			battle_screen._on_board_hovered(entries[0]["cell"])
			battle_screen._on_board_hovered(entries[1]["cell"])
			var latest_markers: Array = battle_screen.board.markers.duplicate(true)
			battle_screen._on_board_hovered(entries[1]["cell"])
			t.eq(battle_screen.board.markers, latest_markers, "连续预览不会累积文字标记")
		battle_screen._clear_aim()
		unit.skills = old_skills
		var enemy: CombatUnit = state.alive_units("enemy")[0]
		battle_screen._on_board_clicked(enemy.cell)
		t.check(battle_screen.action_panel.visible, "单击敌方显示行动窗口")
		t.eq(battle_screen.skill_box.get_child(0).text, "查看详情", "敌方窗口提供详情入口")
		var double_click := InputEventMouseButton.new()
		double_click.button_index = MOUSE_BUTTON_LEFT; double_click.pressed = true; double_click.double_click = true
		double_click.position = BoardView.cell_center(enemy.cell)
		battle_screen.board._gui_input(double_click)
		t.check(battle_screen.modal_layer == null, "双击敌方不再打开详情")
		battle_screen.skill_box.get_child(0).pressed.emit()
		t.check(battle_screen.modal_layer != null, "查看详情按钮仍可打开详情")
		battle_screen._close_modal()
		var old_merchant: Dictionary = state.merchant.duplicate(true)
		var old_kind: String = state.node_kind
		state.node_kind = "event"
		state.merchant = {"cell": Vector2i(7, 0)}
		battle_screen._on_board_clicked(Vector2i(7, 0))
		var talk: Button = battle_screen.skill_box.find_child("MerchantTalkButton", true, false)
		t.check(talk != null and battle_screen.action_panel.visible, "远距离点击商人显示对话窗口")
		if talk != null:
			t.eq(talk.disabled, not state.can_interact_at(Vector2i(7, 0)), "商人对话依训练师距离启用")
			t.check(not talk.tooltip_text.is_empty(), "商人对话提供距离提示")
		battle_screen._dismiss_action_panel()
		state.merchant = old_merchant
		state.node_kind = old_kind
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
	t.check(not app.run.relic_stacks.is_empty(), "三选一遗物已进入构筑")
	app.run.reward_inventory.append("position:forest")
	var index_before: int = app.run.battle_index
	continue_button.pressed.emit()
	t.eq(app.run.battle_index, index_before + 1, "进入下一场")
	t.eq(app.current_screen.name, "PrepScreen", "回到整备界面")
	t.eq(app.run.carried.size(), 6, "名单为 6（含新捕获）")
	t.eq(app.run.storage.size(), 1, "仓库有 1 只（放入的捕获）")
	# 第二场：从背包选一张卡，开战后只消耗所选的一张。
	var selected_item := String(app.run.reward_inventory[0])
	var inventory_before_battle: int = app.run.reward_inventory.size()
	# 第二场：验证战后恢复与补给流程。
	app.show_preview([1, 2, 3])
	var preview2 = app.current_screen
	var reward_selector: OptionButton = preview2.find_child("RewardItemOption", true, false)
	t.check(reward_selector != null and reward_selector.item_count > 1, "预览页列出背包卡")
	reward_selector.select(1)
	var use_card: Button = preview2.find_child("UseRewardItemButton", true, false)
	use_card.pressed.emit()
	t.eq(app.run.preview_used_reward_item, selected_item, "预览页使用一张已有消耗卡")
	t.eq(app.run.reward_inventory.size(), inventory_before_battle - 1, "使用时立即消耗卡")
	var start2: Button = preview2.find_child("StartBattleButton", true, false)
	t.check(start2 != null, "第二场预览开始按钮存在")
	start2.pressed.emit()
	var battle2 = app.current_screen
	t.eq(battle2.name, "BattleScreen", "第二场进入战斗")
	var trainer_before: int = battle2.state.units[0].hp
	battle2.state.units[0].hp -= 3
	battle2.state.undo_stack.append({"uid": battle2.state.units[0].uid, "from": Vector2i(1, 2)})
	battle2.state.pending_casts.append({"uid": 100, "side": "enemy", "skill_id": "rock_slide", "cells": [Vector2i(2, 3)], "due_round": 2})
	battle2.state.burning_cells[Vector2i(2, 3)] = 2
	var battle_snapshot := BattleSnapshot.save_state(battle2.state)
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(battle_snapshot))
	var restored_battle := BattleSnapshot.load_state(json_snapshot)
	t.check(restored_battle != null, "战斗快照可经 JSON 往返恢复")
	if restored_battle != null:
		t.eq(restored_battle.units.size(), battle2.state.units.size(), "战斗单位完整恢复")
		t.eq(restored_battle.units[0].cell, battle2.state.units[0].cell, "单位站位完整恢复")
		t.eq(restored_battle.units[0].hp, battle2.state.units[0].hp, "单位生命完整恢复")
		t.eq(restored_battle.terrain, battle2.state.terrain, "战场地形完整恢复")
		t.eq(restored_battle.capture_rng.state, battle2.state.capture_rng.state, "捕获随机数进度完整恢复")
		t.eq(restored_battle.spawn_rng.state, battle2.state.spawn_rng.state, "产敌随机数进度完整恢复")
		t.eq(restored_battle.undo_stack, battle2.state.undo_stack, "撤回栈完整恢复")
		t.eq(restored_battle.pending_casts, battle2.state.pending_casts, "蓄力落点完整恢复")
		t.eq(restored_battle.burning_cells, battle2.state.burning_cells, "燃烧地块完整恢复")
	app.run.battle_snapshot = battle_snapshot
	var resume_path := "res://.test_midbattle_save.json"
	t.check(SaveSystem.save_run(app.run, resume_path), "战斗中存档写入成功")
	var resumed_run := SaveSystem.load_run(resume_path)
	t.check(resumed_run != null and not resumed_run.battle_snapshot.is_empty(), "战斗中存档可读取")
	if resumed_run != null:
		var resumed_battle := BattleSnapshot.load_state(resumed_run.battle_snapshot)
		t.check(resumed_battle != null, "从本局存档恢复战场")
		if resumed_battle != null:
			t.eq(resumed_battle.units[0].cell, battle2.state.units[0].cell, "存档后的站位一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(resume_path))
	var legacy_data: Dictionary = app.run.to_dict()
	legacy_data["version"] = 8
	legacy_data.erase("battle_snapshot")
	var legacy_path := "res://.test_v8_battle_save.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy_data))
		legacy_file.close()
		t.check(SaveSystem.load_run(legacy_path) != null, "v8 逐场存档仍可读取")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	battle2.state.units[0].hp = trainer_before
	battle2.state.undo_stack.clear()
	battle2.state.pending_casts.clear()
	battle2.state.burning_cells.clear()
	t.eq(app.run.reward_inventory.size(), inventory_before_battle - 1, "开战不重复消耗卡")
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
	var trainer_max: int = app.run.trainer_max_hp()
	var supply_amount := maxi(1, roundi(float(trainer_max) * Balance.SUPPLY_TRAINER_RECOVERY_RATIO))
	t.eq(app.run.trainer_hp, 1 + supply_amount, "补给点：训练家恢复 50%% 上限")
	var leave_supply: Button = app.current_screen.find_child("LeaveSupplyButton", true, false)
	t.check(leave_supply != null, "补给界面有继续出发按钮")
	var supply_choice := String(app.run.supply_choices()[0])
	var supply_button: Button = app.current_screen.find_child("SupplyChoice_%s" % supply_choice.replace(":", "_"), true, false)
	t.check(supply_button != null, "补给点提供消耗卡")
	if supply_button != null:
		supply_button.pressed.emit()
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
		t.check(RelicDB.DEFINITIONS.has(id), "战后池只给本局遗物")
		var reward_button: Button = app.current_screen.find_child("RewardChoice_%s" % id.replace(":", "_"), true, false)
		t.check(reward_button != null, "战后奖励按钮与待选项目一致")
		if reward_button == null:
			break
		var before: int = RelicDB.rank(app.run.relic_stacks, id)
		reward_button.pressed.emit()
		t.eq(RelicDB.rank(app.run.relic_stacks, id), before + 1, "领取后遗物升级")
		count += 1
	t.eq(app.run.pending_reward_choices, 0, "本场奖励选择全部处理完成")


func _claim_pending_monster_levels(t: TestContext, app: Control) -> void:
	var count := 0
	while not app.run.pending_monster_levels().is_empty() and count < 20:
		var before: Array = app.run.pending_monster_levels()
		var entry: Dictionary = before[0]
		var uid := int(entry["uid"])
		var level := int(entry["level"])
		if level == 10:
			var trait_button: Button = app.current_screen.find_child("MonsterTrait_%d_10" % uid, true, false)
			t.check(trait_button != null, "Lv10 结算页提供特性强化入口")
			if trait_button == null:
				break
			trait_button.pressed.emit()
			t.check(bool(app.run.owned_record_by_uid(uid).get("trait_upgrade_claimed", false)), "领取特性强化入口")
			count += 1
			continue
		var choices: Array = app.run.monster_level_choices(uid, level)
		t.eq(choices.size(), 3, "偶数级结算页提供三招候选")
		var skill_id := String(choices[0]) if not choices.is_empty() else ""
		var button: Button = app.current_screen.find_child("MonsterLearn_%d_%d_%s" % [uid, level, skill_id], true, false)
		t.check(button != null, "结算页直接列出三招候选")
		if button == null:
			break
		button.pressed.emit()
		var equipped: Array = app.run.owned_record_by_uid(uid).get("equipped_skills", [])
		if app.run.pending_monster_levels().size() == before.size() and equipped.size() >= RunState.MAX_EQUIPPED_SKILLS:
			var replace_skill := String(equipped[0])
			var replace_button: Button = app.current_screen.find_child("MonsterReplace_%d_%d_%s_%s" % [uid, level, skill_id, replace_skill], true, false)
			t.check(replace_button != null, "装备已满时可指定卸下招式")
			if replace_button == null:
				break
			replace_button.pressed.emit()
		t.eq(app.run.pending_monster_levels().size(), before.size() - 1, "领取一项后只移除当前怪物升级")
		t.check((app.run.record_by_uid(uid).get("known_skills", []) as Array).has(skill_id), "所选技能只记录到对应怪物")
		count += 1
	t.eq(app.run.pending_monster_levels().size(), 0, "本场怪物升级选择全部完成")
