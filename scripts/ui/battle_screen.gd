extends Control

var app = null
var state: BattleState = null
var deploy_uids: Array = []

var board: BoardView = null
var feedback_layer: Control = null
var speech_layer: Control = null
var battle_notice: Control = null
var victory_announced := false
var skill_banner: PanelContainer = null
var playback: Control = null
var speed_button: Button = null
var selected_uid: int = 0
var viewed_enemy_uid: int = 0
var action_mode: String = "main" # main / move / skills；仅界面状态，不写入战斗快照。
var aim_skill: String = ""
var aim_entries: Array = []
var aim_cells: Array = []
var aim_first_uid: int = 0
var capture_mode := false
var busy := false
var settled_reported := false

var round_label: Label = null
var status_label: Label = null
var unit_title: Label = null
var unit_body: Label = null
var unit_health: ProgressBar = null
var skill_box: VBoxContainer = null
var capture_button: Button = null
var end_turn_button: Button = null
var undo_button: Button = null
var leave_node_button: Button = null
var hint_label: Label = null
var log_label: RichTextLabel = null
var menu_button: Button = null
var action_panel: Control = null
var merchant_actions_open := false
var unit_panel: Control = null
var terrain_panel: Control = null
var terrain_label: Label = null
var terrain_scroll: ScrollContainer = null
var objective_panel: Control = null
var relic_panel: PanelContainer = null
var relic_list: VBoxContainer = null
var relic_scroll: ScrollContainer = null
var objective_label: Label = null
var corner_top_left: Control = null
var team_panel: Control = null
var team_list: VBoxContainer = null
var team_scroll: ScrollContainer = null
var modal_layer: ColorRect = null
var item_aim: String = ""
var hovered_uid: int = 0
var corner_cards_swapped := false


func _ready() -> void:
	name = "BattleScreen"
	victory_announced = state.exploration_started or GridSpec.is_inside(state.boss_portal_cell)
	battle_notice = preload("res://scripts/ui/battle_notice.gd").new()
	add_child(battle_notice)
	battle_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.fill_background(self)
	board = BoardView.new()
	board.name = "BoardView"
	board.cell_clicked.connect(_on_board_clicked)
	board.cell_double_clicked.connect(_on_board_double_clicked)
	board.cell_right_clicked.connect(func(_cell: Vector2i) -> void: _cancel_action())
	board.cell_hovered.connect(_on_board_hovered)
	add_child(board)
	feedback_layer = preload("res://scripts/ui/battle_feedback.gd").new()
	feedback_layer.name = "BattleFeedback"
	board.add_child(feedback_layer)
	feedback_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speech_layer = preload("res://scripts/ui/speech_bubbles.gd").new()
	speech_layer.screen = self
	add_child(speech_layer)
	speech_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_notice.started.connect(func() -> void: speech_layer.set_suppressed(true))
	battle_notice.finished.connect(func() -> void: speech_layer.set_suppressed(false))
	skill_banner = preload("res://scripts/ui/skill_banner.gd").new()
	add_child(skill_banner)
	playback = preload("res://scripts/ui/battle_playback.gd").new()
	playback.screen = self
	board.add_child(playback)
	playback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state.presentation_started.connect(playback.begin)
	state.presentation_finished.connect(playback.finish)
	state.feedback.connect(_on_feedback)
	state.enable_feedback()
	state.enemy_defeated.connect(_on_enemy_defeated)
	state.enemy_captured.connect(_on_enemy_captured)
	hint_label = UIKit.label("点击己方单位开始行动；右键/Esc 取消瞄准。", 13, UIKit.TEXT_DIM)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint_label)
	var top_left := UIKit.vbox(6)
	corner_top_left = top_left
	add_child(top_left)
	menu_button = UIKit.small_button("☰ 菜单")
	menu_button.pressed.connect(_open_menu)
	top_left.add_child(menu_button)
	speed_button = UIKit.small_button("速度：%d×" % int(app.battle_playback_speed))
	speed_button.pressed.connect(_toggle_speed)
	top_left.add_child(speed_button)
	top_left.add_child(_header_box())
	top_left.add_child(_action_row())
	top_left.set_meta("corner", "top_left")
	team_panel = UIKit.panel(UIKit.PANEL)
	add_child(team_panel)
	var team_column := UIKit.vbox(4)
	team_panel.add_child(team_column)
	team_column.add_child(UIKit.label("我方队伍", 15, UIKit.ACCENT))
	team_list = UIKit.vbox(3)
	team_scroll = ScrollContainer.new()
	team_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	team_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_scroll.add_child(team_list)
	team_column.add_child(team_scroll)
	objective_panel = UIKit.panel(UIKit.PANEL)
	add_child(objective_panel)
	objective_label = UIKit.label("战斗目标", 15, UIKit.ACCENT)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size.x = 270
	objective_panel.add_child(objective_label)
	objective_panel.set_meta("corner", "top_right")
	relic_panel = UIKit.panel(UIKit.PANEL)
	relic_panel.name = "RelicBonusPanel"
	add_child(relic_panel)
	var relic_column := UIKit.vbox(5)
	relic_panel.add_child(relic_column)
	relic_column.add_child(UIKit.label("遗物加成", 15, UIKit.ACCENT))
	relic_scroll = ScrollContainer.new()
	relic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	relic_column.add_child(relic_scroll)
	relic_list = UIKit.vbox(5)
	relic_list.custom_minimum_size.x = 250
	relic_scroll.add_child(relic_list)
	unit_panel = _unit_box()
	add_child(unit_panel)
	unit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_panel.set_meta("corner", "bottom_left")
	terrain_panel = UIKit.panel(UIKit.PANEL)
	add_child(terrain_panel)
	terrain_label = UIKit.label("悬停地块查看信息", 13, UIKit.TEXT_DIM)
	terrain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terrain_label.custom_minimum_size.x = 258
	terrain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_scroll = ScrollContainer.new()
	terrain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	terrain_scroll.add_child(terrain_label)
	terrain_panel.add_child(terrain_scroll)
	terrain_panel.set_meta("corner", "bottom_right")
	action_panel = _skill_box()
	# 行动浮窗高于棋盘及侧栏；菜单等模态窗口仍在其上方。
	action_panel.z_index = 10
	add_child(action_panel)
	var log_scroll := UIKit.scroll()
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(220, 0)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_scroll.add_child(log_label)
	log_scroll.visible = false
	add_child(log_scroll)
	board.set_from_state(_display_state())
	refresh_all()
	resized.connect(_layout_overlays)
	call_deferred("_layout_overlays")
	state.check_speech_events()
	app.sync_and_save(state)
	call_deferred("_announce_initial_phase")


func _on_feedback(event: Dictionary) -> void:
	if event["kind"] == "speech" and playback.frames.is_empty():
		_show_feedback(event)
	else:
		playback.capture(event)


func _show_feedback(event: Dictionary) -> void:
	if event["kind"] == "collision":
		return # 接触字样由播放层放在撞击点；只为伤害显示单位飘字，避免重叠。
	if event["kind"] == "speech":
		speech_layer.push(event)
	elif event["kind"] == "skill":
		skill_banner.present(String(event["text"]))
	else:
		feedback_layer.push(event)


func _playback_active() -> bool:
	return (playback != null and playback.active()) or (battle_notice != null and battle_notice.active())

func _display_state() -> BattleState:
	return playback.visual if playback != null and playback.active() else state

func _toggle_speed() -> void:
	app.battle_playback_speed = 2.0 if app.battle_playback_speed == 1.0 else 1.0
	speed_button.text = "速度：%d×" % int(app.battle_playback_speed)

func _render_playback(snapshot: BattleState) -> void:
	board.set_from_state(snapshot)
	board.clear_overlays()
	_update_header()
	_update_team_list()
	_update_unit_card()
	_update_channel_markers()
	_update_log()
	_update_action_buttons()
	action_panel.visible = false

func _playback_finished() -> void:
	_check_victory_notice()
	_update_action_buttons()
	_rebuild_skill_buttons()
	_position_action_panel()

func _wait_playback() -> void:
	while (_playback_active() or modal_layer != null) and is_inside_tree():
		await get_tree().process_frame


func _on_enemy_defeated(_entry: Dictionary) -> void:
	if app != null and app.run != null:
		app.run.sync_from_battle(state)

func _on_enemy_captured(_entry: Dictionary) -> void:
	if app != null and app.run != null:
		app.run.sync_from_battle(state)


func _process(_delta: float) -> void:
	if battle_notice != null:
		battle_notice.playback_speed = app.battle_playback_speed
	if speech_layer != null:
		speech_layer.set_suppressed(modal_layer != null or (battle_notice != null and battle_notice.active()))
	if feedback_layer != null:
		feedback_layer.playback_speed = app.battle_playback_speed
		feedback_layer.paused = modal_layer != null
	if unit_panel == null or terrain_panel == null:
		return
	var pointer := get_global_mouse_position()
	if not corner_cards_swapped and unit_panel.get_global_rect().has_point(pointer):
		corner_cards_swapped = true
		_layout_corner_cards()
	elif corner_cards_swapped and pointer.y < size.y - 160.0:
		corner_cards_swapped = false
		_layout_corner_cards()


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
	unit_health = ProgressBar.new()
	unit_health.custom_minimum_size = Vector2(230, 12)
	unit_health.show_percentage = false
	column.add_child(unit_health)
	unit_body = UIKit.label("", 13, UIKit.TEXT_DIM)
	unit_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_body.visible = false
	column.add_child(unit_body)
	return box


func _skill_box() -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(4)
	box.add_child(column)
	column.add_child(UIKit.label("行动", 15, UIKit.ACCENT))
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
	if state.node_kind == "event":
		end_turn_button.text = "结束回合（收集）"
	end_turn_button.name = "EndTurnButton"
	end_turn_button.pressed.connect(do_end_turn)
	row1.add_child(end_turn_button)
	leave_node_button = UIKit.small_button("返回区域")
	leave_node_button.name = "LeaveNodeButton"
	leave_node_button.pressed.connect(do_leave_node)
	column.add_child(leave_node_button)
	return column


func _layout_overlays() -> void:
	if board == null or size.x <= 0 or size.y <= 0:
		return
	var side_space := 310.0
	var board_size := minf(size.y - 100.0, size.x - side_space * 2.0)
	var factor := maxf(0.5, board_size / (GridSpec.W * BoardView.TILE))
	board.scale = Vector2.ONE * factor
	board.position = Vector2((size.x - GridSpec.W * BoardView.TILE * factor) * 0.5, (size.y - GridSpec.H * BoardView.TILE * factor) * 0.5)
	corner_top_left.position = Vector2(14, 12)
	corner_top_left.custom_minimum_size.x = side_space - 28.0
	objective_panel.position = Vector2(size.x - side_space + 10.0, 12)
	objective_panel.custom_minimum_size = Vector2(side_space - 24.0, 105)
	relic_panel.position = Vector2(size.x - side_space + 10.0, 130)
	relic_panel.custom_minimum_size.x = side_space - 24.0
	relic_scroll.custom_minimum_size = Vector2(260, minf(170.0, maxf(50.0, size.y * 0.22)))
	relic_panel.reset_size()
	_fit_relic_panel()
	team_panel.position = Vector2(14, maxf(178, corner_top_left.position.y + corner_top_left.get_combined_minimum_size().y + 10))
	team_panel.custom_minimum_size.x = side_space - 28.0
	_fit_team_panel()
	_layout_corner_cards()
	hint_label.position = Vector2(board.position.x, size.y - 34)
	hint_label.custom_minimum_size.x = board_size
	_position_action_panel()


func _layout_corner_cards() -> void:
	var side_space := 310.0
	unit_panel.position = Vector2(size.x - side_space + 10.0 if corner_cards_swapped else 14.0, size.y - 136.0)
	unit_panel.custom_minimum_size = Vector2(side_space - 28.0, 92)
	terrain_panel.position = Vector2(14.0 if corner_cards_swapped else size.x - side_space + 10.0, size.y - 136.0)
	terrain_panel.custom_minimum_size = Vector2(side_space - 24.0, 120)
	_fit_terrain_panel()


func _fit_terrain_panel() -> void:
	if terrain_scroll == null or terrain_label == null:
		return
	var available := maxf(120.0, size.y - maxf(270.0, relic_panel.position.y + relic_panel.size.y + 28.0))
	var height := clampf(terrain_label.get_minimum_size().y + 24.0, 120.0, available)
	terrain_scroll.custom_minimum_size = Vector2(266, height - 20.0)
	terrain_panel.custom_minimum_size.y = height
	terrain_panel.size = Vector2(286, height)
	terrain_panel.position.y = size.y - height - 16.0


func _position_action_panel() -> void:
	if action_panel == null or board == null:
		return
	action_panel.visible = (selected_uid > 0 or merchant_actions_open) and action_mode != "move" and item_aim == "" and aim_skill == "" and not capture_mode and not busy and not _playback_active() and not state.ended and state.phase == BattleState.PHASE_PLAYER
	if not action_panel.visible:
		return
	var unit := state.unit_by_uid(selected_uid)
	if unit == null and not merchant_actions_open:
		action_panel.visible = false
		return
	var panel_width := 220.0
	action_panel.custom_minimum_size.x = panel_width
	var anchor_cell: Vector2i = state.merchant["cell"] if merchant_actions_open else unit.cell
	var cell_screen := board.position + (Vector2(anchor_cell) + Vector2.ONE) * BoardView.TILE * board.scale.x
	var x := cell_screen.x + 8.0
	if x + panel_width > size.x - 12.0:
		x = board.position.x + anchor_cell.x * BoardView.TILE * board.scale.x - panel_width - 8.0
	action_panel.position = Vector2(clampf(x, 8.0, size.x - panel_width - 8.0), clampf(cell_screen.y - 70.0, 8.0, size.y - 260.0))


# ---------------------------------------------------------------- 刷新


func refresh_all() -> void:
	state.check_battle_end()
	_check_victory_notice()
	if playback != null and not playback.active():
		playback.visual = state.clone()
	board.set_from_state(_display_state())
	board.selected_uid = selected_uid
	board.clear_overlays()
	_update_header()
	_update_relic_panel()
	_update_team_list()
	_update_unit_card()
	_rebuild_skill_buttons()
	_update_action_buttons()
	_update_channel_markers()
	_update_log()
	_update_selection_overlay()
	_position_action_panel()
	if state.ended and not settled_reported:
		settled_reported = true
		call_deferred("_report_end")


func _update_team_list() -> void:
	var state := _display_state()
	if team_list == null:
		return
	UIKit.clear_children(team_list)
	for unit in state.units:
		if unit.side != "player":
			continue
		var entry := UIKit.small_button("%s  HP %d/%d" % [unit.display_name, unit.hp, unit.max_hp])
		entry.disabled = not unit.is_alive()
		entry.add_theme_color_override("font_color", UIKit.ACCENT if unit.uid == selected_uid else UIKit.TEXT)
		var uid: int = unit.uid
		entry.pressed.connect(func() -> void: select_unit(uid))
		team_list.add_child(entry)
		if unit.summon_owner_uid < 0 and app != null and app.run != null:
			_add_battle_xp_bar(unit)
	call_deferred("_fit_team_panel")


func _fit_team_panel() -> void:
	if team_scroll == null or team_panel == null:
		return
	team_scroll.custom_minimum_size = Vector2(262, minf(team_list.get_combined_minimum_size().y, maxf(70, size.y - team_panel.position.y - 180)))
	team_panel.reset_size()


func _add_battle_xp_bar(unit: CombatUnit) -> void:
	var state := _display_state()
	if unit.summon_owner_uid >= 0 or not state.experience_recipients.has(unit.uid):
		return
	var level := unit.combat_level
	var gained := int(state.experience_gains.get(unit.uid, 0))
	var total := unit.combat_xp
	var target_level := level
	var floor_xp := MonsterProgression.threshold_for_level(level)
	var next_xp := MonsterProgression.threshold_for_level(level + 1)
	var caption := "Lv.%d · XP %d/%d · 本场 +%d" % [level, total - floor_xp, next_xp - floor_xp, gained]
	if not unit.is_alive():
		caption = "濒死 · Lv.%d · 已保留经验 %d" % [level, total]
	elif level >= MonsterProgression.MAX_LEVEL:
		caption = "Lv.%d · 已满级" % level
	var label := UIKit.label(caption, 12, UIKit.GOOD if target_level > level else UIKit.TEXT_DIM)
	label.name = "BattleXPText_%d" % unit.uid
	team_list.add_child(label)
	var bar := ProgressBar.new()
	bar.name = "BattleXP_%d" % unit.uid
	bar.custom_minimum_size = Vector2(0, 7)
	bar.show_percentage = false
	bar.max_value = maxi(1, next_xp - floor_xp)
	bar.value = bar.max_value if level >= MonsterProgression.MAX_LEVEL else maxi(0, total - floor_xp)
	bar.tooltip_text = "击败与捕获经验即时入账，等级和生命立即成长；濒死保留此前经验，之后不再获得。2、5、7级的学招在战后选择。"
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("59b8e8")
	bar.add_theme_stylebox_override("fill", fill)
	team_list.add_child(bar)


func _update_header() -> void:
	var state := _display_state()
	var phase_text: String = {"player": "我方行动", "enemy": "敌方行动", "settle": "结算", "ended": "战斗结束"}.get(state.phase, state.phase)
	var region_name := "收集区" if state.node_kind == "event" else "首领区" if state.node_kind == "boss" else "%d/6 战" % (BattleDB.local_battle_of(state.battle_index) + 1)
	round_label.text = "第 %d 层 · %s\n第 %d 回合 · %s" % [BattleDB.floor_of(state.battle_index) + 1, region_name, maxi(1, state.round), phase_text]
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
	reward_text = "奖励待拾取 %d · 我方持有 %d · 敌方携带 %d" % [state.all_rewards().filter(func(p): return p.get("state") in ["map", "guarding"]).size(), state.reward_count_held("player"), state.reward_count_held("enemy")]
	status_label.text = "敌人剩余 %d｜已击败 %d｜已捕获 %d%s" % [
		state.alive_enemy_count(), state.enemy_kills.size(), state.captured.size(), reward_text,
	]
	status_label.visible = false
	objective_label.text = "战斗目标\n敌人 %d · 击败 %d · 捕获 %d" % [state.alive_enemy_count(), state.enemy_kills.size(), state.captured.size()]
	if state.corruption_active:
		objective_label.text += "\n敌军黑化：生命/威力+10%\n击杀无经验 · 天雷仍生效"
	elif not state.is_free_exploration():
		objective_label.text += "\n第8轮末敌军黑化"
	if state.has_live_nests():
		var guards := 0
		for current in state.all_nests():
			guards += state.nest_guard_charges(current["cell"])
		objective_label.text += "\n巢穴守军：%d 名分担伤害" % guards
	if state.node_kind == "event":
		objective_label.text = "收集区\n本次收集食物 %d\n可随时返回区域" % state.food_collected
	if state.sheltered_boss() != null:
		objective_label.text = "首领已回巢 · 巢内庇护\n摧毁主巢穴（剩余 %d HP）\n破巢后可继续攻击或捕获。" % int(state.nest.get("hp", 0))
	if GridSpec.is_inside(state.boss_portal_cell):
		objective_label.text = "首领已击败 · 敌军撤离\n训练师相邻后，点击传送门或行动按钮前往下一层。"
	elif not state.is_free_exploration() and state.round >= 7:
		objective_label.text += "\n" + ("天雷已锁定 %d 格：本轮末落雷，伤害为最大生命50%%，可误伤敌人。" % state.storm_strikes.size() if not state.storm_strikes.is_empty() else "第8轮末开始预告天雷，可移动躲避。")
	if state.is_free_exploration():
		objective_label.text += "\n自由探索 · 无限行动 · 禁止恢复"
	objective_label.text += "\n宝箱 %d · 待拾 %d · 我持 %d · 敌持 %d" % [state.chests.size(), state.all_rewards().filter(func(p): return p.get("state") in ["map", "guarding"]).size(), state.reward_count_held("player"), state.reward_count_held("enemy")]
	if not state.can_leave_node() and state.node_kind != "boss" and state.boss_uid < 0:
		objective_label.text += "\n部署/撤离区：绿色框\n区外%d名：撤离损失25%%最大生命" % state.escape_stragglers().size()
	objective_label.text += "\n原质 %d%s" % [app.run.essence + state.essence_earned - self.state.essence_applied, " · 捕获辅助生效" if state.capture_aid else ""]


func _update_relic_panel() -> void:
	if relic_list == null:
		return
	UIKit.clear_children(relic_list)
	var stacks: Dictionary = _display_state().relic_stacks
	var owned: Array = []
	for relic_id in stacks:
		if RelicDB.rank(stacks, String(relic_id)) > 0:
			owned.append(String(relic_id))
	owned.sort()
	if owned.is_empty():
		relic_list.add_child(UIKit.wrapped("暂无遗物", 13, UIKit.TEXT_DIM))
	else:
		for relic_id in owned:
			var rank := RelicDB.rank(stacks, relic_id)
			var line := UIKit.wrapped("%s Lv.%d  %s" % [RelicDB.display_name_of(relic_id), rank, RelicDB.description_of(relic_id)], 12, UIKit.TEXT)
			line.custom_minimum_size.x = 248
			relic_list.add_child(line)
	call_deferred("_fit_relic_panel")


func _fit_relic_panel() -> void:
	if relic_list == null or relic_scroll == null:
		return
	objective_panel.reset_size()
	relic_panel.position.y = maxf(130.0, objective_panel.position.y + objective_panel.size.y + 10.0)
	relic_scroll.custom_minimum_size.y = minf(170.0, maxf(34.0, relic_list.get_combined_minimum_size().y))
	relic_panel.reset_size()
	_fit_terrain_panel()


func _update_unit_card() -> void:
	var state := _display_state()
	if unit_title == null:
		return
	var unit: CombatUnit = null
	if hovered_uid != 0:
		unit = state.unit_by_uid(hovered_uid)
	if unit == null and selected_uid != 0:
		unit = state.unit_by_uid(selected_uid)
	elif unit == null and viewed_enemy_uid != 0:
		unit = state.unit_by_uid(viewed_enemy_uid)
	if unit == null:
		unit_title.text = "未选择单位"
		unit_health.value = 0
		unit_body.text = "点击己方单位进行移动或施放技能；点击敌人查看信息。"
		return
	var side_text := "我方" if unit.side == "player" else "野生"
	unit_title.text = "%s%s（%s · %s）" % ["首领·" if unit.is_boss else "", unit.display_name, side_text, Elements.FULL_NAMES.get(unit.element, "无属性")]
	if unit.side == "enemy" and (unit.corrupted or (unit.spawned_from_nest and unit.spawn_round > Balance.REINFORCEMENT_XP_LAST_ROUND)):
		unit_title.text += " · 击杀无经验"
	unit_title.text += "\nHP %d/%d" % [unit.hp, unit.max_hp]
	unit_health.max_value = maxi(1, unit.max_hp)
	unit_health.value = unit.hp
	var lines: Array = []
	if unit.side == "enemy":
		lines.append("Lv.%d%s" % [unit.enemy_level, " · 首领：最大生命 +20" if unit.is_boss else ""])
		var upgrades_list: Array = []
		for key in unit.upgrades:
			for upgrade_id in RunState.MONSTER_UPGRADES:
				var info: Dictionary = RunState.MONSTER_UPGRADES[upgrade_id]
				if String(info.get("key", "")) == String(key):
					upgrades_list.append(String(info["name"]))
		if not upgrades_list.is_empty():
			lines.append("敌方技能强化：%s" % "、".join(upgrades_list))
	lines.append("生命 %d/%d　移动 %s（基础 %d）" % [unit.hp, unit.max_hp, "无限" if state.is_free_exploration() else str(state.move_budget_for(unit)), unit.move_points])
	if Elements.MATCHUPS_ENABLED:
		lines.append(Elements.counter_hint(unit.element))
	var statuses: Array = []
	if unit.corrupted:
		statuses.append("黑化：最大生命+10%、技能威力+10%，击杀无经验")
	if unit.guard_nest.x >= 0:
		statuses.append("守护巢穴：不能施法，持续分担一半伤害" if state.active_nest_guards(unit.guard_nest).has(unit) else "守护已中断；本阶段仍不能施法")
	if unit.side == "enemy" and unit.spawned_from_nest and unit.spawn_round > Balance.REINFORCEMENT_XP_LAST_ROUND:
		statuses.append("第%d轮增援：击杀不提供经验" % unit.spawn_round)
	if unit.burn_ticks > 0:
		statuses.append("灼烧 %d 回合（每回合损失 %d HP）" % [unit.burn_ticks, Balance.burn_damage_for(unit.max_hp)])
	if unit.parasite_source_uid >= 0:
		var parasite_source := state.unit_by_uid(unit.parasite_source_uid)
		var parasite_bonus := int(parasite_source.upgrades.get("leech_seed_tick_bonus", 0)) if parasite_source != null and parasite_source.side == unit.parasite_source_side else 0
		statuses.append("寄生：整轮结束失去 %d HP；受到其他实际伤害解除" % (Balance.PARASITE_DAMAGE + parasite_bonus))
	if unit.fire_amp_stacks > 0:
		statuses.append("火焰增幅 +%d：下一次造成技能直伤时消耗" % unit.fire_amp_stacks)
	if unit.electric_resonance_bonus > 0:
		statuses.append("电共鸣蓄伤 +%d：下一次造成实际技能伤害时消耗" % unit.electric_resonance_bonus)
	if unit.mountain_form_ticks > 0:
		statuses.append("山岳形态 %d 回合：3×3 内友军与自身伤害减免三分之一后转移给施法者" % unit.mountain_form_ticks)
	if unit.shield_hp > 0:
		statuses.append("护盾 %d：优先抵挡伤害，破坏时冲击四邻格敌人；剩余 %d 回合" % [unit.shield_hp, unit.shield_ticks])
	if unit.ice_glide_until_round > 0 and unit.ice_glide_until_round >= state.round:
		statuses.append("溜冰：至第 %d 回合，沿连通冰面移动不消耗普通移动机会" % unit.ice_glide_until_round)
	if unit.surf_until_round > 0 and unit.surf_until_round >= state.round:
		statuses.append("冲浪：至第 %d 回合，沿连通水域移动不消耗普通移动机会" % unit.surf_until_round)
	if unit.mirror_until_round > 0 and unit.mirror_until_round >= state.round:
		statuses.append("镜花水月：至第 %d 回合，可免费跃迁至任意水格，水系技能直伤 +%d，可免疫一次伤害" % [unit.mirror_until_round, Balance.MIRROR_WATER_DAMAGE_BONUS])
	if unit.root_pending:
		statuses.append("定身待生效")
	if unit.move_cancelled:
		statuses.append("本回合被定身")
	if unit.imprison_ticks > 0:
		statuses.append("禁锢 %d 回合：不能普通移动，但仍可施法或进行其他行动" % unit.imprison_ticks)
	if unit.vine_reapply_round > 0:
		statuses.append("藤蔓禁锢将在第 %d 回合再次触发" % unit.vine_reapply_round)
	if unit.slow_ticks > 0:
		statuses.append("浸湿 %d 层（移动 -1）" % unit.slow_ticks)
	if unit.shock_ticks > 0:
		statuses.append("感电 %d 层" % unit.shock_ticks)
	if unit.paralyzed_ticks > 0:
		statuses.append("麻痹 %d 回合（每轮开始时衰减）" % unit.paralyzed_ticks)
	if unit.frozen:
		statuses.append("冰冻 %d 回合（无法行动；受到伤害时解除）" % unit.frozen_ticks)
	if unit.channel_lock_round > state.round:
		statuses.append("吟唱中：第 %d 回合本方阶段结算，届时不能行动" % unit.channel_lock_round)
	elif unit.channel_lock_round == state.round:
		statuses.append("吟唱代价：本阶段不能行动")
	if unit.vine_ticks > 0:
		statuses.append("禁锢（旧存档藤蔓字段兼容）")
	if unit.inspired:
		statuses.append("首领鼓舞：移动 +1，当前生命与生命上限各 +5（本场）")
	if unit.is_boss:
		statuses.append("半血鼓舞并回巢一次；提前拆巢可阻止回巢。")
		if unit.sheltered:
			statuses.append("巢内庇护：摧毁主巢穴后可攻击；异常暂停。")
	if unit.haste_ticks > 0:
		statuses.append("加速 +2")
	if unit.extra_casts > 0:
		statuses.append("额外施法 %d 次" % unit.extra_casts)
	for buff_id in unit.battle_buffs:
		statuses.append("本场 Buff：%s" % BattleBuffDB.name_of(String(buff_id)))
	if state.all_rewards().any(func(p): return p.get("state") == "carried" and int(p.get("owner_uid", -1)) == unit.uid and not bool(p.get("credited", false))):
		statuses.append("持有战场奖励：战斗结束前须存活" if unit.side == "player" else "持有抢走的奖励点：击杀后原格掉落，危险格死亡或捕获不掉落")
	if statuses.is_empty():
		statuses.append("无")
	lines.append("状态：" + "、".join(statuses))
	if unit.last_skill_id != "":
		lines.append("最后使用：%s%s" % [
			SkillDB.name_of(unit.last_skill_id),
			"（已强化）" if unit.last_skill_upgraded else "",
		])
	var slide := state.ice_slide_outcome(unit)
	if not slide.is_empty():
		var direction_name := String(GridSpec.DIR_NAMES.get(slide["direction"], "未知"))
		if bool(slide["blocked"]):
			lines.append("冰面滑行（按当前站位）：向%s，目标受阻，回合末停在原地（灰色止步标记）。" % direction_name)
		else:
			var target: Vector2i = slide["to"]
			lines.append("冰面滑行（按当前站位）：向%s至 (%d,%d)%s。" % [direction_name, target.x, target.y, "，落点致命" if bool(slide["lethal"]) else ""])
	lines.append("本回合移动：%s" % _move_status(unit))
	if unit.is_trainer:
		lines.append("本回合捕获机会：%s" % ("已使用" if unit.capture_used else "可用"))
	else:
		var skill_reason := _skill_phase_block_reason(unit)
		lines.append("本回合技能：%s" % ("可用" if skill_reason == "" else "不可用（%s）" % skill_reason))
	if unit.side == "enemy":
		var low_hp_rules := bool(state.capture_options.get("capture_low_hp", false))
		lines.append("捕获概率：%d%%（训练家在周围两格可尝试%s）" % [
			mini(100, CaptureSystem.chance_percent(unit, low_hp_rules, state.debug_capture_percent) + (20 if state.capture_aid else 0)), "，目标需不高于半血" if low_hp_rules else "",
		])
	if unit.reward_carrier:
		lines.append("携带奖励点：击杀后原格掉落；落入深水、岩浆或深坑时不掉落。")
	if unit.fresh_spawn:
		lines.append("本回合新生成：不能移动或施法")
	if unit.summon_owner_uid >= 0:
		var owner := state.unit_by_uid(unit.summon_owner_uid)
		lines.append("召唤物：施法者 %s；战斗结束后消失" % (owner.display_name if owner != null else "未知"))
	if unit.summon_power_bonus > 0:
		lines.append("地形赋予技能威力 +%d" % unit.summon_power_bonus)
	for skill_id in unit.skills:
		var id := String(skill_id)
		var used_text := "（本场已用尽）" if not unit.can_use_in_battle(id) else ""
		lines.append("· %s%s：%s" % [SkillDB.name_of(id), used_text, SkillDB.get_def(id).get("desc", "")])
	unit_body.text = "\n".join(lines)


func _move_status(unit: CombatUnit) -> String:
	if not unit.is_alive():
		return "无法移动（已倒下）"
	if unit.channel_lock_round == state.round:
		return "无法移动（吟唱代价）"
	if unit.frozen:
		return "无法移动（冰冻）"
	if unit.paralyzed_ticks > 0:
		return "无法移动（麻痹）"
	if unit.vine_ticks > 0:
		return "无法移动（禁锢）"
	if unit.move_cancelled:
		return "无法移动（本回合被定身或施法锁定）"
	if state.terrain_travel_mode(unit) >= 0:
		return "可用（地形移动免费）"
	if state.mirror_water_travel_active(unit):
		return "可用（镜花水月水格移动免费）"
	if unit.moved:
		return "已用"
	if unit.effective_move() <= 0:
		return "无法移动（移动力为 0）"
	return "可用"


func _rebuild_skill_buttons() -> void:
	UIKit.clear_children(skill_box)
	var unit := state.unit_by_uid(selected_uid)
	if merchant_actions_open:
		var talk := UIKit.small_button("对话")
		talk.name = "MerchantTalkButton"
		talk.disabled = state.merchant.is_empty() or not state.can_interact_at(state.merchant["cell"])
		talk.tooltip_text = "训练师需走到商人相邻格才能对话。" if talk.disabled else "与商人交易"
		hint_label.text = talk.tooltip_text
		talk.pressed.connect(_interact_with_merchant)
		skill_box.add_child(talk)
		if talk.disabled:
			skill_box.add_child(UIKit.label("训练师需与商人相邻", 13, UIKit.TEXT_DIM))
		call_deferred("_fit_action_panel")
		return
	if unit != null and unit.side == "enemy":
		var detail := UIKit.small_button("查看详情")
		detail.pressed.connect(func() -> void: _show_unit_detail(unit))
		skill_box.add_child(detail)
		call_deferred("_fit_action_panel")
		return
	if unit == null or not unit.is_alive():
		skill_box.add_child(UIKit.label("选择己方单位后显示行动。", 13, UIKit.TEXT_DIM))
		return
	if action_mode == "items" and unit.is_trainer:
		for item_id in Merchant.ITEMS:
			var id := String(item_id)
			var button := UIKit.small_button("%s ×%d" % [Merchant.ITEMS[id][0], int(app.run.trainer_items.get(id, 0))])
			button.tooltip_text = Merchant.ITEMS[id][2]
			button.disabled = (id == "potion" and state.is_free_exploration()) or int(app.run.trainer_items.get(id, 0)) <= 0 or unit.capture_used or not unit.can_act_skill() or (id == "capture_aid" and state.capture_aid)
			if id == "potion" and state.alive_units("player").filter(func(target): return Merchant.item_target_valid(state, target)).is_empty():
				button.disabled = true
				button.tooltip_text += "\n当前没有可治疗目标。"
			button.pressed.connect(func() -> void:
				if id == "potion":
					item_aim = id
					board.clear_overlays()
					for target in state.alive_units("player"):
						if Merchant.item_target_valid(state, target):
							board.attack_cells.append(target.cell)
					_position_action_panel()
					hint_label.text = "治疗药：点击三格内受伤己方单位；右键或Esc取消。"
					board.queue_redraw()
				else:
					_use_trainer_item(id)
			)
			skill_box.add_child(button)
		var back := UIKit.small_button("返回行动")
		back.pressed.connect(_return_to_main_actions)
		skill_box.add_child(back)
		call_deferred("_fit_action_panel")
		return
	capture_button = null
	if action_mode == "skills":
		for skill_id in unit.skills:
			var id := String(skill_id)
			var def := SkillDB.get_def(id)
			var button_text := "%s%s（%s）" % [def.get("name", id), "·特殊" if SkillDB.is_special(id) else "", _skill_tag(id, unit)]
			var phase_reason := _skill_phase_block_reason(unit, id)
			if phase_reason != "":
				button_text += "·" + phase_reason
			elif not unit.can_use_in_battle(id):
				button_text += "·本场已用"
			var button := UIKit.small_button(button_text)
			button.name = "SkillButton_%s" % id
			button.tooltip_text = String(def.get("desc", ""))
			var entries := state.skill_targets(unit, id)
			if phase_reason != "":
				button.disabled = true
				button.tooltip_text += "\n（%s）" % phase_reason
			elif not unit.can_use_in_battle(id):
				button.disabled = true
				button.tooltip_text += "\n（本场使用次数已耗尽）"
			elif id == "tree_man" and state.active_summon(unit.uid) != null:
				button.disabled = true
				button.tooltip_text += "\n（已有存活召唤物）"
			elif entries.is_empty():
				button.disabled = true
				button.tooltip_text += "\n（蒸汽中无法施法）" if state.steam_cells.has(unit.cell) else "\n（当前没有有效目标）"
			button.pressed.connect(func() -> void: _on_skill_pressed(id))
			skill_box.add_child(button)
		var back_button := UIKit.small_button("返回行动")
		back_button.pressed.connect(_return_to_main_actions)
		skill_box.add_child(back_button)
		call_deferred("_fit_action_panel")
		return
	var undo_move := state.can_undo() and int(state.undo_stack.back().get("uid", 0)) == unit.uid
	var move_button := UIKit.small_button("撤销移动" if undo_move else "移动")
	move_button.name = "MoveActionButton"
	move_button.disabled = not undo_move and (not state.can_move_unit_now(unit) or state.move_options(unit).is_empty())
	move_button.pressed.connect(func() -> void:
		if undo_move:
			do_undo()
		else:
			_on_move_pressed()
	)
	skill_box.add_child(move_button)
	if not unit.is_trainer:
		var skills_button := UIKit.small_button("技能")
		skills_button.name = "ChooseSkillButton"
		skills_button.disabled = unit.skills.is_empty()
		skills_button.pressed.connect(_on_choose_skill_pressed)
		skill_box.add_child(skills_button)
	else:
		if not state.merchant.is_empty() and state.can_interact_at(state.merchant["cell"]):
			var merchant_action := UIKit.small_button("与商人交易")
			merchant_action.name = "MerchantInteractButton"
			merchant_action.pressed.connect(_interact_with_merchant)
			skill_box.add_child(merchant_action)
		if not state.mentor.is_empty() and state.can_interact_at(state.mentor["cell"]):
			var training := UIKit.small_button("向技能导师学习强化")
			training.name = "MentorInteractButton"
			training.pressed.connect(_show_mentor)
			skill_box.add_child(training)
		if state.can_interact_at(state.boss_portal_cell):
			var portal_action := UIKit.small_button("进入传送门")
			portal_action.name = "PortalInteractButton"
			portal_action.pressed.connect(_request_portal)
			skill_box.add_child(portal_action)
		capture_button = UIKit.small_button("捕获")
		capture_button.name = "CaptureButton"
		capture_button.disabled = unit.capture_used or _capture_targets(unit).is_empty()
		capture_button.pressed.connect(_on_capture_pressed)
		skill_box.add_child(capture_button)
		var items := UIKit.small_button("道具")
		items.name = "TrainerItemsButton"
		items.pressed.connect(func() -> void:
			action_mode = "items"
			_rebuild_skill_buttons()
		)
		skill_box.add_child(items)
	var detail_button := UIKit.small_button("查看详情")
	detail_button.pressed.connect(func() -> void: _show_unit_detail(unit))
	skill_box.add_child(detail_button)
	var cancel_button := UIKit.small_button("取消选择")
	cancel_button.pressed.connect(_cancel_action)
	skill_box.add_child(cancel_button)
	call_deferred("_fit_action_panel")


func _fit_action_panel() -> void:
	if action_panel == null or not is_inside_tree():
		return
	action_panel.reset_size()
	_position_action_panel()


func _on_move_pressed() -> void:
	if busy or _playback_active():
		return
	var unit := state.unit_by_uid(selected_uid)
	if unit == null or not state.can_move_unit_now(unit):
		return
	action_mode = "move"
	board.clear_overlays()
	_update_selection_overlay()
	_position_action_panel()
	hint_label.text = "移动：点击蓝色格；右键或 Esc 返回行动。"
	board.queue_redraw()


func _on_choose_skill_pressed() -> void:
	if busy or _playback_active():
		return
	action_mode = "skills"
	hint_label.text = "选择具体技能；右键或 Esc 返回行动。"
	_rebuild_skill_buttons()
	_position_action_panel()


func _return_to_main_actions() -> void:
	action_mode = "main"
	hint_label.text = "选择下一步行动。"
	board.clear_overlays()
	_update_selection_overlay()
	_rebuild_skill_buttons()
	_position_action_panel()
	board.queue_redraw()


func _skill_phase_block_reason(unit: CombatUnit, skill_id: String = "") -> String:
	if unit == null or not unit.is_alive():
		return "已倒下"
	if unit.fresh_spawn:
		return "出生轮待机"
	if unit.frozen:
		return "冰冻"
	if unit.paralyzed_ticks > 0:
		return "麻痹"
	if state.recovery_skill_blocked(skill_id):
		return "自由探索期间禁止恢复技能"
	if unit.channel_lock_round == state.round:
		return "吟唱代价"
	if state.steam_cells.has(unit.cell) and not state.is_free_exploration():
		return "雾中禁用"
	if unit.skill_used and unit.extra_casts <= 0:
		return "本回合已施法"
	if skill_id != "" and bool(SkillDB.get_def(skill_id).get("channel", false)) and not state.can_begin_channel(unit):
		return "本方本回合已有吟唱者"
	return ""


func _skill_tag(skill_id: String, unit: CombatUnit) -> String:
	var def := SkillDB.get_def(skill_id)
	var parts: Array = []
	var base_damage := int(def.get("damage", 0))
	base_damage = SkillResolver.upgraded_base_damage(unit, skill_id, base_damage)
	if String(def.get("element", "")) == "water" and state.mirror_water_travel_active(unit):
		base_damage += Balance.MIRROR_WATER_DAMAGE_BONUS
	var damage := Balance.skill_damage_for_side(base_damage, unit.side)
	if skill_id == "flame_jet":
		parts.append("伤害 %d · 邻格 %d" % [damage, Balance.skill_damage_for_side(SkillResolver.upgraded_base_damage(unit, skill_id, int(def.get("damage", 0)) + int(def.get("adjacent_bonus", 0))), unit.side)])
	elif skill_id == "flame_charge":
		parts.append("撞击 %d" % Balance.skill_damage_for_side(SkillResolver.upgraded_base_damage(unit, skill_id, int(def.get("damage", 0)) + (Balance.SKILL_DAMAGE_UPGRADE if unit.has_buff("flame_charge") else 0)), unit.side))
	elif skill_id == "leech_seed":
		parts.append("寄生 %d/轮" % (Balance.PARASITE_DAMAGE + int(unit.upgrades.get("leech_seed_tick_bonus", 0))))
	elif skill_id == "fire_amplify":
		parts.append("吸火 ≤2 格 · 每格 +%d" % int(unit.upgrades.get("fire_amplify_power", Balance.SKILL_DAMAGE_UPGRADE)))
	elif skill_id == "ice_glide" or skill_id == "surf":
		parts.append("地形免费移动 %d 回合" % (3 + int(unit.upgrades.get("ice_glide_duration", 0)) if skill_id == "ice_glide" else 3 + int(unit.upgrades.get("surf_duration", 0))))
	elif skill_id == "mirror_water_moon":
		parts.append("%d 回合 · 水伤 +%d · 受击免疫" % [Balance.MIRROR_WATER_MOON_ROUNDS + int(unit.upgrades.get("mirror_water_moon_duration", 0)), Balance.MIRROR_WATER_DAMAGE_BONUS])
	elif skill_id == "flame_rush":
		parts.append("伤害 %d · 跃迁燃烧格" % damage)
	elif skill_id == "windfire_breath":
		parts.append("前方 8 格 · 伤害 %d · 击退 1 格" % damage)
	elif skill_id == "furnace_fist":
		var furnace_heal := 5 + int(unit.upgrades.get("furnace_fist_healing", 0))
		parts.append("伤害 %d · 回复 %d/%d" % [damage, furnace_heal, furnace_heal + 5])
	elif skill_id == "skyfire":
		parts.append("十字 5 格 · 伤害 %d · 灼烧" % damage)
	elif skill_id == "combustion":
		parts.append("伤害 %d · 灼烧 %d" % [damage, Balance.skill_damage_for_side(SkillResolver.upgraded_base_damage(unit, skill_id, 16), unit.side)])
	elif skill_id == "burn_out":
		var sacrifice_damage := ceili(float(unit.max_hp) * 0.5)
		sacrifice_damage = SkillResolver.upgraded_base_damage(unit, skill_id, sacrifice_damage)
		parts.append("单体伤害 %d · 射程 5 · 自损 %d" % [Balance.skill_damage_for_side(sacrifice_damage, unit.side), ceili(float(unit.max_hp) * 0.5)])
	elif skill_id == "wild_vines":
		parts.append("前方 %d 格 · 生成藤蔓 · 进入禁锢" % SkillResolver.wild_vines_reach(unit))
	elif skill_id == "water_magic_burst":
		var center_damage := Balance.skill_damage_for_side(SkillResolver.upgraded_base_damage(unit, skill_id, 11), unit.side)
		parts.append("十字 5 格 · 伤害 %d · 中心 %d · 击退" % [damage, center_damage])
	elif skill_id == "ice_breath":
		parts.append("前方 3 格宽 × 2 格深 · 伤害 %d · 浸湿转冰冻" % damage)
	elif skill_id == "tree_man":
		parts.append("即时召唤 · 上限 1")
	elif skill_id == "herbal_heal":
		parts.append("吟唱治疗 %d · 固定曼哈顿 2 格" % (Balance.HERBAL_HEAL + int(unit.upgrades.get("herbal_heal_amount", 0))))
	elif skill_id == "first_aid":
		parts.append("回复 %d" % SkillResolver.first_aid_healing(unit))
	elif skill_id == "rooted_grass":
		var rooted_width := 3 + 2 * int(unit.upgrades.get("rooted_grass_radius", 0))
		parts.append("%d×%d 草丛 · 含自身" % [rooted_width, rooted_width])
	elif skill_id == "leaf_wind":
		var strong_damage := Balance.skill_damage_for_side(SkillResolver.upgraded_base_damage(unit, skill_id, 12), unit.side)
		parts.append("伤害 %d · 草丛/藤蔓 %d" % [damage, strong_damage])
	elif skill_id == "antidote":
		parts.append("解除异常（冰冻除外） · 回复 %d" % SkillResolver.antidote_healing(unit))
	elif skill_id == "tailwind":
		var width := 5 + 2 * int(unit.upgrades.get("tailwind_reach", 0))
		parts.append("自身周围 %d×%d · 移动力 +2" % [width, width])
	elif skill_id == "fire_burst":
		parts.append("中心 %d · 外围 %d" % [Balance.skill_damage_for_side(SkillResolver.fireball_base_damage(unit, true), unit.side), Balance.skill_damage_for_side(SkillResolver.fireball_base_damage(unit, false), unit.side)])
	elif skill_id == "electric_arc":
		parts.append("伤害 %d · 传导每两格−2，最低4" % damage)
	elif skill_id in ["rain_call", "rain_dance"]:
		parts.append("13格菱形" if int(unit.upgrades.get("rain_radius_bonus", 0)) > 0 else "3×3九格")
	elif skill_id == "magnet_pull":
		parts.append("射程 %d · 拉近 1 格/带电 2 格" % SkillResolver.magnet_pull_range(unit))
	elif skill_id == "glare":
		var glare_width := 3 + 2 * int(unit.upgrades.get("glare_radius", 0))
		parts.append("%d×%d · 敌人感电 1 层" % [glare_width, glare_width])
	elif skill_id == "electromagnetic_laser":
		parts.append("伤害 %d · 射程 4 · 带电目标可穿障" % damage)
	elif skill_id == "electric_resonance":
		parts.append("感电 +%d · 麻痹 +%d" % [SkillResolver.resonance_shock_bonus(unit), SkillResolver.resonance_paralysis_bonus(unit)])
	elif skill_id == "electric_spark":
		parts.append("直线 3 格 · 伤害 %d · 带电灼烧" % damage)
	elif skill_id == "imprint":
		parts.append("复制最后普通技能 · 不保留")
	elif skill_id == "mountain_chain":
		parts.append("基础 %d 段 · 周围岩石加段 · 每段 %d" % [2 + int(unit.upgrades.get("mountain_chain_segments", 0)), damage])
	elif skill_id == "mountain_form":
		parts.append("%d×%d 减伤三分之一 · 转移给自身 · 1 回合" % [
			3 + 2 * int(unit.upgrades.get("mountain_form_radius", 0)),
			3 + 2 * int(unit.upgrades.get("mountain_form_radius", 0)),
		])
	elif skill_id == "guard_rock":
		parts.append("护盾 %d · 持续 %d 回合 · 破盾四邻 %d 伤害" % [
			SkillResolver.guard_rock_shield_amount(unit),
			Balance.SHIELD_TICKS,
			Balance.GUARD_ROCK_BREAK_DAMAGE,
		])
	elif skill_id == "rock_blast":
		parts.append("伤害 %d · 击退 1 格 · 两侧分裂 %d 伤害" % [
			damage,
			3 + (2 if int(unit.upgrades.get("rock_blast_damage", 0)) > 0 else 0),
		])
	elif skill_id == "water_drop_stone":
		parts.append("伤害 %d · 浸湿追加 %d · 岩石延伸" % [
			damage,
			3 + (2 if int(unit.upgrades.get("water_drop_stone_damage", 0)) > 0 else 0),
		])
	elif skill_id == "fire_burst" and int(unit.upgrades.get("fireball_damage", 0)) > 0:
		parts.append("伤害 %d · 中心 %d" % [damage, Balance.skill_damage_for_side(base_damage + int(unit.upgrades["fireball_damage"]), unit.side)])
	elif skill_id == "double_cast" and int(unit.upgrades.get("double_cast_range", 0)) > 0:
		parts.append("相邻双目标")
	elif damage > 0:
		parts.append("伤害 %d" % damage)
	var kind := String(def.get("kind", ""))
	if kind == "ray":
		parts.append("射线 %d-%d" % [int(def.get("min_range", 1)), int(def.get("max_range", 8)) + SkillResolver._range_bonus(state, unit, skill_id) + (int(unit.upgrades.get("freeze_ray_range", 0)) if skill_id == "freeze_ray" else 0)])
	elif skill_id == "lightning":
		parts.append("全场锁定 · 蓄力")
	elif skill_id == "flame_rush":
		parts.append("全图燃烧格落点")
	elif kind == "unit":
		var actual_range := int(def.get("range", 1))
		if SkillDB.is_placeholder(skill_id):
			actual_range += int(unit.upgrades.get(skill_id + "_range", 0))
		elif skill_id == "rock_break":
			actual_range += int(unit.upgrades.get(skill_id + "_range", 0))
		parts.append("射程 %d" % actual_range)
	elif bool(def.get("global_range", false)):
		parts.append("全图落点")
	elif kind == "cell":
		parts.append("落点 %d%s" % [int(def.get("range", 3)), " · 蓄力" if bool(def.get("channel", false)) else ""])
	elif kind == "charge":
		parts.append("冲撞最多 2 格")
	elif kind == "teleport":
		parts.append("瞬移 %d" % int(def.get("range", 2)))
	elif kind == "direction":
		parts.append("蓄力 · 方向" if bool(def.get("channel", false)) else "方向")
	if parts.is_empty():
		parts.append("辅助")
	return " · ".join(parts)


func _update_action_buttons() -> void:
	if leave_node_button != null:
		leave_node_button.text = "返回区域" if state.can_leave_node() else "首领战不可撤退" if state.node_kind == "boss" or state.boss_uid >= 0 else "撤退" if state.can_escape() else "前往撤离区"
		leave_node_button.tooltip_text = "首领战必须击败或捕获首领。" if state.node_kind == "boss" or state.boss_uid >= 0 else "训练家进入部署/撤离区后可撤离；区外队员损失25%最大生命，可能濒死；濒死者奖励留原地。"
		leave_node_button.disabled = busy or _playback_active() or state.ended or not (state.can_leave_node() or state.can_escape())
	if end_turn_button != null:
		end_turn_button.disabled = busy or state.ended or state.is_free_exploration() or state.phase != BattleState.PHASE_PLAYER
	if undo_button != null:
		undo_button.disabled = busy or not state.can_undo()


func _update_selection_overlay() -> void:
	var unit := state.unit_by_uid(selected_uid)
	if unit != null and unit.side == "player" and state.phase == BattleState.PHASE_PLAYER and not state.ended and not busy:
		if action_mode == "move" and aim_skill == "" and not capture_mode and state.can_move_unit_now(unit):
			board.movement_cells = state.move_options(unit)
	elif viewed_enemy_uid != 0:
		var enemy := state.unit_by_uid(viewed_enemy_uid)
		if enemy != null and enemy.is_alive():
			var options := PathFinder.stop_cells(state, enemy)
			var cells: Array = []
			for cell in options:
				cells.append(cell)
			board.enemy_cells_view = cells


func _update_channel_markers() -> void:
	var state := _display_state()
	if GridSpec.is_inside(state.boss_portal_cell):
		board.markers.append({"cell": state.boss_portal_cell, "kind": "facility", "text": "传送门", "color": Color("694ca2")})
	for cast in state.pending_casts:
		if String(cast["side"]) != "enemy":
			continue
		for cell in cast["cells"]:
			if GridSpec.is_inside(cell):
				board.markers.append({"cell": cell, "kind": "text", "text": "蓄", "color": UIKit.BAD, "size": 14})


func _action_detail(action: Dictionary) -> String:
	var meta: Dictionary = action.get("meta", {})
	if meta.is_empty():
		return ""
	var parts: Array = []
	for hit in meta.get("hits", []):
		var text := "%s 受伤 %d" % [hit.get("name", "?"), int(hit.get("damage", 0))]
		if int(hit.get("modifier", 0)) != 0:
			text += "（%s）" % ("克制 ×1.25" if int(hit["modifier"]) > 0 else "抵抗 ×0.75")
		if bool(hit.get("killed", false)):
			text += "（致死）"
		if bool(hit.get("mirror_immune", false)):
			text += "（镜花水月免疫）"
		if hit.get("push") != null and bool(hit["push"].get("death", false)):
			text += "（推入致死地形）"
		parts.append(text)
	if int(meta.get("self_damage", 0)) > 0:
		parts.append("自身损失 %d" % int(meta["self_damage"]))
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
	_add_obstacle_push_overlay(meta)
	var self_move = meta.get("self_move")
	if self_move != null and meta.get("caster_uid", -1) >= 0:
		var caster := state.unit_by_uid(int(meta["caster_uid"]))
		var from: Vector2i = caster.cell if caster != null else Vector2i(-1, -1)
		if GridSpec.is_inside(from) and GridSpec.is_inside(self_move):
			board.arrows.append({"from": from, "to": self_move, "color": Color(1.0, 0.7, 0.2, 0.9)})


func _update_log() -> void:
	var state := _display_state()
	if log_label == null:
		return
	log_label.text = "\n".join(state.events)


# ---------------------------------------------------------------- 交互


func _on_board_clicked(cell: Vector2i) -> void:
	if busy or _playback_active() or state.ended or modal_layer != null:
		return
	if item_aim != "":
		var target := state.unit_at(cell)
		_use_trainer_item(item_aim, target.uid if target != null else -1)
		return
	if aim_skill == "" and not capture_mode and state.is_interaction_cell(cell):
		if not state.mentor.is_empty() and cell == state.mentor["cell"]:
			if state.can_interact_at(cell):
				_show_mentor()
			else:
				hint_label.text = "导师暂停服务，清场后恢复。" if state.node_kind != "event" else "训练家需走到导师相邻格。"
		elif cell == state.boss_portal_cell:
			_request_portal()
		else:
			selected_uid = 0
			viewed_enemy_uid = 0
			merchant_actions_open = true
			action_mode = "main"
			board.clear_overlays()
			_rebuild_skill_buttons()
			_position_action_panel()
			board.queue_redraw()
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
	if occupant != null:
		speech_layer.dismiss_on_unit_click()
		select_unit(occupant.uid)
		return
	if action_panel.visible:
		_dismiss_action_panel()
		return
	# 空地形：移动或查看
	var unit := state.unit_by_uid(selected_uid)
	if action_mode == "move" and unit != null and state.can_move_unit_now(unit) and state.move_options(unit).has(cell):
		do_move(cell)
		return
	_show_terrain(cell)
	if selected_uid != 0 and aim_skill == "" and not capture_mode:
		_position_action_panel()


func _interact_with_merchant() -> void:
	if busy or _playback_active():
		return
	if state.merchant.is_empty() or not state.can_interact_at(state.merchant["cell"]):
		hint_label.text = "训练师需走到商人相邻格才能交易。"
		return
	_clear_aim()
	_show_merchant()

func _request_portal() -> void:
	if busy or _playback_active():
		return
	if not state.can_interact_at(state.boss_portal_cell):
		hint_label.text = "训练师需走到传送门相邻格才能进入。"
		return
	if app.run.storage.is_empty():
		_enter_boss_portal()
		return
	_show_modal("前往下一层", "营地留守的 %d 只宝可梦将被抛弃，无法进入永久收藏。确认前往下一层？" % app.run.storage.size())
	var confirm := UIKit.small_button("确认前往下一层")
	confirm.name = "ConfirmPortalButton"
	confirm.pressed.connect(_enter_boss_portal)
	modal_layer.get_child(0).get_child(0).add_child(confirm)

func _enter_boss_portal() -> void:
	if busy or _playback_active() or not state.can_interact_at(state.boss_portal_cell):
		return
	_close_modal()
	state.end_battle("victory")
	refresh_all()

func _on_board_hovered(cell: Vector2i) -> void:
	if busy or _playback_active() or state.ended:
		_show_terrain(cell)
		return
	var hover_unit := state.unit_at(cell)
	var next_hover_uid := hover_unit.uid if hover_unit != null else 0
	if hovered_uid != next_hover_uid:
		hovered_uid = next_hover_uid
		_update_unit_card()
	_show_terrain(cell)
	board.path_cells = []
	board.area_cells = []
	board.ray_cells = []
	board.arrows = []
	board.markers = []
	_update_channel_markers()
	if aim_skill != "":
		var unit := state.unit_by_uid(selected_uid)
		var entry := _find_entry(cell)
		if _double_cast_pair_mode() and aim_first_uid == 0:
			var candidate := state.unit_at(cell)
			if candidate != null and _pair_has_uid(candidate.uid):
				board.area_cells = [cell]
				hint_label.text = "电力引擎：点击第一名相邻友军，再选择第二名。"
			else:
				hint_label.text = "请选择一名高亮的相邻友军。"
			hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
			board.queue_redraw()
			return
		if unit != null and not entry.is_empty():
			var preview := state.preview_skill(unit, aim_skill, entry)
			if bool(preview.get("ok", false)):
				var matchup: Array = []
				var relic_feedback: Array = []
				for hit in preview.get("hits", []):
					if int(hit.get("modifier", 0)) != 0:
						matchup.append("%s %s" % [hit.get("name", "?"), "克制 ×1.25" if int(hit["modifier"]) > 0 else "抵抗 ×0.75"])
					if not (hit.get("statuses", []) as Array).is_empty():
						relic_feedback.append("%s：%s" % [hit.get("name", "?"), "、".join(hit["statuses"])])
					if int(hit.get("relic_healed", 0)) > 0:
						relic_feedback.append("余烬回复 %d HP" % int(hit["relic_healed"]))
				hint_label.text = "%s：%s%s%s" % [SkillDB.name_of(aim_skill), preview.get("text", ""), "｜" + "、".join(matchup) if not matchup.is_empty() else "", "｜" + "、".join(relic_feedback) if not relic_feedback.is_empty() else ""]
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
					occupant.display_name, mini(100, CaptureSystem.chance_percent(occupant, bool(state.capture_options.get("capture_low_hp", false)), state.debug_capture_percent) + (20 if state.capture_aid else 0)), occupant.hp, occupant.max_hp,
				]
			hint_label.add_theme_color_override("font_color", UIKit.TEXT)
		board.queue_redraw()
		return
	if state.is_nest_cell(cell):
		var detail := "不可站立；%d 名主动守军均分一半伤害，巢穴承担另一半；四邻生成增援" % state.nest_guard_charges(cell)
		hint_label.text = "巢穴：%s。" % detail
		hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	var unit := state.unit_by_uid(selected_uid)
	if action_mode == "move" and unit != null and state.can_move_unit_now(unit):
		var options := state.move_options(unit)
		if options.has(cell):
			board.path_cells = [unit.cell] + (options[cell]["path"] as Array)
			hint_label.text = "移动到 (%d,%d)，消耗 %d 移动力（移动优先撤回）" % [cell.x, cell.y, int(options[cell]["cost"])]
			hint_label.add_theme_color_override("font_color", UIKit.TEXT)
	if state.vine_expire_round.has(cell):
		var origin := int(state.vine_origin.get(cell, TerrainDB.PLAIN))
		var warning := "藤蔓第 %d 回合末恢复%s" % [int(state.vine_expire_round[cell]), TerrainDB.name_of(origin)]
		if TerrainDB.is_lethal(origin):
			warning += "；站在上方可能死亡"
		hint_label.text = warning
		hint_label.add_theme_color_override("font_color", UIKit.BAD if TerrainDB.is_lethal(origin) else UIKit.ACCENT)
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
	_add_obstacle_push_overlay(preview)
	if String(preview.get("skill_id", "")) in ["flame_charge", "rock_push", "push"]:
		for obstacle in preview.get("obstacles_damaged", []):
			board.markers.append({"cell": obstacle["cell"], "kind": "damage", "text": str(int(obstacle["damage"]))})
	var nest_hit = preview.get("nest_damaged")
	for hit in preview.get("nests_damaged", [nest_hit] if nest_hit != null else []):
		board.markers.append({"cell": hit["cell"], "kind": "damage", "text": str(int(hit.get("damage", 0)))})
	if preview.get("self_move") != null:
		var unit := state.unit_by_uid(selected_uid)
		if unit != null:
			board.arrows.append({"from": unit.cell, "to": preview["self_move"], "color": Color(1.0, 0.8, 0.3)})
	var pull = preview.get("pull")
	if pull != null:
		var pull_from: Vector2i = pull.get("from", Vector2i(-1, -1))
		var pull_to: Vector2i = pull.get("to", Vector2i(-1, -1))
		if GridSpec.is_inside(pull_from) and GridSpec.is_inside(pull_to) and pull_from != pull_to:
			board.arrows.append({"from": pull_from, "to": pull_to, "color": Color(0.55, 0.9, 1.0)})
	for change in preview.get("terrain_changes", []):
		board.markers.append({
			"cell": change["cell"], "kind": "text", "text": "变%s" % TerrainDB.name_of(int(change["to"])),
			"color": Color(0.5, 0.9, 1.0), "size": 12,
		})


func _add_obstacle_push_overlay(meta: Dictionary) -> void:
	var pushed: Dictionary = meta.get("obstacle_push", {})
	if pushed.is_empty():
		return
	if pushed.get("moved", false) or pushed.get("filled", false):
		board.arrows.append({"from": pushed["from"], "to": pushed["to"], "color": Color("d3b58b")})


func _show_terrain(cell: Vector2i) -> void:
	var state := _display_state()
	if terrain_label == null:
		return
	var value := state.terrain_at(cell)
	var terrain_name := "宝箱（耐久1，不可站立）" if state.is_chest_cell(cell) else "巢穴（不可站立）" if state.is_nest_cell(cell) else TerrainDB.name_of(value)
	var description := "宝箱阻挡移动和射线，飞行可越过但不能停留；命中一次攻击后留下奖励点。" if state.is_chest_cell(cell) else "独立巢穴格，不叠加其他地形；地面不能通过，飞行可越过但不能停留。" if state.is_nest_cell(cell) else String(TerrainDB.DESCRIPTIONS.get(value, ""))
	var lines: Array = ["地块 (%d,%d)：%s" % [cell.x, cell.y, terrain_name], description]
	var selected := state.unit_by_uid(selected_uid)
	var move_cost := -1 if state.is_nest_cell(cell) or state.is_chest_cell(cell) else state.move_cost_for(selected, cell) if selected != null else TerrainDB.move_cost(value, "")
	lines.append("移动消耗：%s" % (str(move_cost) if move_cost >= 0 else "不可进入"))
	if state.is_interaction_cell(cell):
		lines.append(("传送门" if cell == state.boss_portal_cell else "商人") + "：此格不能站立；训练师相邻后，点击设施或选择训练师行动栏中的互动按钮。")
	if state.burning_cells.has(cell):
		lines.append("燃烧：%s" % str(state.burning_cells[cell]))
	if state.vine_expire_round.has(cell):
		var origin := int(state.vine_origin.get(cell, TerrainDB.PLAIN))
		lines.append("临时藤蔓：第 %d 回合敌我行动结束后恢复为%s；不会自行扩张。" % [int(state.vine_expire_round[cell]), TerrainDB.name_of(origin)])
		if TerrainDB.is_lethal(origin):
			lines.append("危险：恢复时立即按底层致死地形结算站位；深水对水系、地面致死地形对飞行单位沿用现有豁免。")
	if value == TerrainDB.ICE:
		lines.append("冰面：每次整轮末最多随机冻结一格相邻浅水或深水；新冰下一轮才会扩张。")
		lines.append("单位本轮在冰面留下位移方向时，蓝色箭头指向回合末滑行格；红色表示致死落点，灰色止步标记表示被挡住。")
	if state.obstacle_durability.has(cell) and not state.is_chest_cell(cell):
		var max_hp := Balance.TREE_DURABILITY if value == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
		lines.append("障碍耐久：%d/%d；树木和岩障会截断射线。" % [int(state.obstacle_durability[cell]), max_hp])
	for strike in state.storm_strikes:
		if strike["cell"] == cell:
			lines.append("天雷预告：第 %d 轮双方行动结束后命中此格，造成当时单位最大生命50%%伤害，敌我均受伤；离开即可躲避。" % int(strike["due_round"]))
	if state.steam_cells.has(cell):
		lines.append("蒸汽：剩余 %d 次整轮结算；站在其中不能施放技能。" % int(state.steam_cells[cell]))
	if state.is_nest_cell(cell):
		if bool(state.nest_at_cell(cell).get("boss_sheltered", false)):
			lines.append("首领正在巢内庇护：摧毁巢穴使其出巢；巢内首领不占格。")
		lines.append("巢穴生命：%d/%d；每两轮在上下左右合法空格生成。" % [int(state.nest_at_cell(cell).get("hp", 0)), int(state.nest_at_cell(cell).get("max_hp", Balance.nest_max_hp(state.battle_index)))])
		lines.append("巢穴不可站立或叠加其他地形；主动守护消耗技能机会，持续到下次敌方阶段。巢穴承担至少一半伤害，其余由四邻有效守军均分，不消耗拦截次数。")
		lines.append("当前守军：%d 名；积压 %d 只。" % [state.nest_guard_charges(cell), int(state.nest_at_cell(cell).get("pending_waves", 0))])
	if state.is_chest_cell(cell):
		lines.append("命中一次攻击后破坏，原格生成奖励点；碰撞不损伤宝箱。")
	if state.all_rewards().any(func(p): return p.get("cell") == cell and p.get("state") in ["map", "guarding"]):
		lines.append("奖励点不受攻击破坏；双方在本方回合末占点，守过对方行动阶段后携带。击杀敌方携带者可夺回。")
	if cell == state.reward.get("cell", Vector2i(-1, -1)):
		match String(state.reward.get("state", "")):
			"map", "guarding":
				lines.append("奖励格：在本方回合末站上去，经过对方行动后仍存活且未离开即可携带；敌人也会拾取。受伤但存活不打断占点。")
			"carried":
				var owner := state.reward_owner()
				lines.append("奖励已由敌方携带，正常击杀可夺回。" if owner != null and owner.side == "enemy" else "奖励已由我方持有；持有者活到战斗结束可记录一次额外战后三选一。")
			"lost", "destroyed":
				lines.append("本场奖励已失去。")
	if state.food_cells.has(cell):
		lines.append("食物：本轮敌方行动结束时仍站在此处，即收集 1 份，用于营地休息。")
	terrain_label.text = "\n".join(lines)
	terrain_scroll.scroll_vertical = 0
	call_deferred("_fit_terrain_panel")


func select_unit(uid: int) -> void:
	merchant_actions_open = false
	action_mode = "main"
	selected_uid = uid
	viewed_enemy_uid = 0
	board.selected_uid = uid
	_clear_aim()
	board.clear_overlays()
	_update_unit_card()
	_update_team_list()
	_rebuild_skill_buttons()
	_update_selection_overlay()
	board.queue_redraw()
	_position_action_panel()


func _on_board_double_clicked(cell: Vector2i) -> void:
	if modal_layer != null:
		return
	var unit := _display_state().unit_at(cell)
	if unit != null:
		speech_layer.dismiss_on_unit_click()
		_show_unit_detail(unit)


func _show_unit_detail(unit: CombatUnit) -> void:
	selected_uid = unit.uid if unit.side == "player" else 0
	viewed_enemy_uid = unit.uid if unit.side == "enemy" else 0
	_update_unit_card()
	var skills: Array = []
	for skill_id in unit.skills:
		skills.append("%s（%s）：%s" % [SkillDB.name_of(String(skill_id)), _skill_tag(String(skill_id), unit), SkillDB.get_def(String(skill_id)).get("desc", "")])
	var progress := "Lv.%d" % (unit.enemy_level if unit.side == "enemy" else unit.combat_level)
	if unit.side == "player" and not unit.is_trainer and app.run != null:
		var record: Dictionary = app.run.record_by_uid(unit.uid)
		progress += " · 经验 %d" % int(record.get("xp", 0))
	var identity := "物种：%s · %s · %s\n等级：%s · 生命：%d/%d\n移动：当前 %d / 基础 %d\n行动：移动%s · 技能%s · 捕获%s\n强化：%s\n\n" % [SpeciesDB.name_of(unit.species_id), "我方" if unit.side == "player" else "敌方", Elements.FULL_NAMES.get(unit.element, "无属性"), progress, unit.hp, unit.max_hp, state.move_budget_for(unit), unit.move_points, "已用" if unit.moved else "可用", "已用" if unit.skill_used else "可用", "已用" if unit.capture_used else "可用", str(unit.upgrades.keys()) if not unit.upgrades.is_empty() else "无"]
	var sources: Array = []
	if unit.burn_ticks > 0:
		sources.append("灼烧来源：%s #%d" % [unit.burn_source_side, unit.burn_source_uid])
	if unit.parasite_source_uid >= 0:
		sources.append("寄生来源：%s #%d" % [unit.parasite_source_side, unit.parasite_source_uid])
	if not unit.vine_sources.is_empty():
		sources.append("藤蔓来源与剩余阶段：%s" % str(unit.vine_sources))
	if unit.summon_owner_uid >= 0:
		sources.append("召唤者：#%d" % unit.summon_owner_uid)
	if not unit.battle_buffs.is_empty():
		sources.append("本场增益：%s" % str(unit.battle_buffs))
	var source_text := "\n".join(sources) if not sources.is_empty() else "无"
	_show_modal("%s %s · 详细信息" % [unit.glyph, unit.display_name], identity + unit_body.text + "\n\n状态来源\n" + source_text + "\n\n可用技能\n" + "\n".join(skills))


func _show_modal(title: String, body: String) -> void:
	if modal_layer != null:
		modal_layer.queue_free()
	modal_layer = ColorRect.new()
	modal_layer.z_index = 20
	modal_layer.color = Color(0.02, 0.03, 0.06, 0.86)
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal_layer)
	var panel := UIKit.panel(UIKit.PANEL)
	modal_layer.add_child(panel)
	var full_detail := title.contains("详细信息")
	var panel_size := Vector2(size.x * (0.9 if full_detail else 0.58), size.y * (0.88 if full_detail else 0.72))
	panel.position = (size - panel_size) * 0.5
	panel.size = panel_size
	var content := UIKit.vbox(8)
	panel.add_child(content)
	content.add_child(UIKit.label(title, 22, UIKit.ACCENT))
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size.y = size.y * (0.69 if full_detail else 0.44)
	content.add_child(scroll)
	scroll.add_child(UIKit.wrapped(body, 15, UIKit.TEXT))
	var close_button := UIKit.small_button("继续战斗" if title == "战斗菜单" else "关闭")
	close_button.pressed.connect(_close_modal)
	content.add_child(close_button)


func _close_modal() -> void:
	if modal_layer != null:
		modal_layer.queue_free()
		modal_layer = null


func _use_trainer_item(id: String, uid: int = -1) -> void:
	if busy or _playback_active():
		return
	var result := Merchant.use_item(app.run, state, id, uid)
	hint_label.text = String(result["reason"])
	if result["ok"]:
		_clear_aim()
		app.sync_and_save(state)
		refresh_all()


func _show_mentor(message: String = "") -> void:
	if state.mentor.is_empty() or not state.can_interact_at(state.mentor["cell"]):
		return
	var price := SkillMentor.cost(state.mentor)
	_show_modal("技能导师 · 本次%d原质" % price, message)
	var content = modal_layer.get_child(0).get_child(0)
	var scroll = content.get_child(1)
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()
	var list := UIKit.vbox(7)
	scroll.add_child(list)
	list.add_child(UIKit.wrapped(message if message != "" else "选择携带队伍的已学招式，每招每局强化一次。成功后下次费用增加8原质。", 14))
	var count := 0
	for record in app.run.carried:
		var uid := int(record["uid"])
		for upgrade_id in app.run.available_monster_upgrades(uid):
			var info := RunState.upgrade_info(upgrade_id)
			var skill := String(info["requires_skill"])
			var button := UIKit.button("%s · %s\n%s · %d原质" % [SpeciesDB.name_of(record["species_id"]), SkillDB.name_of(skill), info["desc"], price], 14)
			button.name = "MentorTrain_%d_%s" % [uid, skill]
			button.disabled = app.run.essence < price
			button.pressed.connect(func() -> void:
				var result: Dictionary = app.mentor_train(state, uid, skill)
				_refresh_after_action()
				_show_mentor(result["reason"]))
			list.add_child(button)
			count += 1
	if count == 0:
		list.add_child(UIKit.label("携带队伍没有可强化的已学招式。", 14))


func _show_merchant(message: String = "") -> void:
	_show_modal("商人 · 原质 %d" % app.run.essence, message)
	var content = modal_layer.get_child(0).get_child(0)
	var scroll = content.get_child(1)
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()
	var list := UIKit.vbox(7)
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(UIKit.wrapped(message if message != "" else "交易不消耗回合。库存不会随重访刷新。", 14))
	for item_id in state.merchant["stock"]:
		var id := String(item_id)
		var is_relic := id.begins_with("relic:")
		var relic := id.trim_prefix("relic:")
		var price := 16 if is_relic else int(Merchant.ITEMS[id][1])
		var title := RelicDB.display_name_of(relic) if is_relic else String(Merchant.ITEMS[id][0])
		var button := UIKit.small_button("购买 %s · %d原质 · 剩%d" % [title, price, int(state.merchant["stock"][id])])
		button.disabled = int(state.merchant["stock"][id]) == 0 or app.run.essence < price or (is_relic and RelicDB.rank(app.run.relic_stacks, relic) >= 3)
		button.tooltip_text = RelicDB.description_of(relic) if is_relic else Merchant.ITEMS[id][2]
		button.pressed.connect(func() -> void: _trade("buy", id))
		list.add_child(button)
	list.add_child(UIKit.label("技能强化 · 每次12原质（亲密度可折扣）", 18, UIKit.ACCENT))
	for record in app.run.carried:
		var uid := int(record["uid"])
		var empty_slots: int = app.run.monster_empty_engraving_slots(record)
		var total_slots: int = app.run.monster_engraving_slots(record)
		list.add_child(UIKit.wrapped("%s · 空刻印槽 %d/%d" % [
			SpeciesDB.name_of(String(record["species_id"])), empty_slots, total_slots,
		], 13, UIKit.TEXT_DIM))
		if empty_slots <= 0:
			list.add_child(UIKit.wrapped("没有空刻印槽，无法继续强化。", 12, UIKit.TEXT_DIM))
			continue
		var equipped: Array = record.get("equipped_skills", [])
		for upgrade_id in app.run.available_monster_upgrades(uid):
			var info := RunState.upgrade_info(String(upgrade_id))
			var skill_id := String(info.get("requires_skill", ""))
			var cost: int = app.run.merchant_skill_upgrade_cost(record)
			var marker := " · 已装备" if equipped.has(skill_id) else " · 未装备"
			var button := UIKit.small_button("强化 %s%s · %d原质\n%s" % [
				SkillDB.name_of(skill_id), marker, cost, String(info.get("desc", "")),
			])
			button.name = "SkillUpgrade_%d_%s" % [uid, skill_id]
			button.disabled = app.run.essence < cost
			button.pressed.connect(_purchase_skill_upgrade.bind(uid, skill_id))
			list.add_child(button)
	list.add_child(UIKit.label("出售", 18, UIKit.ACCENT))
	for kind in app.run.food_inventory:
		var id := String(kind)
		if int(app.run.food_inventory[id]) <= 0:
			continue
		var row := UIKit.hbox(6)
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = int(app.run.food_inventory[id])
		row.add_child(quantity)
		var button := UIKit.small_button("出售%s · 每份1原质" % FoodDB.definition(id)["name"])
		button.pressed.connect(func() -> void: _trade("food", id, int(quantity.value)))
		row.add_child(button)
		list.add_child(row)
	for relic_id in app.run.relic_stacks:
		var id := String(relic_id)
		if RelicDB.rank(app.run.relic_stacks, id) <= 0:
			continue
		var button := UIKit.small_button("出售一级 %s（当前%d级）· 8原质" % [RelicDB.display_name_of(id), RelicDB.rank(app.run.relic_stacks, id)])
		button.pressed.connect(func() -> void: _trade("relic", id))
		list.add_child(button)
	for record in app.run.carried:
		var uid := int(record["uid"])
		var rarity := String(Merchant.RARITIES[Merchant.rarity(String(record["species_id"]))][0])
		var caption := "%s · %s · Lv.%d · HP%d · %d原质" % [SpeciesDB.name_of(String(record["species_id"])), rarity, int(record["level"]), int(record["hp"]), Merchant.monster_price(record)]
		var button := UIKit.small_button("出售 " + caption)
		button.name = "SellMonster_%d" % uid
		button.pressed.connect(_confirm_monster_sale.bind(uid))
		list.add_child(button)


func _confirm_monster_sale(uid: int) -> void:
	var record: Dictionary = app.run.record_by_uid(uid)
	if record.is_empty():
		_show_merchant("该宝可梦已不在背包中。")
		return
	var caption := "%s · Lv.%d · %d原质" % [SpeciesDB.name_of(String(record["species_id"])), int(record["level"]), Merchant.monster_price(record)]
	_show_modal("出售宝可梦", caption + "\n出售后移除本局成员，本次捕获不进入永久收藏；开局前已有收藏保留。")
	var content = modal_layer.get_child(0).get_child(0)
	var cancel: Button = content.get_child(content.get_child_count() - 1)
	cancel.name = "CancelMonsterSaleButton"
	cancel.text = "取消并返回商店"
	cancel.pressed.disconnect(_close_modal)
	cancel.pressed.connect(_show_merchant)
	var confirm := UIKit.small_button("确认出售")
	confirm.name = "ConfirmMonsterSaleButton"
	confirm.pressed.connect(func() -> void: _trade("monster", str(uid)))
	content.add_child(confirm)


func _trade(operation: String, id: String, quantity: int = 1) -> void:
	if busy or _playback_active():
		return
	var result: Dictionary = app.merchant_trade(state, operation, id, quantity)
	selected_uid = 0
	refresh_all()
	_show_merchant(String(result["reason"]))


func _purchase_skill_upgrade(uid: int, skill_id: String) -> void:
	if busy or _playback_active():
		return
	var result: Dictionary = app.purchase_skill_upgrade(state, uid, skill_id)
	selected_uid = 0
	refresh_all()
	_show_merchant(String(result["reason"]))


func _open_menu() -> void:
	_show_modal("战斗菜单", "对战记录、游戏设置和保存返回标题")
	var content := modal_layer.get_child(0).get_child(0)
	for entry in [["对战记录", func() -> void: _show_modal("本场对战记录", "\n".join(_display_state().events))], ["游戏设置", func() -> void: _open_settings()], ["保存并回到标题", func() -> void: _confirm_return()]]:
		var button := UIKit.small_button(String(entry[0]))
		button.pressed.connect(entry[1])
		content.add_child(button)


func _confirm_return() -> void:
	if busy or state.phase != BattleState.PHASE_PLAYER:
		_show_modal("暂不能保存返回", "敌方回合结束后可以保存并返回。关闭菜单即可继续播放。")
		return
	_show_modal("保存并回到标题", "将保存当前回合、站位与战斗记录。下次点击继续上一局即可续战。")
	var button := UIKit.small_button("确认保存并返回")
	button.pressed.connect(func() -> void:
		if not app.save_battle_and_return(state):
			_show_modal("保存失败", "无法写入当前战斗存档，请检查存档目录后重试。")
	)
	modal_layer.get_child(0).get_child(0).add_child(button)


func _open_settings() -> void:
	_show_modal("游戏设置", "音乐音量与窗口显示")
	var content := modal_layer.get_child(0).get_child(0)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.value = app.music_percent
	volume.value_changed.connect(func(value: float) -> void: app.set_music_percent(int(value)))
	content.add_child(volume)
	var mute := CheckButton.new()
	mute.text = "静音"
	mute.button_pressed = app.music_muted
	mute.toggled.connect(func(value: bool) -> void: app.set_music_muted(value))
	content.add_child(mute)
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value: bool) -> void: app.set_fullscreen(value))
	content.add_child(fullscreen)


func _on_skill_pressed(skill_id: String) -> void:
	if busy or _playback_active() or state.ended:
		return
	var unit := state.unit_by_uid(selected_uid)
	if unit == null or unit.channel_lock_round == state.round or not unit.can_act_skill() or not unit.can_use_in_battle(skill_id):
		return
	if _skill_phase_block_reason(unit, skill_id) != "":
		return
	if aim_skill == skill_id:
		_clear_aim()
		return
	aim_skill = skill_id
	aim_cells = []
	aim_first_uid = 0
	capture_mode = false
	aim_entries = state.skill_targets(unit, skill_id)
	board.clear_overlays()
	for entry in aim_entries:
		if String(entry.get("type", "")) == "unit_pair":
			for uid in entry["units"]:
				var pair_target := state.unit_by_uid(int(uid))
				if pair_target != null and not board.attack_cells.has(pair_target.cell):
					board.attack_cells.append(pair_target.cell)
			continue
		var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
		if GridSpec.is_inside(cell):
			board.attack_cells.append(cell)
		if skill_id == "tailwind" or skill_id == "herbal_heal":
			board.area_cells = SkillResolver.support_area(unit.cell, 2 + int(unit.upgrades.get("tailwind_reach", 0)) if skill_id == "tailwind" else 2, skill_id == "tailwind")
		if skill_id == "rooted_grass":
			board.area_cells = SkillResolver.rooted_grass_area(unit)
		if skill_id == "glare":
			board.area_cells = SkillResolver.glare_area(unit)
		if skill_id == "electric_resonance":
			board.area_cells = SkillResolver.resonance_area(unit)
		if skill_id == "magnet_pull":
			for direction in GridSpec.DIRS4:
				for distance in range(1, SkillResolver.magnet_pull_range(unit) + 1):
					var reach: Vector2i = unit.cell + direction * distance
					if GridSpec.is_inside(reach):
						board.area_cells.append(reach)
		if skill_id == "earth_shake":
			for affected in SkillResolver.front_area_cells(unit.cell, entry["dir"], 3):
				if not board.area_cells.has(affected):
					board.area_cells.append(affected)
		if skill_id == "windfire_breath":
			for affected in SkillResolver.half_circle_cells(unit.cell, entry["dir"]):
				if not board.area_cells.has(affected):
					board.area_cells.append(affected)
		if skill_id == "wild_vines":
			for affected in SkillResolver.wild_vines_cells(state, unit, entry["dir"]):
				if not board.area_cells.has(affected):
					board.area_cells.append(affected)
		if skill_id == "electric_spark":
			for affected in SkillResolver.electric_spark_cells(state, unit, entry["dir"]):
				if not board.area_cells.has(affected):
					board.area_cells.append(affected)
	hint_label.text = "电力引擎：依次点击两名高亮友军；右键或 Esc 取消。" if _double_cast_pair_mode() else "瞄准：%s。点击金色格；右键或 Esc 取消。" % SkillDB.name_of(skill_id)
	hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	_rebuild_skill_buttons()
	_position_action_panel()
	board.queue_redraw()


func _on_capture_pressed() -> void:
	if busy or _playback_active() or state.ended:
		return
	var trainer := state.unit_by_uid(selected_uid)
	if trainer == null or not trainer.is_trainer or trainer.capture_used:
		return
	capture_mode = true
	aim_skill = ""
	aim_cells = []
	aim_first_uid = 0
	board.clear_overlays()
	for cell in GridSpec.all_cells():
		var delta: Vector2i = cell - trainer.cell
		if maxi(absi(delta.x), absi(delta.y)) <= Balance.CAPTURE_RANGE:
			board.area_cells.append(cell)
	for enemy in _capture_targets(trainer):
		board.attack_cells.append(enemy.cell)
	hint_label.text = "捕获：橙色为周围两格捕捉范围（金色为合法目标，包含斜向，不受障碍阻挡）。"
	hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
	_position_action_panel()
	board.queue_redraw()


func _clear_aim() -> void:
	item_aim = ""
	if aim_skill == "" and not capture_mode:
		return
	aim_skill = ""
	aim_cells = []
	aim_first_uid = 0
	capture_mode = false
	aim_entries = []
	action_mode = "main"
	board.clear_overlays()
	hint_label.text = "已取消瞄准。"
	hint_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_rebuild_skill_buttons()
	_update_selection_overlay()
	board.queue_redraw()
	_position_action_panel()


func _cancel_action() -> void:
	if action_panel.visible:
		_dismiss_action_panel()
		return
	if aim_skill != "" or capture_mode or item_aim != "":
		_clear_aim()
		return
	if action_mode != "main":
		action_mode = "main"
		hint_label.text = "已返回行动选择。"
		board.clear_overlays()
		_update_selection_overlay()
		_rebuild_skill_buttons()
		_position_action_panel()
		board.queue_redraw()
		return
	selected_uid = 0
	viewed_enemy_uid = 0
	action_mode = "main"
	board.selected_uid = 0
	board.clear_overlays()
	_update_unit_card()
	_rebuild_skill_buttons()
	_position_action_panel()
	board.queue_redraw()


func _find_entry(cell: Vector2i) -> Dictionary:
	if _double_cast_pair_mode():
		if aim_first_uid == 0:
			return {}
		var target := state.unit_at(cell)
		if target == null or target.uid == aim_first_uid:
			return {}
		for entry in aim_entries:
			if (entry["units"] as Array).has(aim_first_uid) and (entry["units"] as Array).has(target.uid):
				return entry
		return {}
	for entry in aim_entries:
		var entry_cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
		if entry_cell == cell:
			return entry
	return {}


func _double_cast_pair_mode() -> bool:
	return aim_skill == "double_cast" and not aim_entries.is_empty() and String(aim_entries[0].get("type", "")) == "unit_pair"


func _pair_has_uid(uid: int) -> bool:
	for entry in aim_entries:
		if (entry.get("units", []) as Array).has(uid):
			return true
	return false


func _try_cast_at(cell: Vector2i) -> void:
	if _double_cast_pair_mode() and aim_first_uid == 0:
		var first := state.unit_at(cell)
		if first == null or not _pair_has_uid(first.uid):
			hint_label.text = "请选择一名高亮的相邻友军。"
			hint_label.add_theme_color_override("font_color", UIKit.BAD)
			return
		aim_first_uid = first.uid
		board.attack_cells = []
		for pair in aim_entries:
			if not (pair["units"] as Array).has(aim_first_uid):
				continue
			for uid in pair["units"]:
				if int(uid) == aim_first_uid:
					continue
				var second := state.unit_by_uid(int(uid))
				if second != null and not board.attack_cells.has(second.cell):
					board.attack_cells.append(second.cell)
		board.area_cells = [first.cell]
		hint_label.text = "已选择 %s；点击第二名高亮友军。" % first.display_name
		hint_label.add_theme_color_override("font_color", UIKit.ACCENT)
		board.queue_redraw()
		return
	var entry := _find_entry(cell)
	if entry.is_empty():
		hint_label.text = "该格不在技能有效范围内。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
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
	if busy or _playback_active() or state.ended:
		return false
	var unit := state.unit_by_uid(selected_uid)
	if unit == null:
		return false
	if not state.move_unit(unit, cell):
		return false
	action_mode = "main"
	hint_label.text = "已移动，选择下一步行动。"
	app.sync_and_save(state)
	viewed_enemy_uid = 0
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_cast(skill_id: String, entry: Dictionary) -> bool:
	if busy or _playback_active() or state.ended:
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
	aim_first_uid = 0
	capture_mode = false
	action_mode = "main"
	app.sync_and_save(state)
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_capture(target_uid: int) -> bool:
	if busy or _playback_active() or state.ended:
		return false
	var trainer := state.unit_by_uid(selected_uid)
	var target := state.unit_by_uid(target_uid)
	if trainer == null or target == null:
		return false
	var result := state.capture_attempt(trainer, target)
	if not bool(result.get("ok", false)):
		hint_label.text = "无法捕获：目标须在周围两格，本回合尚未尝试，且满足当前生命规则。"
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		return false
	capture_mode = false
	action_mode = "main"
	app.sync_and_save(state)
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_undo() -> bool:
	if busy or _playback_active() or state.ended:
		return false
	if not state.undo_last_move():
		return false
	action_mode = "main"
	hint_label.text = "已撤回移动，选择下一步行动。"
	app.sync_and_save(state)
	board.clear_overlays()
	_refresh_after_action()
	return true


func do_leave_node() -> void:
	if busy or _playback_active() or state == null:
		return
	if not state.can_leave_node() and state.can_escape() and not state.escape_stragglers().is_empty():
		var names := state.escape_stragglers().map(func(u): return "%s (#%d)：%d→%d HP" % [u.display_name, u.uid, u.hp, state.escape_hp_after(u)])
		_show_modal("撤离确认", "区外队员扣除最大生命25%%（向上取整）：\n%s\n0 HP者濒死，%d个携带奖励点留在原格，需重访拾取。存活者保留奖励。已入账经验保留，可取消返回撤离区。" % ["\n".join(names), state.escape_losses().size()])
		var button := UIKit.button("确认撤离（区外扣血，可能濒死）")
		button.name = "ConfirmEmergencyEscape"
		button.pressed.connect(func() -> void:
			_close_modal()
			if state.leave_node(true):
				app.sync_and_save(state)
				refresh_all())
		modal_layer.get_child(0).get_child(0).add_child(button)
		return
	if state.leave_node():
		app.sync_and_save(state)
		refresh_all()


func do_end_turn() -> void:
	if busy or _playback_active() or state.ended or state.is_free_exploration() or state.phase != BattleState.PHASE_PLAYER:
		return
	action_mode = "main"
	_clear_aim()
	board.clear_overlays()
	_enemy_phase()


func _enemy_phase() -> void:
	busy = true
	_update_action_buttons()
	battle_notice.push("敌方回合", "enemy")
	await _wait_playback()
	if not is_inside_tree():
		return
	state.begin_enemy_phase()
	await _wait_playback()
	_update_header()
	_update_channel_markers()
	_update_log()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
		await _wait_playback()
		board.set_from_state(_display_state())
		_update_header()
		_update_team_list()
		_update_log()
		app.sync_and_save(state)
		if state.ended:
			break
	if not state.ended:
		state.end_enemy_phase()
		await _wait_playback()
		app.sync_and_save(state)
		if not state.ended and not state.is_free_exploration():
			battle_notice.push("我方回合", "player")
			await _wait_playback()
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
	_check_victory_notice()
	board.set_from_state(_display_state())
	_update_header()
	_update_team_list()
	_update_unit_card()
	_rebuild_skill_buttons()
	_update_action_buttons()
	_update_channel_markers()
	_update_log()
	_update_selection_overlay()
	_position_action_panel()
	board.queue_redraw()
	if state.ended and not settled_reported:
		settled_reported = true
		call_deferred("_report_end")


func report_end_now() -> void:
	if state != null and state.ended and app != null:
		app.finish_battle(state)


func _report_end() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	await _wait_playback()
	if not is_inside_tree():
		return
	var tail := minf(0.5, feedback_layer.remaining_time())
	if tail > 0.0:
		await get_tree().create_timer(tail / app.battle_playback_speed).timeout
	await _wait_playback()
	if state != null and state.ended and is_inside_tree():
		if state.end_reason == "escape":
			while speech_layer.active() and is_inside_tree():
				await get_tree().process_frame
		var kind := result_notice_kind(state.end_reason)
		if kind != "" and not (kind == "victory" and victory_announced):
			battle_notice.push({"victory": "胜利", "defeat": "失败", "escape": "撤退"}[kind], kind)
			await _wait_playback()
		if is_inside_tree():
			app.finish_battle(state)


func _dismiss_action_panel() -> void:
	merchant_actions_open = false
	action_mode = "main"
	selected_uid = 0
	viewed_enemy_uid = 0
	board.selected_uid = 0
	board.clear_overlays()
	_update_channel_markers()
	_update_unit_card()
	_position_action_panel()
	board.queue_redraw()


func _input(event: InputEvent) -> void:
	if modal_layer != null or action_panel == null or not action_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if action_panel.get_global_rect().has_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_LEFT and board.get_global_rect().has_point(event.position):
			return
		_dismiss_action_panel()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_layer != null:
			_close_modal()
		elif aim_skill != "" or capture_mode or item_aim != "" or selected_uid != 0 or viewed_enemy_uid != 0:
			_cancel_action()
		else:
			_open_menu()


static func result_notice_kind(reason: String) -> String:
	if reason == "victory":
		return "victory"
	if reason in ["forced_retreat", "boss_timeout"]:
		return "defeat"
	return "escape" if reason == "escape" else ""

func _announce_initial_phase() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or state.ended or state.is_free_exploration() or state.round != 1 or state.phase != BattleState.PHASE_PLAYER:
		return
	battle_notice.push("我方回合", "player")

func _check_victory_notice() -> void:
	if victory_announced or state.ended or not (state.is_free_exploration() and state.node_kind == "battle" or GridSpec.is_inside(state.boss_portal_cell)):
		return
	victory_announced = true
	call_deferred("_announce_victory")

func _announce_victory() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	await _wait_playback()
	while speech_layer.active() and is_inside_tree():
		await get_tree().process_frame
	if is_inside_tree() and not state.ended:
		battle_notice.push("胜利", "victory")
