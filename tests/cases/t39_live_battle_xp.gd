extends RefCounted

const Snapshot = preload("res://scripts/run/battle_snapshot.gd")


func run(t: TestContext) -> void:
	t.begin("即时共享经验与战后升级")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.enter_region_node("camp")
	app.enter_region_node("battle_1")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	var screen = app.current_screen
	var battle: BattleState = screen.state
	var initial_hp := battle.unit_by_uid(1).max_hp
	battle.unit_by_uid(3).hp = 0
	var foes := battle.alive_units("enemy")
	battle.kill_unit(foes[0], "经验验收", "player", 1)
	t.eq(app.run.battle_kill_xp_for(battle, 1), 2, "击杀者即时获得2经验")
	t.eq(app.run.battle_kill_xp_for(battle, 2), 2, "未击杀的存活出战者即时获得等量经验")
	t.eq(app.run.battle_kill_xp_for(battle, 3), 0, "濒死出战者不获得经验")
	battle.kill_unit(foes[1], "经验验收", "player", 2)
	screen._refresh_after_action()
	t.eq(app.run.battle_kill_xp_for(battle, 1), 4, "两次击杀即时累计到升级门槛")
	t.eq(battle.unit_by_uid(1).combat_level, 1, "战斗内等级不提前生效")
	t.eq(battle.unit_by_uid(1).max_hp, initial_hp, "战斗内属性不因经验门槛变化")
	var caption: Label = screen.find_child("BattleXPText_1", true, false)
	t.check(caption != null and caption.text.contains("战后可升至 Lv.2"), "经验条明确提示战后升级")
	var bar: ProgressBar = screen.find_child("BattleXP_1", true, false)
	t.check(bar != null and bar.value == bar.max_value, "达到经验门槛时进度条填满")
	app.run.battle_snapshot = Snapshot.save_state(battle)
	var restored_run := RunState.from_dict(JSON.parse_string(JSON.stringify(app.run.to_dict())))
	var restored_battle := Snapshot.load_state(restored_run.battle_snapshot)
	t.eq(restored_run.battle_kill_xp_for(restored_battle, 2), 4, "续战保留即时经验")
	restored_battle.end_battle("escape")
	restored_run.settle_battle(restored_battle)
	t.eq(restored_run.record_by_uid(1)["xp"], 4, "战后将即时经验记入本局成长")
	t.eq(restored_run.record_by_uid(2)["xp"], 4, "战后存活出战成员获得相同经验")
	t.eq(restored_run.record_by_uid(3)["xp"], 0, "战后濒死成员不获得经验")
	t.eq(restored_run.record_by_uid(1)["level"], 2, "战后才生效等级")
	restored_run.settle_battle(restored_battle)
	t.eq(restored_run.record_by_uid(1)["xp"], 4, "重复结算不重复增加经验")
	app.queue_free()
	t.finish()
