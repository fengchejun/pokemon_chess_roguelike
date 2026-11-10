extends "res://scripts/ui/region_screen.gd"
const Widgets = preload("res://ui/components/pixel_widgets.gd")
const Flow = preload("res://scripts/run/exploration_flow.gd")
const Garrisons = preload("res://scripts/ui/garrison_dialog.gd")
const Invasion = preload("res://scripts/run/floor_invasion.gd")

var garrison_only := false
var garrison_changed: Callable
var garrison_mode := false
var mode_button: Button
var mode_title: Label
var map_help: Label

func _ready() -> void:
	name = "GarrisonMap" if garrison_only else "RegionScreen"
	garrison_mode = garrison_only
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	mode_title = UIKit.title("", 26)
	row.add_child(mode_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if not garrison_only:
		var team := UIKit.small_button("查看队伍")
		team.pressed.connect(_show_team)
		row.add_child(team)
	if not region.invaded:
		mode_button = UIKit.small_button("")
		mode_button.name = "OpenGarrisons"
		mode_button.pressed.connect(_exit_or_toggle_garrisons)
		row.add_child(mode_button)
	if not garrison_only:
		var bag := UIKit.small_button("道具背包")
		bag.name = "OpenItemBag"
		bag.pressed.connect(func() -> void: app._switch(preload("res://scripts/ui/item_bag_screen.gd").new()))
		row.add_child(bag)
		var menu := UIKit.small_button("保存并返回菜单")
		menu.pressed.connect(func() -> void: app.autosave(); app.show_menu())
		row.add_child(menu)
	var resources := UIKit.hbox(12)
	column.add_child(resources)
	resources.add_child(Widgets.stat("◆", str(app.run.essence), "原质", UIKit.ACCENT))
	resources.add_child(Widgets.stat("食", str(app.run.total_food()), "食物", UIKit.GOOD))
	resources.add_child(UIKit.label(region.next_pressure_text(), 16, UIKit.TEXT_DIM))
	column.add_child(UIKit.wrapped("已知地点保留名称和连线。入侵后从保住的前线逐步夺回节点，失守服务在本层永久关闭。", 15))
	graph = Control.new()
	graph.name = "FogMap"
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(graph)
	graph.resized.connect(_layout_nodes)
	graph.draw.connect(_draw_links)
	for id in region.nodes:
		if id == "hunt":
			continue
		var button := UIKit.button("", 17)
		button.name = "Node_" + id
		button.custom_minimum_size = Vector2(192, 66)
		button.pressed.connect(_select_node.bind(id))
		graph.add_child(button)
	map_help = UIKit.wrapped("", 15, UIKit.TEXT_DIM)
	column.add_child(map_help)
	_refresh_mode()
	call_deferred("_layout_nodes")


func _exit_or_toggle_garrisons() -> void:
	if garrison_only:
		queue_free()
		return
	garrison_mode = not garrison_mode
	_refresh_mode()


func _refresh_mode() -> void:
	region = app.run.get_region()
	mode_title.text = "第%d层 · %s" % [region.floor_index + 1, "驻防选点" if garrison_mode else "探索路线"]
	if mode_button != null:
		mode_button.text = "返回原界面" if garrison_only else "返回移动" if garrison_mode else "指派驻军"
	map_help.text = "选择已点亮的非 Boss 节点查看守备与派驻。驻防选点不消耗移动。" if garrison_mode else "当前位置：%s。亮色地点可以进入；灰色地点须先打通道路。" % region.display_name(region.active_node)
	for child in graph.get_children():
		_update_node_button(String(child.name).trim_prefix("Node_"), child)


func _update_node_button(id: String, button: Button) -> void:
	var node: Dictionary = region.nodes[id]
	var known: bool = bool(node.get("unlocked", false)) or int(node.get("visits", 0)) > 0 or id == "boss"
	var available: bool = region.can_enter_after_invasion(id) if region.invaded else node.get("unlocked", false)
	known = known or available
	var visited: bool = int(node["visits"]) > 0
	var label: String = region.display_name(id) if known else "未知地点"
	var status := "已到达 · 可回访" if visited else "已点亮 · 可探索" if available else "位置已知 · 尚未通路" if known else "未知"
	if node.get("done", false):
		status = "已完成"
	if node.get("occupied", false) and known:
		status = "敌军占领" + (" · 携带军需" if node.get("invasion_carrier", false) else "")
	elif node.get("service_lost", false):
		status = "已夺回 · 服务关闭"
	elif node.get("defense", {}).get("held", false):
		status += " · 已守住"
	if garrison_mode:
		available = not region.invaded and id != "boss" and bool(node.get("unlocked", false))
		if available:
			var count: int = region.garrisons.values().filter(func(entry): return entry["node"] == id).size()
			status = "驻军 %d/3 · 守住 %d%%" % [count, Invasion.chance(app.run, region, id)]
		elif id == "boss":
			status = "不可驻防"
	button.text = "%s\n%s" % [label, status]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("283647") if available else Color("22252b")
	style.border_color = UIKit.ACCENT if id == region.active_node else Color("4a6378") if known else Color("30333a")
	style.set_border_width_all(2 if id == region.active_node else 1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(10)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)
	button.disabled = not available or (not garrison_mode and node.has("rare_species") and node.get("done", false) and not node.get("service_lost", false))


func _select_node(id: String) -> void:
	if not garrison_mode:
		_confirm_entry(id)
		return
	Garrisons.open_node(self, app, id, func() -> void:
		_refresh_mode()
		if garrison_changed.is_valid():
			garrison_changed.call())


func _unhandled_input(event: InputEvent) -> void:
	if garrison_mode and team_overlay == null and event.is_action_pressed("ui_cancel"):
		var panel := get_node_or_null("GarrisonNodeDialog")
		if panel != null:
			panel.queue_free()
		else:
			_exit_or_toggle_garrisons()
		get_viewport().set_input_as_handled()
	else:
		super._unhandled_input(event)


func _layout_nodes() -> void:
	for id in region.nodes:
		if id == "hunt":
			continue
		var cell: Vector2i = Flow.position(id, region.nodes[id])
		graph.get_node("Node_" + id).position = Vector2(0.02 + cell.x * 0.32, 0.02 + cell.y * 0.32) * (graph.size - Vector2(196, 70))
	graph.queue_redraw()

func _draw_links() -> void:
	for id in region.nodes:
		if id == "hunt":
			continue
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
	var known: bool = bool(node.get("unlocked", false)) or int(node.get("visits", 0)) > 0 or id == "boss"
	dialog.title = "前往" + (region.display_name(id) if known else "未知地点")
	var detail: String = {"starter": "少量普通敌人，无巢穴。清场后打通分支；可由训练师前往绿色撤离区撤退，区外伙伴承受原有扣血代价。", "capture": "固定出现3只野生宝可梦；攻击或尝试捕捉会惊动全场，抵达撤离点后停留至下次行动即可逃脱。第8回合结束剩余目标全部逃跑，也可随时直接离开。", "group": "可以玩耍、喂食，或主动选择战斗；事件战斗可直接离开，未胜利不发放挑战奖励。", "request": "%s。只接收随身成员，可先离开准备。" % Flow.request_description(Flow.request_terms(node, region.theme)), "shop": "查看商品、买卖遗物和强化技能；库存不会因回访刷新。", "camp": "消耗食物休息、取用共享仓库、调整队伍。", "treasure": Flow.puzzle_description(node), "boss": "岩系首领带两名同伴，擅长近距离推击与碎岩。不能撤退，需清空敌人与巢穴后通关。"}.get(role, "")
	if node.has("rare_species"):
		detail = "有一只稀有宝可梦在此活动，进入后才会揭晓物种。只有一次遭遇机会，开战后主动离开也会用掉这次机会。"
	if role in ["starter", "battle", "elite"]:
		detail = "%d 名普通敌人，无巢穴。清场后打通分支。未清场可从绿色撤离区撤退。" % (3 + region.floor_index)
	if role == "elite":
		detail += " 敌人等级比本层普通战斗高 1 级。"
	elif role == "item_shop":
		detail = "购买补给、道具及遗物，可出售遗物。回访不补货。"
	elif role == "skill_shop":
		detail = "强化招式或购买技能书。回访不补货。"
	if node.get("occupied", false):
		detail = "夺回战，敌军黑化。每轮预告并落雷。" + (" 有限时军需携带者。" if node.get("invasion_carrier", false) else "")
	elif node.get("service_lost", false):
		detail = "已夺回。原服务永久关闭，可通过此节点。"
	dialog.dialog_text = (detail if known or region.invaded else "这里尚未点亮，节点内容仍未知。") + ("\n入侵已结算，可继续推进。" if region.invaded else "\n确认进入消耗1行动；取消不消耗。")
	dialog.confirmed.connect(func() -> void: app.enter_region_node(id))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
