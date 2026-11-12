extends Control

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
	margin.add_theme_constant_override("margin_left", 100)
	margin.add_theme_constant_override("margin_right", 100)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var column := UIKit.vbox(10)
	margin.add_child(column)
	column.add_child(UIKit.title("选择新一局的三只怪物", 30))
	column.add_child(UIKit.wrapped("携带队伍会在本局结束时进入永久收藏，包括濒死成员；仓库成员默认被抛弃，只有最终结局页明确勾选者才会保留。开局选三只并为每只选择一招起始技能，恢复满生命；亲密度会继承。本局等级、经验与怪物强化在新局重置。", 15))
	column.add_child(UIKit.wrapped("首领之血：%d 份（永久）；未来可用 5 份合成首领血浆，当前尚不能使用。" % app.collection.boss_blood, 15, UIKit.ACCENT))
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
	line.add_child(UIKit.label("亲密度 %d（永久，暂无效果） · 基础生命 %d · 基础移动 %d" % [
		int(record.get("affinity", 0)), SpeciesDB.hp_of(species_id), SpeciesDB.move_of(species_id),
	], 14, UIKit.TEXT_DIM))
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
	content.add_child(UIKit.wrapped("开局从以下技能中携带一招；标注“特殊”的技能不能通过升级学习：" + "、".join(skills), 13))
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
