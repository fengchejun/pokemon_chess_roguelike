extends RefCounted

## 跨回合吟唱、锁定落点与中断。

func run(t: TestContext) -> void:
	t.begin("火球术与打雷跨回合吟唱")
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
	t.eq(ally.hp, ally_hp - 9, "留在外围的友军受到九点火球误伤")
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
	var invalid := state.cast_skill(caster, "lightning", {"type": "cell", "cell": enemy.cell})
	t.check(not bool(invalid.get("ok", false)) and not caster.skill_used, "打雷不能手动指定敌人落点")
	var result := state.cast_skill(caster, "lightning", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "自身格宣告打雷")
	t.eq(state.pending_casts[0]["cells"], [Vector2i(4, 1), Vector2i(7, 6), state.nest["cell"]], "锁定敌方原位置与空置巢穴")
	t.eq(enemy.hp, enemy.max_hp, "闪电宣告时尚不伤害")
	enemy.cell = Vector2i(6, 3)
	ally.cell = Vector2i(4, 1)
	state.start_round()
	t.eq(enemy.hp, enemy.max_hp, "敌方离开固定落点后躲开打雷")
	t.eq(ally.hp, ally.max_hp - SkillDB.damage_of("lightning"), "友军走入固定落点受到误伤")
	t.eq(state.unit_by_uid(101).hp, state.unit_by_uid(101).max_hp - Elements.direct_damage(SkillDB.damage_of("lightning"), "electric", "water"), "全场远处水系敌人受到克制打雷伤害")
	t.eq(state.pending_casts.size(), 0, "闪电三格结算后清空警示")
	var repeat := state.cast_skill(caster, "lightning", {"type": "cell", "cell": caster.cell})
	t.check(not bool(repeat.get("ok", false)), "结算阶段不可再次行动")
	state.start_round()
	repeat = state.cast_skill(caster, "lightning", {"type": "cell", "cell": caster.cell})
	t.check(bool(repeat.get("ok", false)), "不再受每场一次限制")


func _interruptions(t: TestContext) -> void:
	var frozen := TestScenario.make_state(["fire_starter"], [["ice_wild1", Vector2i(4, 3)]])
	var fire := frozen.unit_by_uid(1)
	frozen.trainer().cell = Vector2i(7, 0)
	fire.cell = Vector2i(0, 3)
	frozen.cast_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	SkillResolver.apply(frozen, frozen.unit_by_uid(100), "freeze_ray", {"type": "cell", "cell": fire.cell}, false)
	t.check(fire.frozen, "急冻光线实际施加冻结")
	t.eq(frozen.pending_casts.size(), 0, "冻结立即取消吟唱")
	frozen.start_round()
	t.check(fire.moved and fire.skill_used, "中断后下一阶段仍失去行动")
	var paralyzed := TestScenario.make_state(["fire_starter"], [["electric_wild1", Vector2i(4, 3)]])
	var shocked := paralyzed.unit_by_uid(1)
	paralyzed.trainer().cell = Vector2i(7, 0)
	shocked.cell = Vector2i(0, 3)
	shocked.shock_ticks = 2
	paralyzed.cast_skill(shocked, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
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
	t.eq(steam.unit_by_uid(100).hp, target_hp - SkillDB.damage_of("fire_burst"), "吟唱后进入蒸汽不打断落火球")


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
	t.eq(player.hp, hp - Elements.direct_damage(Balance.skill_damage_for_side(SkillDB.damage_of("fire_burst"), "enemy"), "fire", "water"), "下一敌方阶段开始结算逆克制火球")
	t.check(enemy.moved and enemy.skill_used, "敌方结算阶段失去行动")


func _multiple_and_ai(t: TestContext) -> void:
	var together := TestScenario.make_state(["fire_starter", "fire_starter"], [["rock_wild1", Vector2i(5, 3)], ["water_wild1", Vector2i(7, 6)]])
	var first := together.unit_by_uid(1)
	var second := together.unit_by_uid(2)
	first.cell = Vector2i(0, 3)
	second.cell = Vector2i(5, 0)
	t.check(bool(together.cast_skill(first, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}).get("ok", false)), "第一名火怪宣告吟唱")
	t.check(together.skill_targets(second, "fire_burst").is_empty(), "第二名火怪没有吟唱目标")
	t.check(not bool(together.cast_skill(second, "fire_burst", {"type": "cell", "cell": Vector2i(5, 3)}).get("ok", false)), "第二名火怪本回合不能吟唱")
	t.check(not second.skill_used and together.pending_casts.size() == 1, "拒绝后不消耗施法机会或新增待发技能")
	var preview := together.preview_skill(second, "fire_burst", {"type": "cell", "cell": Vector2i(5, 3)})
	t.check(not bool(preview.get("ok", false)), "克隆预览同样遵守吟唱名额")
	together.cancel_channel(first, "测试中断")
	t.check(not together.can_begin_channel(second), "首名吟唱者中断后本回合名额仍被占用")
	t.check(together.can_begin_channel(first), "首名吟唱者仍是本回合唯一可吟唱的单位")
	together.start_round()
	t.check(together.can_begin_channel(second), "下一回合重置本方吟唱名额")
	t.check(bool(together.cast_skill(second, "fire_burst", {"type": "cell", "cell": Vector2i(5, 3)}).get("ok", false)), "下一回合另一名火怪可以吟唱")
	var independent := TestScenario.make_state(["fire_starter"], [["fire_wild1", Vector2i(6, 3)]])
	var player_caster := independent.unit_by_uid(1)
	var enemy_caster := independent.unit_by_uid(100)
	player_caster.cell = Vector2i(2, 3)
	t.check(bool(independent.cast_skill(player_caster, "fire_burst", {"type": "cell", "cell": enemy_caster.cell}).get("ok", false)), "我方占用自己的吟唱名额")
	t.check(independent.can_begin_channel(enemy_caster), "敌方吟唱名额与我方独立")
	t.check(bool(independent.cast_skill(enemy_caster, "fire_burst", {"type": "cell", "cell": player_caster.cell}).get("ok", false)), "敌方仍可在同一回合宣告吟唱")
	var ai := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 3)]])
	ai.trainer().cell = Vector2i(0, 6)
	ai.unit_by_uid(1).cell = Vector2i(2, 3)
	var enemy := ai.unit_by_uid(100)
	enemy.moved = true
	var actions := EnemyAI.plan(ai)
	var channels := actions.filter(func(action: Dictionary) -> bool:
		return String(action.get("skill", {}).get("id", "")) == "fire_burst")
	t.check(not channels.is_empty(), "远程敌人在无即时攻击时可选择吟唱")
	var ai_two := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 3)], ["fire_wild1", Vector2i(5, 3)]])
	ai_two.trainer().cell = Vector2i(0, 6)
	ai_two.unit_by_uid(1).cell = Vector2i(2, 3)
	ai_two.unit_by_uid(100).moved = true
	ai_two.unit_by_uid(101).moved = true
	var two_actions := EnemyAI.plan(ai_two)
	var channel_casters: Dictionary = {}
	for action in two_actions:
		if bool(SkillDB.get_def(String(action.get("skill", {}).get("id", ""))).get("channel", false)):
			channel_casters[int(action.get("uid", -1))] = true
	t.eq(channel_casters.size(), 1, "两名火系敌人在可选吟唱时只规划一名吟唱者")
	ai.round = Balance.MAX_ROUNDS
	actions = EnemyAI.plan(ai)
	channels = actions.filter(func(action: Dictionary) -> bool:
		return String(action.get("skill", {}).get("id", "")) == "fire_burst")
	t.check(not channels.is_empty(), "第8回合敌方仍可开始后续会生效的吟唱")


func _last_round(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	state.round = Balance.MAX_ROUNDS
	var hp := state.unit_by_uid(100).hp
	var result := state.cast_skill(caster, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(bool(result.get("ok", false)) and not String(result.get("text", "")).contains("不会生效"), "第8回合吟唱不再提示无效")
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
	t.check(screen.state.pending_casts.is_empty() and not caster.skill_used, "进入打雷瞄准时尚未提交行动")
	screen._clear_aim()
	t.check(screen.aim_cells.is_empty() and not caster.skill_used, "取消打雷瞄准不消耗行动")
	screen._on_skill_pressed("lightning")
	screen._try_cast_at(caster.cell)
	t.eq(screen.state.pending_casts.size(), 1, "界面点击施法者格后开始吟唱")
	t.eq(screen.state.pending_casts[0]["cells"], [Vector2i(7, 6), screen.state.nest["cell"]], "界面宣告锁定远处敌方格和空置巢穴")
	t.check(caster.skill_used and caster.moved, "界面成功施放后锁定行动")
	var second_screen = load("res://scripts/ui/battle_screen.gd").new()
	second_screen.state = TestScenario.make_state(["fire_starter", "fire_starter"], [["rock_wild1", Vector2i(5, 3)]])
	app._switch(second_screen)
	var first: CombatUnit = second_screen.state.unit_by_uid(1)
	var second: CombatUnit = second_screen.state.unit_by_uid(2)
	first.cell = Vector2i(0, 3)
	second.cell = Vector2i(5, 0)
	second_screen.state.cast_skill(first, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	second_screen.playback.finish_all()
	second_screen.select_unit(second.uid)
	second_screen._on_choose_skill_pressed()
	var blocked_button: Button = second_screen.skill_box.find_child("SkillButton_fire_burst", true, false)
	t.check(blocked_button != null and blocked_button.disabled and blocked_button.text.contains("本方本回合已有吟唱者"), "第二名吟唱者的界面按钮明确提示名额已占用")
	app.queue_free()
