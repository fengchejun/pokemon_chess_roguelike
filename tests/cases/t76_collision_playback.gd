extends RefCounted

func run(t: TestContext) -> void:
	t.begin("独立碰撞反馈、接触回弹与结算隔离")
	_recording(t)
	_edges_and_rocks(t)
	_pair(t)
	_playback(t)
	t.finish()

func _state() -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(2, 3)], ["grass_wild1", Vector2i(6, 5)]])
	state.node_kind = "battle"
	state.nest["alive"] = false
	state.unit_by_uid(1).cell = Vector2i(1, 3)
	state.unit_by_uid(1).skills = ["rock_push"]
	state.unit_by_uid(100).hp = 100
	state.unit_by_uid(100).max_hp = 100
	state.set_terrain(Vector2i(3, 3), TerrainDB.OBSTACLE)
	state.obstacle_durability[Vector2i(3, 3)] = 2
	return state

func _recording(t: TestContext) -> void:
	var state := _state()
	var events: Array = []
	state.enable_feedback()
	state.feedback.connect(func(e): events.append(e.duplicate(true)))
	var copy := state.clone()
	var entry := {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}
	SkillResolver.apply(state, state.unit_by_uid(1), "rock_push", entry, false)
	SkillResolver.apply(copy, copy.unit_by_uid(1), "rock_push", entry, false)
	t.eq(BattleSnapshot.save_state(state), BattleSnapshot.save_state(copy), "记录碰撞特效不改变规则快照")
	var impacts := events.filter(func(e): return e["kind"] == "collision")
	var damage := events.filter(func(e): return e["kind"] == "collision_damage")
	t.eq(impacts.size(), 1, "一次撞墙生成一个独立接触事件")
	t.eq(damage.size(), 1, "碰撞伤害单独记录")
	if not impacts.is_empty():
		t.eq(impacts[0]["cell"], Vector2i(2, 3), "记录撞击者位置")
		t.eq(impacts[0]["blocker_cell"], Vector2i(3, 3), "记录受阻位置")
	if not damage.is_empty():
		t.check(damage[0]["text"].contains("碰撞"), "碰撞伤害飘字区别普通伤害")
	t.eq(state.obstacle_durability[Vector2i(3, 3)], 2, "撞墙动画不改变障碍耐久规则")
	var frozen := _state()
	var seen: Array = []
	frozen.enable_feedback()
	frozen.feedback.connect(func(e): seen.append(e.duplicate(true)))
	frozen.unit_by_uid(100).frozen = true
	PushResolver.push(frozen, frozen.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "冰冻碰撞", "player", 1)
	t.eq(frozen.unit_by_uid(100).hp, 95, "冰冻碰撞正常受伤")
	t.check(seen.any(func(e): return e["kind"] == "collision_damage" and e["text"] == "碰撞 -5"), "冰冻解除仍明确提示碰撞")

func _edges_and_rocks(t: TestContext) -> void:
	var state := _state()
	var seen: Array = []
	state.enable_feedback()
	state.feedback.connect(func(e): seen.append(e.duplicate(true)))
	state.unit_by_uid(100).cell = Vector2i(7, 3)
	PushResolver.push(state, state.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "边界", "player", 1)
	t.eq(state.unit_by_uid(100).hp, 100, "地图边界仍只受阻不新增伤害")
	t.check(seen.any(func(e): return e["kind"] == "collision" and e["object_kind"] == "edge"), "边界受阻独立反馈")
	state.unit_by_uid(100).cell = Vector2i(4, 3)
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	seen.clear()
	PushResolver.push_obstacle(state, state.unit_by_uid(1), Vector2i(3, 3))
	t.check(seen.any(func(e): return e["kind"] == "collision" and e["object_kind"] == "rock"), "推岩撞人也使用碰撞提示")
	t.eq(state.unit_by_uid(100).hp, 95, "推岩撞人仍造成5点碰撞伤害")

func _pair(t: TestContext) -> void:
	var state := _state()
	state.set_terrain(Vector2i(3, 3), TerrainDB.PLAIN)
	state.obstacle_durability.erase(Vector2i(3, 3))
	state.unit_by_uid(101).cell = Vector2i(3, 3)
	state.unit_by_uid(101).hp = 1
	var events: Array = []
	state.enable_feedback()
	state.feedback.connect(func(e): events.append(e.duplicate(true)))
	PushResolver.push(state, state.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "双方碰撞", "player", 1)
	t.eq(state.unit_by_uid(100).hp, 95, "单位相撞仍对撞击者造成5伤")
	t.check(not state.unit_by_uid(101).is_alive(), "单位碰撞击杀仍正常结算")
	t.eq(events.filter(func(e): return e["kind"] == "collision_damage").size(), 2, "单位相撞双方各显示碰撞伤害")
	t.eq(events.filter(func(e): return e["kind"] == "collision")[0]["blocker_uid"], 101, "保留受撞者身份以播放震动")

func _playback(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(7601)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state()
	app._switch(screen)
	screen.playback.finish_all()
	SkillResolver.apply(screen.state, screen.state.unit_by_uid(1), "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}, false)
	var signature: String = screen.state._signature()
	screen.playback.advance(0.51)
	var direct: Array = screen.playback.steps.filter(func(s): return s["event"]["kind"] == "damage")
	var collision: Array = screen.playback.steps.filter(func(s): return s["event"]["kind"] == "collision_damage")
	t.check(collision[0]["time"] > direct[0]["time"] + 0.20, "碰撞与首次命中之间留出位移时间")
	t.eq(screen.playback.collision_cues.size(), 1, "碰撞使用独立演出记录")
	var cue: Dictionary = screen.playback.collision_cues[0]
	screen.playback.advance(float(cue["time"]) + 0.12 - screen.playback.elapsed)
	t.check(screen.board.presentation_offsets.get(100, Vector2.ZERO).length() > 1, "接触后有可见受阻回弹位移")
	t.check(screen.feedback_layer.entries.any(func(e): return e["label"].text.contains("碰撞")), "碰撞时显示专用飘字")
	t.eq(screen.state._signature(), signature, "回弹不改变真实位置生命或动作")
	screen._open_menu()
	var elapsed: float = screen.playback.elapsed
	screen.playback._process(0.2)
	t.approx(screen.playback.elapsed, elapsed, "菜单暂停碰撞动画")
	screen._close_modal()
	screen._toggle_speed()
	screen.playback._process(0.02)
	t.approx(screen.playback.elapsed, elapsed + 0.04, "倍速同步碰撞动画")
	screen.playback.finish_all()
	t.check(screen.board.presentation_offsets.is_empty(), "播放结束清理展示偏移")
	t.eq(screen.state._signature(), signature, "完整播放不重复结算碰撞")
	screen.state.unit_by_uid(100).hp = 100
	screen.state.unit_by_uid(100).cell = Vector2i(2, 3)
	screen.state.set_terrain(Vector2i(3, 3), TerrainDB.PLAIN)
	screen.state.obstacle_durability.erase(Vector2i(3, 3))
	screen.state.set_terrain(Vector2i(4, 3), TerrainDB.OBSTACLE)
	screen.state.obstacle_durability[Vector2i(4, 3)] = 2
	screen.state.unit_by_uid(1).upgrades["push_distance"] = 2
	SkillResolver.apply(screen.state, screen.state.unit_by_uid(1), "rock_push", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)}, false)
	screen.playback.advance(0.63)
	var cue_move: Dictionary = screen.playback.collision_cues[0]["event"]
	t.eq(cue_move["start_cell"], Vector2i(2, 3), "移动后碰撞保留出发格")
	t.eq(cue_move["cell"], Vector2i(3, 3), "移动后碰撞保留接触前落格")
	t.check(screen.board.presentation_offsets.get(100, Vector2.ZERO).length() > 1, "碰撞前播放实际推移过程")
	screen.playback.finish_all()
	t.eq(screen.state.unit_by_uid(100).cell, Vector2i(3, 3), "碰撞回弹不改变已推进一格的实际结果")
	app.free()
