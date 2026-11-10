extends RefCounted
const Notice = preload("res://scripts/ui/battle_notice.gd")
const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")

func run(t: TestContext) -> void:
	t.begin("大地图队伍资源与中央提示横条")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.essence = 37
	app.run.food_inventory = {"basic": 8}
	app.run.storage.append(app.run._make_record("rock_starter"))
	app.show_region()
	var screen = app.current_screen
	var resources: Control = screen.find_child("RegionResources", true, false)
	t.check(_texts(resources).contains("37") and _texts(resources).contains("8"), "地图直接显示原质与食物")
	var before: Dictionary = app.run.to_dict().duplicate(true)
	screen.find_child("ViewTeamButton", true, false).pressed.emit()
	t.check(screen.team_overlay != null, "点击队伍按钮打开队伍窗口")
	var content: Control = screen.find_child("RegionTeamContent", true, false)
	var texts := _texts(content)
	t.check(texts.contains("训练师") and texts.contains("随行队伍") and texts.contains("营地留守") and texts.contains("装备招式"), "队伍信息包含训练师、随行与留守成员及招式")
	t.eq(app.run.to_dict(), before, "查看队伍不消耗访问次数或改变成员")
	screen.find_child("CloseTeamButton", true, false).pressed.emit()
	t.check(screen.team_overlay == null, "队伍窗口可关闭回地图")
	var banner = Notice.new()
	screen.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	banner.size = Vector2(1280, 720)
	banner._layout()
	banner.push("敌方回合", "enemy")
	t.check(banner.visible and banner.active(), "横条显示时阻止操作")
	t.eq(banner.band.position, Vector2(400, 301), "像素卡片水平垂直居中")
	t.eq(banner.band.size.x, 480.0, "像素卡片限制为480宽度")
	banner.advance(0.99)
	t.check(banner.active(), "0.99秒仍显示")
	banner.advance(0.02)
	t.check(not banner.active() and not banner.visible, "超过1秒自动消失")
	banner.push("胜利", "victory")
	banner.push("我方回合", "player")
	banner.advance(1.0)
	t.eq(banner.caption.text, "我方回合", "连续提示顺序显示")
	t.check(banner.active(), "后一个提示拥有自己的1秒")
	banner.advance(1.0)
	t.check(not banner.active(), "队列全部完成后隐藏")
	for reason in ["forced_retreat", "boss_timeout"]:
		t.eq(BattleScreenScript.result_notice_kind(reason), "defeat", "训练师倒下及首领超时均提示失败")
	t.eq(BattleScreenScript.result_notice_kind("escape"), "escape", "超时强撤提示撤退")
	t.eq(BattleScreenScript.result_notice_kind("victory"), "victory", "胜利结果提示胜利")
	t.eq(BattleScreenScript.result_notice_kind("explored"), "", "主动离开收集区不冒充战斗胜利")
	var battle_screen = BattleScreenScript.new()
	battle_screen.state = TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	app._switch(battle_screen)
	battle_screen.battle_notice.push("我方回合", "player")
	var trainer: CombatUnit = battle_screen.state.trainer()
	battle_screen.selected_uid = trainer.uid
	var origin := trainer.cell
	t.check(not battle_screen.do_move(Vector2i(1, 3)), "提示期间不接受移动")
	t.eq(trainer.cell, origin, "提示期间不改变战斗位置")
	battle_screen.battle_notice.finish_all()
	t.check(not battle_screen._playback_active(), "横条结束后解除操作锁")
	battle_screen.state.node_kind = "battle"
	battle_screen.state.units = battle_screen.state.units.filter(func(unit): return unit.side == "player")
	battle_screen.state.stop_nests()
	battle_screen._check_victory_notice()
	t.check(battle_screen.victory_announced, "自由探索胜利触发一次提示")
	battle_screen._check_victory_notice()
	t.check(battle_screen.battle_notice.pending.is_empty(), "重复刷新不重复排队胜利提示")
	app.queue_free()
	t.finish()

func _texts(node: Node) -> String:
	var value: String = node.text if node is Label else ""
	for child in node.get_children():
		value += _texts(child)
	return value
