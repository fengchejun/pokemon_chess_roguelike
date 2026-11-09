extends RefCounted

func run(t: TestContext) -> void:
	t.begin("巢穴分层生命、半额分伤与旧档迁移")
	_growth(t)
	_sharing(t)
	_modifiers(t)
	_merged_status_sharing(t)
	_migration(t)
	_ui(t)
	t.finish()

func _state(index: int = 0) -> BattleState:
	var run := RunState.new_run(7301)
	var state := BattleState.new()
	state.node_kind = "battle"
	var map := TestScenario.make_map(TestScenario.plain_terrain(), Vector2i(4, 3))
	map["nest_cells"] = [Vector2i(4, 3), Vector2i(6, 3)]
	state.setup(map, {"enemies": [["rock_wild1", Vector2i(4, 2)], ["rock_wild1", Vector2i(4, 4)]]}, 7301, index, run.build_deploy_units([1]), {}, {}, [])
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	state.unit_by_uid(1).skills = ["rock_break"]
	for guard in state.alive_units("enemy"):
		guard.hp = 100
		guard.max_hp = 100
	return state

func _attack(state: BattleState) -> Dictionary:
	return SkillResolver.apply(state, state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": state.nest["cell"]}, false)

func _guard(state: BattleState) -> void:
	for unit in state.alive_units("enemy"):
		state.begin_nest_guard(unit, state.nest["cell"])

func _growth(t: TestContext) -> void:
	for pair in [[0, 30], [5, 30], [6, 50], [11, 50], [12, 70], [17, 70]]:
		var state := _state(pair[0])
		for nest in state.all_nests():
			t.eq(nest["hp"], pair[1], "主副巢穴按层获得30/50/70生命")
			t.eq(nest["max_hp"], pair[1], "上限与初始生命一致")
	var raw := _state()
	raw.damage_nest(7, "player")
	t.eq(raw.nest["hp"], 23, "直接伤害按数值扣血")
	var high := _state()
	var rockfall := SkillResolver.resolve_channel(high, high.unit_by_uid(1), "rock_slide", [high.nest["cell"]])
	t.eq(high.nest["hp"], 10, "无守护时20点岩崩对第一层巢穴造成全额伤害")
	t.check(high.nest["alive"], "单次岩崩不再直接摧毁第一层巢穴")
	t.eq(rockfall["nests_damaged"].size(), 1, "巢穴只命中一次")
	SkillResolver.resolve_channel(high, high.unit_by_uid(1), "rock_slide", [high.nest["cell"]])
	t.check(not high.nest["alive"], "第二次岩崩完成毁巢")
	t.eq(high.all_rewards().filter(func(p): return p.get("id", "").begins_with("nest:")).size(), 1, "毁巢奖励点只掉落一次")

func _sharing(t: TestContext) -> void:
	var state := _state()
	state.debug_skill_damage_bonus["player"] = 10
	_guard(state)
	var target := {"type": "nest", "cell": state.nest["cell"]}
	var preview := state.preview_skill(state.unit_by_uid(1), "rock_break", target)
	t.eq(state.nest["hp"], 30, "预览不改变巢穴")
	t.eq(preview["nest_damaged"]["damage"], 10, "20伤预览巢穴承担10点")
	var result := _attack(state)
	t.eq(state.nest["hp"], 20, "20伤由巢穴承担10点")
	t.eq([state.unit_by_uid(100).hp, state.unit_by_uid(101).hp], [95, 95], "两守军各承担5点")
	t.eq(result["hits"], preview["hits"], "预览和真实分伤相同")
	_attack(state)
	t.eq(state.nest["hp"], 10, "连续攻击也始终推进拆巢")
	t.eq(state.nest_guard_charges(state.nest["cell"]), 2, "守护不会因连续受击消耗")
	var odd := _state()
	odd.debug_skill_damage_bonus["player"] = 1
	_guard(odd)
	_attack(odd)
	t.eq(odd.nest["hp"], 24, "11伤时巢穴承担6点")
	t.eq([odd.unit_by_uid(100).hp, odd.unit_by_uid(101).hp], [97, 98], "余下5点按3/2分配，不增加总伤害")
	var pushed := _state()
	_guard(pushed)
	PushResolver.push(pushed, pushed.unit_by_uid(100), Vector2i.UP, 1, 0, "推离守军", "player", 1)
	PushResolver.push(pushed, pushed.unit_by_uid(100), Vector2i.DOWN, 1, 0, "推回原格", "player", 1)
	t.eq(pushed.nest_guard_charges(pushed.nest["cell"]), 1, "离开再回到四邻不会自动恢复守护")
	t.check(not pushed.unit_by_uid(100).can_act_skill(), "被推离也不退还守护所用技能动作")
	pushed.begin_enemy_phase()
	t.eq(pushed.nest_guard_charges(pushed.nest["cell"]), 0, "下次敌方阶段开始清除旧守护")
	var inactive := _state()
	_attack(inactive)
	t.eq(inactive.nest["hp"], 20, "周围敌人没有主动守护就不分伤")
	t.eq(inactive.unit_by_uid(100).hp, 100, "普通相邻敌人不免费承担伤害")

func _modifiers(t: TestContext) -> void:
	var upgraded := _state()
	var info := RunState.upgrade_info(RunState.upgrade_id_for_skill("rock_break"))
	upgraded.unit_by_uid(1).upgrades[info["key"]] = info["value"]
	_attack(upgraded)
	t.eq(upgraded.nest["hp"], 20 - int(info.get("damage_bonus", 0)), "技能强化提高拆巢伤害")
	var amp := _state()
	amp.unit_by_uid(1).fire_amp_stacks = 5
	_attack(amp)
	t.eq(amp.nest["hp"], 15, "蓄积增幅用于拆巢")
	t.eq(amp.unit_by_uid(1).fire_amp_stacks, 0, "仅命中巢穴也消耗增幅")
	var control := _state()
	_guard(control)
	control.unit_by_uid(100).frozen = true
	control.unit_by_uid(101).paralyzed_ticks = 1
	_attack(control)
	t.eq(control.nest["hp"], 20, "冰冻麻痹守军不能分伤")
	var collision := _state()
	var before := int(collision.nest["hp"])
	collision.unit_by_uid(100).cell = Vector2i(3, 3)
	PushResolver.push(collision, collision.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "撞巢", "player", 1)
	t.eq(collision.nest["hp"], before, "单位碰撞仍不损伤巢穴")

func _migration(t: TestContext) -> void:
	var state := _state(12)
	var data := BattleSnapshot.save_state(state)
	data["version"] = 4
	var nest: Dictionary = BattleSnapshot.decode(data["fields"]["nest"])
	nest.erase("max_hp")
	nest["hp"] = 2
	data["fields"]["nest"] = BattleSnapshot.encode(nest)
	var extras: Array = BattleSnapshot.decode(data["fields"]["extra_nests"])
	for extra in extras:
		extra.erase("max_hp")
		extra["hp"] = 1
	data["fields"]["extra_nests"] = BattleSnapshot.encode(extras)
	var restored := BattleSnapshot.load_state(data)
	t.eq(restored.nest["hp"], 47, "第三层旧剩余2/3耐久迁移为47/70生命")
	t.eq(restored.nest["max_hp"], 70, "旧巢穴迁移上限按层计算")
	t.eq(restored.extra_nests[0]["hp"], 23, "旧副巢穴也按层和剩余比例迁移")
	var destroyed := data.duplicate(true)
	nest["hp"] = 0
	nest["alive"] = false
	destroyed["fields"]["nest"] = BattleSnapshot.encode(nest)
	var dead := BattleSnapshot.load_state(destroyed)
	t.check(dead.nest["hp"] == 0 and not dead.nest["alive"], "旧已毁巢穴不会因迁移复活")
	var twice := BattleSnapshot.load_state(BattleSnapshot.save_state(restored))
	t.eq(twice.nest["hp"], 47, "重复读档不再次放大生命")
	_guard(twice)
	var cloned := twice.clone()
	_attack(cloned)
	t.eq(twice.nest["hp"], 47, "AI模拟不改变真实生命")
	t.eq(cloned.nest["hp"], 42, "克隆保持分伤行为")
	var run := RunState.new_run(7302)
	run.in_battle = true
	run.battle_snapshot = data
	var old := run.to_dict()
	old["version"] = 13
	var path := "user://test_t73_legacy.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := SaveSystem.load_run(path)
	t.check(loaded != null, "实际v13存档入口可读")
	if loaded != null:
		t.eq(BattleSnapshot.load_state(loaded.battle_snapshot).nest["hp"], 47, "实际文件读档也迁移巢穴生命")
	SaveSystem.delete_save(path)

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(7303)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state(6)
	_guard(screen.state)
	app._switch(screen)
	screen.playback.finish_all()
	screen.refresh_all()
	screen._show_terrain(screen.state.nest["cell"])
	t.check(screen.terrain_label.text.contains("巢穴生命：50/50"), "界面显示生命而非三点耐久")
	t.check(screen.objective_label.text.contains("2 名分担伤害"), "界面显示守军人数而非拦截次数")
	t.eq(screen.board.nest["max_hp"], 50, "棋盘保留巢穴生命上限")
	app.free()

func _merged_status_sharing(t: TestContext) -> void:
	var state := _state()
	state.debug_skill_damage_bonus["player"] = 1
	var shielded := state.unit_by_uid(100)
	var mirrored := state.unit_by_uid(101)
	mirrored.cell = Vector2i(5, 3)
	state.apply_guard_rock_shield(shielded, 10, shielded.uid)
	mirrored.mirror_until_round = state.round + 2
	_guard(state)
	var preview := state.preview_skill(state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": state.nest["cell"]})
	var actual := _attack(state)
	t.eq(actual["hits"], preview["hits"], "分伤与护盾、镜影组合的预览实战一致")
	t.eq(state.nest["hp"], 24, "护盾和镜影不免除巢穴自身的一半伤害")
	t.eq(shielded.shield_hp, 7, "三点分摊先扣守军护盾")
	t.eq(mirrored.hp, 100, "守军镜影免疫其两点分摊")
	shielded.mountain_form_ticks = 2
	_attack(state)
	t.eq(state.nest["hp"], 18, "山岳转移也不免除巢穴自身伤害")
	t.eq(shielded.shield_hp, 4, "下一次先结算守军自身分摊护盾")
	t.eq(shielded.hp, 98, "另一守军的两点分摊按山岳减免后转移")
	t.eq(mirrored.hp, 100, "镜影消耗后改由山岳形态转移伤害")
