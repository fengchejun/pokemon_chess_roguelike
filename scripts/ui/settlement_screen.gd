extends Control

const GrowthChoices = preload("res://scripts/ui/monster_growth_choices.gd")

var app = null

var battle: BattleState = null
var outcome: Dictionary = {}
var choice_box: VBoxContainer = null
var step_label: Label = null
var continue_button: Button = null
var skip_remaining_button: Button
var processing := false
var card: PanelContainer
var page: VBoxContainer
var choice_scroll: ScrollContainer
var details_scroll: ScrollContainer
var progress_label: Label
var layout_queued := false
var layout_stage := ""
var stage_height := 0.0
var mage_note_selected: Array = []
var magic_end_uid := -1


func _ready() -> void:
	name = "SettlementScreen"
	UIKit.fill_background(self)
	var data: Dictionary = app.pending_settlement
	battle = data.get("battle")
	outcome = data.get("outcome", {})
	var run: RunState = app.run
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	card = UIKit.panel(Color("202630"))
	card.name = "SettlementCard"
	var surface := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	surface.set_content_margin_all(22)
	surface.set_corner_radius_all(16)
	surface.border_color = Color("394451")
	surface.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", surface)
	center.add_child(card)
	page = UIKit.vbox(14)
	card.add_child(page)
	var header := UIKit.hbox(12)
	page.add_child(header)
	var title := UIKit.label(_result_title(), 29, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var details := UIKit.small_button("查看战报")
	details.name = "ToggleSettlementDetails"
	_style_button(details, Color("2c3542"), UIKit.TEXT)
	details.pressed.connect(func() -> void:
		details_scroll.visible = not details_scroll.visible
		details.text = "收起战报" if details_scroll.visible else "查看战报"
		_schedule_layout())
	header.add_child(details)
	page.add_child(UIKit.label("击败 %d  ·  捕获 %d  ·  队伍经验 +%d" % [int(outcome.get("kills", 0)), int(outcome.get("captures", 0)), int(outcome.get("exp", 0))], 16, UIKit.TEXT_DIM))
	details_scroll = UIKit.scroll()
	details_scroll.name = "SettlementDetails"
	details_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	details_scroll.custom_minimum_size.y = 140
	details_scroll.add_child(_summary_box(run))
	details_scroll.hide()
	page.add_child(details_scroll)
	page.add_child(HSeparator.new())
	step_label = UIKit.wrapped("", 20, UIKit.ACCENT)
	page.add_child(step_label)
	choice_scroll = UIKit.scroll()
	choice_scroll.name = "SettlementChoicesScroll"
	choice_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(choice_scroll)
	choice_box = UIKit.vbox(10)
	choice_box.name = "SettlementChoices"
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_scroll.add_child(choice_box)
	choice_box.minimum_size_changed.connect(_schedule_layout)
	page.add_child(HSeparator.new())
	var footer := UIKit.hbox(16)
	page.add_child(footer)
	progress_label = UIKit.wrapped("", 14, UIKit.TEXT_DIM)
	progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(progress_label)
	skip_remaining_button = UIKit.button("放弃剩余奖励", 15)
	skip_remaining_button.name = "SkipRemainingBattleLoot"
	skip_remaining_button.custom_minimum_size.x = 160
	_style_button(skip_remaining_button, Color("34343d"), Color("c6b9c0"))
	skip_remaining_button.pressed.connect(func() -> void:
		for index in app.run.pending_battle_loot.size():
			app.run.resolve_battle_loot(index, false)
		app.autosave()
		_show_next_step())
	footer.add_child(skip_remaining_button)
	continue_button = UIKit.button("继续", 18)
	continue_button.name = "ContinueButton"
	continue_button.custom_minimum_size = Vector2(176, 48)
	_style_button(continue_button, UIKit.ACCENT, Color("25232b"))
	continue_button.disabled = true
	continue_button.pressed.connect(func() -> void:
		app.continue_after_settlement()
	)
	footer.add_child(continue_button)
	resized.connect(_schedule_layout)
	_show_next_step()
	_schedule_layout()


func _result_title() -> String:
	match String(outcome.get("reason", "")):
		"relic_action":
			return "遗物效果"
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
	if not run.pending_battle_loot.is_empty():
		lines.append("胜利战利品可逐项领取或放弃。")
	if run.pending_reward_choices > 0:
		lines.append("待选战后奖励：%d 次" % run.pending_reward_choices)
	if int(outcome.get("reward_points_earned", 0)) > 0:
		lines.append("奖励点：本场取得 %d 点，每名存活原出战成员额外获得 %d 经验" % [
			int(outcome["reward_points_earned"]), int(outcome["reward_points_earned"]),
		])
	if int(outcome.get("relic_reward_count", 0)) > 0:
		lines.append("遗物机会：+%d" % int(outcome["relic_reward_count"]))
	for notice in outcome.get("relic_notices", []):
		lines.append(String(notice))
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
	choice_scroll.scroll_vertical = 0
	_schedule_layout()
	var run: RunState = app.run
	skip_remaining_button.visible = run.has_pending_battle_loot()
	var taken := run.pending_battle_loot.filter(func(offer): return offer.get("status", "") == "taken")
	if not taken.is_empty():
		choice_box.add_child(UIKit.wrapped("已领取：" + "、".join(taken.map(func(offer): return offer["label"])), 14, UIKit.ACCENT))
	if run.has_pending_battle_loot():
		step_label.text = "胜利奖励 · 可分别领取或放弃"
		choice_box.add_child(UIKit.wrapped("每项单独处理，领取原质后可以放弃遗物。放弃的奖励不会自动入账。", 14))
		for index in run.pending_battle_loot.size():
			var offer: Dictionary = run.pending_battle_loot[index]
			if offer.get("status", "pending") != "pending":
				continue
			var reward_card := UIKit.panel(Color("29323f"))
			var style := reward_card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			var tint := Color("81c5be") if offer["kind"] == "essence" else Color("b9a3df") if offer["kind"] in ["relic", "legendary", "relic_choice"] else Color("8db8df")
			style.border_color = tint.darkened(0.35)
			style.border_width_left = 3
			style.set_content_margin_all(14)
			reward_card.add_theme_stylebox_override("panel", style)
			choice_box.add_child(reward_card)
			var row := UIKit.hbox(16)
			reward_card.add_child(row)
			var info := UIKit.vbox(5)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			info.add_child(UIKit.wrapped(String(offer["label"]), 19, UIKit.TEXT))
			info.add_child(UIKit.wrapped(_reward_description(offer), 14, UIKit.TEXT_DIM))
			var take := UIKit.button("领取", 16)
			take.name = "TakeBattleLoot_%d" % index
			take.custom_minimum_size.x = 104
			take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_style_button(take, Color("365965"), Color("e3f6f5"))
			take.pressed.connect(_resolve_loot.bind(index, true))
			row.add_child(take)
			var skip := UIKit.button("放弃", 16)
			skip.name = "SkipBattleLoot_%d" % index
			skip.custom_minimum_size.x = 80
			skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_style_button(skip, Color("34343d"), Color("c6b9c0"))
			skip.pressed.connect(_resolve_loot.bind(index, false))
			row.add_child(skip)
		continue_button.disabled = true
		return
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
	if run.has_pending_relic_actions():
		_show_relic_action_step(run)
		return
	if run.pending_reward_choices > 0:
		var choices := run.reward_choices()
		if choices.is_empty():
			var discarded := run.discard_unavailable_reward_choices()
			if run.pending_reward_choices > 0:
				_show_next_step()
				return
			step_label.text = "遗物奖励：暂无可领取项目"
			choice_box.add_child(UIKit.wrapped("当前遗物池已耗尽，%d 次机会已折算原质。" % discarded, 13, UIKit.TEXT_DIM))
			app.autosave()
			continue_button.disabled = false
			return
		step_label.text = "遗物三选一（剩余 %d 次）" % run.pending_reward_choices
		choice_box.add_child(UIKit.wrapped("选择一件本局唯一遗物。进化型遗物会替换其前置遗物；效果立即生效并随本局保存。", 13))
		for reward_id in choices:
			var id := String(reward_id)
			var button := UIKit.button("%s【%s】\n%s" % [
				RelicDB.name_of(id), RelicDB.rarity_name(id), RelicDB.description_of(id),
			], 14)
			button.name = "RelicChoice_%s" % id
			button.custom_minimum_size = Vector2(0, 92)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(_choose_settlement_relic.bind(id))
			choice_box.add_child(button)
		var skip_reward := UIKit.small_button("放弃本次遗物选择")
		skip_reward.name = "SkipRewardChoice"
		skip_reward.pressed.connect(func() -> void:
			run.skip_reward_choice()
			app.autosave()
			_show_next_step())
		choice_box.add_child(skip_reward)
		continue_button.disabled = true
		return
	step_label.text = "结算完成"
	choice_box.add_child(UIKit.wrapped("奖励与队伍整理已完成，可以继续探索。", 13))
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
	choice_box.add_child(UIKit.wrapped("仓库成员会随本局跨层保留，但本局结束时默认被抛弃；结束时仍留在仓库者不会自动进入永久收藏。", 13, UIKit.BAD))
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


func _resolve_loot(index: int, take: bool) -> void:
	if app.run.resolve_battle_loot(index, take):
		app.autosave()
		_show_next_step()


func _schedule_layout() -> void:
	if layout_queued:
		return
	layout_queued = true
	call_deferred("_fit_layout")


func _fit_layout() -> void:
	layout_queued = false
	if not is_inside_tree():
		return
	_style_choices(choice_box)
	var available := get_viewport_rect().size
	card.custom_minimum_size.x = minf(1080, available.x - 40)
	var fixed_height := page.get_combined_minimum_size().y - choice_scroll.custom_minimum_size.y + 44
	var max_height := maxf(100, available.y - 40 - fixed_height)
	if layout_stage != step_label.text:
		layout_stage = step_label.text
		stage_height = 0.0
	stage_height = maxf(64, choice_box.get_combined_minimum_size().y + 4)
	choice_scroll.custom_minimum_size.y = minf(max_height, stage_height)
	var run: RunState = app.run
	var taken := run.pending_battle_loot.filter(func(offer): return offer.get("status", "") == "taken").size()
	var skipped := run.pending_battle_loot.filter(func(offer): return offer.get("status", "") == "skipped").size()
	progress_label.text = "已领取 %d 项  ·  已放弃 %d 项" % [taken, skipped]
	if continue_button.disabled:
		progress_label.text += "  ·  请先完成当前选择"
	else:
		continue_button.text = "继续探索" if run.region_mode else "继续"
	card.reset_size()


func _style_choices(node: Node) -> void:
	for child in node.get_children():
		if child is Button and not child.has_meta("settlement_styled"):
			_style_button(child, Color("303b4b"), UIKit.TEXT)
			child.add_theme_font_size_override("font_size", 16)
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			child.clip_text = false
			if child.text.contains("\n"):
				child.alignment = HORIZONTAL_ALIGNMENT_LEFT
				child.custom_minimum_size.y = 82
		_style_choices(child)


func _style_button(button: Button, background: Color, foreground: Color) -> void:
	button.set_meta("settlement_styled", true)
	button.custom_minimum_size.y = maxf(44, button.custom_minimum_size.y)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = background
		if state_name == "hover":
			style.bg_color = background.lightened(0.12)
		elif state_name == "pressed":
			style.bg_color = background.darkened(0.10)
		elif state_name == "disabled":
			style.bg_color = Color("2a2e36")
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		if state_name == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color = UIKit.ACCENT
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_color_override("font_disabled_color", Color("737d8a"))


func _reward_description(offer: Dictionary) -> String:
	match String(offer["kind"]):
		"essence":
			return "用于商店购买与技能强化。"
		"relic":
			return RelicDB.description_of(String(offer["id"]))
		"relic_choice":
			return "从三件本局尚未拥有的遗物中选择，也可以放弃。"
		"legendary":
			return "从三个传奇遗物中选择一件，也可以跳过。"
		"item":
			var id := String(offer["id"])
			if id.begins_with(Merchant.BOOK_PREFIX):
				return String(SkillDB.get_def(id.trim_prefix(Merchant.BOOK_PREFIX)).get("desc", "选择伙伴学习招式。"))
			return String(Merchant.ITEMS[id][2])
	return ""


func _choose_settlement_relic(relic_id: String) -> void:
	if processing:
		return
	processing = true
	if app.run.choose_reward(relic_id):
		app.autosave()
		_show_next_step()
	else:
		processing = false




func _show_relic_action_step(run: RunState) -> void:
	var action := run.pending_relic_action()
	match String(action.get("kind", "")):
		"mage_notes":
			_show_mage_notes_step(run)
		"unbalanced_scales":
			_show_unbalanced_step(run)
		"magic_end":
			_show_magic_end_step(run)
		_:
			run.pending_relic_actions.pop_front()
			app.autosave()
			_show_next_step()




func _show_mage_notes_step(run: RunState) -> void:
	var eligible := run.mage_note_eligible_uids()
	var required := mini(3, eligible.size())
	step_label.text = "法师笔记：选择 %d 只宝可梦（%d/%d）" % [required, mage_note_selected.size(), required]
	choice_box.add_child(UIKit.wrapped("每名被选成员会随机学会 1 个尚未掌握的本属性普通技能；新技能进入招式库。", 13))
	if required == 0:
		choice_box.add_child(UIKit.wrapped("当前没有可学习新技能的成员，本次法师笔记自动跳过。", 13, UIKit.TEXT_DIM))
		var skip := UIKit.small_button("跳过法师笔记")
		skip.pressed.connect(func() -> void:
			run.resolve_mage_notes([])
			app.autosave()
			_show_next_step()
		)
		choice_box.add_child(skip)
		continue_button.disabled = true
		return
	for record in run.carried:
		var uid := int(record["uid"])
		var selected := mage_note_selected.has(uid)
		var button := UIKit.small_button("%s %s · 可学 %d 个" % [
			"✓" if selected else "○",
			SpeciesDB.name_of(String(record["species_id"])),
			run.mage_note_candidates(uid).size(),
		])
		button.disabled = selected or run.mage_note_candidates(uid).is_empty()
		button.pressed.connect(func() -> void:
			if not mage_note_selected.has(uid):
				mage_note_selected.append(uid)
			if mage_note_selected.size() >= required:
				var result := run.resolve_mage_notes(mage_note_selected)
				mage_note_selected.clear()
				if bool(result.get("ok", false)):
					app.autosave()
				_show_next_step()
			else:
				_show_next_step()
		)
		choice_box.add_child(button)
	var reset := UIKit.small_button("重置选择")
	reset.disabled = mage_note_selected.is_empty()
	reset.pressed.connect(func() -> void:
		mage_note_selected.clear()
		_show_next_step()
	)
	choice_box.add_child(reset)
	continue_button.disabled = true




func _show_unbalanced_step(run: RunState) -> void:
	step_label.text = "不平天秤：选择 1 件遗物摧毁"
	var candidates := run.unbalanced_candidates()
	if candidates.is_empty():
		run.pending_relic_actions.pop_front()
		app.autosave()
		_show_next_step()
		return
	choice_box.add_child(UIKit.wrapped("摧毁后随机获得 2 件遗物：普通 50%、稀有 30%、传奇 20%。", 13))
	for relic_id in candidates:
		var id := String(relic_id)
		var button := UIKit.small_button("摧毁 %s【%s】\n%s" % [
			RelicDB.name_of(id), RelicDB.rarity_name(id), RelicDB.description_of(id),
		])
		button.pressed.connect(func() -> void:
			var result := run.resolve_unbalanced_scales(id)
			if bool(result.get("ok", false)):
				app.autosave()
			_show_next_step()
		)
		choice_box.add_child(button)
	continue_button.disabled = true




func _show_magic_end_step(run: RunState) -> void:
	if magic_end_uid < 0:
		step_label.text = "术之尽头：选择学习魔法的成员"
		choice_box.add_child(UIKit.wrapped("先选择 1 名我方成员，再从 3 个魔法中选择 1 个。", 13))
		for record in run.carried:
			var uid := int(record["uid"])
			var button := UIKit.small_button("选择 %s" % SpeciesDB.name_of(String(record["species_id"])))
			button.pressed.connect(func() -> void:
				magic_end_uid = uid
				_show_next_step()
			)
			choice_box.add_child(button)
	else:
		var record := run.owned_record_by_uid(magic_end_uid)
		step_label.text = "术之尽头：%s 选择魔法" % SpeciesDB.name_of(String(record.get("species_id", "")))
		for magic_id in ["ultra_death_ray", "time_mirror_leap", "mage_key"]:
			var button := UIKit.small_button("%s\n%s" % [SkillDB.name_of(magic_id), SkillDB.get_def(magic_id).get("desc", "")])
			button.pressed.connect(func() -> void:
				var result := run.resolve_magic_end(magic_end_uid, magic_id)
				magic_end_uid = -1
				if bool(result.get("ok", false)):
					app.autosave()
				_show_next_step()
			)
			choice_box.add_child(button)
	continue_button.disabled = true
