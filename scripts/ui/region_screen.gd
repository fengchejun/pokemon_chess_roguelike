extends Control

var app = null
var graph: Control
var region
var team_overlay: Control = null


func _ready() -> void:
	name = "RegionScreen"
	UIKit.fill_background(self)
	region = app.run.get_region()
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		outer.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 14)
	add_child(outer)
	var column := UIKit.vbox(7)
	outer.add_child(column)
	var header := UIKit.hbox(14)
	column.add_child(header)
	var title := UIKit.title("第 %d 层 · %s · 区域路线" % [region.floor_index + 1, BattleDB.THEMES.get(region.theme, {}).get("name", region.theme)], 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var resources := UIKit.label("原质 %d  ·  食物 %d" % [app.run.essence, app.run.total_food()], 18, UIKit.ACCENT)
	resources.name = "RegionResources"
	header.add_child(resources)
	var team_button := UIKit.small_button("查看队伍")
	team_button.name = "ViewTeamButton"
	team_button.pressed.connect(_show_team)
	header.add_child(team_button)
	column.add_child(UIKit.wrapped("移动%d次｜%s｜首领驻军%d名 · 敌人等级+%d" % [region.visits, region.next_pressure_text(), 5 if region.support_triggered else 3, app.run.invasion_level_bonus], 16, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("初始营地邻区已解锁。可进入任意已解锁区域；确认进入才计移动，首领除外。正式战斗无回合上限；第8轮末敌军黑化，天雷照常预告。第8次区域移动全面占领（包括营地）。第11次移动全图黑化；夺回营地恢复食物回复。胜利后自由探索；主动撤离不解锁邻区。", 14))
	graph = Control.new()
	graph.name = "AreaGraph"
	graph.custom_minimum_size.y = 350
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(graph)
	graph.resized.connect(_layout_graph)
	graph.draw.connect(_draw_regions)
	for id in RegionState.AREA_CELLS:
		var node: Dictionary = region.nodes[id]
		var unlocked := bool(node.get("unlocked", false))
		var status := "未解锁" if not unlocked else "当前位置" if region.active_node == id else "敌军撤离" if bool(node.get("withdrawn", false)) else "已清空" if bool(node.get("cleared", false)) and region.node_mode(id) == "event" else "已探索" if int(node.get("visits", 0)) > 0 else "待探索"
		if node.has("merchant") and int(node.get("visits", 0)) > 0:
			status += " · 商人" if region.node_mode(id) == "event" else " · 商人暂停交易"
		if unlocked and node.has("mentor"):
			status += " · 技能导师" if region.node_mode(id) == "event" else " · 导师暂停服务"
		if unlocked and (region.corrupted or bool(node.get("corrupted", false))) and region.node_mode(id) in ["battle", "boss"]:
			status += " · 黑化"
		var button := UIKit.button("%s\n%s" % [region.display_name(String(id)), status], 17)
		button.name = "Node_" + id
		button.custom_minimum_size = Vector2(142, 58)
		button.disabled = not unlocked or (id == "boss" and bool(node.get("cleared", false)))
		var node_id := String(id)
		button.pressed.connect(func() -> void: _confirm_entry(node_id))
		graph.add_child(button)
	if not region.notifications.is_empty():
		var notice := UIKit.panel(UIKit.PANEL)
		var content := UIKit.vbox(2)
		notice.add_child(content)
		content.add_child(UIKit.label("区域变化", 15, UIKit.ACCENT))
		for message in region.notifications:
			content.add_child(UIKit.wrapped(String(message), 14))
		column.add_child(notice)
		region.notifications.clear()
		app.run.region_data = region.to_dict()
		app.autosave()
	call_deferred("_layout_graph")


func _point(x: int, y: int) -> Vector2:
	var point := Vector2(7.0 + maxf(1, graph.size.x - 14.0) * float(x) / 3.0, 4.0 + maxf(1, graph.size.y - 8.0) * float(y) / 3.0)
	if x > 0 and x < 3 and y > 0 and y < 3:
		point += Vector2(17 if (x + y) % 2 == 0 else -15, 10 if x == y else -11)
	return point


func _polygon(id: String) -> PackedVector2Array:
	var cell: Vector2i = RegionState.AREA_CELLS[id]
	return PackedVector2Array([_point(cell.x, cell.y), _point(cell.x + 1, cell.y), _point(cell.x + 1, cell.y + 1), _point(cell.x, cell.y + 1)])


func _layout_graph() -> void:
	for id in RegionState.AREA_CELLS:
		var button := graph.get_node_or_null("Node_" + id)
		if button == null:
			continue
		var points := _polygon(String(id))
		button.position = (points[0] + points[1] + points[2] + points[3]) / 4.0 - button.custom_minimum_size / 2.0
	graph.queue_redraw()


func _draw_regions() -> void:
	for id in RegionState.AREA_CELLS:
		var node: Dictionary = region.nodes[id]
		var color := Color("20242d")
		if bool(node.get("unlocked", false)):
			color = Color("394c45") if region.node_mode(id) == "event" else Color("493b3a") if region.node_mode(id) == "battle" else Color("544038") if id == "boss" else Color("4a4936")
		if bool(node.get("withdrawn", false)):
			color = Color("384852")
		if region.active_node == id:
			color = color.lightened(.22)
		var points := _polygon(String(id))
		graph.draw_colored_polygon(points, color)
		graph.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), UIKit.ACCENT if region.active_node == id else UIKit.TEXT_DIM, 2.0)


func _confirm_entry(id: String) -> void:
	var node: Dictionary = region.nodes[id]
	var kind: String = region.node_mode(id)
	var details: String = "营地：篝火休息与宝可梦互动。" if kind == "camp" else "首领：击败或捕获后开启传送门；第8轮末起预告天雷，无回合上限。" if kind == "boss" else "收集区：无限行动，可随时离开；禁止恢复技能。" if kind == "event" else "战斗区：清空敌人与巢穴后无限探索；第8轮末起预告天雷，可主动撤离，重访补足4名。"
	if kind == "boss" and not app.run.storage.is_empty():
		details += "\n进入首领区后无法返回营地。进入下一层时，营地留守的 %d 只宝可梦将被抛弃，无法进入永久收藏。" % app.run.storage.size()
	if kind == "boss" and app.run.carried.size() >= Balance.CARRIED_LIMIT:
		details += "\n背包已满：本战新捕获的宝可梦将送往营地，进入下一层时被抛弃。"
	if bool(node.get("pending_replenish", false)):
		details += "\n本次进场补足 4 名敌人。"
	if bool(node.get("pending_garrison", false)):
		details += "\n本次出现 3 名新驻军与巢穴。"
	var dialog := ConfirmationDialog.new()
	dialog.title = "进入%s" % region.display_name(id)
	dialog.dialog_text = details + "\n确认进入后计 1 次移动（首领除外）。"
	dialog.confirmed.connect(func() -> void: app.enter_region_node(id))
	add_child(dialog)
	dialog.popup_centered()


func _show_team() -> void:
	if team_overlay != null:
		return
	team_overlay = ColorRect.new()
	team_overlay.name = "RegionTeamOverlay"
	team_overlay.color = Color(0.02, 0.03, 0.06, 0.88)
	team_overlay.z_index = 40
	team_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(team_overlay)
	var panel := UIKit.panel(UIKit.PANEL)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_anchor(SIDE_LEFT, 0.08)
	panel.set_anchor(SIDE_TOP, 0.08)
	panel.set_anchor(SIDE_RIGHT, 0.92)
	panel.set_anchor(SIDE_BOTTOM, 0.92)
	team_overlay.add_child(panel)
	var column := UIKit.vbox(10)
	panel.add_child(column)
	var header := UIKit.hbox(12)
	column.add_child(header)
	var title := UIKit.label("队伍信息 · 原质 %d · 食物 %d" % [app.run.essence, app.run.total_food()], 22, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UIKit.small_button("关闭")
	close.name = "CloseTeamButton"
	close.pressed.connect(_close_team)
	header.add_child(close)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := UIKit.vbox(10)
	content.name = "RegionTeamContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	content.add_child(UIKit.label("训练师 · Lv.%d · 经验 %d · 生命 %d/%d" % [app.run.trainer_level, app.run.trainer_xp, app.run.trainer_hp, app.run.trainer_max_hp()], 18))
	for group in [{"title": "随行队伍", "records": app.run.carried}, {"title": "营地留守", "records": app.run.storage}]:
		content.add_child(UIKit.label("%s（%d）" % [group["title"], group["records"].size()], 18, UIKit.ACCENT))
		if group["records"].is_empty():
			content.add_child(UIKit.label("暂无成员", 14, UIKit.TEXT_DIM))
		for record in group["records"]:
			var names: Array = []
			for skill in record.get("equipped_skills", []):
				names.append(SkillDB.name_of(String(skill)))
			var info := "%s · Lv.%d · 生命 %d/%d%s\n装备招式：%s" % [SpeciesDB.name_of(String(record["species_id"])), int(record.get("level", 1)), int(record["hp"]), app.run.monster_max_hp(record), " · 濒死" if int(record["hp"]) <= 0 else "", "、".join(names) if not names.is_empty() else "无"]
			content.add_child(UIKit.wrapped(info, 16))

func _close_team() -> void:
	if team_overlay != null:
		team_overlay.queue_free()
		team_overlay = null

func _unhandled_input(event: InputEvent) -> void:
	if team_overlay != null and event.is_action_pressed("ui_cancel"):
		_close_team()
		get_viewport().set_input_as_handled()
