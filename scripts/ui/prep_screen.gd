extends Control

var app = null

const MAX_DEPLOY := Balance.DEPLOY_LIMIT

var deploy_selection: Array = []
var check_boxes: Dictionary = {}
var hint_label: Label = null


func _ready() -> void:
	name = "PrepScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var columns := UIKit.hbox(16)
	margin.add_child(columns)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UIKit.label("整备 · 第 %d 场（%s）" % [run.battle_index + 1, run.region_name()], 24, UIKit.ACCENT))
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	left.add_child(UIKit.wrapped("训练家生命：%d / %d（每次冒险前回满）。每只怪物独立累计本局经验；击败、捕获与战场目标按实际贡献结算。等级与强化在新局重置，出战宝可梦冒险结束恢复 30%%，留守基地成员回满。" % [run.trainer_hp, trainer_max], 14, UIKit.TEXT_DIM))
	left.add_child(UIKit.label("出战名单（%d/%d）——每场最多勾选 %d 只出战；其余留守基地（冒险结束时回满）；濒死成员需留守一个冒险周期：" % [run.carried.size(), Balance.CARRIED_LIMIT, MAX_DEPLOY], 16))
	var team_scroll := UIKit.scroll()
	left.add_child(team_scroll)
	var team_box := UIKit.vbox(6)
	team_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_scroll.add_child(team_box)
	for record in run.carried:
		team_box.add_child(_team_row(record))
	if run.carried.is_empty():
		team_box.add_child(UIKit.label("没有可出战的宝可梦。", 16, UIKit.BAD))
	hint_label = UIKit.label("", 14, UIKit.BAD)
	left.add_child(hint_label)
	var preset: Array = app.prep_deploy_preset
	app.prep_deploy_preset = []
	var desired: Array = preset if not preset.is_empty() else run.deployed_uids
	for record in run.carried:
		if deploy_selection.size() >= MAX_DEPLOY:
			break
		if int(record["hp"]) <= 0:
			continue
		if desired.has(int(record["uid"])):
			deploy_selection.append(int(record["uid"]))
			var box: CheckBox = check_boxes[int(record["uid"])]
			box.set_pressed_no_signal(true)
	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(440, 0)
	columns.add_child(right)
	var right_scroll := UIKit.scroll()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(right_scroll)
	var right_content := UIKit.vbox(10)
	right_scroll.add_child(right_content)
	right_content.add_child(_reward_inventory_box(run))
	right_content.add_child(_capture_settings_box(run))
	right_content.add_child(_archive_box(run))
	right_content.add_child(_storage_box(run))
	right_content.add_child(_next_box(run))
	var start := UIKit.button("前往地图预览", 18)
	start.name = "PreviewButton"
	start.pressed.connect(_on_start)
	right.add_child(start)


func _capture_settings_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(5)
	box.add_child(column)
	column.add_child(UIKit.label("本局捕获设置", 17, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("训练家周围八格可捕获。下面两项独立选择；关闭时使用 v2 的概率与离场处理。", 13))
	var low_hp := CheckBox.new()
	low_hp.name = "CaptureLowHpOption"
	low_hp.text = "半血以下才可尝试；1 HP 或减益 2 HP 必成"
	low_hp.button_pressed = bool(run.options.get("capture_low_hp", false))
	low_hp.toggled.connect(func(value: bool) -> void:
		run.options["capture_low_hp"] = value
		app.autosave()
	)
	column.add_child(low_hp)
	var field_join := CheckBox.new()
	field_join.name = "CaptureFieldJoinOption"
	field_join.text = "成功后原地转我方，本轮可行动；战中倒下不入队"
	field_join.button_pressed = bool(run.options.get("capture_field_join", false))
	field_join.toggled.connect(func(value: bool) -> void:
		run.options["capture_field_join"] = value
		app.autosave()
	)
	column.add_child(field_join)
	return box


func _reward_inventory_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(5)
	box.add_child(column)
	column.add_child(UIKit.label("战后奖励背包（%d 张）" % run.reward_inventory.size(), 17, UIKit.ACCENT))
	var selector := OptionButton.new()
	selector.name = "RewardItemOption"
	selector.add_item("本场不使用消耗卡")
	var selected_index := 0
	for reward_id in run.reward_inventory:
		var id := String(reward_id)
		selector.add_item(RewardDB.name_of(id))
		if id == run.selected_reward_item and selected_index == 0:
			selected_index = selector.item_count - 1
	selector.select(selected_index)
	selector.item_selected.connect(func(index: int) -> void:
		var id := "" if index == 0 else String(run.reward_inventory[index - 1])
		if run.select_reward_item(id):
			app.autosave()
			show_prep_after_mode_change()
	)
	column.add_child(selector)
	column.add_child(UIKit.wrapped("每场战斗前最多使用一张，开战时才消耗。站位卡作用于本场战斗；地貌卡改变本场地图生成倾向；改造工具允许预览时改造两格。未选中的卡会留在本局背包。", 12))
	if run.selected_reward_item != "":
		column.add_child(UIKit.wrapped("已选：%s\n%s" % [RewardDB.name_of(run.selected_reward_item), RewardDB.description_of(run.selected_reward_item)], 12, UIKit.ACCENT))
	if run.pending_bonus_choices > 0:
		column.add_child(UIKit.wrapped("旧存档待领额外奖励 %d 次：将在下一次战后结算中兑现。" % run.pending_bonus_choices, 12, UIKit.ACCENT))
	return box


func show_prep_after_mode_change() -> void:
	app.prep_deploy_preset = deploy_selection.duplicate()
	app.show_prep()


func _team_row(record: Dictionary) -> Control:
	var species_id := String(record["species_id"])
	var row := UIKit.panel(UIKit.PANEL_LIGHT)
	var line := UIKit.hbox(10)
	row.add_child(line)
	var box := CheckBox.new()
	box.name = "Deploy_%d" % int(record["uid"])
	if int(record["hp"]) <= 0:
		box.disabled = true
		box.tooltip_text = "濒死：留守基地休养一场后恢复。"
	box.toggled.connect(func(pressed: bool) -> void: _on_toggle(int(record["uid"]), pressed))
	line.add_child(box)
	check_boxes[int(record["uid"])] = box
	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var title_line := UIKit.hbox(10)
	info.add_child(title_line)
	title_line.add_child(UIKit.label(SpeciesDB.name_of(species_id), 17))
	title_line.add_child(UIKit.element_chip(SpeciesDB.element_of(species_id)))
	info.add_child(UIKit.wrapped("本局 Lv.%d · 经验 %d/%d · 生命 %d/%d · 基础移动 %d · 亲密度 %d（永久，暂无效果）" % [
		int(record.get("level", 1)), int(record.get("xp", 0)), MonsterProgression.threshold_for_level(int(record.get("level", 1)) + 1),
		int(record["hp"]), app.run.monster_max_hp(record), SpeciesDB.move_of(species_id), int(record.get("affinity", 0)),
	], 13, UIKit.TEXT_DIM))
	if int(record["hp"]) <= 0:
		title_line.add_child(UIKit.label("濒死（休养中）", 13, UIKit.BAD))
	var upgrade_names: Array = []
	for upgrade_id in record.get("upgrades_taken", []):
		var info_entry: Dictionary = RunState.upgrade_info(String(upgrade_id))
		if not info_entry.is_empty():
			upgrade_names.append(String(info_entry.get("name", upgrade_id)))
	info.add_child(UIKit.wrapped("本局强化：%s" % ("、".join(upgrade_names) if not upgrade_names.is_empty() else "尚无"), 12, UIKit.TEXT_DIM))
	var known: Array = record.get("known_skills", SpeciesDB.skills_of(species_id))
	var equipped: Array = record.get("equipped_skills", SpeciesDB.skills_of(species_id))
	var library_names: Array = []
	for skill_id in known:
		var id := String(skill_id)
		var enhanced := (record.get("upgrades_taken", []) as Array).has(RunState.upgrade_id_for_skill(id))
		library_names.append("%s%s%s" % [SkillDB.name_of(id), "★" if enhanced else "", "（占位）" if SkillDB.is_placeholder(id) else ""])
	info.add_child(UIKit.wrapped("本局招式库：" + "、".join(library_names), 12, UIKit.TEXT_DIM))
	for slot in range(RunState.MAX_EQUIPPED_SKILLS):
		var selector := OptionButton.new()
		selector.name = "SkillSlot_%d_%d" % [int(record["uid"]), slot]
		selector.add_item("装备位 %d：空" % (slot + 1))
		selector.set_item_metadata(0, "")
		var selected_index := 0
		for skill_id in known:
			var id := String(skill_id)
			if equipped.has(id) and (slot >= equipped.size() or String(equipped[slot]) != id):
				continue
			var enhanced := (record.get("upgrades_taken", []) as Array).has(RunState.upgrade_id_for_skill(id))
			selector.add_item("装备位 %d：%s%s" % [slot + 1, SkillDB.name_of(id), " ★" if enhanced else ""])
			selector.set_item_metadata(selector.item_count - 1, id)
			if slot < equipped.size() and String(equipped[slot]) == id:
				selected_index = selector.item_count - 1
		selector.select(selected_index)
		selector.item_selected.connect(func(index: int) -> void:
			var id := String(selector.get_item_metadata(index))
			if app.run.equip_monster_skill(int(record["uid"]), slot, id):
				app.autosave()
				show_prep_after_mode_change()
		)
		info.add_child(selector)
	if Elements.MATCHUPS_ENABLED:
		info.add_child(UIKit.wrapped(Elements.counter_hint(SpeciesDB.element_of(species_id)), 12))
	return row


func _archive_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(6)
	box.add_child(column)
	column.add_child(UIKit.label("战损记录（倒下即濒死，基地休养后恢复）", 17, UIKit.BAD))
	if run.deaths.is_empty():
		column.add_child(UIKit.label("尚无战损。", 13, UIKit.TEXT_DIM))
	else:
		var lines: Array = []
		for entry in run.deaths:
			lines.append("- %s（第 %d 场，%s）" % [entry.get("name", "?"), int(entry.get("battle", 0)), entry.get("cause", "?")])
		column.add_child(UIKit.wrapped("\n".join(lines), 13))
	return box


func _storage_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(6)
	box.add_child(column)
	column.add_child(UIKit.label("仓库（%d/%d）" % [run.storage.size(), Balance.STORAGE_LIMIT], 17, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("仓库成员不参战、不受战损，且每场战后与留守成员一并回满；名单满员时，捕获可在战后选择替换（含濒死成员）或放入仓库。", 13))
	if not run.storage.is_empty():
		var names: Array = []
		for record in run.storage:
			names.append(SpeciesDB.name_of(String(record["species_id"])))
		column.add_child(UIKit.wrapped("成员：" + "、".join(names), 13, UIKit.TEXT_DIM))
	return box


func _next_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(6)
	box.add_child(column)
	var cfg := BattleDB.config_for(run.battle_index)
	column.add_child(UIKit.label("下一场：%s" % run.region_name(), 18, UIKit.ACCENT))
	var enemy_names: Array = []
	for pair in cfg.get("enemies", []):
		var species_id := String(pair[0])
		enemy_names.append("%s【%s】" % [SpeciesDB.name_of(species_id), Elements.name_of(SpeciesDB.element_of(species_id))])
	column.add_child(UIKit.wrapped("敌方：%s（共 %d 只，另有巢穴增援）" % [", ".join(enemy_names), enemy_names.size()], 14))
	column.add_child(UIKit.wrapped("巢穴：耐久 3，第 2、4、6 回合各尝试生成 1 只；堵口则排队，摧毁后立即获胜。", 13))
	return box


func _on_toggle(uid: int, pressed: bool) -> void:
	if pressed:
		var record: Dictionary = app.run.record_by_uid(uid)
		if not record.is_empty() and int(record["hp"]) <= 0:
			var box: CheckBox = check_boxes[uid]
			box.set_pressed_no_signal(false)
			hint_label.text = "濒死的宝可梦无法出战：留守基地休养一场后恢复。"
			return
		if deploy_selection.size() >= MAX_DEPLOY:
			var box: CheckBox = check_boxes[uid]
			box.set_pressed_no_signal(false)
			hint_label.text = "最多出战 %d 只。" % MAX_DEPLOY
			return
		if not deploy_selection.has(uid):
			deploy_selection.append(uid)
	else:
		deploy_selection.erase(uid)
	hint_label.text = ""


func _on_start() -> void:
	if app.run.run_lost():
		hint_label.text = "没有可出战的宝可梦，本局结束。"
		return
	if deploy_selection.is_empty():
		hint_label.text = "至少选择 1 只出战宝可梦。"
		return
	app.show_preview(deploy_selection)
