extends Control

const MonsterCatalog = preload("res://scripts/monster_catalog.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")

var chosen: Array[String] = []
var cards: Dictionary = {}
var confirm_button: Button
var count_label: Label


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("#142229")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 48
	page.offset_right = -48
	page.offset_top = 24
	page.offset_bottom = -24
	page.add_theme_constant_override("separation", 16)
	add_child(page)
	var title := Label.new()
	title.text = "选择三只初始怪物"
	title.add_theme_font_size_override("font_size", 30)
	page.add_child(title)
	count_label = Label.new()
	page.add_child(count_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	page.add_child(grid)
	for species_id in MonsterCatalog.SPECIES_ORDER:
		var species: Dictionary = MonsterCatalog.SPECIES[species_id]
		var button := Button.new()
		button.custom_minimum_size = Vector2(275, 180)
		button.toggle_mode = true
		button.text = "%s  %s\n移动 %d · HP %d\n%s" % [species["glyph"], species["name"], species["move"], CombatConfig.MONSTER_HP, _skill_names(species["skills"])]
		button.tooltip_text = _skill_details(species["skills"])
		button.pressed.connect(_toggle.bind(species_id))
		grid.add_child(button)
		cards[species_id] = button
	var actions := HBoxContainer.new()
	page.add_child(actions)
	var back := Button.new()
	back.text = "返回菜单"
	back.custom_minimum_size = Vector2(180, 48)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	actions.add_child(back)
	confirm_button = Button.new()
	confirm_button.text = "以所选三只开始"
	confirm_button.custom_minimum_size = Vector2(240, 48)
	confirm_button.pressed.connect(_confirm)
	actions.add_child(confirm_button)
	_refresh()


func _skill_names(skill_ids: Array) -> String:
	var names: Array[String] = []
	for skill_id in skill_ids:
		names.append(str(CombatConfig.SKILLS[skill_id]["name"]))
	return " / ".join(names)


func _skill_details(skill_ids: Array) -> String:
	var details: Array[String] = []
	for skill_id in skill_ids:
		var skill: Dictionary = CombatConfig.SKILLS[skill_id]
		details.append("%s：%s" % [skill["name"], skill["description"]])
	return "\n".join(details)


func _toggle(species_id: String) -> void:
	if chosen.has(species_id):
		chosen.erase(species_id)
	elif chosen.size() < CombatConfig.DEPLOYED_MONSTER_LIMIT:
		chosen.append(species_id)
	_refresh()


func _refresh() -> void:
	count_label.text = "已选择 %d/%d · 本局仅携带所选三只；其他怪物可在战斗中捕获。" % [chosen.size(), CombatConfig.DEPLOYED_MONSTER_LIMIT]
	confirm_button.disabled = chosen.size() != CombatConfig.DEPLOYED_MONSTER_LIMIT
	for species_id in cards.keys():
		cards[species_id].button_pressed = chosen.has(species_id)
		cards[species_id].disabled = not chosen.has(species_id) and chosen.size() >= CombatConfig.DEPLOYED_MONSTER_LIMIT


func _confirm() -> void:
	if RunManager.run_state.set_starters(chosen):
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
