extends RefCounted

func run(t: TestContext) -> void:
	t.begin("技能定位、传导衰减与新经验曲线")
	_water(t)
	_fire(t)
	_arc(t)
	_rain(t)
	_upgrades(t)
	_xp(t)
	_migration(t)
	_ui(t)
	t.finish()

func _state(skill: String, pairs: Array, terrain: Array = []) -> BattleState:
	var state := TestScenario.make_state(["water_starter"], pairs, terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills = [skill]
	for target in state.alive_units("enemy"):
		target.element = ""
		target.max_hp = 200
		target.hp = 200
	return state

func _water(t: TestContext) -> void:
	for upgraded in [false, true]:
		var state := _state("water_flow", [["rock_wild1", Vector2i(3, 3)]])
		var caster := state.unit_by_uid(1)
		if upgraded:
			caster.upgrades = {"water_flow_push": 0}
		var entry := {"type": "cell", "cell": Vector2i(3, 3)}
		var preview := state.preview_skill(caster, "water_flow", entry)
		t.eq(preview["hits"][0]["damage"], 16 if upgraded else 12, "水炮基础与强化伤害")
		var result := state.cast_skill(caster, "water_flow", entry)
		t.eq(result["hits"], preview["hits"], "水炮预览与实战一致")
		t.eq(state.unit_by_uid(100).cell, Vector2i(4, 3), "强化不增加水炮击退")
		t.eq(state.unit_by_uid(100).slow_ticks, 1, "水炮附加一层浸湿")
	var pushed := _state("water_flow", [["rock_wild1", Vector2i(3, 3)]])
	pushed.set_terrain(Vector2i(4, 3), TerrainDB.PIT)
	pushed.cast_skill(pushed.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(3, 3)})
	t.check(not pushed.unit_by_uid(100).is_alive(), "水炮保留推入致死格的作用")
	var blank := _state("water_flow", [["rock_wild1", Vector2i(6, 6)]])
	blank.cast_skill(blank.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(3, 3)})
	t.eq(blank.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "水炮保留空格造水")
	var wall := _state("water_flow", [["rock_wild1", Vector2i(6, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 3), TerrainDB.OBSTACLE]]))
	wall.cast_skill(wall.unit_by_uid(1), "water_flow", {"type": "cell", "cell": Vector2i(3, 3)})
	t.eq(wall.obstacle_durability[Vector2i(3, 3)], 1, "水炮保留破障")
	t.eq(wall.terrain_at(Vector2i(2, 3)), TerrainDB.WATER, "命中障碍在前格造水")

func _fire(t: TestContext) -> void:
	for upgraded in [false, true]:
		var state := _state("fire_burst", [["rock_wild1", Vector2i(4, 3)], ["rock_wild1", Vector2i(4, 4)]])
		var caster := state.unit_by_uid(1)
		if upgraded:
			caster.upgrades["fireball_damage"] = 5
		state.set_terrain(Vector2i(2, 3), TerrainDB.OBSTACLE)
		t.check(state.skill_targets(caster, "fire_burst").has({"type": "cell", "cell": Vector2i(4, 3)}), "火球保留越障选点")
		state.nest["cell"] = Vector2i(5, 3)
		var result := SkillResolver.resolve_channel(state, caster, "fire_burst", [Vector2i(4, 3)])
		t.eq(200 - state.unit_by_uid(100).hp, 20 if upgraded else 15, "火球中心伤害")
		t.eq(200 - state.unit_by_uid(101).hp, 8, "火球外围伤害不随强化提高")
		t.eq(state.nest["hp"], 22, "火球外围伤巢8生命且只结算一次")
		t.eq(result["area_cells"].size(), 9, "火球仍为九宫格")
	var covered := _state("fire_burst", [["rock_wild1", Vector2i(4, 3)]])
	covered.nest["cell"] = Vector2i(4, 3)
	covered.relocate_nest_occupants()
	covered.unit_by_uid(100).hp = 1
	SkillResolver.resolve_channel(covered, covered.unit_by_uid(1), "fire_burst", [Vector2i(4, 3)])
	t.eq(covered.nest["hp"], 15, "敌人位于巢穴邻格时火球中心仍伤巢15生命")
	var ai := _state("fire_burst", [["fire_wild1", Vector2i(4, 3)]])
	ai.unit_by_uid(100).skills = ["fire_burst"]
	ai.unit_by_uid(1).hp = 100
	ai.unit_by_uid(1).max_hp = 100
	var center_score := EnemyAI._channel_score(ai, ai.unit_by_uid(100), "fire_burst", {"cell": Vector2i(1, 3)})
	var edge_score := EnemyAI._channel_score(ai, ai.unit_by_uid(100), "fire_burst", {"cell": Vector2i(1, 2)})
	t.check(center_score > edge_score, "AI按实际中心与外围伤害区别火球落点")

func _arc(t: TestContext) -> void:
	# A bent path makes Manhattan distance wrong: the endpoint is near the seed,
	# but the only connected water route has length ten.
	var path := [Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]
	for upgraded in [false, true]:
		var cells := TestScenario.plain_terrain()
		var pairs: Array = []
		for cell in path:
			cells[GridSpec.index(cell)] = TerrainDB.WATER
			pairs.append(["rock_wild1", cell])
		cells[GridSpec.index(path[3])] = TerrainDB.DEEP
		pairs.append(["rock_wild1", Vector2i(4, 4)])
		var state := _state("electric_arc", pairs, cells)
		var caster := state.unit_by_uid(1)
		if upgraded:
			caster.upgrades["electric_arc_damage"] = 3
		state.unit_by_uid(111).slow_ticks = 2
		var entry := {"type": "cell", "cell": path[0]}
		var preview := state.preview_skill(caster, "electric_arc", entry)
		t.eq(preview["hits"].size(), 12, "所有水格及相邻浸湿目标均可传导")
		for hit in preview["hits"]:
			var index := int(hit["uid"]) - 100
			var distance := index if index < 11 else 11
			var expected := maxi(4, (13 if upgraded else 10) - 2 * (distance / 2))
			t.eq(hit["conduction_distance"], distance, "传导使用最短水路而非曼哈顿距离")
			t.eq(hit["damage"], expected, "每两格衰减两伤且最低四伤")
		var result := state.cast_skill(caster, "electric_arc", entry)
		t.eq(result["hits"], preview["hits"], "传导预览与实战逐目标一致")
	var dry := _state("electric_arc", [["rock_wild1", Vector2i(3, 3)]])
	dry.unit_by_uid(1).upgrades["electric_arc_damage"] = 3
	var result := dry.cast_skill(dry.unit_by_uid(1), "electric_arc", {"type": "cell", "cell": Vector2i(3, 3)})
	t.eq(result["hits"][0]["damage"], 13, "旱地单体强化只追加三伤")
	# Two equal water paths must hit once, including friendly units.
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.WATER], [Vector2i(2, 2), TerrainDB.WATER], [Vector2i(3, 3), TerrainDB.WATER], [Vector2i(3, 2), TerrainDB.WATER]])
	var loop := _state("electric_arc", [["water_wild1", Vector2i(3, 2)]], terrain)
	loop.unit_by_uid(100).element = "water"
	loop.unit_by_uid(100).slow_ticks = 2
	loop.trainer().cell = Vector2i(2, 2)
	result = loop.cast_skill(loop.unit_by_uid(1), "electric_arc", {"type": "cell", "cell": Vector2i(2, 3)})
	t.eq(result["hits"].size(), 2, "多路径去重且友伤保留")
	for hit in result["hits"]:
		if hit["uid"] == 100:
			t.eq(hit["damage"], Elements.direct_damage(8, "electric", "water"), "传导伤害只按技能与属性结算")

func _rain(t: TestContext) -> void:
	var state := _state("rain_call", [["rock_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.upgrades["rain_radius_bonus"] = 1
	var center := Vector2i(3, 3)
	var expected := SkillResolver.rain_cells(caster, center)
	t.eq(expected.size(), 13, "强化造雨恰好十三格")
	t.check(expected.has(Vector2i(5, 3)) and not expected.has(Vector2i(5, 4)), "菱形扩张保留九格并仅延长四向")
	t.eq(SkillResolver.rain_cells(caster, Vector2i.ZERO).size(), 6, "角落菱形范围正确裁剪")
	state.set_terrain(Vector2i(3, 2), TerrainDB.OBSTACLE)
	state.set_terrain(Vector2i(3, 4), TerrainDB.DEEP)
	state.set_terrain(Vector2i(4, 3), TerrainDB.PIT)
	var entry := {"type": "cell", "cell": center}
	var preview := state.preview_skill(caster, "rain_call", entry)
	var result := state.cast_skill(caster, "rain_call", entry)
	t.eq(result["area_cells"], expected, "释放范围使用统一几何")
	t.eq(result["terrain_changes"], preview["terrain_changes"], "造雨预览与地形修改一致")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.OBSTACLE, "造雨跳过障碍")
	t.eq(state.terrain_at(Vector2i(3, 4)), TerrainDB.DEEP, "造雨跳过深水")
	t.eq(state.terrain_at(Vector2i(4, 3)), TerrainDB.PIT, "造雨跳过深坑")
	caster.upgrades.clear()
	t.eq(SkillResolver.rain_cells(caster, center).size(), 9, "基础造雨保持九格")

func _upgrades(t: TestContext) -> void:
	for info in [["rock_push", 3], ["rock_create", 3], ["flame_jet", 3], ["drain", 3], ["flame_charge", 5], ["rock_break", 3], ["ice_shard", 5], ["tsunami", 5], ["rock_slide", 5], ["lightning", 5], ["earth_shake", 5]]:
		var skill := String(info[0])
		var caster := CombatUnit.make("fire_starter", "player", 1)
		var upgrade := RunState.upgrade_info(RunState.upgrade_id_for_skill(skill))
		caster.upgrades[String(upgrade["key"])] = upgrade["value"]
		t.eq(SkillResolver.upgraded_base_damage(caster, skill, 10), 10 + int(info[1]), "强化表增伤符合确定数值：" + skill)
	var ice := _state("ice_shard", [["rock_wild1", Vector2i(3, 3)]])
	ice.unit_by_uid(1).upgrades["ice_shard_damage"] = 5
	var result := ice.cast_skill(ice.unit_by_uid(1), "ice_shard", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)})
	t.eq(result["hits"][0]["damage"], 16, "冰锥强化不双算")

func _xp(t: TestContext) -> void:
	var thresholds := [0, 6, 16, 30, 48, 70, 96, 126, 160, 198]
	for level in range(1, 11):
		t.eq(MonsterProgression.threshold_for_level(level), thresholds[level - 1], "完整经验阈值表")
		if level > 1:
			t.eq(MonsterProgression.level_for_xp(thresholds[level - 1] - 1), level - 1, "升级阈值前一点击验不提前升级")
	for level in [1, 3, 5]:
		var state := _state("water_flow", [["rock_wild1", Vector2i(3, 3)], ["rock_wild1", Vector2i(6, 6)]])
		for enemy in state.alive_units("enemy"):
			enemy.enemy_level = level
		state.kill_unit(state.unit_by_uid(100), "测试", "player", 1)
		state.kill_unit(state.unit_by_uid(100), "重复测试", "player", 1)
		state.on_captured(state.unit_by_uid(101), "rock_wild1", 5)
		state.on_captured(state.unit_by_uid(101), "rock_wild1", 5)
		t.eq(state.enemy_kills.size(), 1, "击杀事件只记录一次")
		t.eq(state.captured.size(), 1, "捕获事件只记录一次")
		t.eq(state.enemy_kills[0]["xp_reward"], MonsterProgression.enemy_xp_reward(level), "击杀奖励随敌方等级变化")
		t.eq(state.captured[0]["enemy_level"], level, "捕获在重置敌方等级前记录")
		t.eq(state.battle_exp(), MonsterProgression.enemy_xp_reward(level) + 2, "经验统计读取事件值")
		var run := RunState.new_run(56)
		run.region_mode = true
		run.mark_deployed([1])
		state.node_kind = "battle"
		state.end_battle("escape")
		t.eq(run.battle_kill_xp_for(state, 1), MonsterProgression.enemy_xp_reward(level), "即时经验与事件奖励一致")
		run.settle_battle(state)
		t.eq(run.record_by_uid(1)["xp"], MonsterProgression.enemy_xp_reward(level) + 3, "战后击杀与捕获经验均正确")
		run.settle_battle(state)
		t.eq(run.record_by_uid(1)["xp"], MonsterProgression.enemy_xp_reward(level) + 3, "重复结算不重复发奖")
	var legacy := {"by_player": true}
	t.eq(Balance.xp_for_event(legacy), 2, "旧事件缺少经验字段按两点处理")
	var record := {"species_id": "fire_starter"}
	var cumulative := 0
	for floor_index in 3:
		var gain := 30 * Balance.xp_for_enemy_level(1 + 2 * floor_index) + 15
		cumulative += gain
		MonsterProgression.award_xp(record, gain)
		t.eq(cumulative, [75, 180, 315][floor_index], "三层经验预算样本")
		t.eq(record["level"], [6, 9, 10][floor_index], "三层主力等级预算")

func _migration(t: TestContext) -> void:
	var run := RunState.new_run(56)
	var fire := run.record_by_uid(1)
	fire["level"] = 3
	fire["xp"] = 14 # Halfway from legacy level 3 (10) to 4 (18).
	fire["hp"] = 17
	fire["known_skills"] = ["fire_burst"]
	fire["equipped_skills"] = ["fire_burst"]
	fire["upgrades_taken"] = ["fireball_damage"]
	fire["claimed_even_levels"] = [2]
	var stored: Dictionary = run.carried.pop_back()
	stored["level"] = 10
	stored["xp"] = 108
	run.storage.append(stored)
	var pending := run._make_record("water_wild1")
	pending["level"] = 5
	pending["xp"] = 28
	run.pending_captures.append(pending)
	var state := _state("electric_arc", [["rock_wild1", Vector2i(3, 3)]])
	state.unit_by_uid(1).upgrades = {"electric_arc_damage": 5, "water_flow_push": 1}
	state.unit_by_uid(100).upgrades = {"electric_arc_damage": 5}
	state.round = 4
	state.enemy_kills = [{"by_player": true}]
	var snapshot := BattleSnapshot.save_state(state)
	snapshot["version"] = 2
	run.battle_snapshot = snapshot
	run.region_data = {"nodes": {"battle_1": {"snapshot": snapshot}}}
	run.pending_region_entry_backup = run.region_data.duplicate(true)
	var data := run.to_dict()
	data["version"] = 11
	data.erase("progression_schema")
	var restored := RunState.from_dict(data)
	t.eq(restored.record_by_uid(1)["level"], 3, "旧档等级不倒退")
	t.eq(restored.record_by_uid(1)["xp"], 23, "旧档同等级升级进度比例换算")
	t.eq(restored.record_by_uid(1)["hp"], 19, "新血量曲线按旧生命比例迁移")
	t.eq(restored.record_by_uid(1)["claimed_even_levels"], [2], "已领取成长不重复发放")
	t.eq(restored.storage[0]["xp"], 198, "仓库满级经验转换为四百")
	t.eq(restored.pending_captures[0]["xp"], 48, "待收容成员也迁移经验")
	for entry in [restored.battle_snapshot, restored.region_data["nodes"]["battle_1"]["snapshot"], restored.pending_region_entry_backup["nodes"]["battle_1"]["snapshot"]]:
		var battle := BattleSnapshot.load_state(entry)
		t.eq(battle.unit_by_uid(1).upgrades["electric_arc_damage"], 3, "当前与节点快照强化数值同步")
		t.eq(battle.unit_by_uid(1).upgrades["water_flow_push"], 0, "旧水炮强化不再加击退")
		t.eq(battle.unit_by_uid(100).upgrades["electric_arc_damage"], 3, "敌人快照强化同步")
		t.eq(battle.round, 4, "迁移保留战斗进度")
		t.eq(Balance.xp_for_event(battle.enemy_kills[0]), 2, "旧未结算战斗事件奖励保持两点")
	var again := RunState.from_dict(restored.to_dict())
	t.eq(again.record_by_uid(1)["xp"], 23, "迁移后重读不重复换算")

func _ui(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(56)
	app.run.region_mode = true
	app.run.mark_deployed([1])
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = _state("electric_arc", [["rock_wild1", Vector2i(2, 3)], ["rock_wild1", Vector2i(3, 3)], ["rock_wild1", Vector2i(4, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.WATER], [Vector2i(3, 3), TerrainDB.WATER], [Vector2i(4, 3), TerrainDB.WATER]]))
	app._switch(screen)
	screen.battle_notice.finish_all()
	screen.state.unit_by_uid(1).upgrades["electric_arc_damage"] = 3
	t.check(screen._skill_tag("electric_arc", screen.state.unit_by_uid(1)).contains("伤害 13"), "技能面板放电强化伤害准确")
	screen.state.unit_by_uid(1).upgrades["fireball_damage"] = 5
	t.check(screen._skill_tag("fire_burst", screen.state.unit_by_uid(1)).contains("中心 20 · 外围 8"), "技能面板区分火球中心与外围")
	var feedbacks: Array = []
	screen.state.feedback.connect(func(event):
		if event["kind"] == "experience":
			feedbacks.append(event["value"]))
	screen.state.unit_by_uid(100).enemy_level = 3
	screen.state.unit_by_uid(102).enemy_level = 5
	screen.state.kill_unit(screen.state.unit_by_uid(100), "测试经验", "player", 1)
	screen.state.on_captured(screen.state.unit_by_uid(102), "rock_wild1", 5)
	t.eq(feedbacks, [1, 3, 2, 2], "训练家与原出战者都显示对应经验")
	screen.playback.finish_all()
	screen._refresh_after_action()
	var label: Label = screen.find_child("BattleXPText_1", true, false)
	t.check(label != null and label.text.contains("本场 +5"), "经验条包含击败与捕获奖励")
	app.queue_free()
