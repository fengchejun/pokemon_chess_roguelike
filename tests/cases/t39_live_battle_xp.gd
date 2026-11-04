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
	foes[0].enemy_level = 5
	battle.kill_unit(foes[0], "经验验收", "player", 1)
	t.eq(app.run.battle_kill_xp_for(battle, 1), 4, "五级敌人给击杀者 4 经验")
	t.eq(app.run.battle_kill_xp_for(battle, 2), 2, "未击杀的存活出战者获得一半参与经验")
	t.eq(app.run.battle_kill_xp_for(battle, 3), 2, "已出战的濒死成员仍可结算参与经验")
	battle.kill_unit(foes[1], "经验验收", "player", 2)
	screen.playback.finish_all()
	screen._refresh_after_action()
	t.eq(app.run.battle_kill_xp_for(battle, 1), 5, "高等级击杀与一级敌人参与经验累计")
	t.eq(app.run.battle_kill_xp_for(battle, 2), 4, "两名不同击杀者按各自贡献累计经验")
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
	restored_run.sync_from_battle(restored_battle)
	restored_run.settle_battle(restored_battle)
	t.eq(restored_run.record_by_uid(1)["xp"], 6, "战后将即时经验与非失败参战经验记入本局成长")
	t.eq(restored_run.record_by_uid(2)["xp"], 5, "第二名击杀者保留自己的等级梯度经验")
	t.eq(restored_run.record_by_uid(3)["xp"], 4, "濒死成员结算参与与参战经验但不复活")
	t.eq(restored_run.record_by_uid(1)["level"], 2, "战后才生效等级")
	t.eq(restored_run.record_by_uid(3)["hp"], 0, "经验不会救活濒死成员")
	restored_run.settle_battle(restored_battle)
	t.eq(restored_run.record_by_uid(1)["xp"], 6, "重复结算不重复增加经验")
	app.queue_free()
	t.finish()
