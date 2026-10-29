extends Control

var app = null


func _ready() -> void:
	name = "SupplyScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	var summary := run.apply_supply_recovery()
	app.autosave()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var columns := UIKit.hbox(16)
	margin.add_child(columns)
	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UIKit.label("补给点 · 完成第 %d 场后" % run.battle_index, 26, UIKit.ACCENT))
	left.add_child(UIKit.wrapped("冒险＝从开始战斗到回到基地；每完成 %d 场进入补给点。出战怪物不自动回血，携带名单中的留守者每场恢复 50%% 最大生命，濒死者留守一场后恢复到 5 HP；仓库成员与训练家按现有规则回满。" % Balance.SUPPLY_INTERVAL, 14))
	left.add_child(_summary_box(summary))
	left.add_child(UIKit.label("出战列表（%d/%d）" % [run.carried.size(), Balance.CARRIED_LIMIT], 17, UIKit.ACCENT))
	var team_scroll := UIKit.scroll()
	left.add_child(team_scroll)
	var team_box := UIKit.vbox(6)
	team_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_scroll.add_child(team_box)
	for record in run.carried:
		var row := UIKit.panel(UIKit.PANEL_LIGHT)
		var line := UIKit.hbox(10)
		row.add_child(line)
		var species_id := String(record["species_id"])
		line.add_child(UIKit.label(SpeciesDB.name_of(species_id), 16))
		line.add_child(UIKit.element_chip(SpeciesDB.element_of(species_id)))
		var level := int(record.get("level", 1))
		var progress := UIKit.label("本局 Lv.%d · 经验 %d/%d · 生命 %d/%d · 亲密度 %d" % [
			level, int(record.get("xp", 0)), MonsterProgression.threshold_for_level(level + 1),
			int(record["hp"]), run.monster_max_hp(record), int(record.get("affinity", 0)),
		], 14, UIKit.TEXT_DIM)
		progress.name = "SupplyGrowth_%d" % int(record["uid"])
		line.add_child(progress)
		team_box.add_child(row)
	if run.carried.is_empty():
		team_box.add_child(UIKit.label("没有可出战的宝可梦。", 16, UIKit.BAD))
	var right := UIKit.vbox(8)
	right.custom_minimum_size = Vector2(430, 0)
	columns.add_child(right)
	right.add_child(_archive_box(run))
	var storage_box := UIKit.panel(UIKit.PANEL)
	var storage_column := UIKit.vbox(4)
	storage_box.add_child(storage_column)
	storage_column.add_child(UIKit.label("仓库（%d/%d）" % [run.storage.size(), Balance.STORAGE_LIMIT], 17, UIKit.ACCENT))
	storage_column.add_child(UIKit.wrapped("仓库成员不参战、不受战损；本局暂无可用的调换入口。", 13))
	right.add_child(storage_box)
	var next_supply := _next_supply(run)
	var hint := UIKit.label("", 14, UIKit.TEXT_DIM)
	if next_supply > 0:
		hint.text = "下次补给点：完成第 %d 场战斗后。" % next_supply
	else:
		hint.text = "本局不再有补给点（最后一场结束后本局结算）。"
	right.add_child(hint)
	var leave := UIKit.button("继续出发", 18)
	var supply_box := UIKit.vbox(5)
	right.add_child(supply_box)
	var supply_choices := run.supply_choices()
	if supply_choices.is_empty():
		supply_box.add_child(UIKit.wrapped("本次消耗卡已领取。旧背包中的卡仍可在战前使用。", 13, UIKit.TEXT_DIM))
	else:
		supply_box.add_child(UIKit.label("免费补给 · 消耗卡三选一", 17, UIKit.ACCENT))
		for candidate in supply_choices:
			var item_id := String(candidate)
			var pick := UIKit.button("%s\n%s" % [RewardDB.name_of(item_id), RewardDB.description_of(item_id)], 13)
			pick.custom_minimum_size = Vector2(0, 68)
			pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var normal_style := StyleBoxFlat.new()
			normal_style.bg_color = UIKit.PANEL_LIGHT
			normal_style.border_color = UIKit.ACCENT.darkened(0.35)
			normal_style.set_border_width_all(1)
			normal_style.set_corner_radius_all(6)
			normal_style.set_content_margin_all(10)
			pick.add_theme_stylebox_override("normal", normal_style)
			var hover_style := normal_style.duplicate() as StyleBoxFlat
			hover_style.bg_color = UIKit.PANEL_LIGHT.lightened(0.18)
			pick.add_theme_stylebox_override("hover", hover_style)
			pick.name = "SupplyChoice_%s" % item_id.replace(":", "_")
			pick.pressed.connect(func() -> void:
				if app.run.choose_supply_item(item_id):
					app.autosave()
					for child in supply_box.get_children():
						child.queue_free()
					supply_box.add_child(UIKit.wrapped("已领取：%s" % RewardDB.name_of(item_id), 14, UIKit.GOOD))
					leave.disabled = false
			)
			supply_box.add_child(pick)
	leave.name = "LeaveSupplyButton"
	leave.disabled = not supply_choices.is_empty()
	leave.pressed.connect(func() -> void: app.leave_supply())
	right.add_child(leave)


func _summary_box(summary: Dictionary) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var from_hp := int(summary.get("trainer_from", 0))
	var to_hp := int(summary.get("trainer_to", 0))
	if to_hp > from_hp:
		box.add_child(UIKit.wrapped("补给结果：训练家 %d → %d（+50%% 生命上限）。" % [from_hp, to_hp], 15, UIKit.GOOD))
	else:
		box.add_child(UIKit.wrapped("补给结果：训练家状态完好（%d/%d）。" % [to_hp, int(SpeciesDB.get_species("trainer").get("hp", 7))], 15))
	return box


func _archive_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(4)
	box.add_child(column)
	column.add_child(UIKit.label("战损记录（倒下即濒死，基地休养后恢复）", 16, UIKit.BAD))
	if run.deaths.is_empty():
		column.add_child(UIKit.label("尚无战损。", 13, UIKit.TEXT_DIM))
	else:
		var lines: Array = []
		for entry in run.deaths:
			lines.append("- %s（第 %d 场，%s）" % [entry.get("name", "?"), int(entry.get("battle", 0)), entry.get("cause", "?")])
		column.add_child(UIKit.wrapped("\n".join(lines), 13))
	return box


func _next_supply(run: RunState) -> int:
	var completed := run.battle_index
	var next_index := completed - completed % Balance.SUPPLY_INTERVAL + Balance.SUPPLY_INTERVAL
	return next_index if next_index < Balance.BATTLES_PER_RUN else 0
