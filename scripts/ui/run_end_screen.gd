extends Control
const Widgets = preload("res://ui/components/pixel_widgets.gd")

var app = null


func _ready() -> void:
	name = "RunEndScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var column := UIKit.vbox(10)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(column)
	var lost := run.run_lost()
	column.add_child(UIKit.title("本局结束" if lost else "本局通关", 40))
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
	lines.append("仓库替补：%d 只" % run.storage.size())
	if lost:
		lines.append("训练家倒下：本局失败，请从主菜单开始新局。" if run.run_failed else "全员濒死：没有可出战的宝可梦，本局结束。")
	if not run.deaths.is_empty():
		lines.append("—— 战损记录 ——")
		for entry in run.deaths:
			lines.append("%s（第 %d 场，%s）" % [entry.get("name", "?"), int(entry.get("battle", 0)), entry.get("cause", "?")])
	var box := UIKit.panel(UIKit.PANEL)
	box.custom_minimum_size = Vector2(560, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var summary := UIKit.wrapped("\n".join(lines), 15)
	summary.name = "RunEndSummary"
	var report := UIKit.vbox(8)
	box.add_child(report)
	var totals := UIKit.hbox(12)
	report.add_child(totals)
	for entry in [["胜", "victories", "胜利"], ["击", "kills", "击败"], ["捕", "captures", "捕获"], ["逃", "escapes", "逃离"], ["退", "retreats", "撤退"]]:
		totals.add_child(Widgets.stat(entry[0], str(run.stats[entry[1]]), entry[2]))
	report.add_child(HSeparator.new())
	for record in run.carried:
		var member := UIKit.panel(UIKit.PANEL_LIGHT)
		report.add_child(member)
		var body := UIKit.vbox(4)
		member.add_child(body)
		body.add_child(UIKit.label(SpeciesDB.name_of(String(record["species_id"])), 17, UIKit.ACCENT))
		body.add_child(Widgets.health(int(record["hp"]), run.monster_max_hp(record)))
		var stats := UIKit.hbox(12)
		body.add_child(stats)
		stats.add_child(Widgets.stat("级", str(record.get("level", 1)), "本局等级"))
		stats.add_child(Widgets.stat("亲", str(record.get("affinity", 0)), "永久亲密度"))
		stats.add_child(Widgets.stat("刻", "%d/%d" % [run.monster_empty_engraving_slots(record), run.monster_engraving_slots(record)], "空余刻印 / 总槽位"))
	var expand := UIKit.small_button("完整成长与战损记录 ▸")
	expand.toggle_mode = true
	expand.toggled.connect(func(open: bool) -> void:
		summary.visible = open
		expand.text = "完整成长与战损记录 ▾" if open else "完整成长与战损记录 ▸")
	report.add_child(expand)
	summary.hide()
	report.add_child(summary)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	column.add_child(scroll)
	var back := UIKit.button("返回主菜单")
	back.name = "BackToMenuButton"
	back.custom_minimum_size = Vector2(240, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: app.end_run_to_menu())
	column.add_child(back)
