extends Control

var app = null
var state: BattleState = null
var deploy_uids: Array = []

var board: BoardView = null
var selected_uid: int = 0
var viewed_enemy_uid: int = 0
var aim_skill: String = ""
var aim_entries: Array = []
var aim_cells: Array = []
var capture_mode := false
var busy := false
var settled_reported := false

var round_label: Label = null
var status_label: Label = null
var unit_title: Label = null
var unit_body: Label = null
var skill_box: VBoxContainer = null
var capture_button: Button = null
var end_turn_button: Button = null
var undo_button: Button = null
var threat_check: CheckBox = null
var hint_label: Label = null
var forecast_list: VBoxContainer = null
var log_label: RichTextLabel = null


func _ready() -> void:
	name = "BattleScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var columns := UIKit.hbox(12)
	margin.add_child(columns)
	# 棋盘列
	var board_column := UIKit.vbox(6)
	columns.add_child(board_column)
	board = BoardView.new()
	board.name = "BoardView"
	board.cell_clicked.connect(_on_board_clicked)
	board.cell_right_clicked.connect(func(_cell: Vector2i) -> void: _clear_aim())
	board.cell_hovered.connect(_on_board_hovered)
	board_column.add_child(board)
	hint_label = UIKit.label("点击己方单位开始行动；右键/Esc 取消瞄准。", 13, UIKit.TEXT_DIM)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(GridSpec.W * BoardView.TILE, 0)
	board_column.add_child(hint_label)
	# 信息与行动列
	var main_column := UIKit.vbox(8)
	main_column.custom_minimum_size = Vector2(400, 0)
	columns.add_child(main_column)
	main_column.add_child(_header_box())
	main_column.add_child(_unit_box())
	main_column.add_child(_skill_box())
	main_column.add_child(_action_row())
	main_column.add_child(_forecast_box())
	# 日志列
	var log_column := UIKit.vbox(6)
	log_column.custom_minimum_size = Vector2(236, 0)
	columns.add_child(log_column)
	log_column.add_child(UIKit.label("战斗日志", 17, UIKit.ACCENT))
	var log_scroll := UIKit.scroll()
	log_column.add_child(log_scroll)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(220, 0)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_scroll.add_child(log_label)
	board.set_from_state(state)
	refresh_all()


func _header_box() -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(2)
	box.add_child(column)
	round_label = UIKit.label("", 19, UIKit.ACCENT)
	column.add_child(round_label)
	status_label = UIKit.label("", 13, UIKit.TEXT_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	return box


func _unit_box() -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(2)
	box.add_child(column)
	unit_title = UIKit.label("", 17)
	column.add_child(unit_title)
	unit_body = UIKit.label("", 13, UIKit.TEXT_DIM)
	unit_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(unit_body)
	return box


func _skill_box() -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(4)
	box.add_child(column)
	column.add_child(UIKit.label("技能与行动", 15, UIKit.ACCENT))
	skill_box = UIKit.vbox(4)
	column.add_child(skill_box)
	return box


func _action_row() -> Control:
	var column := UIKit.vbox(4)
	var row1 := UIKit.hbox(6)
	column.add_child(row1)
	undo_button = UIKit.small_button("撤回移动")
	undo_button.name = "UndoButton"
	undo_button.pressed.connect(do_undo)
	row1.add_child(undo_button)
	end_turn_button = UIKit.small_button("结束回合")
	end_turn_button.name = "EndTurnButton"
	end_turn_button.pressed.connect(do_end_turn)
	row1.add_child(end_turn_button)
	var row2 := UIKit.hbox(6)
	column.add_child(row2)
	threat_check = CheckBox.new()
	threat_check.name = "ThreatCheck"
	threat_check.text = "显示威胁预告"
	threat_check.add_theme_font_size_override("font_size", 13)
	threat_check.toggled.connect(_on_threat_toggled)
	row2.add_child(threat_check)
	return column


func _forecast_box() -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(3)
	box.add_child(column)
	column.add_child(UIKit.label("威胁预告（敌方下一步）", 15, UIKit.ACCENT))
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	forecast_list = UIKit.vbox(2)
	forecast_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(forecast_list)
	return box


# ---------------------------------------------------------------- 刷新


func refresh_all() -> void:
	state.check_battle_end()
	board.set_from_state(state)
	board.selected_uid = selected_uid
	board.clear_overlays()
	_update_header()
	_update_unit_card()
	_rebuild_skill_buttons()
	_update_action_buttons()
	_update_forecast()
	_update_log()
	_update_selection_overlay()
	if state.ended and not settled_reported:
		settled_reported = true
		call_deferred("_report_end")


func _update_header() -> void:
	var phase_text: String = {"player": "我方行动", "enemy": "敌方行动", "settle": "结算", "ended": "战斗结束"}.get(state.phase, state.phase)
	round_label.text = "第 %d/%d 回合 · %s" % [maxi(1, state.round), Balance.MAX_ROUNDS, phase_text]
	var reward_text := ""
	match String(state.reward.get("state", "")):
		"map":
			reward_text = "　奖励待守点"
		"guarding":
			reward_text = "　奖励守点中"
		"carried":
			reward_text = "　奖励已持有（守护持有者）"
		"lost":
			reward_text = "　奖励因持有者倒下而失去"
		"destroyed":
			reward_text = "　奖励已摧毁"
	status_label.text = "敌人剩余 %d｜已击败 %d｜已捕获 %d%s" % [
		state.alive_enemy_count(), state.enemy_kills.size(), state.captured.size(), reward_text,
	]


func _update_unit_card() -> void:
	var unit: CombatUnit = null
	if selected_uid != 0:
		unit = state.unit_by_uid(selected_uid)
	elif viewed_enemy_uid != 0:
		unit = state.unit_by_uid(viewed_enemy_uid)
	if unit == null:
		unit_title.text = "未选择单位"
		unit_body.text = "点击己方单位进行移动或施放技能；点击敌人查看信息。"
		return
	var side_text := "我方" if unit.side == "player" else "野生"
	unit_title.text = "%s（%s · %s）" % [unit.display_name, side_text, Elements.FULL_NAMES.get(unit.element, "无属性")]
	var lines: Array = []
	lines.append("生命 %d/%d　移动 %d（基础 %d）" % [unit.hp, unit.max_hp, state.move_budget_for(unit), unit.move_points])
	if Elements.MATCHUPS_ENABLED:
		lines.append(Elements.counter_hint(unit.element))
	var statuses: Array = []
	var aura_names: Array = []
	for aura_element in unit.attachments.keys():
		aura_names.append("%s×%d" % [Elements.name_of(String(aura_element)), (unit.attachments[aura_element] as Array).size()])
	if not aura_names.is_empty():
		statuses.append("附着：" + "、".join(aura_names))
	if unit.parasite_until_round >= state.round:
		statuses.append("寄生：技能命中时攻击者按实际伤害回复")
	if unit.rock_guard_until_round >= state.round:
		statuses.append("岩护：技能直伤 −1")
	if unit.burn_ticks > 0:
		statuses.append("灼烧 %d 回合" % unit.burn_ticks)
	if unit.root_pending:
		statuses.append("定身待生效")
	if unit.move_cancelled:
		statuses.append("本回合被定身")
	if unit.slow_ticks > 0:
		statuses.append("浸湿（移动 -1）")
	if unit.shock_ticks > 0:
		statuses.append("感电")
	if unit.paralyzed_ticks > 0:
		statuses.append("麻痹")
	if unit.frozen:
		statuses.append("冰冻")
	if unit.channel_lock_round > state.round:
		statuses.append("吟唱中：第 %d 回合本方阶段结算，届时不能行动" % unit.channel_lock_round)
	elif unit.channel_lock_round == state.round:
		statuses.append("吟唱代价：本阶段不能行动")
	if unit.vine_ticks > 0:
		statuses.append("藤蔓束缚")
	if unit.haste_ticks > 0:
		statuses.append("加速 +2")
	if unit.extra_casts > 0:
		statuses.append("额外施法 %d 次" % unit.extra_casts)
	for buff_id in unit.battle_buffs:
		statuses.append("本场 Buff：%s" % BattleBuffDB.name_of(String(buff_id)))
	if String(state.reward.get("state", "")) == "carried" and int(state.reward.get("owner_uid", -1)) == unit.uid:
		statuses.append("持有战场奖励：战斗结束前须存活")
	if statuses.is_empty():
		statuses.append("无")
	lines.append("状态：" + "、".join(statuses))
	lines.append("本回合移动：%s" % _move_status(unit))
	if unit.is_trainer:
		lines.append("本回合捕获机会：%s" % ("已使用" if unit.capture_used else "可用"))
	else:
		lines.append("本回合技能：%s" % ("可用" if unit.can_act_skill() else "已用或受限"))
	if unit.side == "enemy":
		var low_hp_rules := bool(state.capture_options.get("capture_low_hp", false))
		lines.append("捕获概率：%d%%（训练家在周围八格可尝试%s）" % [
			CaptureSystem.chance_percent(unit, low_hp_rules), "，目标需不高于半血" if low_hp_rules else "",
		])
		if unit.fresh_spawn:
			lines.append("本回合新生成：在巢穴出口待机，不能移动或施法")
	for skill_id in unit.skills:
		var id := String(skill_id)
		var used_text := "（本场已用尽）" if not unit.can_use_in_battle(id) else ""
		lines.append("· %s%s：%s" % [SkillDB.name_of(id), used_text, SkillDB.get_def(id).get("desc", "")])
	unit_body.text = "\n".join(lines)


func _move_status(unit: CombatUnit) -> String:
	if not unit.is_alive():
		return "无法移动（已倒下）"
	if unit.moved:
		return "已用"
	if unit.frozen:
		return "无法移动（冰冻）"
	if unit.paralyzed_ticks > 0:
		return "无法移动（麻痹）"
	if unit.vine_ticks > 0:
		return "无法移动（藤蔓束缚）"
	if unit.move_cancelled:
		return "无法移动（本回合被定身或施法锁定）"
	if unit.effective_move() <= 0:
		return "无法移动（移动力为 0）"
	return "可用"


func _rebuild_skill_buttons() -> void:
	UIKit.clear_children(skill_box)
	var unit := state.unit_by_uid(selected_uid)
	if unit == null or not unit.is_alive():
		skill_box.add_child(UIKit.label("选择己方单位后显示技能。", 13, UIKit.TEXT_DIM))
		return
	if unit.is_trainer:
		var trainer_text := "训练家不施放技能；每回合可在周围八格尝试捕获一次。"
		skill_box.add_child(UIKit.wrapped(trainer_text, 13))
	capture_button = null
	if unit.is_trainer:
		capture_button = UIKit.small_button("捕获（周围八格）")
		capture_button.name = "CaptureButton"
		var targets := _capture_targets(unit)
		capture_button.disabled = unit.capture_used or targets.is_empty()
		capture_button.pressed.connect(_on_capture_pressed)
		skill_box.add_child(capture_button)
	for skill_id in unit.skills:
		var id := String(skill_id)
		var def := SkillDB.get_def(id)
		var button_text := "%s（%s）" % [def.get("name", id), _skill_tag(id, unit)]
		if not unit.can_use_in_battle(id):
			button_text += "·本场已用"
		var button := UIKit.small_button(button_text)
		button.name = "SkillButton_%s" % id
		button.tooltip_text = String(def.get("desc", ""))
		if state.round >= Balance.MAX_ROUNDS and (id == "fire_burst" or id == "lightning"):
			button.tooltip_text += "\n第 %d 回合开始吟唱无法在本场结算。" % Balance.MAX_ROUNDS
		button.toggle_mode = true
		button.button_pressed = aim_skill == id
		var entries := state.skill_targets(unit, id)
		if not unit.can_act_skill():
			button.disabled = true
			button.tooltip_text += "\n（本回合无法施法）"
		elif not unit.can_use_in_battle(id):
			button.disabled = true
			button.tooltip_text += "\n（本场使用次数已耗尽）"
		elif entries.is_empty():
			button.disabled = true
			button.tooltip_text += "\n（蒸汽中无法施法）" if state.steam_cells.has(unit.cell) else "\n（当前没有有效目标）"
		button.pressed.connect(func() -> void: _on_skill_pressed(id))
		skill_box.add_child(button)


func _skill_tag(skill_id: String, unit: CombatUnit) -> String:
	var def := SkillDB.get_def(skill_id)
	var parts: Array = []
	var damage := int(def.get("damage", 0))
	if damage > 0:
		parts.append("伤害 %d" % damage)
	var kind := String(def.get("kind", ""))
	if kind == "ray":
		parts.append("射线 %d-%d" % [int(def.get("min_range", 1)), int(def.get("max_range", 8))])
	elif kind == "multi_cell":
		parts.append("选 3 格 · 距离 ≤%d" % int(def.get("range", 5)))
	elif kind == "unit":
		var actual_range := int(def.get("range", 1))
		if SkillDB.is_placeholder(skill_id):
			actual_range += int(unit.upgrades.get(skill_id + "_range", 0))
		elif skill_id == "rock_break" or skill_id == "double_cast":
			actual_range += int(unit.upgrades.get(skill_id + "_range", 0))
		parts.append("射程 %d" % actual_range)
	elif kind == "cell":
		parts.append("落点 %d" % int(def.get("range", 3)))
	elif kind == "charge":
		parts.append("跃迁 2 格")
	elif kind == "teleport":
		parts.append("瞬移 %d" % int(def.get("range", 2)))
	elif kind == "direction":
		parts.append("方向")
	if parts.is_empty():
		parts.append("辅助")
	return " · ".join(parts)


func _update_action_buttons() -> void:
	if threat_check != null:
		var enabled := true
		if app != null and app.run != null:
			enabled = bool(app.run.options.get("threat_preview", true))
		threat_check.set_pressed_no_signal(enabled)
	if end_turn_button != null:
		end_turn_button.disabled = busy or state.ended or state.phase != BattleState.PHASE_PLAYER
	if undo_button != null:
		undo_button.disabled = busy or not state.can_undo()


func _update_selection_overlay() -> void:
	var unit := state.unit_by_uid(selected_uid)
	if unit != null and unit.side == "player" and state.phase == BattleState.PHASE_PLAYER and not state.ended and not busy:
		if aim_skill == "" and not capture_mode and unit.can_move_now():
			board.movement_cells = state.move_options(unit)
	elif viewed_enemy_uid != 0:
		var enemy := state.unit_by_uid(viewed_enemy_uid)
		if enemy != null and enemy.is_alive():
			var options := PathFinder.stop_cells(state, enemy)
			var cells: Array = []
			for cell in options:
				cells.append(cell)
			board.enemy_cells_view = cells


func _update_forecast() -> void:
	if forecast_list == null:
		return
	UIKit.clear_children(forecast_list)
	var enabled := true
	if app != null and app.run != null:
		enabled = bool(app.run.options.get("threat_preview", true))
	for cast in state.pending_casts:
		var caster := state.unit_by_uid(int(cast["uid"]))
		var caster_name := caster.display_name if caster != null else "?"
		forecast_list.add_child(UIKit.wrapped("蓄力警示：%s 的%s，第 %d 回合%s阶段命中 %s" % [
			caster_name, SkillDB.name_of(String(cast["skill_id"])), int(cast["due_round"]),
			"我方" if String(cast["side"]) == "player" else "敌方", str(cast["cells"]),
		], 12, UIKit.BAD))
	if not enabled:
		forecast_list.add_child(UIKit.label("普通威胁预告已关闭；蓄力警示始终显示。", 12, UIKit.TEXT_DIM))
		return
	if state.ended:
		forecast_list.add_child(UIKit.label("战斗已结束。", 12, UIKit.TEXT_DIM))
		return
	if state.phase != BattleState.PHASE_PLAYER:
		forecast_list.add_child(UIKit.label("敌方行动中……", 12, UIKit.TEXT_DIM))
		return
	var plan := state.forecast()
	if plan.is_empty():
		forecast_list.add_child(UIKit.label("敌方没有可执行的行动。", 12, UIKit.TEXT_DIM))
		return
	for action in plan:
		var line := EnemyAI.describe(action, state)
		var detail := _action_detail(action)
		var text := line
		if detail != "":
			text += "　[%s]" % detail
		var label := UIKit.wrapped(text, 12, UIKit.TEXT)
		forecast_list.add_child(label)
		_mark_action_on_board(action)


func _action_detail(action: Dictionary) -> String:
	var meta: Dictionary = action.get("meta", {})
	if meta.is_empty():
		return ""
	var parts: Array = []
	for hit in meta.get("hits", []):
		var text := "%s 受伤 %d" % [hit.get("name", "?"), int(hit.get("damage", 0))]
		if int(hit.get("modifier", 0)) != 0:
			text += "（%s）" % ("克制 +1" if int(hit["modifier"]) > 0 else "逆克制 -1")
		if bool(hit.get("killed", false)):
			text += "（致死）"
		if hit.get("push") != null and bool(hit["push"].get("death", false)):
			text += "（推入致死地形）"
		parts.append(text)
	if meta.get("self_death", false):
		parts.append("自毁")
	return "；".join(parts)


func _mark_action_on_board(action: Dictionary) -> void:
	var meta: Dictionary = action.get("meta", {})
	var path: Array = action.get("move_path", [])
	if not path.is_empty():
		var dest: Vector2i = path[path.size() - 1]
		board.markers.append({"cell": dest, "kind": "text", "text": "移", "color": Color(1, 0.6, 0.5, 0.9), "size": 14})
	if meta.is_empty():
		return
	for hit in meta.get("hits", []):
		var hit_cell: Vector2i = hit.get("cell", Vector2i(-1, -1))
		if not GridSpec.is_inside(hit_cell):
			continue
		if bool(hit.get("killed", false)):
			board.markers.append({"cell": hit_cell, "kind": "lethal"})
		else:
			board.markers.append({"cell": hit_cell, "kind": "damage", "text": str(int(hit.get("damage", 0)))})
		var push = hit.get("push")
		if push != null:
			var from_cell: Vector2i = push.get("from", Vector2i(-1, -1))
			var to_cell: Vector2i = push.get("to", Vector2i(-1, -1))
			if GridSpec.is_inside(from_cell) and GridSpec.is_inside(to_cell) and from_cell != to_cell:
				board.arrows.append({"from": from_cell, "to": to_cell, "color": Color(1.0, 0.45, 0.35, 0.9)})
	var self_move = meta.get("self_move")
	if self_move != null and meta.get("caster_uid", -1) >= 0:
		var caster := state.unit_by_uid(int(meta["caster_uid"]))
		var from: Vector2i = caster.cell if caster != null else Vector2i(-1, -1)
		if GridSpec.is_inside(from) and GridSpec.is_inside(self_move):
			board.arrows.append({"from": from, "to": self_move, "color": Color(1.0, 0.7, 0.2, 0.9)})


func _update_log() -> void:
	if log_label == null:
		return
	log_label.text = "\n".join(state.events)


# ---------------------------------------------------------------- 交互


func _on_board_clicked(cell: Vector2i) -> void:
	if busy or state.ended:
		return
	var occupant := state.unit_at(cell)
	if capture_mode:
		if occupant != null and occupant.side == "enemy":
			do_capture(occupant.uid)
		else:
			_clear_aim()
		return
	if aim_skill != "":
		_try_cast_at(cell)
		return
	if occupant != null and occupant.side == "player":
		select_unit(occupant.uid)
		return
	if occupant != null:
		viewed_enemy_uid = occupant.uid
		selected_uid = 0
		board.clear_overlays()
		_update_unit_card()
		_update_selection_overlay()
		board.queue_redraw()
		return
	# 空地形：移动或查看
	var unit := state.unit_by_uid(selected_uid)
	if unit != null and unit.can_move_now() and state.move_options(unit).has(cell):
		do_move(cell)
		return
	_show_terrain(cell)


func _on_board_hovered(cell: Vector2i) -> void:
	if busy or state.ended:
		return
	board.path_cells = []
	board.area_cells = []
	board.ray_cells = []
	board.arrows = []
	if aim_skill != "":
		var unit := state.unit_by_uid(selected_uid)
		var entry := _find_entry(cell)
		if aim_skill == "lightning":
			if not entry.is_empty() and not aim_cells.has(cell):
				hint_label.text = "闪电落点 %d/3：选中 (%d,%d)；已锁定 %s" % [aim_cells.size() + 1, cell.x, cell.y, str(aim_cells)]
				board.area_cells = aim_cells + [cell]
			else:
				hint_label.text = "闪电需选三个不同且距施法者不超过 5 格的落点。"
			board.queue_redraw()
			return
		if unit != null and not entry.is_empty():
			var preview := state.preview_skill(unit, aim_skill, entry)
			if bool(preview.get("ok", false)):
				var matchup: Array = []
				for hit in preview.get("hits", []):
					if int(hit.get("modifier", 0)) != 0:
						matchup.append("%s %s" % [hit.get("name", "?"), "克制 +1" if int(hit["modifier"]) > 0 else "逆克制 -1"])
					if String(hit.get("reaction", "")) != "":
						matchup.append("%s 触发%s" % [hit.get("name", "?"), hit["reaction"]])
				hint_label.text = "%s：%s%s" % [SkillDB.name_of(aim_skill), preview.get("text", ""), "｜" + "、".join(matchup) if not matchup.is_empty() else ""]
				hint_label.add_theme_color_override("font_color", UIKit.TEXT)
				_preview_overlays(preview)
				board.queue_redraw()
				return
		hint_label.text = "无效目标，右键或 Esc 取消瞄准。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		board.queue_redraw()
		return
	if capture_mode:
		var trainer := state.unit_by_uid(selected_uid)
		var occupant := state.unit_at(cell)
		if trainer != null and occupant != null and CaptureSystem.in_range(trainer, occupant):
			if trainer.capture_used:
				hint_label.text = "本回合已尝试过捕获。"
			elif not CaptureSystem.can_attempt(state, trainer, occupant):
				hint_label.text = "当前设置要求目标生命不高于一半。"
			else:
				hint_label.text = "捕获 %s：成功率 %d%%（生命 %d/%d）" % [
					occupant.display_name, CaptureSystem.chance_percent(occupant, bool(state.capture_options.get("capture_low_hp", false))), occupant.hp, occupant.max_hp,
				]
			hint_label.add_theme_color_override("font_color", UIKit.TEXT)
		board.queue_redraw()
		return
	if bool(state.nest.get("alive", false)) and (state.nest.get("exits", []) as Array).has(cell):
		var occupant := state.unit_at(cell)
		var detail := "空置" if occupant == null else "敌方守口：1 点伤害无效，2 点以上命中掉 1 耐久" if occupant.side == "enemy" else "我方堵口，产怪排队"
		if occupant == null and (Balance.nest_warning_due(state.round) or int(state.nest.get("pending_waves", 0)) > 0):
			detail += "；%s" % ("末轮仍有积压，本场不再产怪" if state.round >= Balance.MAX_ROUNDS else "下回合将尝试产怪")
		hint_label.text = "巢穴唯一出口：%s。" % detail
		hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	var unit := state.unit_by_uid(selected_uid)
	if unit != null and unit.can_move_now():
		var options := state.move_options(unit)
		if options.has(cell):
			board.path_cells = [unit.cell] + (options[cell]["path"] as Array)
			hint_label.text = "移动到 (%d,%d)，消耗 %d 移动力（移动优先撤回）" % [cell.x, cell.y, int(options[cell]["cost"])]
			hint_label.add_theme_color_override("font_color", UIKit.TEXT)
	board.queue_redraw()


func _preview_overlays(preview: Dictionary) -> void:
	board.ray_cells = preview.get("ray_cells", [])
	board.area_cells = preview.get("area_cells", [])
	for hit in preview.get("hits", []):
		var hit_cell: Vector2i = hit.get("cell", Vector2i(-1, -1))
		if not GridSpec.is_inside(hit_cell):
			continue
		if bool(hit.get("killed", false)):
			board.markers.append({"cell": hit_cell, "kind": "lethal"})
		else:
			board.markers.append({"cell": hit_cell, "kind": "damage", "text": str(int(hit.get("damage", 0)))})
		var push = hit.get("push")
		if push != null:
			var from_cell: Vector2i = push.get("from", Vector2i(-1, -1))
			var to_cell: Vector2i = push.get("to", Vector2i(-1, -1))
			if GridSpec.is_inside(from_cell) and GridSpec.is_inside(to_cell) and from_cell != to_cell:
				board.arrows.append({"from": from_cell, "to": to_cell, "color": Color(1.0, 0.45, 0.35)})
	if preview.get("self_move") != null:
		var unit := state.unit_by_uid(selected_uid)
		if unit != null:
			board.arrows.append({"from": unit.cell, "to": preview["self_move"], "color": Color(1.0, 0.8, 0.3)})
	for change in preview.get("terrain_changes", []):
		board.markers.append({
			"cell": change["cell"], "kind": "text", "text": "变%s" % TerrainDB.name_of(int(change["to"])),
			"color": Color(0.5, 0.9, 1.0), "size": 12,
		})


func _show_terrain(cell: Vector2i) -> void:
	var value := state.terrain_at(cell)
	var lines: Array = ["地块 (%d,%d)：%s" % [cell.x, cell.y, TerrainDB.name_of(value)], TerrainDB.DESCRIPTIONS.get(value, "")]
	if state.obstacle_durability.has(cell):
		var max_hp := Balance.TREE_DURABILITY if value == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
		lines.append("障碍耐久：%d/%d；树木和岩障会截断射线。" % [int(state.obstacle_durability[cell]), max_hp])
	if state.steam_cells.has(cell):
		lines.append("蒸汽：剩余 %d 次整轮结算；站在其中不能施放技能。" % int(state.steam_cells[cell]))
	if state.is_nest_cell(cell):
		lines.append("巢穴耐久：%d/3（第 2、4、6 回合各尝试生成 1 只；堵口排队）" % int(state.nest.get("hp", 3)))
		lines.append("敌人守住出口时，单次 1 点伤害无效；2 点以上命中仍只掉 1 耐久。我方堵口不提供防御。")
	if bool(state.nest.get("alive", false)) and (state.nest.get("exits", []) as Array).has(cell):
		var holder := state.unit_at(cell)
		var status := "空置"
		if holder != null:
			status = "敌方守口：1 伤无效" if holder.side == "enemy" else "我方堵口：延迟产怪"
		elif int(state.nest.get("pending_waves", 0)) > 0:
			status = "待产怪：末轮无法继续补产" if state.round >= Balance.MAX_ROUNDS else "待产怪：下回合尝试出现"
		elif Balance.nest_warning_due(state.round):
			status = "预警：下回合将产怪"
		lines.append("巢穴唯一出口：%s。积压 %d 只。" % [status, int(state.nest.get("pending_waves", 0))])
	if cell == state.reward.get("cell", Vector2i(-1, -1)):
		match String(state.reward.get("state", "")):
			"map", "guarding":
				lines.append("奖励格：我方在结束行动时站上去，敌方行动结束时仍活着且站在此格即可取得奖励。受伤但存活不妨碍守点；持有者须活到战斗结束。")
			"carried":
				lines.append("奖励已由我方持有；持有者活到战斗结束可记录一次额外战后三选一。")
			"lost", "destroyed":
				lines.append("本场奖励已失去。")
	if state.fruits.has(cell):
		lines.append("恢复果实：拾取回复 2 生命。")
	unit_title.text = "地块信息"
	unit_body.text = "\n".join(lines)


func select_unit(uid: int) -> void:
	selected_uid = uid
	viewed_enemy_uid = 0
	board.selected_uid = uid
	_clear_aim()
	board.clear_overlays()
	_update_unit_card()
	_rebuild_skill_buttons()
	_update_selection_overlay()
	board.queue_redraw()


func _on_skill_pressed(skill_id: String) -> void:
	if busy or state.ended:
		return
	var unit := state.unit_by_uid(selected_uid)
	if unit == null or not unit.can_act_skill() or not unit.can_use_in_battle(skill_id):
		return
	if aim_skill == skill_id:
		_clear_aim()
		return
	aim_skill = skill_id
	aim_cells = []
	capture_mode = false
	aim_entries = state.skill_targets(unit, skill_id)
	board.clear_overlays()
	for entry in aim_entries:
		var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
		if GridSpec.is_inside(cell):
			board.attack_cells.append(cell)
	hint_label.text = "瞄准：%s。%s右键或 Esc 取消。" % [SkillDB.name_of(skill_id), "依次点击三个不同金色格；" if skill_id == "lightning" else "点击金色格；"]
	if state.round >= Balance.MAX_ROUNDS and (skill_id == "fire_burst" or skill_id == "lightning"):
		hint_label.text += " 第 %d 回合开始吟唱将不会在本场结算。" % Balance.MAX_ROUNDS
	hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	_rebuild_skill_buttons()
	board.queue_redraw()


func _on_capture_pressed() -> void:
	if busy or state.ended:
		return
	var trainer := state.unit_by_uid(selected_uid)
	if trainer == null or not trainer.is_trainer or trainer.capture_used:
		return
	capture_mode = true
	aim_skill = ""
	aim_cells = []
	board.clear_overlays()
	for enemy in _capture_targets(trainer):
		board.attack_cells.append(enemy.cell)
	hint_label.text = "捕获：点击周围八格内的合法目标。"
	hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	board.queue_redraw()


func _clear_aim() -> void:
	if aim_skill == "" and not capture_mode:
		return
	aim_skill = ""
	aim_cells = []
	capture_mode = false
	aim_entries = []
	board.clear_overlays()
	hint_label.text = "已取消瞄准。"
	hint_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_rebuild_skill_buttons()
	_update_selection_overlay()
	board.queue_redraw()


func _find_entry(cell: Vector2i) -> Dictionary:
	for entry in aim_entries:
		var entry_cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
		if entry_cell == cell:
			return entry
	return {}


func _try_cast_at(cell: Vector2i) -> void:
	var entry := _find_entry(cell)
	if entry.is_empty():
		hint_label.text = "该格不在技能有效范围内。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		return
	if aim_skill == "lightning":
		if aim_cells.has(cell):
			hint_label.text = "闪电三个落点不能重复。"
			return
		aim_cells.append(cell)
		board.area_cells = aim_cells.duplicate()
		if aim_cells.size() < 3:
			hint_label.text = "闪电已选 %d/3 格；右键或 Esc 可取消。" % aim_cells.size()
			board.queue_redraw()
			return
		var chosen := aim_cells.duplicate()
		if not do_cast("lightning", {"type": "multi", "cells": chosen}):
			aim_cells = chosen.slice(0, 2)
		return
	do_cast(aim_skill, entry)


func _capture_targets(unit: CombatUnit) -> Array:
	var result: Array = []
	for enemy in state.alive_units("enemy"):
		if CaptureSystem.can_attempt(state, unit, enemy):
			result.append(enemy)
	return result


# ---------------------------------------------------------------- 行动入口（测试可直接调用）


func do_move(cell: Vector2i) -> bool:
	if busy or state.ended:
		return false
	var unit := state.unit_by_uid(selected_uid)
	if unit == null:
		return false
	if not state.move_unit(unit, cell):
		return false
	app.sync_and_save(state)
	viewed_enemy_uid = 0
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_cast(skill_id: String, entry: Dictionary) -> bool:
	if busy or state.ended:
		return false
	var unit := state.unit_by_uid(selected_uid)
	if unit == null:
		return false
	var result := state.cast_skill(unit, skill_id, entry)
	if not bool(result.get("ok", false)):
		hint_label.text = "技能无法施放。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		return false
	aim_skill = ""
	aim_entries = []
	aim_cells = []
	capture_mode = false
	app.sync_and_save(state)
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_capture(target_uid: int) -> bool:
	if busy or state.ended:
		return false
	var trainer := state.unit_by_uid(selected_uid)
	var target := state.unit_by_uid(target_uid)
	if trainer == null or target == null:
		return false
	var result := state.capture_attempt(trainer, target)
	if not bool(result.get("ok", false)):
		hint_label.text = "无法捕获：目标须在周围八格，本回合尚未尝试，且满足当前生命规则。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		return false
	capture_mode = false
	app.sync_and_save(state)
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_undo() -> bool:
	if busy or state.ended:
		return false
	if not state.undo_last_move():
		return false
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_end_turn() -> void:
	if busy or state.ended or state.phase != BattleState.PHASE_PLAYER:
		return
	_clear_aim()
	board.clear_overlays()
	_enemy_phase()


func _enemy_phase() -> void:
	busy = true
	_update_action_buttons()
	state.begin_enemy_phase()
	_update_header()
	_update_forecast()
	_update_log()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
		board.set_from_state(state)
		_update_header()
		_update_log()
		app.sync_and_save(state)
		if state.ended:
			break
		await get_tree().create_timer(0.42).timeout
	if not state.ended:
		state.end_enemy_phase()
		app.sync_and_save(state)
	busy = false
	if selected_uid != 0:
		var unit := state.unit_by_uid(selected_uid)
		if unit == null or not unit.is_alive():
			selected_uid = 0
	board.clear_overlays()
	refresh_all()
	hint_label.text = "已进入第 %d 回合（我方行动）。" % maxi(1, state.round)
	hint_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)


func _refresh_after_action() -> void:
	board.set_from_state(state)
	_update_header()
	_update_unit_card()
	_rebuild_skill_buttons()
	_update_action_buttons()
	_update_forecast()
	_update_log()
	_update_selection_overlay()
	board.queue_redraw()
	if state.ended and not settled_reported:
		settled_reported = true
		call_deferred("_report_end")


func report_end_now() -> void:
	if state != null and state.ended and app != null:
		app.finish_battle(state)


func _report_end() -> void:
	if state != null and state.ended and is_inside_tree():
		app.finish_battle(state)


func _on_threat_toggled(pressed: bool) -> void:
	if app != null and app.run != null:
		app.run.options["threat_preview"] = pressed
		app.autosave()
	board.clear_overlays()
	board.set_from_state(state)
	_update_forecast()
	board.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_clear_aim()
