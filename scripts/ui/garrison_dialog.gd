extends RefCounted

const Invasion = preload("res://scripts/run/floor_invasion.gd")


static func make_button(owner: Control, app, changed: Callable) -> Button:
	var button := UIKit.small_button("指派驻军")
	button.name = "OpenGarrisons"
	button.pressed.connect(func() -> void: _open(owner, app, changed))
	return button


static func _open(owner: Control, app, changed: Callable) -> void:
	var run: RunState = app.run
	var region: RegionState = run.get_region()
	var dialog := AcceptDialog.new()
	dialog.title = "楼层驻防"
	var page := UIKit.vbox(8)
	dialog.add_child(page)
	var selector := OptionButton.new()
	var nodes: Array = []
	for id in region.nodes:
		if id in ["boss", "hunt"] or not region.nodes[id].get("unlocked", false):
			continue
		selector.add_item(region.display_name(id))
		nodes.append(id)
	page.add_child(selector)
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size = Vector2(620, 390)
	page.add_child(scroll)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if not nodes.is_empty():
		selector.select(maxi(0, nodes.find(region.active_node)))
		selector.item_selected.connect(func(index: int) -> void:
			_fill(list, app, nodes[index], changed))
		_fill(list, app, nodes[selector.selected], changed)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	owner.add_child(dialog)
	dialog.popup_centered()


static func _fill(list: VBoxContainer, app, id: String, changed: Callable) -> void:
	UIKit.clear_children(list)
	var run: RunState = app.run
	var region: RegionState = run.get_region()
	list.add_child(UIKit.wrapped("防守成功率 %d%% · 适配%s" % [Invasion.chance(run, region, id), Invasion.specialty(region, id)], 17))
	var notice := UIKit.wrapped("随身成员守当前节点立即就位。其他指派需再完成一次移动。", 14)
	list.add_child(notice)
	for member in run.carried + run.storage:
		var uid := int(member["uid"])
		var assignment: Dictionary = region.garrisons.get(str(uid), {})
		var at_target: bool = assignment.get("node", "") == id
		var status := "随身" if run.carried.has(member) else "仓库"
		if not assignment.is_empty():
			status += " · %s" % region.display_name(assignment["node"])
			var points := Invasion.contribution(region, assignment, member)
			status += " 守备 +%d" % points if points > 0 else " 待就位"
		var button := UIKit.small_button("%s Lv.%d · %s · %s" % [SpeciesDB.name_of(member["species_id"]), member["level"], status, "撤回" if at_target else "指派至此"])
		button.disabled = int(member["hp"]) <= 0
		button.pressed.connect(func() -> void:
			var ok := Invasion.recall(run, uid) if at_target else Invasion.assign(run, id, uid)
			if not ok:
				notice.text = "无法指派。每处最多三只，并须保留一只可出战随身成员。"
				return
			app.autosave()
			changed.call()
			_fill(list, app, id, changed))
		list.add_child(button)
