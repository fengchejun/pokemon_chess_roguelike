extends RefCounted

func run(t: TestContext) -> void:
	t.begin("设施相邻互动与宝可梦出售界面")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var id := "event_1" if region.nodes["event_1"].has("merchant") else "event_2"
	region.nodes[id]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var screen = app.current_screen
	var state: BattleState = screen.state
	state.merchant["cell"] = Vector2i(4, 3)
	var cell: Vector2i = state.merchant["cell"]
	var trainer := state.trainer()
	trainer.cell = Vector2i.ZERO
	for x in range(2, 7):
		state.set_terrain(Vector2i(x, 3), TerrainDB.PLAIN)
	screen.playback.finish_all()
	screen.refresh_all()
	screen.select_unit(trainer.uid)
	t.check(screen.skill_box.find_child("MerchantInteractButton", true, false) == null, "远离商人时没有交易行为")
	screen._on_board_clicked(cell)
	t.check(screen.modal_layer == null and screen.hint_label.text.contains("相邻"), "远程点击商人提示靠近")
	t.check(not app.merchant_trade(state, "buy", "potion")["ok"], "交易底层也校验相邻")
	var actor := state.unit_by_uid(1)
	actor.cell = Vector2i(3, 3)
	t.check(not state.move_options(actor).has(cell), "地面单位不能站商人格")
	actor.battle_buffs["flight"] = true
	t.check(not state.move_options(actor).has(cell), "飞行单位也不能停在商人格")
	t.check(not SkillResolver.targets(state, actor, "volt_step").any(func(e): return e["cell"] == cell), "不能瞬移至商人格")
	t.check(not SkillResolver.targets(state, actor, "tree_man").any(func(e): return e["cell"] == cell), "不能在商人格召唤")
	PushResolver.push(state, actor, Vector2i.RIGHT, 1, 0, "设施验证")
	t.eq(actor.cell, Vector2i(3, 3), "击退不能将单位推上商人")
	screen.playback.finish_all()
	actor.cell = Vector2i(2, 4)
	trainer.cell = Vector2i(3, 3)
	screen.refresh_all()
	screen.select_unit(trainer.uid)
	var interact: Button = screen.skill_box.find_child("MerchantInteractButton", true, false)
	t.check(interact != null, "训练师相邻后出现交易行为")
	interact.pressed.emit()
	t.check(screen.modal_layer != null, "点击交易行为打开商店")
	var uid := int(app.run.carried[1]["uid"])
	var price := Merchant.monster_price(app.run.record_by_uid(uid))
	var before: int = app.run.essence
	var sale: Button = screen.modal_layer.find_child("SellMonster_%d" % uid, true, false)
	t.check(sale != null, "商店有对应成员出售按钮")
	sale.pressed.emit()
	var confirm: Button = screen.modal_layer.find_child("ConfirmMonsterSaleButton", true, false)
	t.check(confirm != null, "出售使用可交互的同层确认页")
	var cancel: Button = screen.modal_layer.find_child("CancelMonsterSaleButton", true, false)
	cancel.pressed.emit()
	t.check(not app.run.record_by_uid(uid).is_empty(), "取消出售保留成员")
	t.eq(app.run.essence, before, "取消出售不改变原质")
	screen.modal_layer.find_child("SellMonster_%d" % uid, true, false).pressed.emit()
	confirm = screen.modal_layer.find_child("ConfirmMonsterSaleButton", true, false)
	confirm.pressed.emit()
	t.check(app.run.record_by_uid(uid).is_empty(), "确认后实际移除成员")
	t.check(state.unit_by_uid(uid) == null, "确认后移除战场上的售出成员")
	t.eq(app.run.essence, before + price, "出售金额实际到账")
	t.check(app.run.sold_monster_uids.has(uid), "售出成员保留收藏排除记录")
	t.check(screen.modal_layer != null, "出售完成后返回商店")
	screen._close_modal()
	state.node_kind = "boss"
	state.boss_portal_cell = Vector2i(6, 3)
	screen.refresh_all()
	screen.select_unit(trainer.uid)
	t.check(screen.skill_box.find_child("PortalInteractButton", true, false) == null, "远离传送门时没有进入行为")
	screen.action_mode = "move"
	screen._on_board_clicked(state.boss_portal_cell)
	t.check(not state.ended and screen.hint_label.text.contains("相邻"), "移动模式点击远处门也不绕过距离校验")
	trainer.cell = Vector2i(5, 3)
	t.check(not state.move_options(trainer).has(state.boss_portal_cell), "不能站上传送门")
	screen.action_mode = "main"
	screen.refresh_all()
	screen.select_unit(trainer.uid)
	var portal: Button = screen.skill_box.find_child("PortalInteractButton", true, false)
	t.check(portal != null, "训练师靠近后出现进入传送门行为")
	app.run.storage.clear()
	screen.settled_reported = true # This synchronous fixture owns teardown.
	portal.pressed.emit()
	t.check(state.ended and state.end_reason == "victory", "相邻时通过行为按钮进入传送门")
	app.queue_free()
	t.finish()
