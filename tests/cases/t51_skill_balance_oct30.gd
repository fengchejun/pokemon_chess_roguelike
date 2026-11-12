extends RefCounted

func run(t: TestContext) -> void:
	t.begin("技能射程、固定治疗、磁场与首轮粮食")
	_ranges(t)
	_healing(t)
	_magnetic(t)
	_food(t)
	_migration(t)
	t.finish()

func _ranges(t: TestContext) -> void:
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	for distance in range(1, 5):
		var dest := caster.cell + Vector2i(distance, 0)
		state.unit_by_uid(100).cell = dest
		var entry := {"type": "unit", "unit": 100, "cell": dest}
		t.eq(SkillResolver.targets(state, caster, "volt_replace").has(entry), distance <= 3, "单位换位距离 %d" % distance)
		state.unit_by_uid(100).cell = Vector2i(7, 7)
		t.eq(SkillResolver.targets(state, caster, "volt_replace").has({"type": "cell", "cell": dest}), distance <= 3, "空格换位距离 %d" % distance)
	t.eq(SkillDB.get_def("freeze_ray")["max_range"], 6, "急冻基础六格")
	t.eq(SkillDB.damage_of("freeze_ray"), 6, "急冻光线基础六伤")
	var freeze_upgrade := RunState.upgrade_info("freeze_ray_range")
	t.eq(String(freeze_upgrade.get("key", "")), "freeze_ray_damage", "急冻旧强化ID迁移为伤害键")
	t.eq(int(freeze_upgrade.get("damage_bonus", 0)), 4, "急冻强化增伤四点")
	t.eq(SkillDB.get_def("water_flow")["max_range"], 3, "水炮基础三格")
	t.eq(SkillDB.name_of("double_cast"), "电力引擎", "电力引擎保留内部编号")

func _healing(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter", "fire_starter", "water_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	var ally := state.unit_by_uid(2)
	ally.cell = Vector2i(5, 3)
	ally.hp = ally.max_hp - 3
	var outside := state.unit_by_uid(3)
	outside.cell = Vector2i(5, 4)
	outside.hp = 1
	var events: Array = []
	state.feedback_enabled = true
	state.feedback.connect(func(e): events.append(e))
	var entry := {"type": "cell", "cell": caster.cell}
	var preview := state.preview_skill(caster, "herbal_heal", entry)
	t.eq(preview.get("area_cells", []).size(), 13, "治疗预览曼哈顿二格共十三格")
	t.check(events.is_empty(), "治疗预览不产生实战反馈")
	var cast := state.cast_skill(caster, "herbal_heal", entry)
	t.check(bool(cast.get("ok", false)), "治疗可开始吟唱")
	t.eq(ally.hp, ally.max_hp - 3, "宣告时不提前治疗")
	t.eq(state.pending_casts[0]["cells"], [Vector2i(3, 3)], "吟唱锁定原始中心")
	caster.cell = Vector2i(0, 6)
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	restored.start_round()
	t.eq(restored.unit_by_uid(2).hp, ally.max_hp, "读档后下阶段按固定中心恢复实际缺失三血")
	t.eq(restored.unit_by_uid(3).hp, 1, "曼哈顿三格友军不治疗")
	t.check(restored.pending_casts.is_empty(), "治疗结算后不残留吟唱")
	t.check(restored.unit_by_uid(1).moved and restored.unit_by_uid(1).skill_used, "治疗结算阶段施法者锁定")
	var cancelled := state.clone()
	cancelled.cancel_channel(cancelled.unit_by_uid(1), "测试麻痹")
	cancelled.start_round()
	t.eq(cancelled.unit_by_uid(2).hp, ally.max_hp - 3, "中断后不治疗")

func _magnetic(t: TestContext) -> void:
	var state := TestScenario.make_state(["wind_starter", "fire_starter", "water_starter"], [["rock_wild1", Vector2i(5, 4)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	state.unit_by_uid(2).cell = Vector2i(1, 1)
	state.unit_by_uid(3).cell = Vector2i(0, 3)
	var entry := {"type": "cell", "cell": caster.cell}
	var preview := state.preview_skill(caster, "tailwind", entry)
	t.eq(preview.get("area_cells", []).size(), 25, "磁场中心覆盖二十五格")
	t.eq(caster.haste_ticks, 0, "磁场预览不施加真实增益")
	var result := state.cast_skill(caster, "tailwind", entry)
	t.eq(result.get("area_cells", []), preview.get("area_cells", []), "磁场预览和结算一致")
	t.eq(caster.haste_ticks, 2, "自身加速覆盖下一次移动机会")
	t.check(state.unit_by_uid(2).haste_ticks > 0, "对角二格也加速")
	t.eq(state.unit_by_uid(3).haste_ticks, 0, "横向三格不加速")
	t.eq(state.unit_by_uid(100).haste_ticks, 0, "范围内敌人不加速")
	state._finish_movement_effects("player")
	t.eq(caster.haste_ticks, 1, "本阶段结束自身加速仍保留")
	t.eq(SkillResolver.support_area(Vector2i.ZERO, 2, true).size(), 9, "角落磁场裁剪为九格")

func _food(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 7)]])
	state.node_kind = "battle"
	state.nest["alive"] = false
	var picker := state.unit_by_uid(1)
	state.food_cells = [picker.cell]
	state.settle_round()
	t.eq(state.food_collected, 1, "普通战斗第一次回合末即拾取粮食")
	t.check(state.food_cells.is_empty(), "粮食从地图移除")
	state._pickups()
	t.eq(state.food_collected, 1, "后续结算不重复领取")
	var blocked := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 7)]])
	blocked.food_cells = [Vector2i(7, 7)]
	blocked._pickups()
	t.eq(blocked.food_collected, 0, "敌人占据粮食不发给玩家")

func _migration(t: TestContext) -> void:
	var run := RunState.new_run(51030)
	var record: Dictionary = run.carried[0]
	record["species_id"] = "wind_starter"
	record["known_skills"] = ["wind_gust", "tailwind", "double_cast"]
	record["equipped_skills"] = ["wind_gust", "tailwind"]
	record["level"] = 4
	record["upgrades_taken"] = ["wind_gust_distance", "tailwind_reach"]
	record["claimed_even_levels"] = [2, 4]
	run._normalize_record_growth(record, false)
	t.eq(record["known_skills"], ["tailwind", "double_cast"], "旧队伍移除推风保留改名技能")
	t.eq(record["equipped_skills"], ["tailwind"], "配招不残留推风")
	t.eq(record["claimed_even_levels"], [2], "退役强化退还一次选择")
	var state := TestScenario.make_state(["wind_starter"], [])
	state.unit_by_uid(1).skills = ["tailwind", "wind_gust"]
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.unit_by_uid(1).skills, ["tailwind"], "区域快照也移除推风")
	state.unit_by_uid(1).skills = ["wind_gust"]
	restored = BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.unit_by_uid(1).skills, ["tailwind"], "仅有退役技能的旧单位获得有效默认招式")
