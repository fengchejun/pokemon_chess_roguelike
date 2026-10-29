extends RefCounted

const Region = preload("res://scripts/run/region_state.gd")


func run(t: TestContext) -> void:
	t.begin("区域块、限时与敌军支援")
	var region := Region.create_floor(0, "grass")
	t.eq(region.nodes.size(), 9, "每层九个区域")
	t.eq(region.active_node, "camp", "开局已处于营地")
	t.eq(region.visits, 0, "初始营地不计移动")
	t.check(region.nodes["event_1"]["unlocked"] and region.nodes["battle_1"]["unlocked"] and region.nodes["battle_3"]["unlocked"], "初始解锁共享边邻区")
	t.check(not region.nodes["boss"]["unlocked"], "首领区域初始未解锁")
	t.check(region.record_entry("battle_3"), "可进入已解锁战斗区")
	t.check(region.nodes["boss"]["unlocked"], "进入后解锁共享边邻区")
	t.eq(region.visits, 1, "确认进入才计移动")
	t.check(not region.record_entry("event_1"), "未结束本次探索不可重复进入")
	region.complete_visit()
	t.check(region.record_entry("boss"), "首领解锁后可提前挑战")
	t.eq(region.visits, 1, "首领进入不计移动")
	region.complete_visit()
	var supply := TestScenario.make_state(["fire_starter"], [])
	supply.node_kind = "event"
	var picker := supply.unit_by_uid(1)
	t.eq(supply.move_budget_for(picker), picker.effective_move(), "收集区使用普通移动力")
	supply.round = 8
	supply.settle_round()
	t.eq(supply.end_reason, "escape", "收集区第八回合强撤")
	t.check(region.store_battle("event_1", supply), "原生收集区保存战场快照")
	t.eq(region.node_mode("event_1"), "battle", "超时后收集区改为战斗区")
	t.check(region.nodes["event_1"]["pending_garrison"], "重新进场待生成新驻军和巢穴")
	var saved := Region.from_dict(JSON.parse_string(JSON.stringify(region.to_dict())))
	t.eq(saved.node_mode("event_1"), "battle", "节点转换经 JSON 持久化")
	t.check(saved.load_battle("event_1") != null, "原生收集区快照经 JSON 持久化")
	var fight := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(6, 2)]])
	fight.node_kind = "battle"
	var foe: CombatUnit = fight.alive_units("enemy")[0]
	foe.hp -= 3
	fight.nest["hp"] = 2
	fight.end_battle("escape")
	t.check(region.store_battle("battle_1", fight), "战斗区保存受损敌军和巢穴")
	t.check(region.nodes["battle_1"]["pending_replenish"], "未清场超时登记补兵")
	var resumed := region.resume_node("battle_1", [CombatUnit.make("trainer", "player", Balance.TRAINER_UID)])
	t.eq(resumed.unit_by_uid(foe.uid).hp, foe.max_hp, "重访存活敌军回满")
	t.eq(resumed.nest["hp"], 2, "巢穴损耗不恢复")
	t.check(not resumed.can_leave_node(), "未清场不可提前离开")
	foe.hp = 0
	fight.nest["alive"] = false
	region.store_battle("battle_1", fight)
	t.eq(region.node_mode("battle_1"), "event", "真正清场后转收集区")
	var pressure := Region.create_floor(0, "water")
	var stationed := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 2)]])
	stationed.node_kind = "battle"
	stationed.food_cells.append(Vector2i(4, 4))
	pressure.store_battle("battle_1", stationed)
	for index in range(7):
		t.check(pressure.record_entry("camp"), "营地重访可计移动 %d" % (index + 1))
		pressure.complete_visit()
	t.check(not pressure.support_triggered, "第七次移动尚未支援")
	pressure.record_entry("event_1")
	pressure.store_battle("event_1", supply)
	pressure.complete_visit()
	t.check(pressure.support_triggered, "第八次探索结束触发一次支援")
	t.eq(pressure.node_mode("event_1"), "event", "同次收集超时由支援撤军覆盖")
	t.check(not pressure.nodes["event_1"]["pending_garrison"], "不遗留待生成驻军")
	t.check(pressure.nodes["battle_1"]["withdrawn"], "普通战斗区永久撤军")
	var abandoned := pressure.load_battle("battle_1")
	t.eq(abandoned.alive_enemy_count(), 0, "已保存战场内的敌人随支援撤离")
	t.check(not abandoned.nest["alive"], "撤军后巢穴停止产兵")
	t.check(abandoned.food_cells.has(Vector2i(4, 4)), "撤军后场景物资仍在")
	pressure.record_entry("event_1")
	pressure.store_battle("event_1", supply)
	pressure.complete_visit()
	t.eq(pressure.node_mode("event_1"), "event", "支援后收集超时不再转战斗")
	t.check(not pressure.nodes["event_1"]["pending_garrison"], "支援后不再准备驻军")
	for expected in range(10, 15):
		pressure.record_entry("camp")
		pressure.complete_visit()
		t.eq(pressure.boss_level_bonus, 0 if expected < 11 else 1 if expected < 14 else 2, "首领等级在 11、14 次边界提升")
	var roundtrip := Region.from_dict(JSON.parse_string(JSON.stringify(pressure.to_dict())))
	t.eq(roundtrip.visits, 14, "移动计数持久化")
	t.eq(roundtrip.boss_level_bonus, 2, "支援阶段持久化")
	t.check(roundtrip.complete_visit().is_empty(), "读档不重复执行压力事件")
	var run_state := RunState.new_run(42)
	run_state.region_mode = true
	run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
	run_state.trainer_hp = 1
	run_state.carried[0]["hp"] = 0
	var rest := run_state.rest_with_food({"basic": 3})
	t.check(rest["ok"], "初始营地可立即休息")
	t.eq(run_state.trainer_hp, SpeciesDB.hp_of("trainer"), "恢复训练家")
	t.eq(run_state.carried[0]["hp"], run_state.monster_max_hp(run_state.carried[0]), "恢复濒死成员")
	t.eq(run_state.food_inventory["basic"], 0, "按食物种类扣除 3 份")
	t.check(not run_state.rest_with_food({"basic": 3})["ok"], "无需恢复时不能重复休息")
	var legacy: Dictionary = run_state.to_dict()
	legacy["version"] = 9
	legacy.erase("food_inventory")
	var migrated := RunState.from_dict(legacy)
	t.eq(migrated.food_inventory["basic"], 0, "v9 食物总数迁移为基础食物库存")
	var legacy_path := "res://.test_region_v9.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	var disk_migrated := SaveSystem.load_run(legacy_path)
	t.check(disk_migrated != null and int(disk_migrated.food_inventory["basic"]) == 0, "存档入口继续读取 v9")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	t.finish()
