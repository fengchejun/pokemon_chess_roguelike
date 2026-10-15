extends RefCounted

## 缩短射程、施法提交移动、巢穴出生轮待机及致死格占位碰撞。


func run(t: TestContext) -> void:
	t.begin("施法移动、巢穴接敌与致死格碰撞")
	_test_skill_movement(t)
	_test_channel_full_round(t)
	_test_spawn_wait(t)
	_test_occupied_lethal_collision(t)
	t.finish()


func _test_skill_movement(t: TestContext) -> void:
	var invalid := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var invalid_fire := invalid.unit_by_uid(1)
	invalid_fire.cell = Vector2i(1, 3)
	var rejected := invalid.cast_skill(invalid_fire, "fire_burst", {"type": "cell", "cell": Vector2i(6, 3)})
	t.check(not bool(rejected.get("ok", false)) and invalid_fire.can_move_now(), "第五格火球无效且保留移动机会")
	t.check(invalid.move_unit(invalid_fire, Vector2i(2, 3)), "无效施法后仍可移动")
	t.check(bool(invalid.cast_skill(invalid_fire, "fire_burst", {"type": "cell", "cell": Vector2i(6, 3)}).get("ok", false)), "前进后原目标进入第四格火球范围")
	var fire := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var caster := fire.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("fire_seed")
	t.check(fire.move_unit(caster, Vector2i(2, 3)), "可以先移动再施法")
	t.check(bool(fire.cast_skill(caster, "fire_seed", {"type": "cell", "cell": Vector2i(4, 3)}).get("ok", false)), "移动后即时技能可施放")
	t.check(caster.moved and not fire.can_undo(), "成功施法用完移动并提交已有移动")
	var before := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var first_caster := before.unit_by_uid(1)
	first_caster.cell = Vector2i(1, 3)
	first_caster.skills.append("fire_seed")
	t.check(bool(before.cast_skill(first_caster, "fire_seed", {"type": "cell", "cell": Vector2i(3, 3)}).get("ok", false)), "未移动也可直接施法")
	t.check(not first_caster.can_move_now() and not before.move_unit(first_caster, Vector2i(2, 3)), "先施法后不能普通移动")
	var heal := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var healer := heal.unit_by_uid(1)
	t.check(bool(heal.cast_skill(healer, "herbal_heal", {"type": "cell", "cell": healer.cell}).get("ok", false)), "治疗技能成功施放")
	t.check(not healer.can_move_now(), "治疗技能也耗尽普通移动机会")
	var charge := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var charger := charge.unit_by_uid(1)
	charger.cell = Vector2i(1, 3)
	t.check(bool(charge.cast_skill(charger, "flame_charge", {"type": "cell", "cell": Vector2i(3, 3)}).get("ok", false)), "带位移的技能可正常施放")
	t.eq(charger.cell, Vector2i(3, 3), "技能自身位移仍生效")
	t.check(not charger.can_move_now(), "技能位移后不能再次普通移动")
	var extra := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var boosted := extra.unit_by_uid(1)
	boosted.cell = Vector2i(1, 3)
	boosted.skills.append("fire_seed")
	boosted.extra_casts = 1
	extra.cast_skill(boosted, "fire_seed", {"type": "cell", "cell": Vector2i(3, 3)})
	t.check(bool(extra.cast_skill(boosted, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)}).get("ok", false)), "额外施法机会仍允许第二个技能")
	t.check(not boosted.can_move_now(), "额外施法不恢复普通移动")


func _test_channel_full_round(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	t.check(bool(state.cast_skill(caster, "fire_burst", {"type": "cell", "cell": Vector2i(4, 3)}).get("ok", false)), "第 1 回合宣告火球")
	state.begin_enemy_phase()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
	state.end_enemy_phase()
	t.eq(state.round, 2, "完整敌方阶段后进入第 2 回合")
	t.check(caster.channel_lock_round == 2 and caster.moved and caster.skill_used, "火球落下阶段仍锁定行动")
	t.check(not state.move_unit(caster, Vector2i(2, 3)), "火球落下后不能普通移动")


func _test_spawn_wait(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["rock_wild1"])
	var exit_cell: Vector2i = state.nest["exits"][0]
	state.start_round()
	var spawn: CombatUnit = state.units.back()
	t.check(spawn.fresh_spawn and not spawn.moved and spawn.cell == exit_cell, "第 2 回合增援出生后在出口待机")
	var plan := EnemyAI.plan(state)
	t.check(not _contains_uid(plan, spawn.uid), "出生轮敌方队列不移动或施法")
	state.begin_enemy_phase()
	while not state.enemy_phase_finished() and not state.ended:
		state.step_enemy_phase()
	state.end_enemy_phase()
	t.check(not spawn.fresh_spawn and not spawn.moved and spawn.can_move_now(), "下一完整回合增援恢复移动资格")
	state.start_round()
	t.eq(state.round, 4, "进入第 4 回合")
	t.eq(state.alive_enemy_count(), 2, "第 2 回合增援占住出口时第 4 回合产怪排队")
	t.eq(int(state.nest["pending_waves"]), 1, "被堵住的第 4 回合产怪仍在队列中")
	spawn.cell = Vector2i(5, 7)
	state.start_round()
	t.eq(state.alive_enemy_count(), 3, "出口腾出后下一回合补产一只")
	t.check(state.units.back().fresh_spawn and not state.units.back().moved and state.units.back().cell == exit_cell, "补产增援同样在出口待机")
	var blocked := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], [], {}, {}, ["rock_wild1"])
	var blocker := CombatUnit.make("water_starter", "player", 50)
	blocker.cell = blocked.nest["exits"][0]
	blocked.units.append(blocker)
	blocked.start_round()
	t.eq(int(blocked.nest["pending_waves"]), 1, "出口被占时保留待产队列")
	blocker.cell = Vector2i(0, 0)
	blocked.start_round()
	t.eq(int(blocked.nest["pending_waves"]), 0, "次轮解除堵口后立即补产")
	t.check(blocked.units.back().fresh_spawn and not blocked.units.back().moved, "补产增援出生轮不可移动")
	var trapped_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(5, 7), TerrainDB.OBSTACLE], [Vector2i(6, 6), TerrainDB.OBSTACLE],
	])
	var trapped := TestScenario.make_state([], [["fire_wild1", Vector2i(5, 4)]], trapped_terrain, {}, {}, ["rock_wild1"])
	trapped.start_round()
	t.eq(trapped.units.back().cell, trapped.nest["exits"][0], "增援不检查接敌路径，出生轮留在出口")
	t.check(trapped.units.back().fresh_spawn and not trapped.units.back().moved, "周围有无合法路径都不能在出生轮移动")
	var warned := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(5, 4)]], [], {}, {}, ["rock_wild1"])
	var fire := warned.unit_by_uid(1)
	fire.cell = Vector2i(4, 7)
	var warned_exit: Vector2i = warned.nest["exits"][0]
	t.check(bool(warned.cast_skill(fire, "fire_burst", {"type": "cell", "cell": warned_exit}).get("ok", false)), "在出口锁定合法火球落点")
	warned.start_round()
	var escaped: CombatUnit = warned.units.back()
	t.eq(escaped.cell, warned_exit, "增援不会躲避已警示的出口落点")
	t.check(escaped.hp < escaped.max_hp, "出生轮待机时会受到已警示的火球打击")


func _test_occupied_lethal_collision(t: TestContext) -> void:
	var deep_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.DEEP]])
	var deep := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(4, 3)]], deep_terrain)
	var pushed := deep.unit_by_uid(1)
	pushed.cell = Vector2i(3, 3)
	var holder := deep.unit_by_uid(100)
	var pushed_hp := pushed.hp
	var holder_hp := holder.hp
	var result := PushResolver.push(deep, pushed, Vector2i.RIGHT, 1, 0, "测试")
	t.eq(pushed.cell, Vector2i(3, 3), "深水由水系占据时，被推者停在原格")
	t.check(not result["death"] and result["collisions"][0]["kind"] == "unit", "深水占位先判单位碰撞")
	t.eq(pushed.hp, pushed_hp - Balance.COLLISION_DAMAGE, "被推者承受碰撞伤害")
	t.eq(holder.hp, holder_hp - Balance.COLLISION_DAMAGE, "深水占位者承受被撞伤害")
	var preview_state := TestScenario.make_state(["rock_starter"], [
		["rock_wild1", Vector2i(3, 3)], ["water_wild1", Vector2i(4, 3)],
	], deep_terrain)
	var rock_caster := preview_state.unit_by_uid(1)
	rock_caster.cell = Vector2i(2, 3)
	var entry := {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)}
	var preview := preview_state.preview_skill(rock_caster, "rock_push", entry)
	t.check(bool(preview.get("ok", false)) and preview_state.unit_by_uid(100).cell == Vector2i(3, 3), "推击预览不改变真实棋盘")
	var actual := preview_state.cast_skill(rock_caster, "rock_push", entry)
	t.eq(preview["hits"][0]["push"]["collisions"], actual["hits"][0]["push"]["collisions"], "预览与实际均为深水占位碰撞")
	t.eq(preview_state.unit_by_uid(100).cell, Vector2i(3, 3), "实际技能不会将被推者压入占位深水")
	var pit_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.PIT]])
	var pit := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]], pit_terrain)
	var flyer := pit.unit_by_uid(1)
	flyer.cell = Vector2i(4, 3)
	flyer.battle_buffs["flight"] = true
	var enemy := pit.unit_by_uid(100)
	result = PushResolver.push(pit, enemy, Vector2i.RIGHT, 1, 0, "测试")
	t.eq(enemy.cell, Vector2i(3, 3), "飞行单位站在深坑时阻止地面单位坠落")
	t.eq(result["collisions"][0]["kind"], "unit", "深坑占位优先判碰撞")
	var empty := TestScenario.make_state([], [["rock_wild1", Vector2i(3, 3)]], pit_terrain)
	result = PushResolver.push(empty, empty.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player")
	t.check(bool(result["death"]) and empty.unit_by_uid(100).hp == 0, "空深坑仍立即致死")
	var empty_deep := TestScenario.make_state([], [["rock_wild1", Vector2i(3, 3)]], deep_terrain)
	result = PushResolver.push(empty_deep, empty_deep.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player")
	t.check(bool(result["death"]), "空深水仍使非水系单位溺水")
	var chain := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(4, 3)]], deep_terrain)
	var mover := chain.unit_by_uid(1)
	mover.cell = Vector2i(2, 3)
	var blocker := chain.unit_by_uid(100)
	blocker.hp = 1
	result = PushResolver.push(chain, mover, Vector2i.RIGHT, 3, 0, "测试")
	t.eq(mover.cell, Vector2i(3, 3), "多格推击在第二格碰撞后停住")
	t.eq(blocker.hp, 0, "占位者即使因碰撞倒下也不被穿过")
	t.eq(result["to"], Vector2i(3, 3), "多格推击结果停在碰撞前一格")


func _contains_uid(actions: Array, uid: int) -> bool:
	for action in actions:
		if int(action.get("uid", -1)) == uid:
			return true
	return false
