extends RefCounted

func run(t: TestContext) -> void:
	t.begin("推击碰撞仅伤单位与普通战斗主动撤退")
	_collisions(t)
	_escape(t)
	_ui(t)
	t.finish()

func _state(terrain: Array = []) -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	state.node_kind = "battle"
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	state.unit_by_uid(100).max_hp = 200
	state.unit_by_uid(100).hp = 200
	return state

func _collisions(t: TestContext) -> void:
	for kind in [TerrainDB.TREE, TerrainDB.OBSTACLE, -1]:
		for skill in ["rock_push", "water_flow", "flame_charge"]:
			var cell := Vector2i(4, 3)
			var terrain := TestScenario.plain_terrain()
			if kind != -1:
				terrain[GridSpec.index(cell)] = kind
			var state := _state(terrain)
			if kind == -1:
				state.nest["cell"] = cell
			var hp := state.unit_by_uid(100).hp
			var before := int(state.nest["hp"]) if kind == -1 else int(state.obstacle_durability[cell])
			var entry := {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}
			if skill != "rock_push":
				entry["type"] = "cell"
			state.unit_by_uid(1).skills = [skill]
			var preview := state.preview_skill(state.unit_by_uid(1), skill, entry)
			var result := SkillResolver.apply(state, state.unit_by_uid(1), skill, entry, false)
			t.check(result.get("ok", false), "%s可击退单位撞物体" % skill)
			t.eq(state.unit_by_uid(100).cell, Vector2i(3, 3), "物体持续阻挡落点")
			t.check(state.unit_by_uid(100).hp < hp, "被推单位仍承受伤害")
			t.eq(int(state.nest["hp"]) if kind == -1 else int(state.obstacle_durability[cell]), before, "单位撞树岩障巢穴不扣物体耐久")
			t.eq(preview["hits"][0]["push"]["collisions"], result["hits"][0]["push"]["collisions"], "预览与实际碰撞一致")
			PushResolver.push(state, state.unit_by_uid(100), Vector2i.RIGHT, 3, 10, "重复碰撞", "player", 1)
			t.eq(int(state.nest["hp"]) if kind == -1 else int(state.obstacle_durability[cell]), before, "重复或强化碰撞也不拆物体")
	var guarded := _state()
	guarded.nest["cell"] = Vector2i(4, 3)
	guarded.begin_nest_guard(guarded.unit_by_uid(100), guarded.nest["cell"])
	var hp := guarded.unit_by_uid(100).hp
	PushResolver.push(guarded, guarded.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1)
	t.eq(guarded.unit_by_uid(100).hp, hp - Balance.COLLISION_DAMAGE, "撞巢穴的单位承受碰撞伤害")
	t.eq(guarded.nest_guard_charges(guarded.nest["cell"]), 1, "撞巢穴不消耗守护次数")
	var bodies := _state()
	var blocker := CombatUnit.make("rock_wild1", "enemy", 101)
	blocker.cell = Vector2i(4, 3)
	bodies.units.append(blocker)
	var blocker_hp := blocker.hp
	PushResolver.push(bodies, bodies.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试")
	t.eq(blocker.hp, blocker_hp - Balance.COLLISION_DAMAGE, "单位相撞仍对双方造成碰撞伤害")

func _escape(t: TestContext) -> void:
	for current_round in [1, 5, 9, 20]:
		var state := _state()
		state.round = current_round
		state.unit_by_uid(1).moved = true
		state.unit_by_uid(1).skill_used = true
		state.storm_strikes = [{"cell": Vector2i(2, 3), "due_round": current_round + 1}]
		t.check(state.can_escape() and not state.can_leave_node(), "清场前任何轮次都可撤退，无需剩余动作")
		t.check(state.leave_node(), "主动撤退入口成功")
		t.eq(state.end_reason, "escape", "未清场撤退不误判胜利")
		t.check(state.storm_strikes.is_empty(), "撤退清理战斗预告")
		t.check(not state.leave_node(), "结束后不能重复撤退结算")
	var enemy_phase := _state()
	enemy_phase.phase = BattleState.PHASE_ENEMY
	t.check(not enemy_phase.leave_node(), "敌方结算期间不能中断撤退")
	for node_kind in ["boss", ""]:
		var boss := _state()
		boss.node_kind = node_kind
		boss.boss_uid = 100
		boss.unit_by_uid(100).is_boss = true
		t.check(not boss.can_escape() and not boss.leave_node(), "区域和旧流程首领战都禁止主动撤退")
		boss.end_battle("escape")
		t.check(not boss.ended, "底层结束入口也不能绕过首领战撤退限制")
	var clear := _state()
	clear.unit_by_uid(100).hp = 0
	clear.stop_nests()
	t.check(clear.leave_node() and clear.end_reason == "victory", "清场后返回区域仍算胜利")
	var event := _state()
	event.node_kind = "event"
	t.check(event.leave_node() and event.end_reason == "explored", "收集区仍按探索离开")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state()
	app._switch(screen)
	screen.playback.finish_all()
	screen.refresh_all()
	t.eq(screen.leave_node_button.text, "撤退", "普通战斗显示撤退按钮")
	t.check(not screen.leave_node_button.disabled, "首轮未清场也可点击撤退")
	screen.state.node_kind = "boss"
	screen.refresh_all()
	t.check(screen.leave_node_button.disabled and screen.leave_node_button.text.contains("不可撤退"), "首领战明确显示禁止撤退")
	screen.do_leave_node()
	t.check(not screen.state.ended, "UI调用不能绕过首领限制")
	screen.state.node_kind = "battle"
	screen.do_leave_node()
	t.eq(screen.state.end_reason, "escape", "UI实际触发撤退结算")
	app.free()
