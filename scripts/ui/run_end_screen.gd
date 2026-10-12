extends Control

var app = null


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
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	var lost := run.run_lost()
	column.add_child(UIKit.title("本局结束" if lost else "本局通关", 40))
	var lines: Array = []
	lines.append("完成战斗场次：%d / %d" % [mini(run.battle_index, Balance.BATTLES_PER_RUN), Balance.BATTLES_PER_RUN])
	lines.append("击败：%d　捕获：%d　胜利：%d　逃离：%d　撤退：%d" % [
		int(run.stats["kills"]), int(run.stats["captures"]), int(run.stats["victories"]),
		int(run.stats["escapes"]), int(run.stats["retreats"]),
	])
	lines.append("累计经验：%d　局内强化：%d 项" % [run.exp, run.upgrades_taken.size()])
	var team_names: Array = []
	for record in run.carried:
		team_names.append("%s(%d/%d)" % [
			SpeciesDB.name_of(String(record["species_id"])), int(record["hp"]), SpeciesDB.hp_of(String(record["species_id"])),
		])
	lines.append("存活队伍：" + ("、".join(team_names) if not team_names.is_empty() else "无"))
	lines.append("仓库替补：%d 只" % run.storage.size())
	if lost:
		lines.append("全员濒死：没有可出战的宝可梦，本局结束。")
	if not run.deaths.is_empty():
		lines.append("—— 战损记录 ——")
		for entry in run.deaths:
			lines.append("%s（第 %d 场，%s）" % [entry.get("name", "?"), int(entry.get("battle", 0)), entry.get("cause", "?")])
	var box := UIKit.panel(UIKit.PANEL)
	box.custom_minimum_size = Vector2(560, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(UIKit.wrapped("\n".join(lines), 15))
	column.add_child(box)
	var back := UIKit.button("返回主菜单")
	back.name = "BackToMenuButton"
	back.custom_minimum_size = Vector2(240, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: app.end_run_to_menu())
	column.add_child(back)
