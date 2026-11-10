extends Control

const GrowthChoices = preload("res://scripts/ui/monster_growth_choices.gd")

var app = null
var return_to_node := false
var content: VBoxContainer
var message := ""
var growth_uid := -1
var scroll: ScrollContainer
var selected_item := ""
var item_grid: GridContainer
const Widgets = preload("res://ui/components/pixel_widgets.gd")

func _ready() -> void:
	name = "ItemBagScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
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
	scroll = UIKit.scroll()
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
	var pending := run.pending_monster_levels()
	var choices := pending.filter(func(entry): return int(entry["uid"]) == growth_uid)
	if not choices.is_empty():
		var heading := UIKit.label("", 19, UIKit.ACCENT)
		content.add_child(heading)
		var box := UIKit.vbox(8)
		content.add_child(box)
		GrowthChoices.show_choice(run, box, heading, choices[0], choices.size(), func() -> void:
			app.autosave()
			refresh())
		scroll.set_deferred("scroll_vertical", 0)
		return
	growth_uid = -1
	for member in run.carried:
		var uid := int(member["uid"])
		if not pending.any(func(entry): return int(entry["uid"]) == uid):
			continue
		var growth_button := UIKit.small_button("处理%s的升级选择" % SpeciesDB.name_of(member["species_id"]))
		growth_button.name = "OpenGrowth_%d" % uid
		growth_button.pressed.connect(func() -> void:
			growth_uid = uid
			refresh())
		content.add_child(growth_button)
	var has_items := false
	item_grid = GridContainer.new()
	item_grid.columns = 8
	content.add_child(item_grid)
	var available: Array = []
	for key in run.trainer_items:
		if int(run.trainer_items[key]) > 0:
			available.append(String(key))
	if not available.has(selected_item):
		selected_item = String(available[0]) if available.size() == 1 else ""
	for key in run.trainer_items:
		var id := String(key)
		var count := int(run.trainer_items[key])
		if count <= 0:
			continue
		has_items = true
		var is_book := id.begins_with(Merchant.BOOK_PREFIX)
		var item_name := SkillDB.name_of(id.trim_prefix(Merchant.BOOK_PREFIX)) if is_book else String(Merchant.ITEMS.get(id, [id])[0])
		var slot := Widgets.slot(item_name, count, "书" if is_book else ("药" if id == "potion" else "◆"), "选择后查看使用目标", UIKit.ACCENT if is_book else UIKit.GOOD)
		slot.name = "SelectItem_" + id.replace(":", "_")
		slot.pressed.connect(func() -> void:
			selected_item = id
			refresh())
		item_grid.add_child(slot)
		if id != selected_item:
			continue
		if id.begins_with(Merchant.BOOK_PREFIX):
			_show_book(run, id.trim_prefix(Merchant.BOOK_PREFIX), count)
		elif Merchant.ITEMS.has(id):
			content.add_child(UIKit.label("%s ×%d" % [Merchant.ITEMS[id][0], count], 19, UIKit.ACCENT))
			if id == "potion":
				_potion_target(Balance.TRAINER_UID, "训练师", run.trainer_hp, run.trainer_max_hp())
				for member in run.carried:
					_potion_target(int(member["uid"]), SpeciesDB.name_of(member["species_id"]), int(member["hp"]), run.monster_max_hp(member))
			elif id == Merchant.RARE_CANDY or Merchant.CANDY_XP.has(id):
				for member in run.carried:
					_candy_target(id, member)
			elif id == "capture_aid":
				content.add_child(UIKit.wrapped("捕获辅助在战斗中通过训练师道具菜单使用。", 15))
	for card in run.reward_inventory:
		has_items = true
		var reward_slot := Widgets.slot(RewardDB.name_of(card), 1, RewardDB.name_of(card).left(2), "战前整备使用\n" + RewardDB.description_of(card), UIKit.ACCENT)
		reward_slot.pressed.connect(func() -> void:
			message = reward_slot.tooltip_text
			refresh())
		item_grid.add_child(reward_slot)
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
	content.add_child(Widgets.health(hp, max_hp))
	var button := UIKit.small_button("为%s使用治疗药" % display_name)
	button.name = "UsePotion_%d" % uid
	button.disabled = hp <= 0 or hp >= max_hp
	button.pressed.connect(func() -> void:
		if Merchant.use_potion_outside_battle(app.run, uid):
			message = "%s已使用治疗药。" % display_name
			app.autosave()
			refresh())
	content.add_child(button)


func _candy_target(id: String, member: Dictionary) -> void:
	var uid := int(member["uid"])
	var monster_name := SpeciesDB.name_of(member["species_id"])
	var level := int(member["level"])
	var xp := int(member["xp"])
	var amount := Merchant.candy_xp(id, member)
	var after_xp := mini(xp + amount, MonsterProgression.threshold_for_level(MonsterProgression.MAX_LEVEL))
	var after_level := MonsterProgression.level_for_xp(after_xp)
	var button := UIKit.small_button("%s · Lv.%d（%d 经验） → Lv.%d（%d 经验）" % [monster_name, level, xp, after_level, after_xp])
	button.name = "UseCandy_%s_%d" % [id, uid]
	button.disabled = amount <= 0
	button.pressed.connect(func() -> void:
		var growth := Merchant.use_candy(app.run, id, uid)
		if growth.is_empty():
			return
		message = "%s已使用%s，获得 %d 经验。" % [monster_name, Merchant.ITEMS[id][0], int(growth["gained"])]
		growth_uid = uid
		app.autosave()
		refresh())
	content.add_child(button)
