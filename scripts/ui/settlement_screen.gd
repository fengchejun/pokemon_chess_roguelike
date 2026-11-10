extends Control

const GrowthChoices = preload("res://scripts/ui/monster_growth_choices.gd")

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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	choice_box = UIKit.vbox(8)
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_box.custom_minimum_size.x = 500
	scroll.add_child(choice_box)
	continue_button = UIKit.button("继续", 18)
	continue_button.name = "ContinueButton"
	continue_button.disabled = true
	continue_button.pressed.connect(func() -> void:
		var region = app.run.get_region() if app.run.region_mode else null
		if region != null and region.active_node == "boss" and bool(region.nodes["boss"]["cleared"]) and not app.run.storage.is_empty() and not bool(app.run.options.get("exploration_v2", false)):
			var confirm := ConfirmationDialog.new()
			confirm.title = "前往下一层"
			confirm.dialog_text = "留在营地的 %d 只宝可梦将被抛弃，无法进入永久收藏。" % app.run.storage.size()
			confirm.confirmed.connect(func() -> void: app.continue_after_settlement())
			confirm.popup_hide.connect(func() -> void: confirm.queue_free())
			add_child(confirm)
			confirm.popup_centered()
		else:
			app.continue_after_settlement()
	)
	right.add_child(continue_button)
	_show_next_step()


func _result_title() -> String:
	match String(outcome.get("reason", "")):
		"victory":
			return "战斗胜利"
		"forced_retreat":
			return "强制撤退（战斗失败）"
		"escape":
			return "主动撤离 · 返回区域（敌人留守）" if app.run.region_mode else "主动撤离"
		"explored":
			return "收集结束 · 返回区域"
	return "战斗结束"


func _summary_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UIKit.vbox(4)
	box.add_child(column)
	var lines: Array = []
	if String(outcome.get("reason", "")) == "forced_retreat":
		lines.append("本场已入账的击杀、捕获经验保留；失败不追加战后目标经验。")
	else:
		lines.append("本场怪物经验合计：+%d（按击败、捕获与战场目标的实际贡献结算）" % int(outcome.get("exp", 0)))
	if not outcome.get("loot", []).is_empty():
		lines.append("战利品 · " + "、".join(outcome["loot"]))
	if outcome.has("trainer_exp"):
		var gained: Dictionary = outcome["trainer_exp"]
		lines.append("训练家：Lv.%d · 累计经验 %d · 本场已保留 +%d" % [int(gained["level"]), int(gained["xp"]), int(gained["gained"])])
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
	if not (outcome.get("escape_penalties", []) as Array).is_empty():
		lines.append("撤离代价：" + "、".join(outcome["escape_penalties"].map(func(p): return "%s %d→%d HP" % [p["name"], p["from"], p["to"]] if p.has("from") else "%s（旧版已结算记录）" % p["name"])))
	lines.append("击败：%d　捕获：%d" % [int(outcome.get("kills", 0)), int(outcome.get("captures", 0))])
	if int(outcome.get("boss_blood", 0)) > 0:
		lines.append("捕获首领：永久首领之血 +%d（当前 %d 份）" % [int(outcome["boss_blood"]), app.collection.boss_blood])
	if bool(outcome.get("bonus_choice_earned", false)):
		lines.append("奖励点：本场额外获得一次三选一")
	if run.pending_reward_choices > 0:
		lines.append("待选战后奖励：%d 次" % run.pending_reward_choices)
	var pending_monster_levels: Array = run.pending_monster_levels()
	if not pending_monster_levels.is_empty():
		lines.append("待选怪物学招：%d 次（按怪物与等级顺序逐项处理）" % pending_monster_levels.size())
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
		lines.append("战后恢复：" + "；".join(parts))
	var base_rest: Array = outcome.get("base_rest", [])
	if not base_rest.is_empty():
		var rested: Array = []
		for entry in base_rest:
			rested.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("备战席休养（存活者恢复 50% 上限；濒死者恢复到 5 HP）：" + "；".join(rested))
	var trainer_to := int(outcome.get("trainer_to", 0))
	var storage_rest := int(outcome.get("storage_rest", 0))
	if storage_rest > 0:
		lines.append("仓库休养：%d 只回满 100%%" % storage_rest)
	var trainer_from := int(outcome.get("trainer_from", trainer_to))
	if trainer_to > 0 and trainer_from < trainer_to:
		lines.append("训练家每次出征前回满：%d→%d" % [trainer_from, trainer_to])
	var death_entries: Array = outcome.get("deaths", [])
	if death_entries.size() > 0:
		lines.append("—— 本场濒死（营地休息恢复半血）——" if app.run.region_mode else "—— 本场濒死（留守一场后恢复到 5 HP）——")
		for entry in death_entries:
			lines.append("%s（%s）" % [entry.get("name", "?"), entry.get("cause", "?")])
	column.add_child(UIKit.wrapped("\n".join(lines), 14))
	return box


func _show_next_step() -> void:
	processing = false
	UIKit.clear_children(choice_box)
	var run: RunState = app.run
	if not run.pending_captures.is_empty():
		if run.region_mode and bool(run.options.get("exploration_v2", false)) and run.carried.size() >= Balance.CARRIED_LIMIT:
			step_label.text = "新伙伴 · 选择随身替换或送入仓库"
			var incoming: Dictionary = run.pending_capture()
			choice_box.add_child(UIKit.wrapped("捕获了%s；换下的成员完整保留培养，送往共享仓库。" % SpeciesDB.name_of(String(incoming["species_id"])), 16))
			for member in run.carried:
				var uid := int(member["uid"])
				if run.is_garrisoned(uid):
					continue
				var swap := UIKit.small_button("换下%s，带上新伙伴" % SpeciesDB.name_of(String(member["species_id"])))
				swap.name = "CaptureSwap_%d" % uid
				swap.pressed.connect(func() -> void:
					for index in run.carried.size():
						if int(run.carried[index]["uid"]) == uid:
							run.storage.append(run.carried[index]); run.carried[index] = run.pending_captures.pop_front(); break
					app.autosave(); _show_next_step())
				choice_box.add_child(swap)
			var store := UIKit.small_button("送入共享仓库")
			store.name = "CaptureToStorageButton"
			store.pressed.connect(func() -> void: run.capture_to_storage(); app.autosave(); _show_next_step())
			choice_box.add_child(store)
			continue_button.disabled = true
			return
		if run.region_mode and run.carried.size() >= Balance.CARRIED_LIMIT:
			if run.camp_facility_destroyed("storage"):
				step_label.text = "仓库已毁，背包已满"
				var target: Dictionary = run.pending_capture()
				choice_box.add_child(UIKit.wrapped("%s 无法入库：本层仓库已被摧毁，已有留守成员无法存取。" % SpeciesDB.name_of(String(target["species_id"])), 15))
				var discard := UIKit.small_button("放弃这只新捕获的宝可梦")
				discard.name = "DiscardCaptureDestroyedStorage"
				discard.pressed.connect(func() -> void:
					run.capture_discard()
					app.autosave()
					_show_next_step()
				)
				choice_box.add_child(discard)
				continue_button.disabled = true
				return
			run.capture_to_storage()
			app.autosave()
			_show_next_step()
			return
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
		continue_button.disabled = true
		GrowthChoices.show_choice(run, choice_box, step_label, pending_monster_levels[0], pending_monster_levels.size(), func() -> void:
			processing = true
			app.autosave()
			_show_next_step())
		return
	if run.pending_reward_choices > 0:
		var legendary := not run.legendary_offers.is_empty()
		step_label.text = "%s三选一（剩余 %d 次）" % ["传奇遗物" if legendary else "战后奖励", run.pending_reward_choices]
		var prompt := "从高级奖励点的三个传奇遗物中选一件。满级遗物可折算为原质。" if legendary else "从本次旧版奖励的候选遗物中选一件，同种遗物最多三级。"
		choice_box.add_child(UIKit.wrapped(prompt, 13))
		for reward_id in run.reward_choices():
			var id := String(reward_id)
			var next_rank := RelicDB.rank(run.relic_stacks, id) + 1
			var result := "已满级，兑换 16 原质" if next_rank > RelicDB.MAX_RANK else "取得后 %d/%d 级" % [next_rank, RelicDB.MAX_RANK]
			var button := UIKit.button("%s · %s\n%s" % [RelicDB.display_name_of(id), result, RelicDB.description_of(id)], 14)
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
			button.pressed.connect(_choose_settlement_reward.bind(id))
			choice_box.add_child(button)
		continue_button.disabled = true
		return
	step_label.text = "全部处理完成，可以进入下一场。"
	choice_box.add_child(UIKit.wrapped("战斗结算顺序已完成：怪物经验 → 捕获 → 怪物升级 → 战后奖励 → 下一场准备。", 13))
	continue_button.disabled = false


func _choose_settlement_reward(reward_id: String) -> void:
	if app.run.choose_reward(reward_id):
		app.autosave()
		_show_next_step()


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
