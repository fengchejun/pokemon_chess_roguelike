extends "res://scripts/ui/battle_screen.gd"
const Art = preload("res://sample/pixel_art.gd")
var portrait_focus_hint: PanelContainer

func _layout_overlays() -> void:
	super._layout_overlays()
	if board == null: return
	board.scale = Vector2.ONE
	board.position = Vector2(320, 135)
	board.queue_redraw()
	hint_label.position = Vector2(352, 666)
	hint_label.custom_minimum_size.x = 576

func _update_unit_card() -> void:
	super._update_unit_card()
	if unit_title == null: return
	var unit := _display_state().unit_by_uid(selected_uid)
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

func _position_action_panel() -> void:
	super._position_action_panel()
	if action_panel == null: return
	action_panel.position = Vector2(980, 316)
	action_panel.custom_minimum_size.x = 278

func _fit_team_panel() -> void:
	if team_panel == null or team_scroll == null: return
	team_panel.position = Vector2(16, 258)
	team_panel.custom_minimum_size = Vector2(108, 0)
	team_scroll.custom_minimum_size = Vector2(84, 0)
	team_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	team_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	team_panel.size = Vector2(108, minf(450, size.y - 270))
	var column := team_scroll.get_parent()
	for child in column.get_children():
		if child is Label: child.hide()
	if unit_panel != null: unit_panel.hide()

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
		choose.custom_minimum_size = Vector2(84, 72)
		choose.tooltip_text = "%s · Lv.%d\n绿色：生命；金色：经验\n点击选择，选择后可移动或施放技能。" % [unit.display_name, unit.combat_level]
		choose.disabled = not unit.is_alive()
		choose.pressed.connect(select_unit.bind(unit.uid))
		choose.focus_entered.connect(_show_portrait_help.bind(choose))
		choose.focus_exited.connect(_hide_portrait_help)
		if unit.uid == selected_uid:
			choose.add_theme_stylebox_override("normal", preload("res://sample/sample_theme.gd").box(Color("393344"), UIKit.ACCENT, 0))
		card.add_child(choose)
		var art_index := Art.unit_index(unit.species_id)
		if art_index >= 0:
			var portrait := TextureRect.new()
			portrait.texture = Art.tile(art_index)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.position = Vector2(6, 0)
			portrait.size = Vector2(72, 72)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choose.add_child(portrait)
		else:
			var portrait := preload("res://sample/trainer_portrait.gd").new()
			portrait.position = Vector2(10, 2)
			portrait.size = Vector2(64, 68)
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
	bar.custom_minimum_size = Vector2(84, 16)
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
	portrait_focus_hint.position = button.global_position - global_position + Vector2(94, 0)

func _hide_portrait_help() -> void:
	if is_instance_valid(portrait_focus_hint):
		portrait_focus_hint.queue_free()
	portrait_focus_hint = null

func _rebuild_skill_buttons() -> void:
	super._rebuild_skill_buttons()
	if action_mode != "skills" or skill_box == null: return
	var grid := GridContainer.new()
	grid.columns = 3
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
		child.custom_minimum_size = Vector2(78, 78)
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
	var instruction := UIKit.wrapped("选择招式后，点击棋盘上的有效目标。\n右键或 Esc 取消瞄准。", 13)
	instruction.custom_minimum_size.x = 240
	skill_box.add_child(instruction)
