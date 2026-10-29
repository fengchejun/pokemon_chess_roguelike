extends RefCounted

## 风力引擎双目标、手动点选与蓄力后的额外施法。

func run(t: TestContext) -> void:
	t.begin("风力引擎双目标与蓄力行动锁定")
	_two_targets(t)
	_ui_selection(t)
	_channel_recast(t)
	_pregranted_channel(t)
	_enemy_late_support(t)
	t.finish()


func _two_targets(t: TestContext) -> void:
	var state := TestScenario.make_state(["wind_starter", "fire_starter", "grass_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	state.unit_by_uid(2).cell = Vector2i(3, 3)
	state.unit_by_uid(3).cell = Vector2i(2, 2)
	state.trainer().cell = Vector2i(1, 3)
	var normal := state.skill_targets(caster, "double_cast")
	t.check(normal.has({"type": "unit", "unit": 2, "cell": Vector2i(3, 3)}), "未强化时选择一名相邻友军")
	caster.upgrades["double_cast_range"] = 1
	var pairs := state.skill_targets(caster, "double_cast")
	t.eq(pairs.size(), 3, "三名相邻友军生成三种双目标组合")
	var chosen := {"type": "unit_pair", "units": [2, 3], "cell": Vector2i(2, 2)}
	t.check(pairs.has(chosen), "可手动指定其中任意两名友军")
	var preview := state.preview_skill(caster, "double_cast", chosen)
	t.check(bool(preview.get("ok", false)) and state.unit_by_uid(2).extra_casts == 0, "双目标预览不消耗或授予真实行动")
	t.check(bool(state.cast_skill(caster, "double_cast", chosen).get("ok", false)), "强化风力引擎成功施放")
	t.eq(state.unit_by_uid(2).extra_casts, 1, "第一名指定友军获得一次额外施法")
	t.eq(state.unit_by_uid(3).extra_casts, 1, "第二名指定友军获得一次额外施法")
	t.eq(state.trainer().extra_casts, 0, "未选中的相邻友军不受效果")
	var single := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var single_caster := single.unit_by_uid(1)
	single_caster.cell = Vector2i(2, 3)
	single.unit_by_uid(2).cell = Vector2i(3, 3)
	single_caster.upgrades["double_cast_range"] = 1
	t.check(single.skill_targets(single_caster, "double_cast").has({"type": "unit", "unit": 2, "cell": Vector2i(3, 3)}), "只有一名邻近友军时仍可使用技能")


func _ui_selection(t: TestContext) -> void:
	var state := TestScenario.make_state(["wind_starter", "fire_starter", "grass_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	caster.upgrades["double_cast_range"] = 1
	state.unit_by_uid(2).cell = Vector2i(3, 3)
	state.unit_by_uid(3).cell = Vector2i(2, 2)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	screen.board = BoardView.new()
	screen.hint_label = Label.new()
	screen.skill_box = VBoxContainer.new()
	screen.add_child(screen.board)
	screen.add_child(screen.hint_label)
	screen.add_child(screen.skill_box)
	screen.selected_uid = caster.uid
	screen.aim_skill = "double_cast"
	screen.aim_entries = state.skill_targets(caster, "double_cast")
	screen._try_cast_at(state.unit_by_uid(3).cell)
	t.eq(screen.aim_first_uid, 3, "界面第一点击只记录第一名友军")
	t.eq(state.unit_by_uid(3).extra_casts, 0, "第一点击尚不施放技能")
	t.eq(screen.board.attack_cells, [state.unit_by_uid(2).cell], "第二点击只高亮可配对的友军")
	screen._on_board_hovered(state.unit_by_uid(2).cell)
	t.check(screen.board.area_cells.has(state.unit_by_uid(2).cell) and screen.board.area_cells.has(state.unit_by_uid(3).cell), "悬停第二名友军时预览两名受益者")
	var chosen: Dictionary = screen._find_entry(state.unit_by_uid(2).cell)
	t.check(chosen.get("units", []).has(2) and chosen.get("units", []).has(3), "界面按两次点选构造双目标")
	screen._clear_aim()
	t.eq(screen.aim_first_uid, 0, "取消瞄准会清除第一名目标")
	screen.free()


func _channel_recast(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "wind_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	var wind := state.unit_by_uid(2)
	wind.cell = Vector2i(1, 4)
	var first := {"type": "cell", "cell": Vector2i(4, 3)}
	var second := {"type": "cell", "cell": Vector2i(5, 3)}
	t.check(bool(state.cast_skill(fire, "fire_burst", first).get("ok", false)), "先宣告一项蓄力技能")
	t.check(not fire.can_act_skill() and fire.channel_lock_round == state.round + 1, "蓄力宣告消耗当前行动并标记下回合锁定")
	t.check(bool(state.cast_skill(wind, "double_cast", {"type": "unit", "unit": fire.uid, "cell": fire.cell}).get("ok", false)), "风力引擎可施加给已宣告蓄力的友军")
	t.check(fire.can_act_skill() and fire.extra_casts == 1, "额外机会使蓄力者本回合可再次施法")
	t.check(bool(state.cast_skill(fire, "fire_burst", second).get("ok", false)), "蓄力者本回合可以再次宣告技能")
	t.eq(state.pending_casts.size(), 2, "两项蓄力均保留到下一本方阶段")
	state.start_round()
	t.check(fire.channel_lock_round == state.round and fire.moved and fire.skill_used, "下一回合蓄力代价仍锁定行动")
	state.set_terrain(fire.cell, TerrainDB.WATER)
	fire.surf_until_round = state.round
	t.check(not state.can_move_unit_now(fire) and state.move_options(fire).is_empty(), "结算轮即使有水域免费移动也不能行动")
	t.check(not state.skill_targets(wind, "double_cast").has({"type": "unit", "unit": fire.uid, "cell": fire.cell}), "结算轮风力引擎不能解除蓄力锁定")
	fire.extra_casts = 1
	t.check(not bool(state.cast_skill(fire, "fire_burst", first).get("ok", false)), "即使额外次数存在也不能在蓄力结算轮施法")
	state.start_round()
	t.check(fire.channel_lock_round < state.round and fire.can_act_skill(), "再下一回合恢复正常施法")


func _pregranted_channel(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "wind_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var fire := state.unit_by_uid(1)
	fire.cell = Vector2i(1, 3)
	var wind := state.unit_by_uid(2)
	wind.cell = Vector2i(1, 4)
	state.cast_skill(wind, "double_cast", {"type": "unit", "unit": fire.uid, "cell": fire.cell})
	t.eq(fire.extra_casts, 1, "先施加风力引擎会保留一次额外机会")
	state.cast_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)})
	t.check(fire.extra_casts == 1 and fire.can_act_skill(), "首次蓄力不会吞掉预先获得的额外机会")
	state.cast_skill(fire, "fire_burst", {"type": "cell", "cell": Vector2i(5, 3)})
	t.check(fire.extra_casts == 0 and state.pending_casts.size() == 2, "第二次蓄力恰好消耗一次额外机会")


func _enemy_late_support(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["fire_wild1", Vector2i(4, 3)], ["wind_wild1", Vector2i(5, 3)]])
	state.trainer().cell = Vector2i(2, 3)
	var fire := state.unit_by_uid(100)
	var wind := state.unit_by_uid(101)
	wind.skills.append("double_cast")
	state.begin_channel(fire, "fire_burst", [state.trainer().cell])
	fire.moved = true
	wind.moved = true
	var plan := EnemyAI.plan(state)
	var wind_boosted := false
	var fire_recast := false
	for action in plan:
		var skill: Dictionary = action.get("skill", {})
		if int(action.get("uid", -1)) == wind.uid and String(skill.get("id", "")) == "double_cast":
			wind_boosted = true
		if int(action.get("uid", -1)) == fire.uid and not skill.is_empty():
			fire_recast = true
	t.check(wind_boosted and fire_recast, "敌方后行动的风力引擎可让先前蓄力者本阶段再次施法")
