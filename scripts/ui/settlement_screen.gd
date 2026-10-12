extends Control

var app = null

var battle: BattleState = null
var outcome: Dictionary = {}
var upgrade_pending := false
var rng := RandomNumberGenerator.new()
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
	rng.seed = hash("settle_ui:%d:%d" % [run.seed, run.battle_index])
	upgrade_pending = run.pending_upgrades()
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
		lines.append("本场经验：+%d（击败与捕获各 2 点；合计 %d）" % [int(outcome.get("exp", 0)), run.exp])
	lines.append("击败：%d　捕获：%d" % [battle.enemy_kills.size(), battle.captured.size()])
	if battle.captured.size() > 0:
		var names: Array = []
		for entry in battle.captured:
			names.append(SpeciesDB.name_of(String(entry["species_id"])))
		lines.append("捕获待处理：" + "、".join(names))
	var flee_penalty: Array = outcome.get("flee_penalty", [])
	if not flee_penalty.is_empty():
		var punished: Array = []
		for entry in flee_penalty:
			punished.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("失败惩罚（出战宝可梦生命减半）：" + "；".join(punished))
	if int(outcome.get("carrier_exp", 0)) > 0:
		lines.append("奖励携带者存活至结算：额外 +%d 经验" % int(outcome["carrier_exp"]))
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
	if battle.deaths.size() > 0:
		lines.append("—— 本场濒死（留守基地一场后恢复）——")
		for entry in battle.deaths:
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
	if upgrade_pending:
		step_label.text = "局内强化（只卖新解法）"
		for upgrade_id in run.upgrade_choices(rng):
			choice_box.add_child(_upgrade_choice(String(upgrade_id)))
		continue_button.disabled = true
		return
	if run.environment_reward_pending:
		step_label.text = "地图构筑卡（三选一，影响后续战场）"
		for card_id in run.environment_choices():
			var id := String(card_id)
			var card := MapCardDB.get_card(id)
			var button := UIKit.button("%s\n%s" % [card.get("name", id), card.get("desc", "")], 14)
			button.name = "EnvironmentChoice_%s" % id
			button.pressed.connect(func() -> void:
				if app.run.choose_environment_card(id):
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(button)
		continue_button.disabled = true
		return
	step_label.text = "全部处理完成，可以进入下一场。"
	choice_box.add_child(UIKit.wrapped("战斗结算顺序已完成：经验 → 捕获 → 奖励携带者经验 → 濒死记录 → 下一场准备。" , 13))
	continue_button.disabled = false


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


func _upgrade_choice(upgrade_id: String) -> Control:
	var info: Dictionary = RunState.UPGRADES[upgrade_id]
	var button := UIKit.button("%s\n%s" % [info["name"], info["desc"]], 14)
	button.custom_minimum_size = Vector2(0, 64)
	button.pressed.connect(func() -> void:
		if processing or not upgrade_pending:
			return
		processing = true
		app.run.take_upgrade(upgrade_id)
		upgrade_pending = false
		app.autosave()
		_show_next_step()
	)
	return button
