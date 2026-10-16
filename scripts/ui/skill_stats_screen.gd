extends Control

var app = null


func _ready() -> void:
	name = "SkillStatsScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)
	var column := UIKit.vbox(12)
	margin.add_child(column)
	column.add_child(UIKit.title("技能使用统计", 32))
	var profile: CollectionState = app.collection
	column.add_child(UIKit.wrapped("跨所有开局的已完成战斗累计。从启用统计后开始记录；成功施放计 1 次，蓄力技在开始蓄力时计数。", 15))
	var summary := UIKit.label("已统计战斗 %d 场　我方施放 %d 次　敌方施放 %d 次" % [
		profile.recorded_skill_battles.size(), profile.skill_use_total("player"), profile.skill_use_total("enemy"),
	], 18, UIKit.ACCENT)
	summary.name = "SkillStatsSummary"
	column.add_child(summary)
	var scroll := UIKit.scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := UIKit.vbox(5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(_row("属性", "技能", "我方次数", "敌方次数", true))
	var ids := _skill_ids(profile)
	for skill_id in ids:
		var player_counts: Dictionary = profile.skill_use_counts.get("player", {})
		var enemy_counts: Dictionary = profile.skill_use_counts.get("enemy", {})
		var element := SkillDB.element_of(skill_id)
		list.add_child(_row(Elements.name_of(element), SkillDB.name_of(skill_id),
			str(int(player_counts.get(skill_id, 0))), str(int(enemy_counts.get(skill_id, 0))), false))
	var back := UIKit.button("返回主菜单")
	back.name = "SkillStatsBackButton"
	back.custom_minimum_size = Vector2(240, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: app.show_menu())
	column.add_child(back)


func _skill_ids(profile: CollectionState) -> Array:
	var found: Dictionary = {}
	for species_id in SpeciesDB.SPECIES:
		for skill_id in SpeciesDB.skills_of(String(species_id)):
			found[String(skill_id)] = true
	for element in ["fire", "water", "grass", "electric", "rock", "ice", "wind"]:
		for skill_id in SkillDB.learnable_ids_for(element):
			if not SkillDB.is_placeholder(String(skill_id)):
				found[String(skill_id)] = true
	for side in ["player", "enemy"]:
		var counts: Dictionary = profile.skill_use_counts.get(side, {})
		for skill_id in counts:
			found[String(skill_id)] = true
	var ids := found.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var a_total := _count(profile, a)
		var b_total := _count(profile, b)
		return a_total > b_total if a_total != b_total else a < b
	)
	return ids


func _count(profile: CollectionState, skill_id: String) -> int:
	return int((profile.skill_use_counts["player"] as Dictionary).get(skill_id, 0)) + int((profile.skill_use_counts["enemy"] as Dictionary).get(skill_id, 0))


func _row(element: String, skill_name: String, player_count: String, enemy_count: String, header: bool) -> Control:
	var panel := UIKit.panel(UIKit.PANEL_LIGHT if header else UIKit.PANEL)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cells := UIKit.hbox(10)
	panel.add_child(cells)
	for item in [[element, 85], [skill_name, 300], [player_count, 140], [enemy_count, 140]]:
		var cell := UIKit.label(String(item[0]), 16, UIKit.ACCENT if header else UIKit.TEXT)
		cell.custom_minimum_size = Vector2(int(item[1]), 0)
		cells.add_child(cell)
	return panel
