extends RefCounted

const Region = preload("res://scripts/run/region_state.gd")


func run(t: TestContext) -> void:
	t.begin("区域节点持久化")
	var region := Region.create(1, "water", [{"id": "camp", "type": "camp"}, {"id": "a", "type": "battle"}, {"id": "b", "type": "event"}, {"id": "boss", "type": "boss"}])
	t.check(region != null, "四类节点可建立区域")
	t.check(region.record_entry("a") and region.record_entry("camp") and region.record_entry("a"), "普通节点可重复访问")
	t.eq(region.visits, 3, "每次进入分别计数，供 Boss 强化使用")
	var battle := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(6, 2)]])
	var enemy: CombatUnit = battle.alive_units("enemy")[0]
	enemy.hp -= 3
	battle.nest = {"alive": true, "hp": 2, "pending_waves": 1}
	t.check(region.store_battle("a", battle), "战场可保存至所属节点")
	var json: Dictionary = JSON.parse_string(JSON.stringify(region.to_dict()))
	var loaded := Region.from_dict(json)
	var restored := loaded.load_battle("a")
	t.eq(restored.unit_by_uid(enemy.uid).hp, enemy.hp, "重读区域保留敌人生命")
	t.eq(restored.nest, battle.nest, "保留巢穴耐久和产敌额度")
	t.eq(loaded.visits, 3, "访问次数经存档保留")
	for member in battle.alive_units("enemy"):
		member.hp = 0
	region.store_battle("a", battle)
	t.eq(region.node_mode("a"), "battle", "敌人清除但巢穴仍在时不算清空")
	battle.nest["alive"] = false
	region.store_battle("a", battle)
	t.eq(region.node_mode("a"), "event", "敌人与巢穴都清空后作为非战斗节点")
	t.check(region.record_entry("a"), "清空节点仍可进入")
	var floor_region := Region.create_floor(0, "grass")
	t.eq(floor_region.nodes.size(), 9, "每层包含五战斗、两事件、营地和首领")
	t.check(not floor_region.record_entry("boss"), "未连通首领不可直接进入")
	t.check(floor_region.record_entry("camp") and floor_region.record_entry("event_1") and floor_region.record_entry("battle_3") and floor_region.record_entry("battle_5"), "访问节点即可沿分支解锁，无需清空战斗")
	var visits_before := floor_region.visits
	t.check(floor_region.record_entry("boss"), "路线推进后首领解锁")
	t.eq(floor_region.visits, visits_before, "进入首领自身不增加强化次数")
	var boss_battle := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)], ["water_wild1", Vector2i(6, 4)]])
	var boss: CombatUnit = boss_battle.alive_units("enemy")[0]
	boss_battle.boss_uid = boss.uid
	boss_battle.round = 7
	boss_battle.end_enemy_phase()
	t.check(not boss_battle.ended, "首领战第七回合不超时")
	boss_battle.round = 8
	boss_battle.end_enemy_phase()
	t.eq(boss_battle.end_reason, "boss_timeout", "第八回合首领存活判失败")
	var failed_run := RunState.new_run(42)
	failed_run.settle_battle(boss_battle)
	t.check(failed_run.run_failed, "首领超时终止本局")
	var win := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)], ["water_wild1", Vector2i(6, 4)]])
	var defeated: CombatUnit = win.alive_units("enemy")[0]
	win.boss_uid = defeated.uid
	defeated.hp = 0
	t.check(win.check_battle_end() and win.end_reason == "victory", "首领被击败即可获胜，无需清空其余敌人")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.trainer_hp = 1
	app.run.carried[0]["hp"] = 0
	app.show_region()
	t.eq(app.current_screen.name, "RegionScreen", "区域路线页可打开")
	app.enter_region_node("camp")
	var rest: Button = app.current_screen.find_child("CampRestButton", true, false)
	t.check(rest != null and not rest.disabled, "营地提供有物资的休息指令")
	rest.pressed.emit()
	t.eq(app.run.food, 0, "休息消耗三份食物")
	t.eq(app.run.trainer_hp, SpeciesDB.hp_of("trainer"), "营地恢复训练家")
	t.eq(app.run.carried[0]["hp"], app.run.monster_max_hp(app.run.carried[0]), "营地恢复濒死成员")
	t.check(not app.run.rest_at_region_camp(), "物资不足不能继续休息")
	var restored_run := RunState.from_dict(JSON.parse_string(JSON.stringify(app.run.to_dict())))
	t.check(restored_run.region_mode and restored_run.get_region().active_node == "camp", "区域模式和当前位置可存档往返")
	t.eq(restored_run.food, 0, "食物消耗可存档往返")
	app.queue_free()
	t.finish()
