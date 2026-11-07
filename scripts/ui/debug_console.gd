extends Control

## 调试构建专用 F7 面板。所有写操作由 DebugTools 验证。

const DebugActions = preload("res://scripts/debug/debug_tools.gd")

var app = null
var content: VBoxContainer
var feedback: Label
var monster_option: OptionButton
var member_option: OptionButton
var skill_option: OptionButton
var xp_amount: SpinBox
var player_damage: SpinBox
var enemy_damage: SpinBox
var capture_percent: SpinBox


func _ready() -> void:
	name = "DebugConsole"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL)
	panel.custom_minimum_size = Vector2(760, 460)
	center.add_child(panel)
	var column := UIKit.vbox(10)
	panel.add_child(column)
	var header := UIKit.hbox(12)
	column.add_child(header)
	var title := UIKit.label("F7 · 战斗测试控制台", 23, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UIKit.small_button("关闭  F7")
	close.pressed.connect(func() -> void: hide())
	header.add_child(close)
	column.add_child(UIKit.wrapped("仅调试构建可用。首次修改后本局标记为调试局：仍可存档和继续战斗，但本局成果不进入永久收藏或技能统计。伤害与捕获率覆盖仅在本场有效。", 13, UIKit.TEXT_DIM))
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	content = UIKit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	feedback = UIKit.wrapped("选择操作后在这里查看结果。", 14, UIKit.GOOD)
	column.add_child(feedback)
	rebuild()


func rebuild() -> void:
	if content == null:
		return
	UIKit.clear_children(content)
	if app == null or app.current_screen == null:
		return
	match app.current_screen.name:
		"PrepScreen": _build_prep()
		"BattleScreen": _build_battle()
		_: content.add_child(UIKit.wrapped("控制台只在整备选人页与战斗页开放。", 16))


func _build_prep() -> void:
	var run: RunState = app.run
	if run == null:
		return
	content.add_child(UIKit.label("整备：怪物 / 技能 / 经验", 18, UIKit.ACCENT))
	var add_row := UIKit.hbox(8)
	content.add_child(add_row)
	monster_option = OptionButton.new()
	monster_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var species_ids: Array = SpeciesDB.SPECIES.keys()
	species_ids.sort()
	for species_id in species_ids:
		var id := String(species_id)
		if SpeciesDB.is_trainer(id) or id == "tree_summon":
			continue
		monster_option.add_item("%s · %s (%s)" % [SpeciesDB.name_of(id), Elements.name_of(SpeciesDB.element_of(id)), id])
		monster_option.set_item_metadata(monster_option.item_count - 1, id)
	add_row.add_child(monster_option)
	var add_button := UIKit.small_button("加入携带队伍")
	add_button.pressed.connect(_add_monster)
	add_row.add_child(add_button)
	content.add_child(UIKit.wrapped("携带上限 6 只；满员时可先把下面选中的携带怪物移到仓库。", 13, UIKit.TEXT_DIM))
	var member_row := UIKit.hbox(8)
	content.add_child(member_row)
	member_option = OptionButton.new()
	member_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for group in [run.carried, run.storage]:
		for record in group:
			var uid := int(record["uid"])
			var place := "携带" if group == run.carried else "仓库"
			member_option.add_item("%s · %s · Lv.%d · %d XP · UID %d" % [
				place, SpeciesDB.name_of(String(record["species_id"])), int(record.get("level", 1)), int(record.get("xp", 0)), uid,
			])
			member_option.set_item_metadata(member_option.item_count - 1, uid)
	member_row.add_child(member_option)
	var store_button := UIKit.small_button("移入仓库")
	store_button.pressed.connect(_move_to_storage)
	member_row.add_child(store_button)
	var skill_row := UIKit.hbox(8)
	content.add_child(skill_row)
	skill_option = OptionButton.new()
	skill_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skill_ids: Array = SkillDB.DEFS.keys()
	skill_ids.sort()
	for skill_id in skill_ids:
		var id := String(skill_id)
		skill_option.add_item("%s · %s (%s)" % [SkillDB.name_of(id), Elements.name_of(SkillDB.element_of(id)), id])
		skill_option.set_item_metadata(skill_option.item_count - 1, id)
	skill_row.add_child(skill_option)
	var learn_button := UIKit.small_button("让所选怪物学会")
	learn_button.pressed.connect(_add_skill)
	skill_row.add_child(learn_button)
	var xp_row := UIKit.hbox(8)
	content.add_child(xp_row)
	xp_row.add_child(UIKit.label("增加经验", 15))
	xp_amount = SpinBox.new()
	xp_amount.min_value = 1
	xp_amount.max_value = 1000
	xp_amount.value = 10
	xp_amount.rounded = true
	xp_amount.custom_minimum_size.x = 140
	xp_row.add_child(xp_amount)
	var xp_button := UIKit.small_button("给予所选怪物")
	xp_button.pressed.connect(_add_xp)
	xp_row.add_child(xp_button)
	content.add_child(UIKit.wrapped("技能可跨属性学习；装备位有空会自动装备，否则留在招式库。经验按现有 Lv10 上限计算，2、5、7级学习机会按正常战后流程领取，技能强化请找导师。", 13, UIKit.TEXT_DIM))


func _build_battle() -> void:
	var screen = app.current_screen
	var battle: BattleState = screen.state
	content.add_child(UIKit.label("战斗：快速复现与数值覆盖", 18, UIKit.ACCENT))
	var damage_row := UIKit.hbox(8)
	content.add_child(damage_row)
	damage_row.add_child(UIKit.label("我方技能直伤", 14))
	player_damage = _spin(-20, 20, int(battle.debug_skill_damage_bonus.get("player", 0)))
	damage_row.add_child(player_damage)
	damage_row.add_child(UIKit.label("敌方技能直伤", 14))
	enemy_damage = _spin(-20, 20, int(battle.debug_skill_damage_bonus.get("enemy", 0)))
	damage_row.add_child(enemy_damage)
	var damage_button := UIKit.small_button("应用伤害调整")
	damage_button.pressed.connect(_set_damage)
	damage_row.add_child(damage_button)
	content.add_child(UIKit.wrapped("对直接命中的每个单位加减伤害；不改变碰撞、灼烧、寄生或地形伤害。预览与敌方推演也使用该数值。", 13, UIKit.TEXT_DIM))
	var capture_row := UIKit.hbox(8)
	content.add_child(capture_row)
	capture_row.add_child(UIKit.label("捕获成功率 %", 14))
	capture_percent = _spin(-1, 100, battle.debug_capture_percent)
	capture_row.add_child(capture_percent)
	var capture_button := UIKit.small_button("应用捕获率")
	capture_button.pressed.connect(_set_capture)
	capture_row.add_child(capture_button)
	capture_row.add_child(UIKit.wrapped("-1 恢复正常概率；捕获距离与其他合法条件保持原规则。", 13, UIKit.TEXT_DIM))
	var action_row := UIKit.hbox(8)
	content.add_child(action_row)
	var heal := UIKit.small_button("存活己方回满血")
	heal.pressed.connect(func() -> void: _battle_action(DebugActions.heal_players(battle)))
	action_row.add_child(heal)
	var soften := UIKit.small_button("敌人设为 1 HP")
	soften.pressed.connect(func() -> void: _battle_action(DebugActions.soften_enemies(battle)))
	action_row.add_child(soften)
	var win := UIKit.small_button("一键获胜")
	win.pressed.connect(func() -> void: _battle_action(DebugActions.win_battle(battle)))
	action_row.add_child(win)
	content.add_child(UIKit.wrapped("一键获胜走正常战后结算；未击杀或捕获的敌人不会凭空提供相应经验。回满血不会复活濒死单位。", 13, UIKit.TEXT_DIM))


func _spin(low: int, high: int, current: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = current
	spin.rounded = true
	spin.custom_minimum_size.x = 82
	return spin


func _member_uid() -> int:
	return int(member_option.get_selected_metadata()) if member_option != null and member_option.selected >= 0 else -1


func _show_result(result: Dictionary, refresh_prep: bool = false) -> void:
	feedback.text = String(result.get("message", "操作未完成。"))
	feedback.add_theme_color_override("font_color", UIKit.GOOD if bool(result.get("ok", false)) else UIKit.BAD)
	if not bool(result.get("ok", false)):
		return
	if refresh_prep:
		app.prep_deploy_preset = app.current_screen.deploy_selection.duplicate()
		app.show_prep()
		show()
		move_to_front()
		rebuild()
	else:
		app.current_screen.refresh_all()


func _add_monster() -> void:
	_show_result(DebugActions.add_monster(app.run, String(monster_option.get_selected_metadata())), true)
	app.autosave()


func _move_to_storage() -> void:
	_show_result(DebugActions.move_to_storage(app.run, _member_uid()), true)
	app.autosave()


func _add_skill() -> void:
	_show_result(DebugActions.add_skill(app.run, _member_uid(), String(skill_option.get_selected_metadata())), true)
	app.autosave()


func _add_xp() -> void:
	_show_result(DebugActions.add_xp(app.run, _member_uid(), int(xp_amount.value)), true)
	app.autosave()


func _set_damage() -> void:
	var battle: BattleState = app.current_screen.state
	var first := DebugActions.set_damage_bonus(battle, "player", int(player_damage.value))
	var second := DebugActions.set_damage_bonus(battle, "enemy", int(enemy_damage.value))
	_battle_action({"ok": bool(first.get("ok", false)) and bool(second.get("ok", false)), "message": "%s %s" % [first.get("message", ""), second.get("message", "")]})


func _set_capture() -> void:
	_battle_action(DebugActions.set_capture_percent(app.current_screen.state, int(capture_percent.value)))


func _battle_action(result: Dictionary) -> void:
	if bool(result.get("ok", false)) and app.run != null:
		app.run.debug_tainted = true
		app.autosave()
	_show_result(result)
