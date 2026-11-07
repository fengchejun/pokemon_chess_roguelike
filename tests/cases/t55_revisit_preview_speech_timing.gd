extends RefCounted

const Notice = preload("res://scripts/ui/battle_notice.gd")
const Speech = preload("res://scripts/ui/speech_bubbles.gd")

func run(t: TestContext) -> void:
	t.begin("复战重置、地图实物预览与提示时序")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var merchant_id := ""
	for id in ["event_1", "event_2"]:
		if region.nodes[id].has("merchant"):
			merchant_id = id
	t.check(merchant_id != "", "测试层有商人节点")
	region.active_node = merchant_id
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	var preview = app.current_screen
	t.check(preview.board.nest.is_empty() and preview.board.extra_nests.is_empty(), "非战斗节点预览没有巢穴")
	t.check(GridSpec.is_inside(preview.board.merchant_cell), "首访预览显示商人")
	t.eq(preview.board.food_cells, preview.map.get("food_cells", []), "首访预览绘制将生成的粮食")
	var first_food: Array = preview.board.food_cells.duplicate()
	var first_merchant: Vector2i = preview.board.merchant_cell
	preview._on_start()
	var battle: BattleState = app.current_screen.state
	t.eq(battle.food_cells, first_food, "首访粮食与预览一致")
	t.eq(battle.merchant["cell"], first_merchant, "首访商人与预览一致")
	var saved_food: Vector2i = GridSpec.all_cells().filter(func(cell): return battle.food_cell_valid(cell) and battle.unit_at(cell) == null)[0]
	battle.food_cells = [saved_food]
	battle.reward["state"] = "carried"
	region = app.run.get_region()
	region.store_battle(merchant_id, battle)
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	preview = app.current_screen
	t.eq(preview.board.food_cells, [saved_food], "重访预览显示尚未拾取的粮食")
	t.eq(preview.board.reward["state"], "carried", "已拾取奖励不重新显示为地图奖励")
	t.check(preview.board.nest.is_empty() and GridSpec.is_inside(preview.board.merchant_cell), "重访收集区只显示商人")
	region = app.run.get_region()
	region.active_node = "battle_1"
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	preview = app.current_screen
	preview._on_start()
	battle = app.current_screen.state
	var original: Dictionary = battle.enemy_origins.duplicate(true)
	var survivor: CombatUnit = battle.alive_units("enemy")[0]
	var survivor_uid := survivor.uid
	survivor.cell = Vector2i(3, 0)
	survivor.hp = 1
	if battle.alive_units("enemy").size() > 1:
		battle.alive_units("enemy")[1].hp = 0
	battle.reward["state"] = "carried"
	battle.reward["owner_uid"] = Balance.TRAINER_UID
	battle.round = Balance.MAX_ROUNDS
	battle.end_battle("escape")
	t.check(battle.reward_bonus_earned(), "撤退时存活单位携带的奖励点仍可结算")
	region = app.run.get_region()
	region.store_battle("battle_1", battle)
	app.run.region_data = region.to_dict()
	app.show_preview([1, 2, 3])
	preview = app.current_screen
	var shown: CombatUnit = null
	for enemy in preview.deploy_enemies:
		if enemy.uid == survivor_uid:
			shown = enemy
	t.check(shown != null, "存活敌人保留身份")
	if shown != null:
		t.eq(shown.cell, original[survivor_uid], "预览中的存活敌人返回初次出生格")
		t.eq(shown.hp, shown.max_hp, "预览中的存活敌人回满生命")
	t.eq(preview.deploy_enemies.size(), 4, "复战空缺补足四名")
	t.eq(preview.board.reward["state"], "carried", "撤退获得的奖励点不在复战预览中重现")
	var expected: Dictionary = {}
	for enemy in preview.deploy_enemies:
		expected[enemy.uid] = [enemy.cell, enemy.hp]
	preview._on_start()
	battle = app.current_screen.state
	for uid in expected:
		var unit: CombatUnit = battle.unit_by_uid(uid)
		t.check(unit != null and unit.cell == expected[uid][0] and unit.hp == expected[uid][1], "复战实际敌人与预览一致")
	var notice = Notice.new()
	app.add_child(notice)
	notice.push("我方回合", "player")
	notice.playback_speed = 2.0
	notice.advance(0.49 * notice.playback_speed)
	t.check(notice.active(), "2倍速 0.49 秒仍显示")
	notice.advance(0.02 * notice.playback_speed)
	t.check(not notice.active(), "2倍速 0.5 秒后消失")
	var speech = Speech.new()
	app.add_child(speech)
	speech.screen = app.current_screen
	speech.push({"uid": Balance.TRAINER_UID, "cell": Vector2i(1, 3), "text": "好好大干一场吧！"})
	t.check(speech.entries[0]["panel"].jagged, "感叹号气泡使用折线轮廓")
	speech.set_suppressed(true)
	speech._process(2.0)
	t.eq(speech.entries[0]["remaining"], 3.0, "中央宣告期间气泡暂停计时")
	speech.set_suppressed(false)
	speech._process(0.1)
	speech.dismiss_on_unit_click()
	t.check(not speech.active(), "点击说话单位提前关闭气泡")
	app.queue_free()
	t.finish()
