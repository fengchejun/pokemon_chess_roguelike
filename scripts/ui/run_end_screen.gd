extends Control

var app = null
var back_button: Button
var summary_label: Label
var retention_layer: Control
var retention_confirm: Button
var retention_hint: Label
var retention_error: Label
var retention_checks: Array = []
var final_choice_summary := ""


func _ready() -> void:
	name = "RunEndScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var column := UIKit.vbox(10)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(column)
	column.add_child(UIKit.title("本局结束" if run.run_lost() else "本局通关", 40))
	var box := UIKit.panel(UIKit.PANEL)
	box.custom_minimum_size = Vector2(560, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	summary_label = UIKit.wrapped(_summary_text(), 15)
	summary_label.name = "RunEndSummary"
	box.add_child(summary_label)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	column.add_child(scroll)
	back_button = UIKit.button("返回主菜单")
	back_button.name = "BackToMenuButton"
	back_button.disabled = not run.storage.is_empty()
	back_button.custom_minimum_size = Vector2(240, 40)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: app.end_run_to_menu())
	column.add_child(back_button)
	if not run.storage.is_empty():
		_show_storage_retention()


func _summary_text() -> String:
	var run: RunState = app.run
	var lost := run.run_lost()
	var lines: Array = []
	lines.append("完成战斗场次：%d / %d" % [mini(run.battle_index, Balance.BATTLES_PER_RUN), Balance.BATTLES_PER_RUN])
	lines.append("击败：%d　捕获：%d　胜利：%d　逃离：%d　撤退：%d" % [
		int(run.stats["kills"]), int(run.stats["captures"]), int(run.stats["victories"]),
		int(run.stats["escapes"]), int(run.stats["retreats"]),
	])
	lines.append("经验由每只怪物独立累计；等级与强化在新局重置，亲密度永久保留。")
	lines.append("剩余消耗卡：%d 张（本局结束后清除）" % run.reward_inventory.size())
	lines.append("永久首领之血：%d 份（5 份可在未来合成首领血浆）" % app.collection.boss_blood)
	if run.pending_bonus_choices > 0:
		lines.append("旧存档待领额外选择：%d 次（本局结束后清除）" % run.pending_bonus_choices)
	lines.append("本局携带队伍：" if not run.carried.is_empty() else "本局携带队伍：无")
	for record in run.carried:
		var level := int(record.get("level", 1))
		var engraving_total := run.monster_engraving_slots(record)
		var engraving_empty := run.monster_empty_engraving_slots(record)
		lines.append("- %s：本局 Lv.%d · 经验 %d/%d · 生命 %d/%d · 刻印槽 %d/%d · 亲密度 %d" % [
			SpeciesDB.name_of(String(record["species_id"])), level,
			int(record.get("xp", 0)), MonsterProgression.threshold_for_level(level + 1),
			int(record["hp"]), run.monster_max_hp(record),
			engraving_empty, engraving_total, int(record.get("affinity", 0)),
		])
		var upgrade_names: Array = []
		for upgrade_id in record.get("upgrades_taken", []):
			var info: Dictionary = RunState.upgrade_info(String(upgrade_id))
			if not info.is_empty():
				upgrade_names.append(String(info.get("name", upgrade_id)))
		lines.append("  本局强化：%s" % ("、".join(upgrade_names) if not upgrade_names.is_empty() else "尚无"))
		if bool(record.get("trait_upgrade_claimed", false)):
			lines.append("  特性强化：已领取（具体效果待配置）")
	lines.append("仓库替补：%d 只%s" % [
		run.storage.size(), "（最终结算时默认抛弃）" if not run.storage.is_empty() else "",
	])
	lines.append("携带队伍会自动进入永久收藏；仓库成员只有最终勾选者才会保留。")
	if final_choice_summary != "":
		lines.append(final_choice_summary)
	if lost:
		lines.append("训练家倒下：本局失败，请从主菜单开始新局。" if run.run_failed else "全员濒死：没有可出战的宝可梦，本局结束。")
	if not run.deaths.is_empty():
		lines.append("—— 战损记录 ——")
		for entry in run.deaths:
			lines.append("%s（第 %d 场，%s）" % [entry.get("name", "?"), int(entry.get("battle", 0)), entry.get("cause", "?")])
	return "\n".join(lines)


func _show_storage_retention() -> void:
	if retention_layer != null or app.run.storage.is_empty():
		return
	retention_layer = ColorRect.new()
	retention_layer.name = "RunEndStorageRetention"
	retention_layer.color = Color(0.02, 0.03, 0.06, 0.88)
	retention_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	retention_layer.z_index = 80
	retention_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(retention_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	retention_layer.add_child(center)
	var card := UIKit.panel(UIKit.PANEL_LIGHT)
	card.custom_minimum_size = Vector2(720, 520)
	center.add_child(card)
	var column := UIKit.vbox(10)
	card.add_child(column)
	column.add_child(UIKit.title("最终保留选择", 28))
	var notice := UIKit.wrapped("仓库中的 %d 只宝可梦默认会被抛弃，不会进入永久收藏。想稳定保留时，应在结束对局前到营地将其换入携带名单；此处勾选仅作为最终例外保留。" % app.run.storage.size(), 15, UIKit.BAD)
	notice.name = "RunEndStorageRetentionText"
	column.add_child(notice)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	retention_checks.clear()
	for record in app.run.storage:
		var uid := int(record.get("uid", -1))
		var check := CheckBox.new()
		check.name = "RetainStorage_%d" % uid
		check.text = "%s · Lv.%d · 生命 %d/%d · 亲密度 %d" % [
			SpeciesDB.name_of(String(record["species_id"])), int(record.get("level", 1)),
			int(record["hp"]), app.run.monster_max_hp(record), int(record.get("affinity", 0)),
		]
		check.add_theme_font_size_override("font_size", 16)
		check.button_pressed = false
		check.toggled.connect(func(_pressed: bool) -> void: _update_retention_hint())
		list.add_child(check)
		retention_checks.append(check)
	retention_hint = UIKit.label("", 15, UIKit.ACCENT)
	retention_hint.name = "RunEndStorageRetentionHint"
	column.add_child(retention_hint)
	retention_error = UIKit.wrapped("", 14, UIKit.BAD)
	retention_error.name = "RunEndStorageRetentionError"
	column.add_child(retention_error)
	retention_confirm = UIKit.button("", 17)
	retention_confirm.name = "ConfirmRunEndStorageButton"
	retention_confirm.pressed.connect(_confirm_storage_retention)
	column.add_child(retention_confirm)
	_update_retention_hint()


func _selected_storage_uids() -> Array:
	var selected: Array = []
	for check in retention_checks:
		if check.button_pressed:
			selected.append(String(check.name).trim_prefix("RetainStorage_").to_int())
	return selected


func _update_retention_hint() -> void:
	var retained := _selected_storage_uids().size()
	var discarded: int = app.run.storage.size() - retained
	retention_hint.text = "已勾选保留 %d 只；未勾选并抛弃 %d 只。" % [retained, discarded]
	retention_confirm.text = "保留所选并结束" if retained > 0 else "全部抛弃并结束"


func _confirm_storage_retention() -> void:
	var selected := _selected_storage_uids()
	var result: Dictionary = app.resolve_run_end_storage(selected)
	if not bool(result.get("ok", false)):
		retention_error.text = String(result.get("reason", "无法完成最终结算。"))
		return
	final_choice_summary = "最终保留选择：保留 %d 只，抛弃 %d 只；本次新增 %d 条永久收藏。" % [
		int(result.get("retained", 0)), int(result.get("discarded", 0)), int(result.get("added", 0)),
	]
	retention_layer.visible = false
	back_button.disabled = false
	summary_label.text = _summary_text()
