extends Control

var app = null


func _ready() -> void:
	name = "FloorThemeScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	if run.offered_floor_themes.is_empty():
		run.refresh_theme_offers()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var column := UIKit.vbox(18)
	margin.add_child(column)
	column.add_child(UIKit.title("第 %d 层 · 选择主题" % (run.floor_index() + 1), 32))
	var floor_hint := "本层共六场战斗，主题决定地形倾向和主要敌人。"
	if run.region_mode and run.options.get("exploration_v2", false):
		floor_hint = "本层使用随机 4×4 区域地图，包含两家商店。普通战斗有 %d 名敌人，主题决定地形倾向和主要敌人。" % (3 + run.floor_index())
	elif run.region_mode:
		floor_hint = "本层含营地、五个战斗节点、两个事件节点及首领。主题决定地形倾向和主要敌人。"
	column.add_child(UIKit.wrapped(floor_hint, 16))
	var row := UIKit.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for offered_id in run.offered_floor_themes:
		var theme_id := String(offered_id)
		var theme: Dictionary = BattleDB.THEMES[theme_id]
		var card := UIKit.panel(UIKit.PANEL)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var content := UIKit.vbox(12)
		card.add_child(content)
		content.add_child(UIKit.label(String(theme["name"]) + " · " + Elements.name_of(theme_id), 24, UIKit.ACCENT))
		var primary_names: Array = []
		for species_id in theme["primary"]:
			primary_names.append(SpeciesDB.name_of(String(species_id)))
		var support_names: Array = []
		for species_id in theme["support"]:
			support_names.append(SpeciesDB.name_of(String(species_id)))
		content.add_child(UIKit.wrapped("主要敌人：%s\n支援敌人：%s" % ["、".join(primary_names), "、".join(support_names)], 16))
		content.add_child(UIKit.wrapped(_terrain_hint(theme_id), 14))
		var choose := UIKit.button("前往%s" % String(theme["name"]), 18)
		choose.name = "ChooseTheme_%s" % theme_id
		choose.pressed.connect(func() -> void:
			if app.run.choose_floor_theme(theme_id):
				app.autosave()
				if app.run.region_mode:
					app.show_region()
				else:
					app.show_prep()
		)
		content.add_child(choose)


func _terrain_hint(theme_id: String) -> String:
	match theme_id:
		"fire": return "地貌倾向：蓝火与岩障较多，水和草较少，也可能出现熔岩。"
		"water": return "地貌倾向：成片浅水及少量深水；可与电、冰技能联动。"
		"grass": return "地貌倾向：草丛与树木较多，火焰容易改变通路。"
		"rock": return "地貌倾向：岩障与易碎地块较多，绕行和破障更重要。"
	return ""
