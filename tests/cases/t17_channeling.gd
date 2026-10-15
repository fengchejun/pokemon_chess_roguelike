extends RefCounted

## 跨回合吟唱、锁定落点与中断。

func run(t: TestContext) -> void:
	t.begin("火球术与闪电跨回合吟唱")
	_player_fireball(t)
	_lightning_cells(t)
	_interruptions(t)
	_enemy_timing(t)
	_multiple_and_ai(t)
	_last_round(t)
	_ui_pick_and_cancel(t)
	t.finish()


func _player_fireball(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "rock_starter"], [["rock_wild1", Vector2i(4, 3)], ["water_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	ally.cell = Vector2i(4, 4)
	var old_hp := enemy.hp
	var ally_hp := ally.hp
	var moved := state.move_unit(caster, Vector2i(1, 3))
	t.check(moved and state.can_undo(), "移动后仍可撤回")
	var result := state.cast_skill(caster, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(bool(result.get("ok", false)), "移动后宣告火球")
	t.eq(enemy.hp, old_hp, "宣告阶段不提前伤害")
	t.eq(state.pending_casts.size(), 1, "落点记录为一项待发技能")
	t.check(not state.can_undo() and not state.move_options(caster).size() > 0, "宣告提交移动并锁定本阶段剩余行动")
	enemy.cell = Vector2i(6, 3)
	state.start_round()
	t.eq(enemy.hp, old_hp, "敌人离开落点后躲避")
	t.eq(ally.hp, ally_hp - 4, "留在九宫格内的友军受到四点误伤")
	t.eq(state.pending_casts.size(), 0, "结算后移除待发技能")
	t.check(caster.moved and caster.skill_used, "结算当阶段施法者不能移动或施法")
	state.start_round()
	t.check(not caster.moved and not caster.skill_used, "再下一轮恢复行动")


func _lightning_cells(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 1)], ["water_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 1)
	var enemy := state.unit_by_uid(100)
	var ally := state.trainer()
	ally.cell = Vector2i(2, 1)
	var invalid := state.cast_skill(caster, "lightning", {"type": "multi", "cells": [Vector2i(4, 1), Vector2i(4, 1), Vector2i(2, 1)]})
	t.check(not bool(invalid.get("ok", false)) and not caster.skill_used, "重复落点无效且不消耗机会")
	invalid = state.cast_skill(caster, "lightning", {"type": "multi", "cells": [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)]})
	t.check(not bool(invalid.get("ok", false)) and not caster.skill_used, "曼哈顿第六格无效且不消耗机会")
	var result := state.cast_skill(caster, "lightning", {"type": "multi", "cells": [Vector2i(4, 1), Vector2i(5, 1), Vector2i(2, 1)]})
	t.check(bool(result.get("ok", false)), "三个合法不同落点开始吟唱")
	var boundary := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(7, 7)]])
	boundary.unit_by_uid(1).cell = Vector2i(3, 3)
	var edges := [Vector2i(0, 1), Vector2i(7, 2), Vector2i(5, 6)]
	t.check(bool(boundary.cast_skill(boundary.unit_by_uid(1), "lightning", {"type": "multi", "cells": edges}).get("ok", false)), "三个落点均处于曼哈顿第五格边界时合法")
	t.eq(enemy.hp, enemy.max_hp, "闪电宣告时尚不伤害")
	caster.cell = Vector2i(7, 7)
	state.start_round()
	t.eq(enemy.hp, enemy.max_hp - 4, "施法者移走后仍按原位置选定的落点命中")
	t.eq(ally.hp, ally.max_hp - 4, "闪电落点会误伤我方")
	t.eq(state.pending_casts.size(), 0, "闪电三格结算后清空警示")
	var repeat := state.cast_skill(caster, "lightning", {"type": "multi", "cells": [Vector2i(4, 1), Vector2i(5, 1), Vector2i(2, 1)]})
	t.check(not bool(repeat.get("ok", false)), "结算阶段不可再次行动")
	state.start_round()
	caster.cell = Vector2i(0, 1)
	repeat = state.cast_skill(caster, "lightning", {"type": "multi", "cells": [Vector2i(4, 1), Vector2i(5, 1), Vector2i(2, 1)]})
	t.check(bool(repeat.get("ok", false)), "不再受每场一次限制")


func _interruptions(t: TestContext) -> void:
	var frozen := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(4, 3)]])
	var fire := frozen.unit_by_uid(1)
	frozen.trainer().cell = Vector2i(7, 0)
	fire.cell = Vector2i(0, 3)
	frozen.cast_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	frozen.add_attachment(fire, "ice")
	frozen.add_attachment(fire, "ice")
	SkillResolver.apply(frozen, frozen.unit_by_uid(100), "freeze_ray", {"type": "cell", "cell": fire.cell}, false)
	t.check(fire.frozen, "第二层冰附着实际施加冻结")
	t.eq(frozen.pending_casts.size(), 0, "第二层冰冻结立即取消吟唱")
	frozen.start_round()
	t.check(fire.moved and fire.skill_used, "中断后下一阶段仍失去行动")
	var paralyzed := TestScenario.make_state(["fire_starter"], [["electric_wild1", Vector2i(4, 3)]])
	var shocked := paralyzed.unit_by_uid(1)
	paralyzed.trainer().cell = Vector2i(7, 0)
	shocked.cell = Vector2i(0, 3)
	paralyzed.cast_skill(shocked, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	shocked.attachments.clear()
	paralyzed.add_attachment(shocked, "electric")
	SkillResolver.resolve_channel(paralyzed, paralyzed.unit_by_uid(100), "lightning", [shocked.cell, Vector2i(0, 2), Vector2i(0, 4)])
	t.check(shocked.paralyzed_ticks > 0 and paralyzed.pending_casts.is_empty(), "二次感电造成麻痹并中断吟唱")
	var captured := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var wild := captured.unit_by_uid(100)
	captured.begin_channel(wild, "fire_burst", [Vector2i(1, 3)])
	captured.on_captured(wild, wild.species_id, wild.hp)
	t.eq(captured.pending_casts.size(), 0, "捕获后的阵营转换取消原吟唱")
	var steam := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var steamer := steam.unit_by_uid(1)
	steamer.cell = Vector2i(0, 3)
	steam.add_steam(steamer.cell)
	var failed := steam.cast_skill(steamer, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(not bool(failed.get("ok", false)) and steam.pending_casts.is_empty(), "雾中不能开始吟唱")
	steam.steam_cells.erase(steamer.cell)
	steam.cast_skill(steamer, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	steam.add_steam(steamer.cell)
	var target_hp := steam.unit_by_uid(100).hp
	steam.start_round()
	t.eq(steam.unit_by_uid(100).hp, target_hp - 4, "吟唱后进入蒸汽不打断落火球")


func _enemy_timing(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["fire_wild1", Vector2i(5, 3)]])
	var enemy := state.unit_by_uid(100)
	var player := state.unit_by_uid(1)
	player.cell = Vector2i(2, 3)
	state.begin_channel(enemy, "fire_burst", [Vector2i(2, 3)])
	var hp := player.hp
	state.begin_enemy_phase()
	t.eq(player.hp, hp, "敌方宣告轮不提前结算")
	state.round = 2
	state.phase = BattleState.PHASE_PLAYER
	state.begin_enemy_phase()
	t.eq(player.hp, hp - 4, "下一敌方阶段开始自动结算")
	t.check(enemy.moved and enemy.skill_used, "敌方结算阶段失去行动")


func _multiple_and_ai(t: TestContext) -> void:
	var together := TestScenario.make_state(["fire_starter", "fire_starter"], [["rock_wild1", Vector2i(5, 3)], ["water_wild1", Vector2i(7, 6)]])
	var first := together.unit_by_uid(1)
	var second := together.unit_by_uid(2)
	first.cell = Vector2i(0, 3)
	second.cell = Vector2i(5, 0)
	t.check(bool(together.cast_skill(first, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}).get("ok", false)), "第一名火怪宣告吟唱")
	t.check(bool(together.cast_skill(second, "fire_burst", {"type": "cell", "cell": Vector2i(5, 3)}).get("ok", false)), "第二名火怪同时吟唱")
	t.eq(together.pending_casts.size(), 2, "可并存两项待发技能")
	together.start_round()
	t.eq(together.unit_by_uid(100).hp, 0, "两项按顺序结算，累计足以击倒目标")
	t.eq(together.pending_casts.size(), 0, "战斗结束停止并清空待发技能")
	var ai := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 3)]])
	ai.trainer().cell = Vector2i(0, 6)
	ai.unit_by_uid(1).cell = Vector2i(2, 3)
	var enemy := ai.unit_by_uid(100)
	enemy.moved = true
	var actions := EnemyAI.plan(ai)
	var channels := actions.filter(func(action: Dictionary) -> bool:
		return String(action.get("skill", {}).get("id", "")) == "fire_burst")
	t.check(not channels.is_empty(), "远程敌人在无即时攻击时可选择吟唱")
	ai.round = Balance.MAX_ROUNDS
	actions = EnemyAI.plan(ai)
	channels = actions.filter(func(action: Dictionary) -> bool:
		return String(action.get("skill", {}).get("id", "")) == "fire_burst")
	t.eq(channels.size(), 0, "敌方末轮不会选择无收益吟唱")


func _last_round(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	state.round = Balance.MAX_ROUNDS
	var hp := state.unit_by_uid(100).hp
	var result := state.cast_skill(caster, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(bool(result.get("ok", false)) and String(result.get("text", "")).contains("不会生效"), "最后一回合可宣告但提示不会结算")
	t.eq(state.unit_by_uid(100).hp, hp, "末轮宣告无即时伤害")
	state.end_battle("escape")
	t.eq(state.pending_casts.size(), 0, "战斗结束清除未结算吟唱")


func _ui_pick_and_cancel(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(42, CollectionState.defaults().select_records([1, 2, 3]))
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(7, 6)]])
	app._switch(screen)
	var caster: CombatUnit = screen.state.unit_by_uid(1)
	caster.cell = Vector2i(1, 1)
	screen.select_unit(caster.uid)
	screen._on_skill_pressed("lightning")
	screen._try_cast_at(Vector2i(3, 1))
	screen._try_cast_at(Vector2i(3, 2))
	t.eq(screen.aim_cells.size(), 2, "界面可连续选取两个闪电落点")
	t.check(screen.state.pending_casts.is_empty() and not caster.skill_used, "选满三个落点之前不提交行动")
	screen._clear_aim()
	t.check(screen.aim_cells.is_empty() and not caster.skill_used, "取消闪电选点不消耗行动")
	screen._on_skill_pressed("lightning")
	for cell in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(4, 1)]:
		screen._try_cast_at(cell)
	t.eq(screen.state.pending_casts.size(), 1, "界面第三个落点确认后开始吟唱")
	t.check(caster.skill_used and caster.moved, "界面成功施放后锁定行动")
	app.queue_free()
