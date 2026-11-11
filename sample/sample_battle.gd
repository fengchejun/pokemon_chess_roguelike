extends "res://scripts/ui/battle_screen.gd"
const Art = preload("res://sample/pixel_art.gd")

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

func _update_team_list() -> void:
	if team_list == null: return
	UIKit.clear_children(team_list)
	for unit in _display_state().units:
		if unit.side != "player": continue
		var row := UIKit.hbox(8)
		team_list.add_child(row)
		var art_index := Art.unit_index(unit.species_id)
		if art_index >= 0:
			var portrait := TextureRect.new()
			portrait.texture = Art.tile(art_index)
			portrait.custom_minimum_size = Vector2(44, 44)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(portrait)
		var body := UIKit.vbox(2)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var choose := UIKit.small_button(unit.display_name)
		choose.disabled = not unit.is_alive()
		choose.pressed.connect(select_unit.bind(unit.uid))
		body.add_child(choose)
		var health := ProgressBar.new()
		health.custom_minimum_size = Vector2(150, 20)
		health.max_value = unit.max_hp
		health.value = unit.hp
		health.show_percentage = false
		body.add_child(health)
		var number := UIKit.label("%d / %d" % [unit.hp, unit.max_hp], 12)
		number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health.add_child(number)
		if unit.summon_owner_uid < 0 and app != null and app.run != null:
			_add_battle_xp_bar(unit)
	call_deferred("_fit_team_panel")

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
