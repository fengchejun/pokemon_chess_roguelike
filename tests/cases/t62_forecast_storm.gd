extends RefCounted

func run(t: TestContext) -> void:
	t.begin("第八轮后预告天雷与无限回合")
	_timing(t)
	_fixed_cells(t)
	_damage(t)
	_save_and_free(t)
	_channels(t)
	_ui(t)
	t.finish()

func _state() -> BattleState:
	return TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(6, 6)]])

func _timing(t: TestContext) -> void:
	var state := _state()
	state.round = 7
	state.settle_round()
	t.check(state.storm_strikes.is_empty(), "第7轮末尚无天雷锁定")
	state.round = 8
	var hp := state.unit_by_uid(1).hp
	state.end_enemy_phase()
	t.check(not state.ended and state.round == 9, "第8轮结束进入第9轮而不强撤")
	t.eq(state.unit_by_uid(1).hp, hp, "首次预告不立即造成伤害")
	t.eq(state.storm_strikes.size(), 2, "锁定训练家和我方宝可梦")
	t.check(state.storm_strikes.all(func(s): return int(s["due_round"]) == 9), "锁定在下一轮末才生效")
	var training_hp := state.trainer().hp
	state.begin_enemy_phase()
	t.eq(state.trainer().hp, training_hp, "我方阶段结束不提前落雷")
	state.end_enemy_phase()
	t.eq(state.unit_by_uid(1).hp, hp - ceili(state.unit_by_uid(1).max_hp * 0.5), "第9轮末扣最大生命一半")
	t.check(not state.ended and state.round == 10, "一次命中后仍继续第10轮")
	t.check(state.storm_strikes.all(func(s): return int(s["due_round"]) == 10), "旧波次结束后预告新一轮")
	var damage_hp := state.unit_by_uid(1).hp
	state.round = 9
	state.settle_round()
	t.eq(state.unit_by_uid(1).hp, damage_hp, "同轮重复结算不会重复落雷")

func _fixed_cells(t: TestContext) -> void:
	var state := _state()
	var actor := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	var old := actor.cell
	state.round = 8
	state.end_enemy_phase()
	t.check(state.move_unit(actor, Vector2i(2, 2)), "玩家有完整行动机会离开旧标记")
	enemy.cell = old
	var hp := actor.hp
	var ehp := enemy.hp
	state.begin_enemy_phase()
	state.end_enemy_phase()
	t.eq(actor.hp, hp, "落雷不追踪已离开旧格的玩家")
	t.eq(enemy.hp, ehp - ceili(enemy.max_hp * 0.5), "敌人走进旧落点会被误伤")
	t.check(state.storm_strikes.any(func(s): return s["cell"] == actor.cell), "新波次才锁定玩家新位置")
	t.check(not state.storm_strikes.any(func(s): return s["cell"] == old), "旧落点不因为站了敌人而继续锁定")
	t.check(EnemyAI._pending_hazard(state, actor.cell, "player") >= 200, "敌人也将当前预告视为危险格")

func _damage(t: TestContext) -> void:
	var state := _state()
	var target := state.unit_by_uid(100)
	target.max_hp = 31
	target.hp = 31
	target.battle_buffs["direct_guard"] = true
	state.round = 9
	state.storm_strikes = [{"cell": target.cell, "due_round": 9}, {"cell": state.nest["cell"], "due_round": 9}]
	state._settle_storm()
	t.eq(target.hp, 15, "奇数最大生命向上取整，直接伤害减免不改变环境伤害")
	t.eq(state.nest["hp"], Balance.NEST_DURABILITY, "空巢穴不受单位落雷伤害")
	var frozen := _state()
	var shielded := frozen.unit_by_uid(1)
	shielded.frozen = true
	var shield_hp := shielded.hp
	frozen.round = 9
	frozen.storm_strikes = [{"cell": shielded.cell, "due_round": 9}]
	frozen._settle_storm()
	t.eq(shielded.hp, shield_hp - ceili(shielded.max_hp * 0.5), "冰冻承受天雷伤害后解除")
	t.check(not shielded.frozen, "冰冻抵挡后解除")
	var fatal := _state()
	fatal.trainer().hp = 17
	fatal.round = 9
	fatal.storm_strikes = [{"cell": fatal.trainer().cell, "due_round": 9}]
	fatal._settle_storm()
	t.eq(fatal.end_reason, "forced_retreat", "训练家被击倒仍正常失败")
	t.check(fatal.storm_strikes.is_empty(), "失败后清空预告")
	var boss_state := _state()
	boss_state.node_kind = "boss"
	boss_state.boss_uid = 100
	var boss := boss_state.unit_by_uid(100)
	boss.is_boss = true
	boss.sheltered = true
	boss_state.boss_retreat_used = true
	boss_state.round = 9
	boss_state.storm_strikes = [{"cell": boss.cell, "due_round": 9}]
	var bhp := boss.hp
	boss_state._settle_storm()
	t.eq(boss.hp, bhp, "巢内首领庇护不被落雷绕过")
	t.check(not boss_state.ended, "首领战不因经过第8轮自动失败")

func _save_and_free(t: TestContext) -> void:
	var state := _state()
	state.round = 8
	state.end_enemy_phase()
	var clone := state.clone()
	t.eq(clone.storm_strikes, state.storm_strikes, "预览克隆保留落点与轮次")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.storm_strikes, state.storm_strikes, "保存恢复预告")
	t.eq(restored.storm_last_round, 8, "恢复已结算轮次，避免重复预告")
	var unit := restored.unit_by_uid(1)
	var hp := unit.hp
	restored.end_enemy_phase()
	t.eq(unit.hp, hp - ceili(unit.max_hp * 0.5), "读档后只结算一次正确伤害")
	var snapshot := BattleSnapshot.save_state(state)
	snapshot["fields"].erase("storm_strikes")
	snapshot["fields"].erase("storm_last_round")
	var legacy := BattleSnapshot.load_state(snapshot)
	t.check(legacy.storm_strikes.is_empty(), "旧快照没有预告字段也能读取")
	var exploration := _state()
	exploration.node_kind = "event"
	exploration.round = 20
	exploration.storm_strikes = [{"cell": exploration.trainer().cell, "due_round": 20}]
	exploration.check_battle_end()
	exploration.settle_round()
	t.check(exploration.storm_strikes.is_empty(), "自由探索清除并停止天雷")

func _channels(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var actor := state.unit_by_uid(1)
	actor.cell = Vector2i(1, 3)
	state.round = 8
	var result := state.cast_skill(actor, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(result.get("ok", false), "第8轮可正常开始吟唱")
	var hp := state.unit_by_uid(100).hp
	state.begin_enemy_phase()
	state.end_enemy_phase()
	t.check(state.unit_by_uid(100).hp < hp, "第9轮开始实际释放第8轮宣告的技能")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state()
	app._switch(screen)
	var state: BattleState = screen.state
	state.round = 8
	state.end_enemy_phase()
	screen.playback.finish_all()
	screen.refresh_all()
	t.eq(screen.board.storm_strikes, state.storm_strikes, "棋盘独立显示天雷预告")
	t.check(not screen.round_label.text.contains("/8"), "回合标签不再显示八回合上限")
	t.check(screen.objective_label.text.contains("50%"), "目标提示固定百分比伤害")
	screen._fit_terrain_panel()
	t.check(screen.terrain_panel.position.y >= screen.objective_panel.position.y + screen.objective_panel.size.y, "新增天雷说明不与地格面板重叠")
	screen._show_terrain(state.unit_by_uid(1).cell)
	t.check(screen.terrain_label.text.contains("第 9 轮"), "地格提示准确落雷轮次")
	state.end_enemy_phase()
	var hp := state.unit_by_uid(1).hp
	screen.playback.finish_all()
	t.eq(state.unit_by_uid(1).hp, hp, "播放落雷不会重复执行伤害")
	app.free()
