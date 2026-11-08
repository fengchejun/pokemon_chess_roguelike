extends RefCounted

const Invasion = preload("res://scripts/run/floor_invasion.gd")


static func make_button(owner: Control, app, changed: Callable) -> Button:
	var button := UIKit.small_button("指派驻军")
	button.name = "OpenGarrisons"
	button.pressed.connect(func() -> void:
		if owner.has_node("GarrisonMap"):
			return
		var map = load("res://scripts/ui/exploration_map_screen.gd").new()
		map.app = app
		map.garrison_only = true
		map.garrison_changed = changed
		map.z_index = 20
		map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		owner.add_child(map))
	return button


static func open_node(owner: Control, app, id: String, changed: Callable) -> void:
	var run: RunState = app.run
	var region: RegionState = run.get_region()
	if owner.has_node("GarrisonNodeDialog") or region.invaded or id in ["boss", "hunt"] or not region.nodes.get(id, {}).get("unlocked", false):
		return
	var overlay := ColorRect.new()
	overlay.name = "GarrisonNodeDialog"
	overlay.color = Color(0.02, 0.03, 0.06, 0.86)
	overlay.z_index = 30
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.add_child(overlay)
	var panel := UIKit.panel()
	panel.set_anchor(SIDE_LEFT, 0.14)
	panel.set_anchor(SIDE_TOP, 0.09)
	panel.set_anchor(SIDE_RIGHT, 0.86)
	panel.set_anchor(SIDE_BOTTOM, 0.91)
	overlay.add_child(panel)
	var page := UIKit.vbox(10)
	panel.add_child(page)
	var header := UIKit.hbox(12)
	page.add_child(header)
	var title := UIKit.label("%s · 指派驻军" % region.display_name(id), 23, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := UIKit.small_button("返回地图")
	back.name = "CloseGarrisonNode"
	back.pressed.connect(overlay.queue_free)
	header.add_child(back)
	var summary := UIKit.wrapped("", 17, UIKit.ACCENT)
	summary.name = "GarrisonSummary"
	page.add_child(summary)
	var notice := UIKit.wrapped("", 14)
	page.add_child(notice)
	var scroll := UIKit.scroll()
	page.add_child(scroll)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_fill(list, summary, notice, app, id, changed)


static func _fill(list: VBoxContainer, summary: Label, notice: Label, app, id: String, changed: Callable) -> void:
	UIKit.clear_children(list)
	var run: RunState = app.run
	var region: RegionState = run.get_region()
	var count := region.garrisons.values().filter(func(entry): return entry["node"] == id).size()
	summary.text = "驻军 %d/3 · 防守成功率 %d%% · 入侵压力 −%d
适配招式：%s" % [count, Invasion.chance(run, region, id), Invasion.pressure(region, id), Invasion.specialty(region, id)]
	notice.text = "随身成员守当前节点立即就位。其他成员完成下一次移动后就位，改派会重置准备。"
	for member in run.carried + run.storage:
		var uid := int(member["uid"])
		var assignment: Dictionary = region.garrisons.get(str(uid), {})
		var at_target: bool = assignment.get("node", "") == id
		var carried := run.carried.has(member)
		var preview := assignment if at_target else Invasion.assignment_for(region, id, carried)
		var points := Invasion.breakdown(region, preview, member)
		var status := "随身" if carried else "仓库"
		if not assignment.is_empty():
			status += " · 驻守%s" % region.display_name(assignment["node"])
		var total := "已计入 +%d" % points["total"] if at_target and points["ready"] else "立即就位 +%d" % points["total"] if points["ready"] else "下一次移动后 +%d" % (int(points["base"]) + int(points["level"]) + int(points["specialty"]))
		if int(member["hp"]) <= 0:
			total = "濒死，无法派驻"
		var row := UIKit.panel(UIKit.PANEL_LIGHT)
		var line := UIKit.hbox(8)
		row.add_child(line)
		var info := UIKit.wrapped("%s Lv.%d · %s · %s
基础 %d · 等级 +%d · 招式适配 +%d · 准备 +%d" % [
			SpeciesDB.name_of(member["species_id"]), member["level"], status, total,
			points["base"], points["level"], points["specialty"], points["preparation"],
		], 15)
		info.name = "GarrisonDetails_%d" % uid
		line.add_child(info)
		var button := UIKit.small_button("撤回" if at_target else "指派" if assignment.is_empty() else "改派")
		button.name = "GarrisonMember_%d" % uid
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not at_target and (int(member["hp"]) <= 0 or count >= 3)
		button.pressed.connect(func() -> void:
			var ok := Invasion.recall(run, uid) if at_target else Invasion.assign(run, id, uid)
			if not ok:
				notice.text = "无法派驻，须保留至少一只可出战的随身成员。"
				return
			app.autosave()
			changed.call()
			_fill(list, summary, notice, app, id, changed))
		line.add_child(button)
		list.add_child(row)
