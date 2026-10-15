extends Control

var app = null

var battle: BattleState = null
var outcome: Dictionary = {}
var choice_box: VBoxContainer = null
var step_label: Label = null
var continue_button: Button = null
var processing := false


func _ready() -> void:
	name = "SettlementScreen"
	UIKit.fill_background(self)
	var data: Dictionary = app.pending_settlement
	battle = data.get("battle")
	outcome = data.get("outcome", {})
	var run: RunState = app.run
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var columns := UIKit.hbox(16)
	margin.add_child(columns)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UIKit.label(_result_title(), 30, UIKit.ACCENT))
	left.add_child(_summary_box(run))
	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(500, 0)
	columns.add_child(right)
	step_label = UIKit.label("", 19, UIKit.ACCENT)
	right.add_child(step_label)
	var scroll := UIKit.scroll()
	right.add_child(scroll)
	choice_box = UIKit.vbox(8)
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(choice_box)
	continue_button = UIKit.button("继续", 18)
	continue_button.name = "ContinueButton"
	continue_button.disabled = true
	continue_button.pressed.connect(func() -> void: app.continue_after_settlement())
	right.add_child(continue_button)
	_show_next_step()


func _result_title() -> String:
	match String(outcome.get("reason", "")):
		"victory":
			return "战斗胜利"
		"forced_retreat":
			return "强制撤退（战斗失败）"
		"escape":
			return "野生逃离"
	return "战斗结束"


func _summary_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UIKit.vbox(4)
	box.add_child(column)
	var lines: Array = []
	if String(outcome.get("reason", "")) == "forced_retreat":
		lines.append("本场经验：0（强制撤退不结算本场经验）")
	else:
		lines.append("本场怪物经验合计：+%d（按击败、捕获与战场目标的实际贡献结算）" % int(outcome.get("exp", 0)))
	if bool(outcome.get("growth_migrated", false)):
		lines.append("旧本局存档已迁移：旧经验、等级与全队强化清零，保留关卡和奖励。")
	if bool(outcome.get("upgrade_migrated", false)):
		lines.append("局内强化规则已更新：旧通用强化退还为待选升级，原技能强化保留。")
	for growth in outcome.get("monster_exp", []):
		var level_text := "，升级至 Lv.%d" % int(growth["level_after"]) if int(growth["level_after"]) > int(growth["level_before"]) else ""
		var record := run.owned_record_by_uid(int(growth.get("uid", -1)))
		var affinity := int(record.get("affinity", 0))
		lines.append("%s：本局经验 +%d（%d/%d）%s；永久亲密度 %d" % [
			growth["name"], int(growth["gained"]), int(growth["xp_after"]),
			MonsterProgression.threshold_for_level(int(growth["level_after"]) + 1), level_text, affinity,
		])
	lines.append("击败：%d　捕获：%d" % [int(outcome.get("kills", 0)), int(outcome.get("captures", 0))])
	if bool(outcome.get("bonus_choice_earned", false)):
		lines.append("奖励点：本场额外获得一次三选一")
	if run.pending_reward_choices > 0:
		lines.append("待选战后奖励：%d 次" % run.pending_reward_choices)
	var pending_monster_levels: Array = run.pending_monster_levels()
	if not pending_monster_levels.is_empty():
		lines.append("待选怪物升级：%d 次（按怪物与等级顺序逐项处理）" % pending_monster_levels.size())
	var captured_names: Array = outcome.get("captured_names", [])
	if not captured_names.is_empty():
		lines.append("本场捕获：" + "、".join(captured_names))
	var flee_penalty: Array = outcome.get("flee_penalty", [])
	if not flee_penalty.is_empty():
		var punished: Array = []
		for entry in flee_penalty:
			punished.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("失败惩罚（出战宝可梦生命减半）：" + "；".join(punished))
	var recovery: Array = outcome.get("recovery", [])
	if not recovery.is_empty():
		var parts: Array = []
		for entry in recovery:
			parts.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("战后恢复（出战 30% 上限）：" + "；".join(parts))
	var base_rest: Array = outcome.get("base_rest", [])
	if not base_rest.is_empty():
		var rested: Array = []
		for entry in base_rest:
			rested.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("基地休养（冒险结束回满 100%）：" + "；".join(rested))
	var trainer_to := int(outcome.get("trainer_to", 0))
	var storage_rest := int(outcome.get("storage_rest", 0))
	if storage_rest > 0:
		lines.append("仓库休养：%d 只回满 100%%" % storage_rest)
	var trainer_from := int(outcome.get("trainer_from", trainer_to))
	if trainer_to > 0 and trainer_from < trainer_to:
		lines.append("训练家每次出征前回满：%d→%d" % [trainer_from, trainer_to])
	var death_entries: Array = outcome.get("deaths", [])
	if death_entries.size() > 0:
		lines.append("—— 本场濒死（留守基地一场后恢复）——")
		for entry in death_entries:
			lines.append("%s（%s）" % [entry.get("name", "?"), entry.get("cause", "?")])
	column.add_child(UIKit.wrapped("\n".join(lines), 14))
	return box


func _show_next_step() -> void:
	processing = false
	UIKit.clear_children(choice_box)
	var run: RunState = app.run
	if not run.pending_captures.is_empty():
		# 名单未满：直接入队（不打断流程）
		if run.carried.size() < Balance.CARRIED_LIMIT:
			run.capture_join_team()
			app.autosave()
			_show_next_step()
			return
		_show_capture_step(run)
		return
	var pending_monster_levels: Array = run.pending_monster_levels()
	if not pending_monster_levels.is_empty():
		_show_monster_level_step(run, pending_monster_levels[0], pending_monster_levels.size())
		return
	if run.pending_reward_choices > 0:
		step_label.text = "战后奖励：三选一（剩余 %d 次）" % run.pending_reward_choices
		choice_box.add_child(UIKit.wrapped("三项均为消耗卡：选择一张加入本局背包，之后任意一场战斗前可用一张；未使用会保留。怪物强化在升级时分别选择。", 13))
		for reward_id in run.reward_choices():
			var id := String(reward_id)
			var button := UIKit.button("%s\n%s" % [RewardDB.name_of(id), RewardDB.description_of(id)], 14)
			button.custom_minimum_size = Vector2(0, 76)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var normal_style := StyleBoxFlat.new()
			normal_style.bg_color = UIKit.PANEL_LIGHT
			normal_style.border_color = UIKit.ACCENT.darkened(0.35)
			normal_style.set_border_width_all(1)
			normal_style.set_corner_radius_all(6)
			normal_style.set_content_margin_all(12)
			button.add_theme_stylebox_override("normal", normal_style)
			var hover_style := normal_style.duplicate() as StyleBoxFlat
			hover_style.bg_color = UIKit.PANEL_LIGHT.lightened(0.18)
			button.add_theme_stylebox_override("hover", hover_style)
			button.name = "RewardChoice_%s" % id.replace(":", "_")
			button.pressed.connect(func() -> void:
				if app.run.choose_reward(id):
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(button)
		continue_button.disabled = true
		return
	step_label.text = "全部处理完成，可以进入下一场。"
	choice_box.add_child(UIKit.wrapped("战斗结算顺序已完成：怪物经验 → 捕获 → 怪物升级 → 战后奖励 → 下一场准备。", 13))
	continue_button.disabled = false


func _show_monster_level_step(run: RunState, entry: Dictionary, remaining: int) -> void:
	var uid := int(entry.get("uid", -1))
	var level := int(entry.get("level", 1))
	var record := run.owned_record_by_uid(uid)
	var monster_name := SpeciesDB.name_of(String(record.get("species_id", ""))) if not record.is_empty() else "怪物 #%d" % uid
	step_label.text = "%s · Lv.%d 升级选择（剩余 %d 项）" % [monster_name, level, remaining]
	choice_box.add_child(UIKit.wrapped("二选一：强化一招已学技能，或学习一招本属性的临时占位技能。先选类型，再选具体招式；本场结束后生效。", 13))
	for mode in ["enhance", "learn"]:
		var options := run.available_monster_upgrades(uid) if mode == "enhance" else run.available_new_skills(uid)
		if options.is_empty():
			continue
		var label := "强化已学技能（%d 招可选）" if mode == "enhance" else "学习新技能（%d 招占位）"
		var button := UIKit.button(label % options.size(), 16)
		button.name = "MonsterGrowth_%s_%d_%d" % [mode, uid, level]
		button.pressed.connect(func() -> void: _show_growth_options(run, uid, level, mode))
		choice_box.add_child(button)
	continue_button.disabled = true


func _show_growth_options(run: RunState, uid: int, level: int, mode: String) -> void:
	UIKit.clear_children(choice_box)
	step_label.text = "%s · Lv.%d：%s" % [SpeciesDB.name_of(String(run.owned_record_by_uid(uid).get("species_id", ""))), level, "强化技能" if mode == "enhance" else "学习技能"]
	var back := UIKit.small_button("返回类型选择")
	back.name = "MonsterGrowthBack"
	back.pressed.connect(func() -> void:
		UIKit.clear_children(choice_box)
		_show_monster_level_step(run, {"uid": uid, "level": level}, run.pending_monster_levels().size())
	)
	choice_box.add_child(back)
	if mode == "enhance":
		var record := run.owned_record_by_uid(uid)
		var equipped: Array = record.get("equipped_skills", [])
		for upgrade_id in run.available_monster_upgrades(uid):
			var id := String(upgrade_id)
			var info := RunState.upgrade_info(id)
			var skill_id := String(info.get("requires_skill", ""))
			var marker := "（已装备）" if equipped.has(skill_id) else "（未装备，换装后生效）"
			var button := UIKit.button("%s%s\n%s" % [SkillDB.name_of(skill_id), marker, info.get("desc", "")], 14)
			button.name = "MonsterEnhance_%d_%d_%s" % [uid, level, skill_id]
			button.pressed.connect(func() -> void:
				if not processing and run.enhance_monster_skill(uid, level, skill_id):
					processing = true
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(button)
	else:
		choice_box.add_child(UIKit.wrapped("试招Ⅰ／Ⅱ目前效果完全相同，仅作正式技能的临时占位。每只怪物最多装备四招。", 13, UIKit.TEXT_DIM))
		for candidate in run.available_new_skills(uid):
			var skill_id := String(candidate)
			var button := UIKit.button("%s\n%s" % [SkillDB.name_of(skill_id), SkillDB.get_def(skill_id).get("desc", "")], 14)
			button.name = "MonsterLearn_%d_%d_%s" % [uid, level, skill_id]
			button.pressed.connect(func() -> void:
				var equipped: Array = run.owned_record_by_uid(uid).get("equipped_skills", [])
				if equipped.size() >= RunState.MAX_EQUIPPED_SKILLS:
					_show_growth_replace(run, uid, level, skill_id)
				elif not processing and run.learn_monster_skill(uid, level, skill_id):
					processing = true
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(button)
	continue_button.disabled = true


func _show_growth_replace(run: RunState, uid: int, level: int, new_skill_id: String) -> void:
	UIKit.clear_children(choice_box)
	step_label.text = "四招已满：选择卸下的一招"
	choice_box.add_child(UIKit.wrapped("卸下的招式留在本局招式库，已取得的强化也会保留；下场战斗前可在整备页换回。", 13))
	var back := UIKit.small_button("返回学招选择")
	back.pressed.connect(func() -> void: _show_growth_options(run, uid, level, "learn"))
	choice_box.add_child(back)
	for equipped_id in run.owned_record_by_uid(uid).get("equipped_skills", []):
		var old_id := String(equipped_id)
		var button := UIKit.button("卸下 %s → 装备 %s" % [SkillDB.name_of(old_id), SkillDB.name_of(new_skill_id)], 14)
		button.name = "MonsterReplace_%d_%d_%s_%s" % [uid, level, new_skill_id, old_id]
		button.pressed.connect(func() -> void:
			if not processing and run.learn_monster_skill(uid, level, new_skill_id, old_id):
				processing = true
				app.autosave()
				_show_next_step()
		)
		choice_box.add_child(button)
	continue_button.disabled = true


func _show_capture_step(run: RunState) -> void:
	## 名单已满：给出「替换（被替换者入仓库）」或「放入仓库」两个选项。
	var target: Dictionary = run.pending_capture()
	if target.is_empty():
		_show_next_step()
		return
	step_label.text = "捕获处理：名单已满（%d 只），选择替换或放入仓库" % Balance.CARRIED_LIMIT
	choice_box.add_child(UIKit.wrapped("新捕获：%s（生命 %d/%d，另有 %d 只待处理）" % [
		SpeciesDB.name_of(String(target["species_id"])), int(target["hp"]),
		SpeciesDB.hp_of(String(target["species_id"])), run.pending_captures.size(),
	], 15))
	var storage_room := run.storage.size() < Balance.STORAGE_LIMIT
	choice_box.add_child(UIKit.label("替换（选定成员将进入仓库）：", 13, UIKit.TEXT_DIM))
	var replace_row := UIKit.vbox(4)
	choice_box.add_child(replace_row)
	for record in run.carried:
		var faint_tag := "（濒死）" if int(record["hp"]) <= 0 else ""
		var button := UIKit.small_button("替换掉 %s%s（%d/%d，其入仓库）" % [
			SpeciesDB.name_of(String(record["species_id"])), faint_tag, int(record["hp"]),
			SpeciesDB.hp_of(String(record["species_id"])),
		])
		var replace_uid := int(record["uid"])
		if not storage_room:
			button.disabled = true
			button.tooltip_text = "仓库已满：先放生或选择放弃。"
		button.pressed.connect(func() -> void:
			if run.capture_replace(replace_uid):
				app.autosave()
				_show_next_step()
		)
		replace_row.add_child(button)
	var to_storage := UIKit.small_button("放入仓库（%d/%d）" % [run.storage.size(), Balance.STORAGE_LIMIT])
	to_storage.name = "CaptureToStorageButton"
	to_storage.disabled = not storage_room
	if not storage_room:
		to_storage.tooltip_text = "仓库已满：可先放生一名仓库成员或选择放弃。"
	to_storage.pressed.connect(func() -> void:
		if run.capture_to_storage():
			app.autosave()
			_show_next_step()
	)
	choice_box.add_child(to_storage)
	if not storage_room:
		choice_box.add_child(UIKit.label("仓库已满：放生一名仓库成员后可继续放入：", 13, UIKit.BAD))
		for record in run.storage.slice(0, mini(10, run.storage.size())):
			var release := UIKit.small_button("放生 %s（%d/%d）" % [
				SpeciesDB.name_of(String(record["species_id"])), int(record["hp"]),
				SpeciesDB.hp_of(String(record["species_id"])),
			])
			var release_uid := int(record["uid"])
			release.pressed.connect(func() -> void:
				if run.release_storage(release_uid):
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(release)
	var give_up := UIKit.small_button("放弃本次捕获")
	give_up.pressed.connect(func() -> void:
		run.capture_discard()
		app.autosave()
		_show_next_step()
	)
	choice_box.add_child(give_up)
	continue_button.disabled = true
