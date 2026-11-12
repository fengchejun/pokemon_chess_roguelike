extends RefCounted

func open_node(app, id: String) -> void:
	var region = app.run.get_region()
	region.nodes[id]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)

func run(t: TestContext) -> void:
	t.begin("精英节点、分工商店、技能书背包与非战斗用药")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	var run: RunState = app.run
	run.choose_floor_theme(String(run.offered_floor_themes[0]))
	run.essence = 100
	open_node(app, "event_2")
	var node = app.current_screen
	t.check(node.find_child("Buy_potion", true, false) != null, "道具店出售治疗药")
	t.check(not node.column.get_children().any(func(child): return String(child.name).begins_with("Upgrade_")), "道具店不提供强化")
	node.find_child("Buy_potion", true, false).pressed.emit()
	t.eq(run.trainer_items["potion"], 1, "道具店购药写入背包")
	node.leave()
	open_node(app, "shop_2")
	node = app.current_screen
	var region = run.get_region()
	var stock: Dictionary = region.nodes["shop_2"]["stock"]
	t.eq(stock.size(), 3, "技能店生成三本技能书")
	t.check(node.find_child("Buy_potion", true, false) == null, "技能店不卖常规药品")
	for id in Merchant.ITEM_SHOP_ADDITIONS:
		t.check(node.find_child("Buy_" + id, true, false) == null, "技能店不卖成长糖果或情报")
	var item := String(stock.keys()[0])
	var skill := item.trim_prefix(Merchant.BOOK_PREFIX)
	var uid := 0
	for record in run.carried:
		if run.available_new_skills(int(record["uid"])).has(skill):
			uid = int(record["uid"])
			break
	t.check(uid > 0, "技能店优先出售队伍可学的书")
	var before := run.essence
	node.find_child("Buy_" + item.replace(":", "_"), true, false).pressed.emit()
	t.eq(run.essence, before - Merchant.BOOK_PRICE, "购买技能书正确扣款")
	t.eq(run.trainer_items[item], 1, "买书不指定成员，直接存入背包")
	t.check(not run.record_by_uid(uid)["known_skills"].has(skill), "购买时尚未学习")
	t.eq(RunState.from_dict(run.to_dict()).trainer_items[item], 1, "技能书可存档")
	node.buy(item)
	t.eq(run.essence, before - Merchant.BOOK_PRICE, "售罄后不能重复购买")
	var visits: int = run.get_region().visits
	run.trainer_hp = 1
	node.find_child("OpenItemBag", true, false).pressed.emit()
	var bag = app.current_screen
	t.eq(bag.name, "ItemBagScreen", "商店可打开道具背包")
	bag.find_child("UseBook_%s_%d" % [skill, uid], true, false).pressed.emit()
	t.check(run.record_by_uid(uid)["known_skills"].has(skill) and int(run.trainer_items[item]) == 0, "背包选成员学习并消耗一本书")
	bag.find_child("UsePotion_%d" % Balance.TRAINER_UID, true, false).pressed.emit()
	t.eq(run.trainer_hp, 16, "非战斗背包用药恢复15点")
	t.eq(run.trainer_items["potion"], 0, "用药扣掉一件库存")
	bag.find_child("ReturnFromItemBag", true, false).pressed.emit()
	t.eq(run.get_region().visits, visits, "打开与关闭背包不消耗地图行动")
	t.eq(app.current_screen.name, "NodeScreen", "从背包返回原商店")
	app.current_screen.leave()
	open_node(app, "elite_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var state: BattleState = app.current_screen.state
	t.eq(state.exploration_role, "elite", "正常入口进入精英战")
	t.check(state.alive_units("enemy").all(func(enemy): return enemy.enemy_level == 2), "第一层精英战实际敌人等级加一")
	t.check(not state.uses_extraction() and not state.can_escape(), "精英战取消撤退区与主动撤退")
	app.free()
	t.finish()
