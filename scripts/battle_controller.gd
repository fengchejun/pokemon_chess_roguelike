extends Control

const CombatConfig = preload("res://scripts/combat_config.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")
const GridSpec = preload("res://scripts/grid_spec.gd")
const BattleBuffSystem = preload("res://scripts/battle_buff_system.gd")

@onready var board: BattleBoard = $Layout/Column/MainRow/BoardCenter/BattleBoard
@onready var turn_label: Label = $Layout/Column/Header/TurnLabel
@onready var team_status_track: HBoxContainer = $Layout/Column/TeamStatusScroll/TeamStatusTrack
@onready var selected_label: Label = $Layout/Column/ActionBar/ActionRow/SelectedLabel
@onready var skill_buttons: HBoxContainer = $Layout/Column/ActionBar/ActionRow/SkillScroll/SkillButtons
@onready var roster_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/RosterLabel
@onready var environment_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/EnvironmentLabel
@onready var terrain_detail_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/TerrainDetailLabel
@onready var enemy_detail_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/EnemyDetailLabel
@onready var preview_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/PreviewLabel
@onready var status_label: Label = $Layout/Column/MainRow/SidePanel/InfoScroll/InfoColumn/StatusLabel
@onready var log_label: Label = $Layout/Column/MainRow/LogPanel/LogColumn/LogScroll/LogLabel
@onready var log_scroll: ScrollContainer = $Layout/Column/MainRow/LogPanel/LogColumn/LogScroll
@onready var end_turn_button: Button = $Layout/Column/Header/EndTurnButton
@onready var result_button: Button = $Layout/Column/MainRow/SidePanel/ResultButton
@onready var undo_move_button: Button = $Layout/Column/Header/UndoMoveButton
@onready var reward_overlay: Control = $RewardChoiceOverlay
@onready var reward_choice_a: Button = $RewardChoiceOverlay/Center/ChoicePanel/ChoiceColumn/ChoiceA
@onready var reward_choice_b: Button = $RewardChoiceOverlay/Center/ChoicePanel/ChoiceColumn/ChoiceB

var state: BattleState
var selected_unit_id: String = "trainer"
var status_message: String = ""
var action_mode: String = "move"
var hover_cell: Vector2i = Vector2i(-1, -1)
var inspected_enemy_id: String = ""


func _ready() -> void:
	board.cell_pressed.connect(_on_cell_pressed)
	board.directed_skill_pressed.connect(_on_directed_skill_pressed)
	board.cell_hovered.connect(_on_cell_hovered)
	board.mouse_exited.connect(_on_board_mouse_exited)
	reward_choice_a.pressed.connect(_on_reward_choice_pressed.bind(0))
	reward_choice_b.pressed.connect(_on_reward_choice_pressed.bind(1))
	_start_new_battle()


func _unhandled_input(event: InputEvent) -> void:
	if action_mode == "move" or state == null or state.phase != "player":
		return
	var cancel: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	cancel = cancel or event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if cancel:
		_cancel_aim()
		get_viewport().set_input_as_handled()


func _start_new_battle() -> void:
	var run: RunState = RunManager.run_state
	var region_id: String = MapGenerator.region_for_battle(run.battle_count)
	var layout: Dictionary = MapGenerator.generate(region_id, run.environment_cards, run.run_seed + run.battle_count * 7919)
	state = BattleState.new(run, layout)
	selected_unit_id = state.current_player_ids()[0] if not state.current_player_ids().is_empty() else "trainer"
	action_mode = "move"
	hover_cell = Vector2i(-1, -1)
	inspected_enemy_id = ""
	status_message = "六回合内击败敌人或摧毁巢穴；巢穴产怪前一回合会预警。"
	_refresh()


func _on_cell_pressed(cell: Vector2i) -> void:
	var clicked: CombatUnit = state.unit_at(cell)
	var caster: CombatUnit = state.unit_by_id(selected_unit_id)
	var ally_skill_target: bool = clicked != null and clicked.team == "player" and action_mode.begins_with("skill:") and state.can_use_skill(caster, action_mode.trim_prefix("skill:"), cell)
	if clicked != null and clicked.team == "player" and not ally_skill_target:
		selected_unit_id = clicked.unit_id
		action_mode = "move"
		inspected_enemy_id = ""
		status_message = "已选择 %s。" % clicked.display_name
		_refresh()
		return
	if state.outcome != "":
		return
	if clicked != null and clicked.team == "enemy":
		inspected_enemy_id = clicked.unit_id
		if action_mode == "move":
			status_message = "已查看 %s 的移动范围。" % clicked.display_name
			_refresh()
			return
	var selected: CombatUnit = state.unit_by_id(selected_unit_id)
	if selected == null or not selected.is_alive():
		status_message = "请先选择一名存活的己方单位。"
	elif not state.can_act_now(selected):
		status_message = "当前不是我方行动阶段，或该单位已倒下。"
	elif action_mode == "capture":
		var old_capture_points: int = selected.capture_points
		var captured: bool = state.try_capture(clicked.unit_id if clicked != null else "")
		if selected.capture_points < old_capture_points:
			action_mode = "move"
		if captured and state.outcome == "" and clicked != null:
			selected_unit_id = clicked.unit_id
			inspected_enemy_id = ""
		status_message = state.events.back()
	elif action_mode.begins_with("skill:"):
		if state.try_use_skill(selected_unit_id, action_mode.trim_prefix("skill:"), cell):
			action_mode = "move"
		status_message = state.events.back()
	elif clicked == null:
		inspected_enemy_id = ""
		state.try_player_move(selected_unit_id, cell)
		status_message = state.events.back()
	else:
		status_message = "选择怪物技能后点击目标；移动模式不能攻击。"
	_refresh()


func _on_directed_skill_pressed(cell: Vector2i) -> void:
	if action_mode not in ["skill:rock_create", "skill:rain_call"] or state.outcome != "":
		return
	if state.try_use_skill(selected_unit_id, action_mode.trim_prefix("skill:"), cell):
		action_mode = "move"
	status_message = state.events.back()
	_refresh()


func _on_cell_hovered(cell: Vector2i) -> void:
	hover_cell = cell
	_refresh_terrain_detail()
	_refresh_preview()


func _on_board_mouse_exited() -> void:
	hover_cell = Vector2i(-1, -1)
	_refresh_terrain_detail()
	_refresh_preview()


func _on_action_button_pressed(mode: String) -> void:
	var selected: CombatUnit = state.unit_by_id(selected_unit_id)
	if selected == null or not state.can_act_now(selected):
		return
	if mode == "capture":
		if selected.unit_id != "trainer" or selected.capture_points <= 0:
			return
	elif mode.begins_with("skill:"):
		var skill_id: String = mode.trim_prefix("skill:")
		if not selected.skill_ids.has(skill_id) or not CombatConfig.SKILLS.has(skill_id):
			return
		var skill: Dictionary = CombatConfig.SKILLS[skill_id]
		var use_limit: int = int(skill.get("uses_per_battle", 0))
		if selected.skill_points < int(skill["cost"]) or state.terrain.is_steam(selected.cell) or use_limit > 0 and int(selected.battle_skill_uses.get(skill_id, 0)) >= use_limit:
			return
	else:
		return
	action_mode = "move" if action_mode == mode else mode
	status_message = "已选择 %s；点击目标格施放，Esc 或右键取消。" % _mode_name(action_mode) if action_mode != "move" else "已返回直接移动。"
	_refresh()


func _cancel_aim() -> void:
	action_mode = "move"
	status_message = "已取消瞄准，可直接移动。"
	_refresh()


func _on_end_turn_pressed() -> void:
	if not state.finish_player_turn():
		return
	inspected_enemy_id = ""
	var active_ids: Array[String] = state.current_player_ids()
	if not active_ids.is_empty():
		selected_unit_id = active_ids[0]
		action_mode = "move"
	status_message = "轮到我方整队行动。" if not active_ids.is_empty() else state.events.back()
	_refresh()


func _on_reward_choice_pressed(index: int) -> void:
	if index < 0 or index >= state.reward_choices.size():
		return
	var chosen: String = state.reward_choices[index]
	if state.choose_reward_buff(chosen):
		status_message = "已选择 %s。" % BattleBuffSystem.description(chosen)
		_refresh()


func _on_undo_move_pressed() -> void:
	var unit_id: String = state.movement_history.back()["unit_id"] if state.can_undo_move() else ""
	if state.undo_last_move():
		selected_unit_id = unit_id
		action_mode = "move"
		inspected_enemy_id = ""
		status_message = state.events.back()
	else:
		status_message = "当前没有可撤回的移动。"
	_refresh()


func _on_restart_pressed() -> void:
	RunManager.start_new_run()
	get_tree().change_scene_to_file("res://scenes/starter_selection.tscn")


func _on_result_pressed() -> void:
	if state.outcome == "defeat":
		RunManager.start_new_run()
		get_tree().change_scene_to_file("res://scenes/starter_selection.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/between_battles.tscn")


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh() -> void:
	if state.outcome != "" and not state.reward_claimed and not state.can_undo_move():
		RunManager.run_state.apply_battle_result(state)
	if inspected_enemy_id != "":
		var inspected: CombatUnit = state.unit_by_id(inspected_enemy_id)
		if inspected == null or not inspected.is_alive():
			inspected_enemy_id = ""
	var selected: CombatUnit = state.unit_by_id(selected_unit_id)
	if action_mode.begins_with("skill:") and (selected == null or not selected.skill_ids.has(action_mode.trim_prefix("skill:"))):
		action_mode = "move"
	if action_mode == "capture" and (selected == null or selected.unit_id != "trainer"):
		action_mode = "move"
	board.battle_state = state
	board.selected_unit_id = selected_unit_id
	board.inspected_enemy_id = inspected_enemy_id
	board.action_mode = action_mode
	board.hover_cell = hover_cell
	board.queue_redraw()
	var phase_text: String = "我方行动" if state.phase == "player" else "敌方行动" if state.phase in ["enemy_move", "enemy_attack"] else "选择战斗 Buff" if state.phase == "reward_choice" else "回合结算" if state.phase == "round_settlement" else "战斗结束"
	turn_label.text = "第 %d/%d 回合 · 剩余 %d · %s" % [state.turn_number, CombatConfig.MAX_PLAYER_ROUNDS, maxi(0, CombatConfig.MAX_PLAYER_ROUNDS - state.turn_number + 1) if state.outcome == "" else 0, phase_text]
	if state.nest_spawn_notice() != "":
		turn_label.text += "\n⚠ " + state.nest_spawn_notice().trim_prefix("巢穴预警：")
	_refresh_team_status_track()
	if selected == null:
		selected_label.text = "选中单位：无"
	else:
		var movement_blocked: bool = state.is_rooted_now(selected) or selected.frozen or selected.frozen_skip_round == state.turn_number or selected.paralyzed_skip_round == state.turn_number
		var move_limit: int = 0 if movement_blocked else state.effective_move_range(selected)
		selected_label.text = "%s · HP %d/%d\n移动 %s（最远 %d） · %s\n%s" % [selected.display_name, selected.hp, selected.max_hp, "受控" if movement_blocked else "可用" if selected.move_points > 0 else "已用", move_limit, _unit_status_text(selected), "捕获 %d/%d" % [selected.capture_points, CombatConfig.CAPTURE_ATTEMPTS_PER_TURN] if selected.unit_id == "trainer" else "技能点 %d" % selected.skill_points]
	_refresh_skill_buttons(selected)
	var player_lines: Array[String] = []
	var enemy_lines: Array[String] = []
	for unit in state.units:
		var status: String = "%s%d/%d%s%s%s%s%s%s" % [unit.glyph, unit.hp, unit.max_hp, "灼" if unit.burned else "", "湿" if unit.wet else "", "电" if unit.shocked else "", "麻" if unit.paralyzed_skip_round > 0 else "", "冻" if unit.frozen else "", "★" if unit.battle_buff != "" else ""] if unit.is_alive() else "%s倒下" % unit.glyph
		if unit.team == "player":
			player_lines.append(status)
		else:
			enemy_lines.append(status)
	roster_label.text = "己方：%s\n敌方：%s" % ["  ".join(player_lines), "  ".join(enemy_lines)]
	var map_info: Dictionary = state.map_info
	var counts := {"shallow_water": 0, "deep_water": 0, "grass": 0, "vine": 0, "ice": 0, "fragile": 0, "collapsed": 0, "rock": 0}
	for terrain_kind in state.terrain.ground.values():
		if counts.has(terrain_kind):
			counts[terrain_kind] += 1
	for terrain_object in state.terrain.objects.values():
		if terrain_object.get("type", "") == "rock":
			counts["rock"] += 1
	var combo_lines: Array[String] = []
	combo_lines.assign(map_info.get("combinations", []))
	var nest_text: String = "巢穴 %d/%d · 待产 %d · %s · 摧毁即胜" % [state.nest.get("hp", 0), CombatConfig.NEST_HP, state.pending_nest_spawns.size(), "守口防御 1" if state.nest_exit_guarded() else "第2/4轮排队"] if not state.nest.is_empty() else "测试布局：无巢穴"
	var reward_text: String = "待争夺%s" % ("（末轮我方不可领取）" if state.turn_number == CombatConfig.MAX_PLAYER_ROUNDS else "") if state.reward_state == "ground" else "由 %s 领取" % state.reward_winner_id if state.reward_state == "claimed" else "已损毁" if state.reward_state == "destroyed" else "末轮失效" if state.reward_state == "expired" else "无"
	environment_label.text = "区域：%s%s\n浅 %d · 深 %d · 草 %d · 藤 %d · 冰 %d · 裂 %d · 坑 %d · 岩 %d\n%s · 奖励：%s\n%s" % [map_info.get("region_name", "测试布局"), "（备用）" if map_info.get("fallback", false) else "", counts.get("shallow_water", 0), counts.get("deep_water", 0), counts.get("grass", 0), counts.get("vine", 0), counts.get("ice", 0), counts.get("fragile", 0), counts.get("collapsed", 0), counts.get("rock", 0), nest_text, reward_text, "；".join(combo_lines) if not combo_lines.is_empty() else "浅水浸湿；藤蔓束缚；火可融冰"]
	_refresh_terrain_detail()
	_refresh_enemy_detail()
	undo_move_button.disabled = not state.can_undo_move()
	undo_move_button.text = "撤回移动（%d）" % state.movement_history.size() if state.can_undo_move() else "撤回移动"
	_refresh_preview()
	status_label.text = "训练家因移动倒下：可撤回移动，或重新开始本局。" if state.outcome == "defeat" and state.can_undo_move() else "战斗胜利！" if state.outcome == "victory" else "训练家被击败，本局结束。" if state.outcome == "defeat" else "野生怪物逃离，本场未获胜。" if state.outcome == "escape" else status_message
	log_label.text = "\n\n".join(state.events)
	call_deferred("_scroll_log_to_bottom")
	end_turn_button.disabled = state.phase != "player" or state.outcome != ""
	end_turn_button.text = "结束回合"
	result_button.disabled = state.outcome == ""
	result_button.text = "重新开始本局" if state.outcome == "defeat" else "战后整备"
	reward_overlay.visible = state.phase == "reward_choice"
	if reward_overlay.visible and state.reward_choices.size() == 2:
		reward_choice_a.text = BattleBuffSystem.description(state.reward_choices[0])
		reward_choice_b.text = BattleBuffSystem.description(state.reward_choices[1])


func _scroll_log_to_bottom() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(log_scroll):
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _refresh_team_status_track() -> void:
	for child in team_status_track.get_children():
		team_status_track.remove_child(child)
		child.queue_free()
	for unit in state.units:
		if unit.team != "player":
			continue
		var chip := Label.new()
		chip.custom_minimum_size = Vector2(120, 40)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", 13)
		var second_action: String = "捕" if unit.unit_id == "trainer" else "技"
		var second_ready: bool = unit.capture_points > 0 if unit.unit_id == "trainer" else unit.skill_points > 0
		chip.text = "%s  HP %d/%d\n移%s · %s%s" % [unit.glyph, unit.hp, unit.max_hp, "禁" if state.is_rooted_now(unit) or unit.frozen or unit.frozen_skip_round == state.turn_number or unit.paralyzed_skip_round == state.turn_number else "可" if unit.move_points > 0 else "已用", second_action, "可" if second_ready else "已用"] if unit.is_alive() else "%s  倒下" % unit.glyph
		chip.add_theme_color_override("font_color", Color(0.61, 0.95, 0.78) if unit.is_alive() and state.phase == "player" else Color(0.58, 0.62, 0.64))
		team_status_track.add_child(chip)


func _unit_status_text(unit: CombatUnit) -> String:
	var labels: Array[String] = []
	if unit.battle_buff != "":
		labels.append(BattleBuffSystem.short_name(unit.battle_buff))
	if unit.burned:
		labels.append("灼烧")
	if unit.wet:
		labels.append("浸湿")
	if unit.shocked:
		labels.append("感电")
	if unit.paralyzed_skip_round > 0:
		labels.append("麻痹")
	if unit.frozen or unit.frozen_skip_round > 0:
		labels.append("冻结")
	if unit.rooted_skip_round > 0:
		labels.append("藤蔓束缚")
	if unit.temporary_move_bonus_round == state.turn_number:
		labels.append("加速 +2")
	if unit.double_cast_round == state.turn_number:
		labels.append("本轮两次施法")
	return "、".join(labels) if not labels.is_empty() else "正常"


func _refresh_skill_buttons(selected: CombatUnit) -> void:
	for child in skill_buttons.get_children():
		skill_buttons.remove_child(child)
		child.queue_free()
	if selected == null:
		return
	var modes: Array[String] = []
	if selected.unit_id == "trainer":
		modes.append("capture")
	for skill_id in selected.skill_ids:
		modes.append("skill:" + skill_id)
	for mode in modes:
		var button := Button.new()
		button.name = "CaptureButton" if mode == "capture" else "SkillButton_" + mode.trim_prefix("skill:")
		button.custom_minimum_size = Vector2(142, 62)
		button.add_theme_font_size_override("font_size", 13)
		button.toggle_mode = true
		button.button_pressed = action_mode == mode
		var reasons: Array[String] = []
		if not state.can_act_now(selected):
			reasons.append("当前不能行动")
		if mode == "capture":
			button.text = "捕获\n机会 %d/%d" % [selected.capture_points, CombatConfig.CAPTURE_ATTEMPTS_PER_TURN]
			if selected.capture_points <= 0:
				reasons.append("捕获机会已用")
			button.tooltip_text = "周围八格、生命不高于一半的野生怪物可捕获。1 HP 必定成功；有任意减益状态时 2 HP 也必定成功。成功后原地成为可行动队友；战后仅收容存活者。"
		else:
			var skill_id: String = mode.trim_prefix("skill:")
			var skill: Dictionary = CombatConfig.SKILLS[skill_id]
			button.text = "%s\n消耗 %d 点" % [skill["name"], skill["cost"]]
			if selected.skill_points < int(skill["cost"]):
				reasons.append("技能点不足（%d/%d）" % [selected.skill_points, int(skill["cost"])])
			var use_limit: int = int(skill.get("uses_per_battle", 0))
			if use_limit > 0 and int(selected.battle_skill_uses.get(skill_id, 0)) >= use_limit:
				reasons.append("本场使用次数已用尽")
			if state.terrain.is_steam(selected.cell):
				reasons.append("站在蒸汽雾中不能施法")
			button.tooltip_text = str(skill["description"]) + "\n施放后将用完本回合尚未使用的移动机会。"
			if selected.upgraded_skill_id == skill_id:
				button.text += " ★"
				button.tooltip_text += "\n强化：" + BattleBuffSystem.description(selected.battle_buff)
		button.disabled = not reasons.is_empty()
		if not reasons.is_empty():
			var reason_label := "暂不能行动"
			if reasons.has("站在蒸汽雾中不能施法"):
				reason_label = "雾中禁用"
			elif reasons.has("本场使用次数已用尽"):
				reason_label = "本场已用"
			elif mode == "capture" and selected.capture_points <= 0:
				reason_label = "捕获机会已用"
			elif mode != "capture" and selected.skill_points < int(CombatConfig.SKILLS[mode.trim_prefix("skill:")]["cost"]):
				reason_label = "技能点不足"
			button.text += "\n" + reason_label
			button.tooltip_text += "\n不可用：" + "；".join(reasons)
		button.pressed.connect(_on_action_button_pressed.bind(mode))
		skill_buttons.add_child(button)


func _refresh_terrain_detail() -> void:
	if state == null or not GridSpec.is_inside(hover_cell):
		terrain_detail_label.text = "地块详情：悬停特殊地块查看"
		return
	var terrain: TerrainManager = state.terrain
	var cell: Vector2i = hover_cell
	var details: Array[String] = []
	match terrain.ground_at(cell):
		"shallow_water", "water":
			details.append("浅水：回合末仍站在这里的非水系单位获得浸湿，下一轮移动力 -1；入水解除灼烧，放电可沿连通水域传导。")
		"deep_water":
			details.append("深水：非水系单位不能主动进入，被推入会立即溺亡；水系可以进入，放电可沿水域传导。")
		"grass":
			details.append("草丛：可站立；受火点燃后每次回合结算向相邻可燃物蔓延，燃烧两次结算后烧尽。")
		"vine":
			details.append("藤蔓：可燃、可站立；进入或在脚下生成时，下一次行动不能主动移动，仍可施法；覆盖浅水时也可燃烧。")
		"ice":
			var underlay: Dictionary = terrain.ice_underlay.get(cell, {})
			details.append("冰面：本场持续，可行走；火命中会融化并露出原地形%s。" % ("（%s）" % str(underlay.get("ground", "地面")) if not underlay.is_empty() else ""))
		"fragile":
			details.append("易碎地块：可站立；被造岩作用时塌为深坑，地面单位立即坠亡；造雨可将其变为浅水。")
		"collapsed":
			details.append("塌陷深坑：不可主动进入；被强制位移到这里的地面单位立即坠亡，深坑不会自行恢复。")
	var object: Dictionary = terrain.object_at(cell)
	if object.get("type", "") == "rock":
		var rock_text: String = "岩石：耐久 %d；阻挡移动和火、水射线，可被碎岩等技能破坏。" % int(object.get("hp", 0))
		if int(object.get("expire_after_enemy_round", 0)) > 0:
			rock_text += " 临时岩石，将在对应敌方行动结束后消失。"
		details.append(rock_text)
	elif object.get("type", "") == "plant":
		details.append("树木：耐久 %d；阻挡移动及火、水射线。可被点燃，燃烧两次回合结算后烧尽。" % int(object.get("hp", 0)))
	if terrain.is_burning(cell):
		details.append("燃烧：剩余 %d 次结算；每次向四邻可燃物扩散，非火系单位在结算时获得灼烧。" % int(terrain.burning[cell]))
	if terrain.is_steam(cell):
		details.append("蒸汽雾：剩余 %d 次结算；站在雾中的怪物不能施放技能，仍可移动。" % int(terrain.steam[cell]))
	if state.is_nest_at(cell):
		details.append("巢穴：耐久 %d；第 2、4 回合新增产怪请求，目前 %d 只排队。每回合最多产一只，堵口则延后；新怪出生轮待机。摧毁后立即获胜。" % [int(state.nest.get("hp", 0)), state.pending_nest_spawns.size()])
		if state.nest_exit_guarded():
			details.append("敌方守住出口：巢穴防御 1；每次命中先减 1 点伤害，1 点伤害无法降低耐久。")
	elif not state.nest.is_empty() and int(state.nest.get("hp", 0)) > 0 and state.nest.get("exit", Vector2i(-1, -1)) == cell:
		details.append("巢穴出口：被单位或障碍占据时，增援排队；下回合出口空出即继续产怪。")
	if state.reward_state == "ground" and state.reward_cell == cell:
		details.append("战斗 Buff 奖励：双方均可争夺；守到对方阶段结束后领取一次，随机二选一；第 6 回合敌方结束后我方不再领取。")
	terrain_detail_label.text = "地块 (%d, %d)：%s" % [cell.x + 1, cell.y + 1, "\n".join(details)] if not details.is_empty() else "地块详情：悬停特殊地块查看"


func _refresh_enemy_detail() -> void:
	var enemy: CombatUnit = state.unit_by_id(inspected_enemy_id) if inspected_enemy_id != "" else null
	if enemy == null or not enemy.is_alive():
		enemy_detail_label.text = "敌人详情：点击敌人查看"
		return
	var element_names := {"fire": "火", "water": "水", "rock": "岩", "electric": "电", "grass": "草", "ice": "冰", "wind": "风"}
	var statuses: Array[String] = []
	if enemy.wet:
		statuses.append("浸湿：移动力 -1")
	if enemy.burned:
		statuses.append("灼烧：后续结算每回合受 1 伤；入水解除")
	if enemy.shocked:
		statuses.append("感电：再次感电将麻痹")
	if enemy.paralyzed_skip_round > 0:
		statuses.append("麻痹：第 %d 回合不能行动" % enemy.paralyzed_skip_round)
	if enemy.frozen or enemy.frozen_skip_round > 0:
		statuses.append("冻结：首次受伤免伤解冻；第 %d 回合不能行动" % enemy.frozen_skip_round)
	if enemy.rooted_skip_round > 0:
		statuses.append("藤蔓束缚：第 %d 回合不能主动移动" % enemy.rooted_skip_round)
	if state.terrain.is_steam(enemy.cell):
		statuses.append("站在雾中：不能施法")
	if enemy.eligible_round > state.turn_number:
		statuses.append("本轮增援待机")
	if enemy.battle_buff != "":
		statuses.append("本场 Buff：" + BattleBuffSystem.description(enemy.battle_buff))
	var skills: Array[String] = []
	for skill_id in enemy.skill_ids:
		var skill: Dictionary = CombatConfig.SKILLS[skill_id]
		var spent: bool = int(skill.get("uses_per_battle", 0)) > 0 and int(enemy.battle_skill_uses.get(skill_id, 0)) >= int(skill["uses_per_battle"])
		skills.append("%s%s%s：%s" % [skill["name"], " ★" if enemy.upgraded_skill_id == skill_id else "", "（本场已用）" if spent else "", skill["description"]])
	var current_move_limit: int = 0 if enemy.eligible_round > state.turn_number or state.is_rooted_now(enemy) or enemy.frozen or enemy.frozen_skip_round == state.turn_number or enemy.paralyzed_skip_round == state.turn_number else state.effective_move_range(enemy)
	enemy_detail_label.text = "敌人详情：%s（%s）· 格 (%d, %d)\n生命 %d/%d · 本轮移动%s · 移动上限 %d 格 · 技能点 %d\n状态：%s\n技能：\n%s" % [enemy.display_name, element_names.get(enemy.element_type, enemy.element_type), enemy.cell.x + 1, enemy.cell.y + 1, enemy.hp, enemy.max_hp, "可用" if enemy.move_points > 0 else "已用", current_move_limit, enemy.skill_points, "；".join(statuses) if not statuses.is_empty() else "正常", "\n".join(skills)]


func _refresh_preview() -> void:
	var selected: CombatUnit = state.unit_by_id(selected_unit_id)
	if selected == null or not selected.is_alive():
		preview_label.text = "行动预览：无"
		return
	var hovered: CombatUnit = state.unit_at(hover_cell)
	if action_mode == "capture":
		if hovered == null or hovered.team != "enemy":
			preview_label.text = "捕获：选择周围八格、生命不高于一半的野生怪物；1 HP 或带任意减益的 2 HP 必定成功。每回合一次。"
		else:
			preview_label.text = "捕获 %s：%d%%；%s" % [hovered.display_name, roundi(state.capture_chance(hovered) * 100.0), "可尝试" if state.can_capture(hovered) else "未满足条件或机会已用"]
		return
	if action_mode.begins_with("skill:"):
		var skill_id: String = action_mode.trim_prefix("skill:")
		var skill: Dictionary = CombatConfig.SKILLS[skill_id]
		var target_cell: Vector2i = hover_cell
		var valid: bool = state.can_use_skill(selected, skill_id, target_cell)
		var detail: String = "目标格不可用"
		if valid:
			var impact: Vector2i = state.projected_skill_impact(selected, skill_id, target_cell)
			var area: Array[Vector2i] = EnvironmentResolver.skill_area(state, skill_id, impact, selected.cell)
			var collapse_count := 0
			var collapse_units := 0
			if skill_id in ["rock_create", "fire_burst"] or skill_id == "rock_break" and selected.upgraded_skill_id == "rock_break":
				for cell in area:
					if state.terrain.is_fragile(cell):
						collapse_count += 1
						if state.unit_at(cell) != null:
							collapse_units += 1
			detail = "影响 %d 格" % area.size()
			if impact != target_cell:
				detail += "；被 (%d, %d) 遮挡，实际落点已标出" % [impact.x + 1, impact.y + 1]
			if state.nest_exit_guarded() and area.has(state.nest["cell"]):
				detail += "；敌方守口：巢穴伤害减 1"
			if collapse_count > 0:
				detail += "；将塌陷 %d 格、波及 %d 个地面单位" % [collapse_count, collapse_units]
			if skill_id == "flame_charge":
				detail += "；越过中间格" + ("；落点致死" if state.terrain.is_deep_water(impact) or state.terrain.is_collapsed(impact) else "")
			if skill_id == "water_flow" and (not state.terrain.object_at(impact).is_empty() or state.is_nest_at(impact)):
				var delta: Vector2i = impact - selected.cell
				var water_cell: Vector2i = impact - Vector2i(signi(delta.x), signi(delta.y))
				detail += "；障碍前方 (%d, %d) 可形成浅水" % [water_cell.x + 1, water_cell.y + 1]
			if skill_id == "rain_call":
				detail += "；仅可转化地面、草丛与裂地；可直接点击友军格作为中心"
			if skill_id == "frozen_ground":
				detail += "；可覆盖深水和深坑；火命中冰面会恢复下层地形"
			if skill_id == "wild_vines":
				detail += "；障碍格跳过，单位脚下可生成；藤蔓下一次行动阻止主动移动"
			if skill_id == "electric_arc":
				detail += "；含相邻浸湿陆地单位；每单位本次最多命中一次"
		if state.terrain.is_steam(selected.cell):
			detail = "站在蒸汽雾中不能施放任何技能；移动离开后可施放，失败不消耗技能点"
		if selected.skill_points < int(skill["cost"]):
			detail = "技能点不足（%d/%d）" % [selected.skill_points, int(skill["cost"])] + ("；站在蒸汽雾中也不能施法" if state.terrain.is_steam(selected.cell) else "")
		if int(skill.get("uses_per_battle", 0)) > 0 and int(selected.battle_skill_uses.get(skill_id, 0)) >= int(skill["uses_per_battle"]):
			detail = "本场战斗的使用次数已用尽"
		if skill_id == "rock_create":
			detail += "；点击相邻方向格选向；友军占据方向格时直接点击；越界格跳过"
		if skill_id in ["rock_push", "water_flow"]:
			var push_preview: Dictionary = state.preview_skill_push(selected, skill_id, hover_cell)
			if not push_preview.is_empty():
				detail += "；" + str(push_preview["description"])
		if selected.upgraded_skill_id == skill_id:
			detail += "；强化：" + BattleBuffSystem.description(selected.battle_buff)
		preview_label.text = "%s（射程 %d，耗 %d 点）：%s；%s" % [skill["name"], state.effective_skill_range(selected, skill_id), skill["cost"], skill["description"], detail]
		return
	var route: Array[Vector2i] = state.get_move_path(selected, hover_cell)
	if not route.is_empty():
		preview_label.text = "移动预览：%d 格；移动后本回合不能再移动。" % route.size()
	elif state.is_rooted_now(selected):
		preview_label.text = "藤蔓束缚：本次行动不能主动移动，仍可施放技能。"
	elif selected.frozen or selected.frozen_skip_round == state.turn_number or selected.paralyzed_skip_round == state.turn_number:
		preview_label.text = "控制状态：本次行动无法移动、施法或捕获。"
	elif GridSpec.is_inside(hover_cell) and (state.terrain.is_collapsed(hover_cell) or (state.terrain.is_deep_water(hover_cell) and selected.element_type != "water")):
		preview_label.text = "不能主动进入此格；强制位移进入会立即死亡。"
	elif inspected_enemy_id != "":
		var enemy: CombatUnit = state.unit_by_id(inspected_enemy_id)
		if enemy.eligible_round > state.turn_number:
			preview_label.text = "%s：HP %d/%d；本轮增援待机，无法主动移动或施法，下回合才可行动。" % [enemy.display_name, enemy.hp, enemy.max_hp]
		else:
			preview_label.text = "%s：HP %d/%d%s；可移动至 %d 个格子（单次最远 %d 格）。红色边框是可达范围，远程敌人若已有通畅射线可能不移动。" % [enemy.display_name, enemy.hp, enemy.max_hp, " · 浸湿" if enemy.wet else "", state.enemy_move_cells(enemy).size(), state.effective_move_range(enemy)]
	else:
		preview_label.text = "点击绿色空格移动；底栏可选择捕获，选择后点周围八格内的目标。" if selected.unit_id == "trainer" else "点击绿色空格移动；底栏选技能后点目标，Esc 或右键取消瞄准。"


func _mode_name(mode: String) -> String:
	if mode == "capture":
		return "捕获"
	if mode.begins_with("skill:"):
		return CombatConfig.SKILLS[mode.trim_prefix("skill:")]["name"]
	return "移动"
