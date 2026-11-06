extends "res://scripts/ui/region_screen.gd"
const Flow = preload("res://scripts/run/exploration_flow.gd")

func _ready() -> void:
	name = "RegionScreen"
	UIKit.fill_background(self)
	region = app.run.get_region()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := UIKit.vbox(12)
	margin.add_child(column)
	var row := UIKit.hbox(16)
	column.add_child(row)
	row.add_child(UIKit.title("第1层 · 探索路线", 26))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var team := UIKit.small_button("查看队伍")
	team.pressed.connect(_show_team)
	row.add_child(team)
	var menu := UIKit.small_button("保存并返回菜单")
	menu.pressed.connect(func() -> void: app.autosave(); app.show_menu())
	row.add_child(menu)
	column.add_child(UIKit.label("剩余行动 %d/%d · 原质 %d · 食物 %d" % [maxi(0, Balance.EXPLORATION_ACTIONS - region.visits), Balance.EXPLORATION_ACTIONS, app.run.essence, app.run.total_food()], 20, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("连线始终可见；点亮后可进入，实际到达才揭示节点类型。处理拦路遭遇才能继续深入。去过的地点可直接回访，每次1行动。Boss位置已知，但仍需探索到达路线。行动耗尽：结算当前节点后强制追猎，敌方全员黑化，胜利可通过本层。", 15))
	graph = Control.new()
	graph.name = "FogMap"
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(graph)
	graph.resized.connect(_layout_nodes)
	graph.draw.connect(_draw_links)
	for id in Flow.POSITIONS:
		var node: Dictionary = region.nodes[id]
		var known: bool = int(node.get("visits", 0)) > 0 or id == "boss"
		var available: bool = node.get("unlocked", false)
		var visited: bool = int(node["visits"]) > 0
		var label: String = region.display_name(id) if known else "未知地点"
		var status := "已到达 · 可回访" if visited else "已点亮 · 可探索" if available else "位置已知 · 尚未通路" if known else "未知"
		if node.get("done", false):
			status = "已完成"
		var button := UIKit.button("%s\n%s" % [label, status], 17)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("283647") if available else Color("22252b")
		style.border_color = UIKit.ACCENT if id == region.active_node else Color("4a6378") if known else Color("30333a")
		style.set_border_width_all(2 if id == region.active_node else 1)
		style.set_corner_radius_all(9)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("disabled", style)
		button.name = "Node_" + id
		button.custom_minimum_size = Vector2(192, 66)
		button.disabled = not available
		var target: String = id
		button.pressed.connect(func() -> void: _confirm_entry(target))
		graph.add_child(button)
	column.add_child(UIKit.wrapped("当前位置：%s。亮色地点可以进入；灰色地点须先打通道路。" % region.display_name(region.active_node), 15, UIKit.TEXT_DIM))
	call_deferred("_layout_nodes")

func _layout_nodes() -> void:
	for id in Flow.POSITIONS:
		var cell: Vector2i = Flow.POSITIONS[id]
		graph.get_node("Node_" + id).position = Vector2(0.02 + cell.x * 0.32, 0.02 + cell.y * 0.32) * (graph.size - Vector2(196, 70))
	graph.queue_redraw()

func _draw_links() -> void:
	for id in Flow.POSITIONS:
		for other in region.nodes[id]["links"]:
			if id > other:
				continue
			var a: Control = graph.get_node("Node_" + id)
			var b: Control = graph.get_node("Node_" + other)
			graph.draw_line(a.position + a.size / 2, b.position + b.size / 2, UIKit.TEXT_DIM, 3)

func _confirm_entry(id: String) -> void:
	var node: Dictionary = region.nodes[id]
	var role: String = node["role"]
	var dialog := ConfirmationDialog.new()
	var known: bool = int(node.get("visits", 0)) > 0 or id == "boss"
	dialog.title = "前往" + (region.display_name(id) if known else "未知地点")
	var detail: String = {"starter": "少量普通敌人，无巢穴。清场后打通分支。", "capture": "刷新1—3只野生宝可梦；第3回合结束后逃跑。本次捕捉不能提前退出；目标全部解决或到时后结算。", "group": "可以玩耍、喂食，或主动选择战斗。", "request": "训练家寻找可达鸭，可先离开准备。", "shop": "查看商品、买卖遗物和强化技能；库存不会因回访刷新。", "camp": "消耗食物休息、取用共享仓库、调整队伍。", "treasure": "宝箱隔在深水另一侧。可使用水系伙伴、移动或地形技能解谜；地形变化和损耗保留。", "boss": "敌方约2级，岩系首领带两名同伴，擅长近距离推击与碎岩。不能撤退，需清空敌人与巢穴后通关。"}.get(role, "")
	dialog.dialog_text = (detail if known else "这里的道路已点亮，进入后才能知道具体遭遇。") + "\n确认进入消耗1行动；取消不消耗。"
	dialog.confirmed.connect(func() -> void: app.enter_region_node(id))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
