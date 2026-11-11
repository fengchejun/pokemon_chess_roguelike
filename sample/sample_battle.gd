extends "res://scripts/ui/battle_screen.gd"
const Art = preload("res://sample/pixel_art.gd")
var portrait_focus_hint: PanelContainer
var round_summary: Control
var compact_toolbar: HBoxContainer
var turn_actions: HBoxContainer
var action_scroll: ScrollContainer

func _ready() -> void:
	super._ready()
	round_summary = round_label.get_parent().get_parent()
	round_summary.reparent(self)
	corner_top_left.hide()
	objective_panel.hide()
	var action_column := skill_box.get_parent()
	action_scroll = ScrollContainer.new()
	action_scroll.name = "CornerActionScroll"
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.custom_minimum_size = Vector2(188, 120)
	action_column.add_child(action_scroll)
	skill_box.reparent(action_scroll)
	skill_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var details_column := unit_body.get_parent()
	var details_scroll := UIKit.scroll()
	details_scroll.name = "UnitDetailsScroll"
	details_scroll.custom_minimum_size.y = 110
	details_column.add_child(details_scroll)
	unit_body.reparent(details_scroll)
	unit_body.custom_minimum_size.x = 240
	compact_toolbar = UIKit.hbox(4)
	compact_toolbar.name = "CompactToolbar"
	add_child(compact_toolbar)
	for control in [menu_button, speed_button, leave_node_button]:
		control.reparent(compact_toolbar)
		control.custom_minimum_size = Vector2(0, 32)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.add_theme_font_size_override("font_size", 14)
	menu_button.text = "菜单"
	turn_actions = UIKit.hbox(6)
	add_child(turn_actions)
	for control in [undo_button, end_turn_button]:
		control.reparent(turn_actions)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rules := UIKit.small_button("战场说明")
	rules.name = "BattleRulesButton"
	rules.pressed.connect(func() -> void: _show_modal("战场说明", objective_label.text))
	rules.tooltip_text = "按需查看本场规则、撤离限制和奖励状态。"
	turn_actions.add_child(rules)
	_layout_compact_chrome()

func _layout_compact_chrome() -> void:
	if not is_instance_valid(compact_toolbar): return
	compact_toolbar.position = Vector2(16, 12)
	compact_toolbar.size = Vector2(280, 32)
	turn_actions.position = Vector2(16, 52)
	turn_actions.size = Vector2(280, 34)
	round_summary.position = Vector2(980, 12)
	round_summary.custom_minimum_size.x = 278
	objective_panel.hide()
	corner_top_left.hide()
	relic_panel.position = Vector2(980, 112)
	round_summary.reset_size()
	leave_node_button.text = "返回区域" if state.can_leave_node() else "撤退"

func _layout_corner_cards() -> void:
	if unit_panel == null or terrain_panel == null: return
	unit_panel.position = Vector2(16, 500)
	unit_panel.custom_minimum_size = Vector2(280, 204)
	unit_panel.size = Vector2(280, 204)
	unit_panel.show()
	terrain_panel.position = Vector2(1040, 608)
	terrain_label.custom_minimum_size.x = 196
	terrain_panel.custom_minimum_size = Vector2(224, 96)
	_fit_terrain_panel()

func _fit_terrain_panel() -> void:
	if terrain_scroll == null or terrain_panel == null: return
	terrain_label.custom_minimum_size.x = 196
	terrain_scroll.custom_minimum_size = Vector2(196, 70)
	terrain_panel.custom_minimum_size = Vector2(224, 96)
	terrain_panel.size = Vector2(224, 96)

func _fit_relic_panel() -> void:
	if relic_scroll == null or relic_panel == null: return
	relic_scroll.custom_minimum_size = Vector2(250, 60)
	relic_panel.reset_size()

func _update_action_buttons() -> void:
	super._update_action_buttons()
	if is_instance_valid(compact_toolbar):
		leave_node_button.text = "返回区域" if state.can_leave_node() else "撤退"

func _head_texture(index: int) -> AtlasTexture:
	var source := Art.tile(index)
	var crop: Rect2 = {
		4: Rect2(44, 36, 124, 116),
		5: Rect2(50, 38, 130, 116),
		6: Rect2(20, 92, 160, 128),
		7: Rect2(30, 35, 150, 140),
	}.get(index, Rect2(32, 32, 192, 160))
	var head := AtlasTexture.new()
	head.atlas = source.atlas
	var ratio := source.region.size / 256.0
	head.region = Rect2(source.region.position + crop.position * ratio, crop.size * ratio)
	head.filter_clip = true
	return head

func _layout_overlays() -> void:
	super._layout_overlays()
	if board == null: return
	board.scale = Vector2.ONE
	board.position = Vector2(192, 34)
	board.queue_redraw()
	hint_label.position = Vector2(438, 696)
	hint_label.custom_minimum_size.x = 400
	_layout_compact_chrome()

func _update_unit_card() -> void:
	super._update_unit_card()
	if unit_title == null: return
	var unit := _display_state().unit_by_uid(selected_uid)
	if unit == null: unit = _display_state().unit_by_uid(viewed_enemy_uid)
	if unit == null: return
	unit_title.text = "%s · %s" % [unit.display_name, "我方" if unit.side == "player" else "敌方"]
	unit_health.custom_minimum_size.y = 22
	var number := unit_health.get_node_or_null("HealthValue") as Label
	if number == null:
		number = UIKit.label("", 12)
		number.name = "HealthValue"
		number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit_health.add_child(number)
	number.text = "%d / %d" % [unit.hp, unit.max_hp]
	unit_body.visible = true
	unit_body.tooltip_text = unit_body.text
	var important: Array[String] = []
	for line in unit_body.text.split("\n"):
		if line.begins_with("状态：") and line != "状态：无": important.append(line)
		elif line.begins_with("本回合技能：") and line.contains("不可用"): important.append(line)
		elif line.begins_with("本回合移动：") and not line.contains("可用"): important.append(line)
	var full_skills: Array = []
	for skill in unit.skills: full_skills.append(SkillDB.name_of(String(skill)))
	unit_body.text = "属性：%s\n等级：%d　移动：%d\n移动%s · 技能%s\n\n招式：%s" % [Elements.FULL_NAMES.get(unit.element, "无属性"), unit.combat_level if unit.side == "player" else unit.enemy_level, _display_state().move_budget_for(unit), "已用" if unit.moved else "可用", "已用" if unit.skill_used else "可用", "、".join(full_skills)]
	if not important.is_empty(): unit_body.text += "\n\n" + "\n".join(important)

func _position_action_panel() -> void:
	super._position_action_panel()
	if action_panel == null: return
	action_panel.position = Vector2(1040, 388)
	action_panel.custom_minimum_size.x = 224
	if action_scroll != null:
		action_scroll.custom_minimum_size.y = minf(166, maxf(40, skill_box.get_combined_minimum_size().y))
		action_panel.reset_size()
		action_panel.size = Vector2(224, action_scroll.custom_minimum_size.y + 42)
		action_panel.position.y = 596 - action_panel.size.y

func _update_relic_panel() -> void:
	super._update_relic_panel()
	if relic_panel != null and app != null and app.run != null:
		relic_panel.visible = app.run.relic_stacks.values().any(func(rank): return int(rank) > 0)

func _fit_team_panel() -> void:
	if team_panel == null or team_scroll == null: return
	team_panel.position = Vector2(16, 104)
	team_panel.custom_minimum_size = Vector2(86, 0)
	team_scroll.custom_minimum_size = Vector2(64, 0)
	team_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	team_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	team_panel.size = Vector2(94, 368)
	var column := team_scroll.get_parent()
	for child in column.get_children():
		if child is Label: child.hide()
	if unit_panel != null: unit_panel.show()

func _update_team_list() -> void:
	if team_list == null: return
	UIKit.clear_children(team_list)
	team_list.add_theme_constant_override("separation", 4)
	for unit in _display_state().units:
		if unit.side != "player": continue
		var card := UIKit.vbox(0)
		card.name = "TeamPortraitCard_%d" % unit.uid
		team_list.add_child(card)
		var choose := Button.new()
		choose.name = "SelectPortrait_%d" % unit.uid
		choose.custom_minimum_size = Vector2(64, 56)
		choose.tooltip_text = "%s · Lv.%d\n绿色：生命；金色：经验\n点击选择，选择后可移动或施放技能。" % [unit.display_name, unit.combat_level]
		choose.disabled = not unit.is_alive()
		choose.clip_contents = true
		choose.pressed.connect(select_unit.bind(unit.uid))
		choose.focus_entered.connect(_show_portrait_help.bind(choose))
		choose.focus_exited.connect(_hide_portrait_help)
		if unit.uid == selected_uid:
			choose.add_theme_stylebox_override("normal", preload("res://sample/sample_theme.gd").box(Color("393344"), UIKit.ACCENT, 0))
		card.add_child(choose)
		var art_index := Art.unit_index(unit.species_id)
		if art_index >= 0:
			var portrait := TextureRect.new()
			portrait.texture = _head_texture(art_index)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.position = Vector2(4, 2)
			portrait.size = Vector2(56, 52)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choose.add_child(portrait)
		else:
			var portrait := preload("res://sample/trainer_portrait.gd").new()
			portrait.position = Vector2(-12, -10)
			portrait.size = Vector2(64, 68)
			portrait.scale = Vector2(1.4, 1.4)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choose.add_child(portrait)
		var health := _portrait_bar(unit.hp, unit.max_hp, Color("75c797"), "生命")
		health.name = "TeamHealth_%d" % unit.uid
		card.add_child(health)
		var level: int = unit.combat_level
		var base := MonsterProgression.threshold_for_level(level)
		var maximum := maxi(1, MonsterProgression.threshold_for_level(level + 1) - base)
		var current := maxi(0, unit.combat_xp - base)
		if level >= MonsterProgression.MAX_LEVEL: current = maximum
		var experience := _portrait_bar(current, maximum, Color("ddb66e"), "经验 · Lv.%d，击败与捕获即时入账；学招在战后选择。" % level)
		experience.name = "BattleXP_%d" % unit.uid
		var number := experience.get_child(0) as Label
		number.name = "BattleXPText_%d" % unit.uid
		number.tooltip_text = experience.tooltip_text
		card.add_child(experience)
	call_deferred("_fit_team_panel")

func _portrait_bar(current: int, maximum: int, color: Color, description: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(64, 14)
	bar.max_value = maxi(1, maximum)
	bar.value = current
	bar.show_percentage = false
	bar.tooltip_text = description
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.25)
	style.border_width_top = 2
	style.anti_aliasing = false
	bar.add_theme_stylebox_override("fill", style)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("11111b")
	bg.border_color = Color("494253")
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", bg)
	var number := UIKit.label("%d/%d" % [current, maximum], 11)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_color_override("font_color", Color("fff5e5"))
	number.add_theme_color_override("font_outline_color", Color("11111b"))
	number.add_theme_constant_override("outline_size", 2)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(number)
	return bar

func _show_portrait_help(button: Button) -> void:
	_hide_portrait_help()
	portrait_focus_hint = UIKit.panel()
	portrait_focus_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_focus_hint.z_index = 30
	var text := UIKit.wrapped(button.tooltip_text, 13)
	text.custom_minimum_size.x = 170
	portrait_focus_hint.add_child(text)
	add_child(portrait_focus_hint)
	portrait_focus_hint.position = button.global_position - global_position + Vector2(74, 0)

func _hide_portrait_help() -> void:
	if is_instance_valid(portrait_focus_hint):
		portrait_focus_hint.queue_free()
	portrait_focus_hint = null

func _rebuild_skill_buttons() -> void:
	super._rebuild_skill_buttons()
	if skill_box == null: return
	if action_mode != "skills":
		var actions := skill_box.get_children()
		if actions.size() <= 1: return
		var compact_grid := GridContainer.new()
		compact_grid.columns = 2
		compact_grid.add_theme_constant_override("h_separation", 4)
		compact_grid.add_theme_constant_override("v_separation", 4)
		skill_box.add_child(compact_grid)
		for action in actions:
			if action is Button:
				action.reparent(compact_grid)
				action.add_theme_font_size_override("font_size", 13)
				action.custom_minimum_size.x = 84
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var children := skill_box.get_children()
	skill_box.add_child(grid)
	skill_box.move_child(grid, 0)
	for child in children:
		if not child is Button or not String(child.name).begins_with("SkillButton_"): continue
		var id := String(child.name).trim_prefix("SkillButton_")
		child.tooltip_text = child.text + "\n" + child.tooltip_text
		child.text = ""
		child.custom_minimum_size = Vector2(76, 76)
		skill_box.remove_child(child)
		grid.add_child(child)
		var icon := TextureRect.new()
		icon.texture = Art.tile(10 if SkillDB.element_of(id) == "fire" else 11)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(18, 4)
		icon.size = Vector2(42, 42)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.add_child(icon)
		var caption := UIKit.label(SkillDB.name_of(id), 12)
		caption.position = Vector2(3, 51)
		caption.size = Vector2(72, 20)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.add_child(caption)
