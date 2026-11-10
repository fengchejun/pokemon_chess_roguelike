extends Control
const Widgets = preload("res://ui/components/pixel_widgets.gd")

var app = null
var selection: Array = []
var boxes: Dictionary = {}
var skill_selectors: Dictionary = {}
var hint: Label = null
var start_button: Button = null


func _ready() -> void:
	name = "CollectionScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var column := UIKit.vbox(10)
	margin.add_child(column)
	column.add_child(UIKit.title("选择新一局的三只怪物", 30))
	column.add_child(UIKit.wrapped("永久收藏会保留携带队伍和仓库的怪物，包括濒死成员。开局选三只并为每只选择一招起始技能，恢复满生命；亲密度会继承，当前暂不提供数值效果。本局等级、经验与怪物强化在新局重置。", 15))
	column.add_child(UIKit.wrapped("首领之血：%d 份（永久）；未来可用 5 份合成首领血浆，当前尚不能使用。" % app.collection.boss_blood, 15, UIKit.ACCENT))
	var scroll := UIKit.scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := GridContainer.new()
	list.columns = 2 if get_viewport_rect().size.x >= 1100 else 1
	resized.connect(func() -> void: list.columns = 2 if size.x >= 1100 else 1)
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
	var stats := UIKit.hbox(8)
	stats.name = "CollectionStats_%d" % id
	content.add_child(stats)
	stats.add_child(Widgets.stat("亲", str(record.get("affinity", 0)), "永久亲密度，暂无数值效果"))
	stats.add_child(Widgets.stat("心", str(SpeciesDB.hp_of(species_id)), "基础生命", UIKit.BAD))
	stats.add_child(Widgets.stat("步", str(SpeciesDB.move_of(species_id)), "基础移动", UIKit.GOOD))
	var skills: Array = []
	var skill_selector := OptionButton.new()
	skill_selector.name = "StartingSkill_%d" % id
	for skill_id in SpeciesDB.skills_of(species_id):
		var skill_name := SkillDB.name_of(String(skill_id))
		if SkillDB.is_special(String(skill_id)):
			skill_name += "（特殊）"
		skills.append(skill_name)
		skill_selector.add_item(skill_name)
		skill_selector.set_item_metadata(skill_selector.item_count - 1, String(skill_id))
		if (species_id.begins_with("ice_") and String(skill_id) == "ice_shard"):
			skill_selector.select(skill_selector.item_count - 1)
	skill_selectors[id] = skill_selector
	skill_selector.tooltip_text = "开局携带一招；特殊技能不能通过升级学习。\n" + "、".join(skills)
	content.add_child(skill_selector)
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
		for record in chosen:
			var selector: OptionButton = skill_selectors.get(int(record["id"]))
			if selector != null and selector.item_count > 0:
				record["starting_skill_id"] = String(selector.get_item_metadata(selector.selected))
		app.begin_new_run_with_collection(chosen)
