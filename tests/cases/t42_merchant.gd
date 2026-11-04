extends RefCounted

func run(t: TestContext) -> void:
	t.begin("原质、商人交易与训练师道具")
	for rarity in Merchant.RARITIES:
		var base := int(Merchant.RARITIES[rarity][1])
		for level in [1, 5, 10]:
			var record := {"species_id": "fire_starter", "level": level, "hp": 0}
			t.eq(Merchant.price_for(rarity, level), base * (level + 4) / 5, "稀有度等级报价")
			record["hp"] = 30
			t.eq(Merchant.monster_price(record), 10 * (level + 4) / 5, "HP不影响售价")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var id := "event_1" if region.nodes["event_1"].has("merchant") else "event_2"
	t.eq(int(region.nodes["event_1"].has("merchant")) + int(region.nodes["event_2"].has("merchant")), 1, "每层恰有一名商人")
	region.nodes[id]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var state: BattleState = app.current_screen.state
	t.check(GridSpec.is_inside(state.merchant["cell"]), "商人有合法位置")
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	for cell in GridSpec.neighbors4(state.merchant["cell"]):
		if state.unit_at(cell) == null and TerrainDB.can_stand(state.terrain_at(cell), ""):
			trainer.cell = cell
			break
	app.run.essence = 100
	var upgrade_uid := int(app.run.carried[0]["uid"])
	MonsterProgression.award_xp(app.run.record_by_uid(upgrade_uid), 4)
	var upgrade_id := String(app.run.available_monster_upgrades(upgrade_uid)[0])
	var upgrade_skill := String(RunState.upgrade_info(upgrade_id).get("requires_skill", ""))
	var upgrade_result: Dictionary = app.purchase_skill_upgrade(state, upgrade_uid, upgrade_skill)
	t.check(bool(upgrade_result.get("ok", false)), "商人为二级宝可梦出售已学技能强化")
	t.eq(app.run.essence, 88, "技能强化消耗 12 原质")
	t.check((app.run.record_by_uid(upgrade_uid).get("upgrades_taken", []) as Array).has(upgrade_id), "强化写入宝可梦记录")
	t.check(not bool(app.purchase_skill_upgrade(state, upgrade_uid, upgrade_skill).get("ok", false)), "唯一空刻印槽用完后不能重复强化")
	var second_uid := int(app.run.carried[1]["uid"])
	MonsterProgression.award_xp(app.run.record_by_uid(second_uid), 4)
	var second_upgrade := String(app.run.available_monster_upgrades(second_uid)[0])
	var second_skill := String(RunState.upgrade_info(second_upgrade).get("requires_skill", ""))
	app.current_screen._show_merchant()
	var upgrade_button: Button = app.current_screen.find_child("SkillUpgrade_%d_%s" % [second_uid, second_skill], true, false)
	t.check(upgrade_button != null, "商人界面列出每只宝可梦的合法技能强化")
	if upgrade_button != null:
		upgrade_button.pressed.emit()
	t.eq(app.run.essence, 76, "商人界面点击技能强化正确扣费")
	t.check((app.run.record_by_uid(second_uid).get("upgrades_taken", []) as Array).has(second_upgrade), "商人界面强化写入对应宝可梦")
	app.run.essence = 100
	t.check(not app.merchant_trade(state, "food", "basic", 99)["ok"], "禁止超量出售食物")
	var first_relic := ""
	for key in state.merchant["stock"]:
		if String(key).begins_with("relic:"):
			first_relic = String(key)
			break
	app.run.relic_stacks[first_relic.trim_prefix("relic:")] = 3
	t.check(not app.merchant_trade(state, "buy", first_relic)["ok"], "满级遗物不能购买")
	t.check(app.merchant_trade(state, "relic", first_relic.trim_prefix("relic:"))["ok"], "遗物逐级出售")
	t.eq(RelicDB.rank(state.relic_stacks, first_relic.trim_prefix("relic:")), 2, "出售更新战场遗物等级")
	app.run.essence = 100
	var round_before := state.round
	t.check(app.merchant_trade(state, "buy", "potion")["ok"], "购买治疗药")
	t.eq(app.run.essence, 95, "正确扣款")
	t.eq(state.merchant["stock"]["potion"], 1, "正确扣库存")
	t.eq(state.round, round_before, "交易不耗回合")
	var stock_before: Dictionary = state.merchant["stock"].duplicate()
	app.autosave_enabled = true
	t.check(not app.merchant_trade(state, "buy", "potion", 1, "user://missing_merchant_directory/save.json")["ok"], "写入失败回滚交易")
	app.autosave_enabled = false
	t.eq(app.run.essence, 95, "回滚余额")
	t.eq(state.merchant["stock"], stock_before, "回滚库存")
	t.eq(app.run.trainer_items["potion"], 1, "回滚商品")
	trainer = state.unit_by_uid(Balance.TRAINER_UID)
	var target := state.unit_by_uid(1)
	target.cell = trainer.cell + Vector2i.RIGHT
	state.set_terrain(target.cell, TerrainDB.PLAIN)
	target.hp = 1
	t.check(not Merchant.use_item(app.run, state, "potion", target.uid)["ok"], "自由探索禁止治疗药")
	state.node_kind = "battle"
	state.nest["alive"] = true
	state.add_garrison(1, ["rock_wild1"])
	t.check(Merchant.use_item(app.run, state, "potion", target.uid)["ok"], "正式战斗训练师使用治疗药")
	t.eq(target.hp, 16, "治疗15HP")
	t.check(trainer.skill_used and trainer.capture_used and not state.can_undo(), "道具消耗行动并提交移动")
	trainer.skill_used = false
	trainer.capture_used = false
	app.run.trainer_items["potion"] = 1
	target.hp = 0
	t.check(not Merchant.use_item(app.run, state, "potion", target.uid)["ok"], "不能复活")
	t.eq(app.run.trainer_items["potion"], 1, "失败不消耗")
	app.run.trainer_items["capture_aid"] = 2
	t.check(Merchant.use_item(app.run, state, "capture_aid")["ok"], "捕获辅助生效")
	t.check(BattleSnapshot.load_state(BattleSnapshot.save_state(state)).capture_aid, "辅助随快照保存")
	trainer.skill_used = false
	trainer.capture_used = false
	t.check(not Merchant.use_item(app.run, state, "capture_aid")["ok"], "辅助不可叠加")
	var foe := CombatUnit.make("fire_wild1", "enemy", 900)
	foe.cell = trainer.cell + Vector2i.UP
	state.units.append(foe)
	var chance := CaptureSystem.capture_chance(foe)
	var result := state.capture_attempt(trainer, foe, 0.99)
	t.check(result["ok"] and is_equal_approx(float(result["chance"]), minf(1.0, chance + 0.2)) and not state.capture_aid, "捕获使用加成并消耗辅助")
	state.kill_unit(foe, "测试", "player", 1)
	state.kill_unit(foe, "重复", "player", 1)
	t.eq(state.essence_earned, 3, "同一敌人只领取一次")
	app.run.sync_from_battle(state)
	var balance: int = app.run.essence
	app.run.sync_from_battle(state)
	t.eq(app.run.essence, balance, "同步不重复入账")
	state.node_kind = "event"
	var saved := BattleSnapshot.save_state(state)
	var restored := BattleSnapshot.load_state(JSON.parse_string(JSON.stringify(saved)))
	t.eq(restored.merchant["stock"], state.merchant["stock"], "快照库存不刷新")
	var old_save := saved.duplicate(true)
	old_save["fields"].erase("natural_essence_cells")
	t.check(BattleSnapshot.load_state(old_save).natural_essence_cells.size() > 0, "旧快照补齐天然障碍资格")
	var cell := Vector2i(7, 7)
	state.set_terrain(cell, TerrainDB.TREE)
	state.obstacle_durability[cell] = 1
	state.natural_essence_cells.append(cell)
	state.damage_obstacle(cell, 1, "player")
	t.eq(state.essence_earned, 4, "天然障碍产出1")
	state.place_temp_obstacle(cell, TerrainDB.PLAIN, state.round + 1)
	state.damage_obstacle(cell, 99, "player")
	t.eq(state.essence_earned, 4, "临时造物不产钱")
	state.set_terrain(cell, TerrainDB.TREE)
	state.obstacle_durability[cell] = 1
	state.natural_essence_cells.append(cell)
	state.damage_obstacle(cell, 1, "enemy")
	t.eq(state.essence_earned, 4, "敌方破坏不产钱")
	state.nest["hp"] = 1
	state.nest["alive"] = true
	for enemy in state.alive_units("enemy"):
		enemy.hp = 0
	state.damage_nest(2, "player")
	t.eq(state.essence_earned, 12, "摧毁巢穴产出8")
	state.damage_nest(2, "player")
	t.eq(state.essence_earned, 12, "重复毁巢不产出")
	var sold := int(app.run.carried[1]["uid"])
	app.collection.absorb_run(app.run)
	t.check(app.merchant_trade(state, "monster", str(sold))["ok"], "出售背包成员")
	t.check(app.run.sold_monster_uids.has(sold), "记录收藏排除")
	app.collection.absorb_run(app.run)
	var source := "run:%d:%d" % [app.run.seed, sold]
	t.check(app.collection.owned.all(func(entry): return String(entry.get("source", "")) != source), "售出成员不重新登记收藏")
	var loaded := RunState.from_dict(JSON.parse_string(JSON.stringify(app.run.to_dict())))
	t.eq(loaded.essence, app.run.essence, "原质读档保留")
	t.check(loaded.sold_monster_uids.has(sold), "收藏排除读档保留")
	for member in app.run.carried:
		member["hp"] = 0
		var field_unit := state.unit_by_uid(int(member["uid"]))
		if field_unit != null:
			field_unit.hp = 0
	app.run.carried[0]["hp"] = 1
	state.unit_by_uid(int(app.run.carried[0]["uid"])).hp = 1
	t.check(not app.merchant_trade(state, "monster", str(app.run.carried[0]["uid"]))["ok"], "保护最后一只可出战成员")
	var stocks: Dictionary = loaded.get_region().nodes[id]["merchant"]["stock"].duplicate()
	t.eq(loaded.get_region().nodes[id]["merchant"]["stock"], stocks, "重复访问区域不重抽库存")
	app.queue_free()
	t.finish()
