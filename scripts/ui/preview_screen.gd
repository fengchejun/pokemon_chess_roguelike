extends Control

## 地形改造工具表：允许的来源地形与目标地形（悬停时会在提示栏显示结算内容）。
const MOD_RULES := {
	"water": {"name": "注水", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.WATER},
	"grass": {"name": "种草", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.GRASS},
	"rock": {"name": "立岩", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.OBSTACLE},
	"clear": {"name": "开垦", "ok_from": TerrainDB.OBSTACLE, "to": TerrainDB.PLAIN},
	"deep": {"name": "深水", "ok_from": TerrainDB.WATER, "to": TerrainDB.DEEP},
	"lava": {"name": "熔岩", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.LAVA},
}

var app = null
var deploy_uids: Array = []
var map: Dictionary = {}
var base_map: Dictionary = {}
var mod_used: int = 0
var mod_kind: String = "water"
var board: BoardView = null
var hint_label: Label = null
var mod_count_label: Label = null
var mod_buttons: Dictionary = {}
var card_toggles: Dictionary = {}
var card_hint: Label = null
var card_detail: Label = null


func _ready() -> void:
	name = "PreviewScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	map = MapGenerator.generate(run.seed, run.battle_index, 0, run.map_deck())
	base_map = map.duplicate(true)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var columns := UIKit.hbox(14)
	margin.add_child(columns)
	var board_column := UIKit.vbox(6)
	columns.add_child(board_column)
	board = BoardView.new()
	board.name = "BoardView"
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board_column.add_child(board)
	board_column.add_child(_legend())
	var right := UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(UIKit.label("地图预览与改造 · 第 %d 场（%s）" % [run.battle_index + 1, run.region_name()], 22, UIKit.ACCENT))
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var content := UIKit.vbox(8)
	scroll.add_child(content)
	content.add_child(UIKit.wrapped("地图构筑模式下，卡组会改变后续地貌生成倾向；站位卡模式下地貌仅由区域与种子决定。开战后地图不再生成。", 13))
	content.add_child(_enemy_box(run))
	content.add_child(_cards_box())
	var mod_box := UIKit.panel(UIKit.PANEL)
	var mod_column := UIKit.vbox(6)
	mod_box.add_child(mod_column)
	mod_column.add_child(UIKit.label("地形改造（悬停查看结算，点击应用）", 17, UIKit.ACCENT))
	var mod_row := UIKit.hbox(6)
	mod_column.add_child(mod_row)
	var mod_row2 := UIKit.hbox(6)
	mod_column.add_child(mod_row2)
	var row_index := 0
	for kind in MOD_RULES:
		var id := String(kind)
		var rule: Dictionary = MOD_RULES[id]
		var button := UIKit.small_button(String(rule["name"]))
		button.name = "ModButton_%s" % id
		button.toggle_mode = true
		button.button_pressed = id == mod_kind
		button.tooltip_text = "%s：%s → %s" % [
			rule["name"], TerrainDB.name_of(int(rule["ok_from"])), TerrainDB.name_of(int(rule["to"])),
		]
		button.pressed.connect(func() -> void: _set_mod_kind(id))
		if row_index < 3:
			mod_row.add_child(button)
		else:
			mod_row2.add_child(button)
		mod_buttons[id] = button
		row_index += 1
	mod_count_label = UIKit.label("", 14, UIKit.TEXT_DIM)
	mod_column.add_child(mod_count_label)
	var mod_actions := UIKit.hbox(8)
	mod_column.add_child(mod_actions)
	var reset_button := UIKit.small_button("重置改造")
	reset_button.pressed.connect(_on_reset)
	mod_actions.add_child(reset_button)
	content.add_child(mod_box)
	hint_label = UIKit.label("", 14, UIKit.BAD)
	right.add_child(hint_label)
	var actions := UIKit.hbox(8)
	right.add_child(actions)
	var back := UIKit.small_button("返回整备")
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(130, 38)
	back.pressed.connect(func() -> void: app.back_to_prep(deploy_uids))
	actions.add_child(back)
	var start := UIKit.button("开始战斗", 18)
	start.name = "StartBattleButton"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_on_start)
	actions.add_child(start)
	_refresh()


func _legend() -> Control:
	var box := UIKit.hbox(10)
	var entries: Array = [
		[TerrainDB.PLAIN, "平地"], [TerrainDB.WATER, "水面"], [TerrainDB.DEEP, "深水"],
		[TerrainDB.GRASS, "草丛"], [TerrainDB.OBSTACLE, "障碍"], [TerrainDB.FRAGILE, "易碎"],
	]
	for entry in entries:
		var swatch := ColorRect.new()
		swatch.color = TerrainDB.color_of(int(entry[0]))
		swatch.custom_minimum_size = Vector2(14, 14)
		box.add_child(swatch)
		box.add_child(UIKit.label(String(entry[1]), 12, UIKit.TEXT_DIM))
	box.add_child(UIKit.label("　蓝框=部署区　紫=巢穴　金星=奖励　红点=恢复果实", 12, UIKit.TEXT_DIM))
	return box


func _enemy_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(4)
	box.add_child(column)
	column.add_child(UIKit.label("敌方配置（可复现）", 17, UIKit.ACCENT))
	var cfg := BattleDB.config_for(run.battle_index)
	for pair in cfg.get("enemies", []):
		var species_id := String(pair[0])
		var skill_names: Array = []
		for skill_id in SpeciesDB.skills_of(species_id):
			skill_names.append(SkillDB.name_of(String(skill_id)))
		var line := UIKit.hbox(8)
		line.add_child(UIKit.label(SpeciesDB.name_of(species_id), 15))
		line.add_child(UIKit.element_chip(SpeciesDB.element_of(species_id)))
		line.add_child(UIKit.label("生命 %d · 移动 %d · %s" % [
			SpeciesDB.hp_of(species_id), SpeciesDB.move_of(species_id), "、".join(skill_names),
		], 13, UIKit.TEXT_DIM))
		column.add_child(line)
	var reinforce_names: Array = []
	for species_id in cfg.get("reinforce", []):
		reinforce_names.append(SpeciesDB.name_of(String(species_id)))
	column.add_child(UIKit.wrapped("巢穴增援池：%s（第 2、4 回合各尝试 1 只；堵口则排队）" % "、".join(reinforce_names), 13))
	return box


func _cards_box() -> Control:
	var run: RunState = app.run
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(6)
	box.add_child(column)
	if String(run.options.get("card_mode", "position")) == "environment":
		column.add_child(UIKit.label("地图构筑卡（整局生效）", 17, UIKit.ACCENT))
		var lines: Array = []
		for card_id in run.environment_deck:
			var card := MapCardDB.get_card(String(card_id))
			lines.append("%s：%s" % [card.get("name", card_id), card.get("desc", "")])
		column.add_child(UIKit.wrapped("尚未获得地图构筑卡；战后可三选一。" if lines.is_empty() else "\n".join(lines), 13))
		return box
	column.add_child(UIKit.label("出战环境卡（5 张中选 2 张，本场生效）", 17, UIKit.ACCENT))
	var row := UIKit.hbox(6)
	column.add_child(row)
	for card_id in CardDB.ALL_IDS:
		var id := String(card_id)
		var card := CardDB.get_card(id)
		var button := UIKit.small_button(String(card.get("name", id)))
		button.name = "CardToggle_%s" % id
		button.toggle_mode = true
		button.button_pressed = run.cards.has(id)
		button.tooltip_text = "%s：%s" % [card.get("anchor", ""), card.get("effect", "")]
		button.pressed.connect(func() -> void: _on_card_toggle(id))
		row.add_child(button)
		card_toggles[id] = button
	card_hint = UIKit.label("", 13, UIKit.BAD)
	column.add_child(card_hint)
	card_detail = UIKit.wrapped("", 13)
	column.add_child(card_detail)
	_refresh_card_detail()
	return box


func _on_card_toggle(card_id: String) -> void:
	var run: RunState = app.run
	var button: Button = card_toggles[card_id]
	if button.button_pressed:
		if run.cards.size() >= Balance.CARDS_PER_BATTLE:
			button.set_pressed_no_signal(false)
			card_hint.text = "最多选择 %d 张；先取消一张再更换。" % Balance.CARDS_PER_BATTLE
			return
		if not run.cards.has(card_id):
			run.cards.append(card_id)
	else:
		run.cards.erase(card_id)
	card_hint.text = ""
	app.autosave()
	_refresh_card_detail()


func _refresh_card_detail() -> void:
	var run: RunState = app.run
	var lines: Array = []
	for card_id in run.cards:
		var card := CardDB.get_card(String(card_id))
		lines.append("【%s】%s：%s" % [card.get("name", card_id), card.get("anchor", ""), card.get("effect", "")])
	if lines.is_empty():
		lines.append("尚未选择环境卡。")
	card_detail.text = "\n".join(lines)


func _set_mod_kind(kind: String) -> void:
	mod_kind = kind
	for key in mod_buttons:
		var button: Button = mod_buttons[key]
		button.button_pressed = String(key) == kind
	hint_label.text = ""


func _on_cell_clicked(cell: Vector2i) -> void:
	var run: RunState = app.run
	if mod_used >= run.mod_points():
		hint_label.text = "改造次数已用尽（共 %d 次）。" % run.mod_points()
		return
	if MapGenerator.mod_protected(map, cell):
		hint_label.text = "部署区、巢穴与奖励格受保护，不能改造。"
		return
	if MapGenerator.apply_modification(map, cell, mod_kind):
		mod_used += 1
		hint_label.text = ""
		_refresh()
	else:
		hint_label.text = _mod_hover_text(cell)


func _on_cell_hovered(cell: Vector2i) -> void:
	if cell == Vector2i(-1, -1):
		return
	hint_label.text = _mod_hover_text(cell)
	hint_label.add_theme_color_override("font_color", UIKit.TEXT)
	board.queue_redraw()


func _mod_hover_text(cell: Vector2i) -> String:
	var run: RunState = app.run
	var rule: Dictionary = MOD_RULES.get(mod_kind, {})
	var tool_name := String(rule.get("name", mod_kind))
	if MapGenerator.mod_protected(map, cell):
		return "【%s】该格受保护（部署区 / 巢穴 / 奖励 / 果实），不能改造。" % tool_name
	var terrain := int(map["terrain"][GridSpec.index(cell)])
	var from_terrain := int(rule.get("ok_from", TerrainDB.PLAIN))
	var to_terrain := int(rule.get("to", TerrainDB.PLAIN))
	if terrain != from_terrain:
		return "【%s】需要%s（当前：%s），该格不能改造。" % [
			tool_name, TerrainDB.name_of(from_terrain), TerrainDB.name_of(terrain),
		]
	if mod_used >= run.mod_points():
		return "【%s】%s → %s：改造次数已用尽。" % [tool_name, TerrainDB.name_of(from_terrain), TerrainDB.name_of(to_terrain)]
	return "【%s】%s → %s：点击应用，消耗 1 次（剩余 %d 次）。" % [
		tool_name, TerrainDB.name_of(from_terrain), TerrainDB.name_of(to_terrain),
		run.mod_points() - mod_used,
	]


func _on_reset() -> void:
	map = base_map.duplicate(true)
	mod_used = 0
	hint_label.text = ""
	_refresh()


func _refresh() -> void:
	var run: RunState = app.run
	board.set_map_preview(map, _preview_units(run))
	mod_count_label.text = "剩余改造次数：%d / %d" % [maxi(0, run.mod_points() - mod_used), run.mod_points()]
	var lethal := int(map.get("lethal_count", 0))
	var obstacle_count: int = (map.get("obstacle_cells", []) as Array).size()
	hint_label.text = hint_label.text if hint_label.text != "" else "致死地形 %d 格｜障碍 %d 格（种子可复现）" % [lethal, obstacle_count]


func _preview_units(run: RunState) -> Array:
	var units: Array = []
	var cfg := BattleDB.config_for(run.battle_index)
	var index := 0
	for pair in cfg.get("enemies", []):
		var unit := CombatUnit.make(String(pair[0]), "enemy", 100 + index)
		unit.cell = pair[1]
		units.append(unit)
		index += 1
	return units


func _on_start() -> void:
	if String(app.run.options.get("card_mode", "position")) == "position" and app.run.cards.size() != Balance.CARDS_PER_BATTLE:
		hint_label.text = "请先选择 %d 张出战环境卡。" % Balance.CARDS_PER_BATTLE
		hint_label.add_theme_color_override("font_color", UIKit.BAD)
		return
	app.begin_battle(deploy_uids, map)
