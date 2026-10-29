extends Control

var app = null
const POSITIONS := {"camp": Vector2(.08, .5), "battle_1": Vector2(.28, .25), "event_1": Vector2(.28, .75), "battle_2": Vector2(.46, .2), "battle_3": Vector2(.46, .72), "event_2": Vector2(.62, .38), "battle_4": Vector2(.78, .23), "battle_5": Vector2(.72, .75), "boss": Vector2(.93, .5)}
const NAMES := {"camp": "营地", "battle": "普通战斗", "event": "非战斗区域", "boss": "首领挑战"}
var graph: Control


func _ready() -> void:
	name = "RegionScreen"
	UIKit.fill_background(self)
	var region = app.run.get_region()
	var column := UIKit.vbox(12)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 30
	column.offset_top = 24
	column.offset_right = -30
	column.offset_bottom = -24
	add_child(column)
	column.add_child(UIKit.title("第 %d 层 · %s" % [region.floor_index + 1, BattleDB.THEMES.get(region.theme, {}).get("name", region.theme)]))
	column.add_child(UIKit.wrapped("访问节点解锁相邻地点。每进入一个非首领节点，首领生命与直伤各增加基础值的 5%。首领战限 8 回合。", 16))
	column.add_child(UIKit.label("食物 %d · 首领强化 +%d%%" % [app.run.food, region.visits * 5], 18, UIKit.ACCENT))
	graph = Control.new()
	graph.custom_minimum_size.y = 350
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(graph)
	graph.resized.connect(_layout_graph)
	graph.draw.connect(_draw_links)
	for id in region.nodes:
		var node: Dictionary = region.nodes[id]
		var unlocked := bool(node.get("unlocked", false))
		var status := "未解锁" if not unlocked else "已清空" if node["cleared"] else "已访问 %d 次" % int(node["visits"])
		var button := UIKit.button("%s\n%s" % [NAMES[region.node_mode(id)], status], 15)
		var style := StyleBoxFlat.new()
		style.bg_color = UIKit.PANEL
		style.border_color = UIKit.ACCENT if unlocked else UIKit.TEXT_DIM.darkened(.5)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(style_name, style)
		button.name = "Node_" + id
		button.custom_minimum_size = Vector2(134, 64)
		button.disabled = not bool(node.get("unlocked", false)) or (node["type"] == "boss" and node["cleared"])
		var node_id := String(id)
		button.pressed.connect(func() -> void: app.enter_region_node(node_id))
		graph.add_child(button)
	if region.active_node == "camp":
		var rest := UIKit.button("休息：消耗 3 食物，携带队伍与训练家恢复全部生命")
		rest.name = "CampRestButton"
		rest.disabled = app.run.food < 3
		rest.pressed.connect(func() -> void:
			if app.run.rest_at_region_camp():
				app.autosave()
				app.show_region()
		)
		column.add_child(rest)
	call_deferred("_layout_graph")


func _point(id: String) -> Vector2:
	return Vector2(70, 45) + POSITIONS[id] * (graph.size - Vector2(140, 90))


func _layout_graph() -> void:
	for id in POSITIONS:
		var button := graph.get_node_or_null("Node_" + id)
		if button != null:
			button.position = _point(id) - Vector2(67, 32)
	graph.queue_redraw()


func _draw_links() -> void:
	var region = app.run.get_region()
	for id in region.nodes:
		for neighbor in region.nodes[id].get("links", []):
			if String(id) < String(neighbor):
				graph.draw_line(_point(id), _point(neighbor), UIKit.TEXT_DIM, 2)
