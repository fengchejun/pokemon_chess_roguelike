extends Control
const Flow = preload("res://scripts/run/exploration_flow.gd")
var app = null
var column: VBoxContainer
var message := ""
var title_label: Label
var resources_label: Label
var return_button: Button

func _ready() -> void:
	name = "NodeScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := UIKit.vbox(14)
	margin.add_child(page)
	var header := UIKit.hbox(16)
	page.add_child(header)
	title_label = UIKit.title("", 28)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	return_button = UIKit.button("返回层地图", 17)
	return_button.name = "ReturnToRegion"
	return_button.pressed.connect(leave)
	header.add_child(return_button)
	var bag := UIKit.small_button("道具背包")
	bag.name = "OpenItemBag"
	bag.pressed.connect(func() -> void:
		var screen = load("res://scripts/ui/item_bag_screen.gd").new()
		screen.return_to_node = true
		app._switch(screen))
	header.add_child(bag)
	if not app.run.get_region().invaded:
		header.add_child(preload("res://scripts/ui/garrison_dialog.gd").make_button(self, app, refresh))
	resources_label = UIKit.label("", 18, UIKit.ACCENT)
	page.add_child(resources_label)
	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	column = UIKit.vbox(12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	refresh()

func button(text: String, id: String, callback: Callable, disabled: bool = false) -> void:
	var control := UIKit.button(text, 16)
	control.name = id
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242b37")
	style.border_color = Color("46566c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	control.add_theme_stylebox_override("normal", style)
	control.disabled = disabled
	control.pressed.connect(callback)
	column.add_child(control)

func persist(region) -> void:
	app.run.region_data = region.to_dict()
	app.autosave()
	refresh()

func refresh() -> void:
	UIKit.clear_children(column)
	var run: RunState = app.run
	var region = run.get_region()
	var node: Dictionary = region.nodes[region.active_node]
	var role: String = node["role"]
	title_label.text = region.display_name(region.active_node)
	resources_label.text = "原质 %d · 食物 %d · %s" % [run.essence, run.total_food(), region.next_pressure_text()]
	return_button.disabled = bool(node.get("reward_pending", false))
	return_button.tooltip_text = "先选择本次奖励，再返回地图。" if return_button.disabled else "结算当前节点后检查楼层入侵。"
	column.add_child(UIKit.wrapped(message, 16))
	if node.get("reward_pending", false):
		column.add_child(UIKit.wrapped("选择本次事件的遗物奖励，再结束这次行动。", 17))
		for id in node.get("offers", []):
			var relic: String = id
			button("%s · %s" % [RelicDB.display_name_of(relic), RelicDB.description_of(relic)], "EventRelic_" + relic, func() -> void:
				if not node.get("reward_pending", false): return
				if RelicDB.rank(run.relic_stacks, relic) >= 3: return
				run.relic_stacks[relic] = RelicDB.rank(run.relic_stacks, relic) + 1
				node["reward_pending"] = false
				persist(region))
		return
	match role:
		"empty": column.add_child(UIKit.wrapped("林间空地上没有新的遭遇。附近道路已经揭示，可以返回地图选择下一处地点。", 17))
		"camp": _camp(run, region)
		"shop", "item_shop", "skill_shop": _shop(run, region)
		"group":
			column.add_child(UIKit.wrapped("一群宝可梦围着树果嬉戏。你可以接近它们，也可以先去准备食物再回来。", 17))
			if node.get("done", false):
				column.add_child(UIKit.label("这群宝可梦已经离开，这次事件已完成。"))
			else:
				button("和它们玩耍：获得4原质与1份食物", "PlayGroup", func() -> void:
					if node.get("done", false): return
					run.essence += 4; run.add_food("basic", 1)
					node["done"] = true
					persist(region))
				button("喂食2份食物：获得一件随机普通遗物", "FeedGroup", func() -> void:
					if node.get("done", false) or int(run.food_inventory.get("basic", 0)) < 2: return
					run.food_inventory["basic"] -= 2; run.food = run.total_food()
					award(run, region, node), int(run.food_inventory.get("basic", 0)) < 2)
				button("主动战斗：争取捕获与战斗收益", "FightGroup", func() -> void:
					node["battle_selected"] = true
					run.region_data = region.to_dict(); app.autosave(); app.show_prep())
		"request":
			var terms := Flow.request_terms(node, region.theme)
			var reward := request_reward(int(terms["tier"]))
			var reward_text := "%d 原质与 %d 份食物" % [reward.x, reward.y]
			if int(terms["tier"]) > 1:
				reward_text += "，另得一件随机普通遗物"
			column.add_child(UIKit.wrapped("%s。奖励 %s。仅接收随身成员，交付后该成员永久离队。可以先离开寻找。" % [Flow.request_description(terms), reward_text], 17))
			if not node.get("done", false):
				var candidates := run.carried.filter(func(record): return not run.is_garrisoned(int(record["uid"])) and Flow.request_matches(terms, record))
				if candidates.is_empty():
					column.add_child(UIKit.wrapped("当前没有符合要求的随身成员。", 14))
				for record in candidates:
					var uid := int(record["uid"])
					button("交付 %s · Lv.%d（永久离队）" % [SpeciesDB.name_of(record["species_id"]), int(record["level"])], "Deliver_%d" % uid, func() -> void:
						var confirm := ConfirmationDialog.new()
						confirm.dialog_text = "确认交付这只伙伴？该成员及其培养将永久离开本局队伍。"
						confirm.confirmed.connect(func() -> void: deliver(uid))
						confirm.canceled.connect(func() -> void: confirm.queue_free())
						add_child(confirm); confirm.popup_centered())
				column.add_child(UIKit.wrapped("交付后会点亮委托节点相邻的道路。", 14))
			else:
				column.add_child(UIKit.label("委托已完成，后方道路已开放。"))

func leave() -> void:
	var run: RunState = app.run
	var region = run.get_region()
	if region.nodes[region.active_node].get("reward_pending", false): return
	region.complete_visit()
	run.region_data = region.to_dict()
	run.pending_region_entry_backup.clear()
	app.autosave()
	app.show_region()


func award(run: RunState, region, node: Dictionary) -> void:
	node["done"] = true
	node["passable"] = true
	region.unlock_neighbors(region.active_node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("event-loot:%d:%d:%s" % [run.seed, region.floor_index, region.active_node])
	var relic := preload("res://scripts/run/battle_loot.gd").grant_random_relic(run, RelicDB.COMMON, rng)
	message = "获得 %s。" % relic
	persist(region)

func request_reward(tier: int) -> Vector2i:
	return [Vector2i(12, 1), Vector2i(24, 3), Vector2i(48, 6)][tier - 1]

func deliver(uid: int) -> void:
	var run: RunState = app.run
	var region = run.get_region()
	var node: Dictionary = region.nodes[region.active_node]
	if node.get("role") != "request" or node.get("done", false) or run.is_garrisoned(uid):
		return
	var terms := Flow.request_terms(node, region.theme)
	for index in run.carried.size():
		var record: Dictionary = run.carried[index]
		if int(record["uid"]) != uid or not Flow.request_matches(terms, record):
			continue
		run.carried.remove_at(index)
		var tier := int(terms["tier"])
		var reward := request_reward(tier)
		run.essence += reward.x
		run.add_food("basic", reward.y)
		if tier > 1:
			award(run, region, node)
		else:
			node["done"] = true
			node["passable"] = true
			region.unlock_neighbors(region.active_node)
			persist(region)
		return

func _camp(run: RunState, region) -> void:
	column.add_child(UIKit.wrapped("营地服务不消耗额外行动。共享仓库成员跨层保留。", 16))
	button("消耗3份食物休息（濒死成员恢复半血）", "CampRestButton", func() -> void:
		var result := run.rest_with_food({"basic": 3})
		message = "\n".join(result.get("results", [])) if result.get("ok", false) else String(result.get("reason", ""))
		app.autosave(); refresh(), int(run.food_inventory.get("basic", 0)) < 3 or not run.needs_camp_rest())
	column.add_child(UIKit.label("随身伙伴", 20, UIKit.ACCENT))
	for member in run.carried:
		column.add_child(UIKit.label("%s · Lv.%d · HP %d/%d" % [SpeciesDB.name_of(member["species_id"]), int(member["level"]), int(member["hp"]), run.monster_max_hp(member)], 16))
	column.add_child(UIKit.label("共享仓库 · %d名" % run.storage.size(), 20, UIKit.ACCENT))
	for stored in run.storage:
		for member in run.carried:
			var a := int(member["uid"]); var b := int(stored["uid"])
			button("%s ↔ 随身的%s" % [SpeciesDB.name_of(stored["species_id"]), SpeciesDB.name_of(member["species_id"])], "CampSwap_%d_%d" % [a, b], func() -> void:
				run.camp_swap(a, b); app.autosave(); refresh())

func _shop(run: RunState, region) -> void:
	var node: Dictionary = region.nodes[region.active_node]
	if not node.has("stock"):
		var stock := {}
		if node["role"] == "skill_shop":
			var pool: Array = []
			for member in run.carried:
				for skill in run.available_new_skills(int(member["uid"])):
					if not pool.has(skill):
						pool.append(skill)
			if pool.size() < 3:
				for element in Elements.LIST:
					for skill in SkillDB.learnable_ids_for(element):
						if not SkillDB.is_special(skill) and not pool.has(skill):
							pool.append(skill)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("skill-shop:%d:%d" % [run.seed, region.floor_index])
			for index in mini(3, pool.size()):
				stock[Merchant.BOOK_PREFIX + String(pool.pop_at(rng.randi_range(0, pool.size() - 1)))] = 1
		else:
			stock = {"food": 6, "potion": 2, "capture_aid": 2}
			for relic in RelicDB.offer(run.seed, region.floor_index, 501, {}):
				stock["relic:" + relic] = 1
		node["stock"] = stock
		run.region_data = region.to_dict(); app.autosave()
	if node["role"] == "item_shop" and not node.get("growth_stock_initialized", false):
		node["stock"].merge(Merchant.ITEM_SHOP_ADDITIONS)
		node["growth_stock_initialized"] = true
		run.region_data = region.to_dict()
		app.autosave()
	var intel_reason := Flow.intel_unavailable(region) if node["role"] == "item_shop" else ""
	if not intel_reason.is_empty() and int(node["stock"].get(Merchant.INTEL_ID, 0)) > 0:
		column.add_child(UIKit.wrapped("神秘宝可梦情报 · " + intel_reason, 15))
	for product in node["stock"]:
		var id: String = product
		var relic := id.trim_prefix("relic:")
		var price := _price(id)
		var title: String
		if id.begins_with(Merchant.BOOK_PREFIX):
			title = "技能书 · " + SkillDB.name_of(id.trim_prefix(Merchant.BOOK_PREFIX))
		elif id.begins_with("relic:"):
			title = RelicDB.display_name_of(relic)
		else:
			title = "基础食物" if id == "food" else String(Merchant.ITEMS[id][0])
		var unavailable := id == Merchant.INTEL_ID and not intel_reason.is_empty()
		var disabled := unavailable or run.essence < price or int(node["stock"][id]) <= 0 or (id.begins_with("relic:") and RelicDB.rank(run.relic_stacks, relic) >= 3)
		button("购买%s · %d原质 · 剩余%d" % [title, price, int(node["stock"][id])], "Buy_" + id.replace(":", "_"), func() -> void: buy(id), disabled)
	if node["role"] != "skill_shop":
		for relic_id in run.relic_stacks:
			var relic: String = relic_id
			if RelicDB.rank(run.relic_stacks, relic) <= 0: continue
			button("出售一级%s · 获得8原质" % RelicDB.name_of(relic), "Sell_" + relic, func() -> void:
				run.relic_stacks[relic] -= 1; run.essence += 8; app.autosave(); refresh())
	if node["role"] == "item_shop":
		return
	for record in run.carried:
		for skill in record.get("equipped_skills", []):
			var uid := int(record["uid"]); var id: String = skill
			var cost := run.merchant_skill_upgrade_cost(record)
			if not run.available_monster_upgrades(uid).has(RunState.upgrade_id_for_skill(id)): continue
			button("强化%s的%s · %d原质" % [SpeciesDB.name_of(record["species_id"]), SkillDB.name_of(id), cost], "Upgrade_%d_%s" % [uid, id], func() -> void:
				if run.essence >= cost and run.apply_merchant_skill_upgrade(uid, id): run.essence -= cost
				app.autosave(); refresh(), run.essence < cost)

func _price(id: String) -> int:
	if id.begins_with(Merchant.BOOK_PREFIX):
		return Merchant.BOOK_PRICE
	if id.begins_with("relic:"):
		return 16
	return 3 if id == "food" else int(Merchant.ITEMS.get(id, ["", 999])[1])

func buy(id: String) -> void:
	var run: RunState = app.run
	var region = run.get_region()
	var node: Dictionary = region.nodes[region.active_node]
	var price := _price(id)
	if int(node.get("stock", {}).get(id, 0)) <= 0 or run.essence < price: return
	if id.begins_with("relic:"):
		var relic := id.trim_prefix("relic:")
		if RelicDB.rank(run.relic_stacks, relic) >= 3: return
		run.relic_stacks[relic] = RelicDB.rank(run.relic_stacks, relic) + 1
	elif id == "food":
		run.add_food("basic", 1)
	elif id == Merchant.INTEL_ID:
		if node["role"] != "item_shop" or not Flow.unlock_rare_habitat(region, run.seed):
			return
		message = "已解锁本层的神秘栖息地。返回地图后可前往。"
	else:
		run.trainer_items[id] = int(run.trainer_items.get(id, 0)) + 1
	run.essence -= price; node["stock"][id] -= 1
	persist(region)
