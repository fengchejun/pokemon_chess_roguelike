extends Control

var app = null
var return_to_node := false
var content: VBoxContainer
var message := ""

func _ready() -> void:
	name = "ItemBagScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := UIKit.vbox(12)
	margin.add_child(page)
	var header := UIKit.hbox(12)
	page.add_child(header)
	var title := UIKit.title("道具背包", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := UIKit.small_button("返回")
	back.name = "ReturnFromItemBag"
	back.pressed.connect(func() -> void:
		if return_to_node:
			app._switch(load("res://scripts/ui/exploration_node_screen.gd").new())
		else:
			app.show_region())
	header.add_child(back)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	content = UIKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	refresh()

func refresh() -> void:
	UIKit.clear_children(content)
	var run: RunState = app.run
	if not message.is_empty():
		content.add_child(UIKit.wrapped(message, 16))
	var has_items := false
	for key in run.trainer_items:
		var id := String(key)
		var count := int(run.trainer_items[key])
		if count <= 0:
			continue
		has_items = true
		if id.begins_with(Merchant.BOOK_PREFIX):
			_show_book(run, id.trim_prefix(Merchant.BOOK_PREFIX), count)
		elif Merchant.ITEMS.has(id):
			content.add_child(UIKit.label("%s ×%d" % [Merchant.ITEMS[id][0], count], 19, UIKit.ACCENT))
			if id == "potion":
				_potion_target(Balance.TRAINER_UID, "训练师", run.trainer_hp, run.trainer_max_hp())
				for member in run.carried:
					_potion_target(int(member["uid"]), SpeciesDB.name_of(member["species_id"]), int(member["hp"]), run.monster_max_hp(member))
			else:
				content.add_child(UIKit.wrapped("捕获辅助在战斗中通过训练师道具菜单使用。", 15))
	for card in run.reward_inventory:
		has_items = true
		content.add_child(UIKit.label("%s · 战前整备使用" % RewardDB.name_of(card), 15))
	if not has_items:
		content.add_child(UIKit.label("背包里还没有道具。", 16))

func _show_book(run: RunState, skill: String, count: int) -> void:
	content.add_child(UIKit.label("技能书 · %s ×%d" % [SkillDB.name_of(skill), count], 19, UIKit.ACCENT))
	content.add_child(UIKit.wrapped("选择随身成员学习。招式栏有空位时自动装备，满栏时可在整备中换装。", 15))
	var eligible := false
	for member in run.carried:
		var uid := int(member["uid"])
		if not run.available_new_skills(uid).has(skill):
			continue
		eligible = true
		var button := UIKit.small_button("让%s学习%s" % [SpeciesDB.name_of(member["species_id"]), SkillDB.name_of(skill)])
		button.name = "UseBook_%s_%d" % [skill, uid]
		button.pressed.connect(func() -> void:
			if Merchant.use_skill_book(run, skill, uid):
				message = "已学会%s。" % SkillDB.name_of(skill)
				app.autosave()
				refresh())
		content.add_child(button)
	if not eligible:
		content.add_child(UIKit.label("当前没有可学习该招式的随身成员。", 15))

func _potion_target(uid: int, display_name: String, hp: int, max_hp: int) -> void:
	var button := UIKit.small_button("为%s使用治疗药 · HP %d/%d" % [display_name, hp, max_hp])
	button.name = "UsePotion_%d" % uid
	button.disabled = hp <= 0 or hp >= max_hp
	button.pressed.connect(func() -> void:
		if Merchant.use_potion_outside_battle(app.run, uid):
			message = "%s已使用治疗药。" % display_name
			app.autosave()
			refresh())
	content.add_child(button)
