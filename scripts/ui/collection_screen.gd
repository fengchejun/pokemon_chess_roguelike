extends Control

var app = null
var selection: Array = []
var boxes: Dictionary = {}
var hint: Label = null
var start_button: Button = null


func _ready() -> void:
	name = "CollectionScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 100)
	margin.add_theme_constant_override("margin_right", 100)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var column := UIKit.vbox(10)
	margin.add_child(column)
	column.add_child(UIKit.title("选择新一局的三只怪物", 30))
	column.add_child(UIKit.wrapped("永久收藏会保留捕获后进入携带队伍或仓库的怪物，包括濒死成员。开局从收藏中选三只，恢复满生命；局内强化不会继承。", 15))
	var scroll := UIKit.scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := UIKit.vbox(6)
	list.custom_minimum_size = Vector2(900, 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for record in app.collection.owned:
		list.add_child(_collection_row(record))
	hint = UIKit.label("请选择 3 只（0/3）", 15, UIKit.ACCENT)
	column.add_child(hint)
	var buttons := UIKit.hbox(10)
	column.add_child(buttons)
	start_button = UIKit.button("开始本局", 18)
	start_button.name = "StartFromCollectionButton"
	start_button.disabled = true
	start_button.pressed.connect(_on_start)
	buttons.add_child(start_button)
	var back := UIKit.button("返回菜单", 18)
	back.name = "CollectionBackButton"
	back.pressed.connect(func() -> void: app.show_menu())
	buttons.add_child(back)


func _collection_row(record: Dictionary) -> Control:
	var id := int(record["id"])
	var species_id := String(record["species_id"])
	var row := UIKit.panel(UIKit.PANEL_LIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := UIKit.vbox(4)
	row.add_child(content)
	var line := UIKit.hbox(10)
	content.add_child(line)
	var box := CheckBox.new()
	box.name = "Collection_%d" % id
	box.toggled.connect(func(pressed: bool) -> void: _on_toggle(id, pressed))
	boxes[id] = box
	line.add_child(box)
	line.add_child(UIKit.label(SpeciesDB.name_of(species_id), 17))
	line.add_child(UIKit.element_chip(SpeciesDB.element_of(species_id)))
	line.add_child(UIKit.label("生命 %d · 移动 %d" % [SpeciesDB.hp_of(species_id), SpeciesDB.move_of(species_id)], 14, UIKit.TEXT_DIM))
	var skills: Array = []
	for skill_id in SpeciesDB.skills_of(species_id):
		skills.append(SkillDB.name_of(String(skill_id)))
	content.add_child(UIKit.wrapped("技能：" + "、".join(skills), 13))
	return row


func _on_toggle(id: int, pressed: bool) -> void:
	if pressed:
		if selection.size() >= Balance.DEPLOY_LIMIT:
			(boxes[id] as CheckBox).set_pressed_no_signal(false)
			return
		selection.append(id)
	else:
		selection.erase(id)
	hint.text = "请选择 3 只（%d/3）" % selection.size()
	start_button.disabled = selection.size() != Balance.DEPLOY_LIMIT


func _on_start() -> void:
	var chosen: Array = app.collection.select_records(selection)
	if chosen.size() == Balance.DEPLOY_LIMIT:
		app.begin_new_run_with_collection(chosen)
