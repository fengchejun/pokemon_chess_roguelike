extends RefCounted

func run(t: TestContext) -> void:
	t.begin("冲锋边缘目标与放电旱地目标")
	for cells in [[Vector2i(6, 3), Vector2i(7, 3)], [Vector2i(1, 3), Vector2i(0, 3)], [Vector2i(3, 6), Vector2i(3, 7)], [Vector2i(3, 1), Vector2i(3, 0)]]:
		var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", cells[1]]])
		state.trainer().cell = Vector2i.ZERO
		var caster := state.unit_by_uid(1)
		caster.cell = cells[0]
		var target := state.unit_by_uid(100)
		target.hp = 999
		var entry := {"type": "cell", "cell": cells[1]}
		t.check(state.skill_targets(caster, "flame_charge").has(entry), "边缘相邻敌人可以选中")
		var before := target.hp
		var preview := state.preview_skill(caster, "flame_charge", entry)
		t.check(preview["ok"] and not preview["hits"].is_empty(), "边缘冲锋预览有实际命中")
		t.eq(target.hp, before, "预览不扣真实血量")
		var result := SkillResolver.apply(state, caster, "flame_charge", entry, false)
		t.check(result["ok"] and target.hp < before, "边缘冲锋执行并造成伤害")
		t.check(GridSpec.is_inside(caster.cell) and GridSpec.is_inside(target.cell), "冲锋与击退不会越界")
	var state := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 3)], ["water_wild1", Vector2i(2, 4)], ["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	state.set_terrain(Vector2i(1, 4), TerrainDB.WATER)
	state.set_terrain(Vector2i(2, 4), TerrainDB.WATER)
	var dry := state.unit_by_uid(100)
	var wet := state.unit_by_uid(101)
	var outside := state.unit_by_uid(102)
	var entry := {"type": "cell", "cell": dry.cell}
	t.check(SkillResolver.targets(state, caster, "electric_arc").has(entry), "存在附近水域也可选两格旱地单位")
	t.check(not SkillResolver.targets(state, caster, "electric_arc").has({"type": "cell", "cell": outside.cell}), "直接选取仍限曼哈顿两格")
	var wet_hp := wet.hp
	var hp := dry.hp
	var preview := state.preview_skill(caster, "electric_arc", entry)
	t.check(preview["ok"] and preview["hits"][0]["uid"] == dry.uid, "旱地目标预览命中正确单位")
	var result := SkillResolver.apply(state, caster, "electric_arc", entry, false)
	t.check(result["ok"] and dry.hp < hp, "放电可实际命中旱地单位")
	t.eq(wet.hp, wet_hp, "旱地直击不误伤无关水域")
	caster.moved = false
	var water_entry := {"type": "cell", "cell": Vector2i(1, 4)}
	result = SkillResolver.apply(state, caster, "electric_arc", water_entry, false)
	t.check(result["ok"] and wet.hp < wet_hp, "选水格仍沿连通水域传导")
	var ally := CombatUnit.make("grass_starter", "player", 50)
	ally.cell = Vector2i(2, 3)
	state.units.append(ally)
	t.check(SkillResolver.targets(state, caster, "electric_arc").has({"type": "cell", "cell": ally.cell}), "任何其他单位包含射程内己方单位")
	t.check(not SkillResolver.targets(state, caster, "electric_arc").has({"type": "cell", "cell": caster.cell}), "仍不直接选择自身")
	t.finish()
