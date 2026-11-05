extends RefCounted
const Region = preload("res://scripts/run/region_state.gd")
func run(t: TestContext) -> void:
	t.begin("区域占领与节点解锁")
	var region := Region.create_floor(0, "grass")
	t.eq(region.visits, 0, "初始营地不计数")
	region.record_entry("battle_3")
	t.check(not region.nodes["boss"]["unlocked"], "进入战斗不解锁邻接")
	var fight := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 2)]])
	fight.node_kind = "battle"
	fight.end_battle("escape")
	region.store_battle("battle_3", fight)
	t.check(not region.nodes["boss"]["unlocked"], "超时撤退不解锁")
	fight.ended = false
	for enemy in fight.alive_units("enemy"):
		enemy.hp = 0
	fight.nest["alive"] = false
	fight.end_battle("victory")
	region.store_battle("battle_3", fight)
	t.check(region.nodes["boss"]["unlocked"], "胜利后解锁邻接")
	region.complete_visit()
	for index in range(7):
		region.record_entry("camp")
		region.complete_visit()
	t.check(region.support_triggered, "第八次移动触发占领")
	region.occupy_all()
	t.check(region.support_triggered, "八轮战斗事件触发全面占领")
	for id in region.nodes:
		if id != "boss":
			t.eq(region.node_mode(id), "battle", "所有非首领节点包括营地战斗化")
	for index in range(6):
		region.record_entry("camp")
		region.complete_visit()
	t.eq(region.boss_level_bonus, 2, "十一和十四次全体各加一级")
	t.eq(region.node_mode("camp"), "battle", "营地被占")
	var loaded := Region.from_dict(region.to_dict())
	t.eq(loaded.boss_level_bonus, 2, "压力持久化")
	t.check(loaded.complete_visit().is_empty(), "加载不重复施加压力")
	var run_state := RunState.new_run(42)
	run_state.region_mode = true
	run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
	run_state.trainer_hp = 1
	run_state.carried[0]["hp"] = 0
	var rest := run_state.rest_with_food({"basic": 3})
	t.check(rest["ok"], "初始营地可立即休息")
	t.eq(run_state.trainer_hp, SpeciesDB.hp_of("trainer"), "恢复训练家")
	t.eq(run_state.carried[0]["hp"], ceili(run_state.monster_max_hp(run_state.carried[0]) / 2.0), "濒死成员恢复一半生命")
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
