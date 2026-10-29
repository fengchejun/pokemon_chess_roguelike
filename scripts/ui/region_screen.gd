extends Control

var app = null
var graph: Control
var region


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
	column.add_child(UIKit.title("第 %d 层 · %s · 区域路线" % [region.floor_index + 1, BattleDB.THEMES.get(region.theme, {}).get("name", region.theme)], 25))
	column.add_child(UIKit.label("移动 %d 次｜%s｜首领驻军 %d 名 · 等级 +%d" % [region.visits, region.next_pressure_text(), 5 if region.support_triggered else 3, region.boss_level_bonus], 16, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("初始已进入营地并解锁邻区。可进入任意已解锁区域；确认进入才计移动，首领除外。每区最多停留 8 回合。", 14))
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
	var details: String = "营地：篝火休息与宝可梦互动。" if kind == "camp" else "首领：8 回合内击败或捕获，否则本局失败。" if kind == "boss" else "收集区：可随时离开；第 8 回合强撤%s。" % ("，之后仍保持撤空" if region.support_triggered else "，下次出现 3 名新驻军和巢穴") if kind == "event" else "战斗区：清空敌人与巢穴可离开；第 8 回合强撤，重访补足 4 名。"
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
