extends RefCounted

## 缩短射程、独立树木遮挡及单出口守口规则。


func run(t: TestContext) -> void:
	t.begin("走位、射线掩体与巢穴出口")
	_test_ranges(t)
	_test_first_contact(t)
	_test_tree_cover(t)
	_test_single_exit_guard(t)
	t.finish()


func _has_target(entries: Array, cell: Vector2i) -> bool:
	for entry in entries:
		if entry.get("cell", Vector2i(-1, -1)) == cell:
			return true
	return false


func _test_ranges(t: TestContext) -> void:
	var cases := [
		["fire_starter", "fire_burst", Vector2i(0, 0), Vector2i(0, 4), Vector2i(0, 5)],
		["water_starter", "water_flow", Vector2i(0, 0), Vector2i(0, 4), Vector2i(0, 5)],
		["ice_starter", "freeze_ray", Vector2i(0, 0), Vector2i(0, 4), Vector2i(0, 5)],
		["fire_starter", "fire_seed", Vector2i(0, 0), Vector2i(0, 6), Vector2i(0, 7)],
	]
	for item in cases:
		var state := TestScenario.make_state([item[0]], [], [], {}, {}, [])
		var caster := state.unit_by_uid(1)
		caster.cell = item[2]
		state.trainer().cell = Vector2i(7, 6)
		var targets := SkillResolver.targets(state, caster, item[1])
		t.check(_has_target(targets, item[3]), "%s 在最大射程内可选点" % item[1])
		t.check(not _has_target(targets, item[4]), "%s 超出最大射程不可选点" % item[1])
		var failed := state.cast_skill(caster, item[1], {"type": "cell", "cell": item[4]})
		t.check(not bool(failed.get("ok", false)) and not caster.skill_used, "%s 越界施法不消耗机会" % item[1])
	var electric := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(5, 0)]])
	electric.unit_by_uid(1).cell = Vector2i(0, 0)
	t.check(_has_target(SkillResolver.targets(electric, electric.unit_by_uid(1), "lightning"), Vector2i(0, 0)), "打雷可在自身格宣告")
	electric.unit_by_uid(100).cell = Vector2i(6, 0)
	t.check(bool(electric.cast_skill(electric.unit_by_uid(1), "lightning", {"type": "cell", "cell": Vector2i(0, 0)}).get("ok", false)), "打雷全地图锁定远处敌方")
	t.check(electric.pending_casts[0]["cells"].has(Vector2i(6, 0)), "曼哈顿 6 格敌人也被锁定")
	var rain := TestScenario.make_state(["water_starter"], [])
	rain.unit_by_uid(1).cell = Vector2i(0, 0)
	t.check(_has_target(SkillResolver.targets(rain, rain.unit_by_uid(1), "rain_call"), Vector2i(0, 4)), "造雨 4 格中心可选")
	t.check(not _has_target(SkillResolver.targets(rain, rain.unit_by_uid(1), "rain_call"), Vector2i(0, 5)), "造雨 5 格中心不可选")


func _test_first_contact(t: TestContext) -> void:
	# 固定空地图：过去 8 格射线可在初始对线直接交火；现在需要接近。
	var fire := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 3)]])
	fire.trainer().cell = Vector2i(7, 6)
	fire.unit_by_uid(1).cell = Vector2i(0, 3)
	t.check(not _has_target(SkillResolver.targets(fire, fire.unit_by_uid(1), "fire_burst"), Vector2i(7, 3)), "固定地图：火球初始 7 格无法直接交火")
	fire.unit_by_uid(1).cell = Vector2i(3, 3)
	t.check(_has_target(SkillResolver.targets(fire, fire.unit_by_uid(1), "fire_burst"), Vector2i(7, 3)), "固定地图：火怪前进 3 格后可交火")
	var water := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 3)]])
	water.trainer().cell = Vector2i(7, 6)
	water.unit_by_uid(1).cell = Vector2i(0, 3)
	t.check(not _has_target(SkillResolver.targets(water, water.unit_by_uid(1), "water_flow"), Vector2i(7, 3)), "固定地图：水流初始 7 格无法直接交火")
	water.unit_by_uid(1).cell = Vector2i(3, 3)
	t.check(_has_target(SkillResolver.targets(water, water.unit_by_uid(1), "water_flow"), Vector2i(7, 3)), "固定地图：水怪前进 3 格后可交火")
	water.set_terrain(Vector2i(4, 3), TerrainDB.TREE)
	water.obstacle_durability[Vector2i(4, 3)] = 1
	t.check(not _has_target(SkillResolver.targets(water, water.unit_by_uid(1), "water_flow"), Vector2i(7, 3)), "固定地图：距离足够仍需先清树或绕射线")


func _test_tree_cover(t: TestContext) -> void:
	var tree := Vector2i(2, 3)
	var enemy_cell := Vector2i(4, 3)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[tree, TerrainDB.TREE]])
	for skill_id in ["water_flow", "freeze_ray", "fire_seed"]:
		var species := "water_starter" if skill_id == "water_flow" else "ice_starter" if skill_id == "freeze_ray" else "fire_starter"
		var state := TestScenario.make_state([species], [["rock_wild1", enemy_cell]], terrain)
		var caster := state.unit_by_uid(1)
		caster.cell = Vector2i(0, 3)
		if skill_id == "fire_seed":
			caster.skills.append(skill_id)
		var enemy := state.unit_by_uid(100)
		var hp := enemy.hp
		t.check(_has_target(SkillResolver.targets(state, caster, skill_id), tree), "%s 可选中树木格" % skill_id)
		t.check(not _has_target(SkillResolver.targets(state, caster, skill_id), enemy_cell), "%s 不能选中树后单位" % skill_id)
		var preview := state.preview_skill(caster, skill_id, {"type": "cell", "cell": tree})
		t.check(bool(preview.get("ok", false)), "%s 可预览树木命中" % skill_id)
		t.eq(int(state.obstacle_durability.get(tree, 0)), 1, "%s 预览不改变树木耐久" % skill_id)
		state.cast_skill(caster, skill_id, {"type": "cell", "cell": tree})
		t.eq(enemy.hp, hp, "%s 毁树当次不穿透到树后单位" % skill_id)
		if skill_id != "freeze_ray":
			t.check(not state.obstacle_durability.has(tree), "%s 对 1 耐久树木造成伤害并摧毁" % skill_id)
	var fire := TestScenario.make_state(["fire_starter"], [["rock_wild1", enemy_cell]], terrain)
	fire.unit_by_uid(1).cell = Vector2i(0, 3)
	t.check(_has_target(SkillResolver.targets(fire, fire.unit_by_uid(1), "fire_burst"), enemy_cell), "火球术仍可越树选中单位")
	var flame := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	flame.unit_by_uid(1).cell = Vector2i(0, 3)
	var flame_hp := flame.unit_by_uid(100).hp
	flame.cast_skill(flame.unit_by_uid(1), "flame_jet", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(1, 3)})
	t.check(not flame.obstacle_durability.has(tree), "喷射火焰摧毁 1 耐久树木")
	t.eq(flame.unit_by_uid(100).hp, flame_hp, "喷射火焰毁树当次停在树格")
	var lightning := TestScenario.make_state(["electric_starter"], [["rock_wild1", enemy_cell]], terrain)
	lightning.unit_by_uid(1).cell = Vector2i(0, 3)
	lightning.cast_skill(lightning.unit_by_uid(1), "lightning", {"type": "cell", "cell": Vector2i(0, 3)})
	t.check(lightning.pending_casts[0]["cells"].has(enemy_cell), "打雷不按射线受树木阻挡")


func _test_single_exit_guard(t: TestContext) -> void:
	var state := TestScenario.make_state([], [["rock_wild1", Vector2i(6, 7)]], [], {}, {}, ["fire_wild1"])
	t.eq((state.nest["exits"] as Array).size(), 1, "巢穴只有一个出口")
	t.check(state.nest_exit_guarded(), "敌人守在出口时提供巢穴防御")
	var preview_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(6, 7)]])
	preview_state.unit_by_uid(1).cell = Vector2i(5, 7)
	var preview := preview_state.preview_skill(preview_state.unit_by_uid(1), "rock_break", {"type": "nest", "cell": Vector2i(7, 7)})
	t.eq(int(preview.get("nest_damaged", {}).get("damage", -1)), 1, "守口碎岩预览显示实际 1 点耐久伤害")
	t.eq(int(preview_state.nest["hp"]), Balance.NEST_DURABILITY, "守口预览不会修改巢穴耐久")
	state.damage_nest(1)
	t.eq(int(state.nest["hp"]), Balance.NEST_DURABILITY, "守口时 1 伤被完全抵消")
	state.damage_nest(2)
	t.eq(int(state.nest["hp"]), Balance.NEST_DURABILITY - 1, "守口时 2 伤只扣 1 耐久")
	state.damage_nest(4)
	t.eq(int(state.nest["hp"]), Balance.NEST_DURABILITY - 2, "守口时 4 伤也只扣 1 耐久")
	state.unit_by_uid(100).cell = Vector2i(5, 7)
	t.check(not state.nest_exit_guarded(), "敌人离开出口立即失去防御")
	var unguarded := TestScenario.make_state([], [["rock_wild1", Vector2i(5, 7)]])
	unguarded.damage_nest(4)
	t.eq(int(unguarded.nest["hp"]), Balance.NEST_DURABILITY - 1, "无守口时高伤命中也只扣 1 耐久")
	unguarded.damage_nest(1)
	t.eq(int(unguarded.nest["hp"]), Balance.NEST_DURABILITY - 2, "无守口时 1 伤正常生效")
	state.trainer().cell = Vector2i(6, 7)
	t.check(not state.nest_exit_guarded(), "我方堵口不提供防御")
	state.damage_nest(1)
	t.check(state.ended and state.end_reason == "victory", "我方堵口时仍可摧毁巢穴获胜")
	var fireball := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 7)]])
	fireball.unit_by_uid(1).cell = Vector2i(3, 7)
	fireball.unit_by_uid(100).hp = 10
	var cast := fireball.cast_skill(fireball.unit_by_uid(1), "fire_burst", {"type": "cell", "cell": Vector2i(7, 7)})
	t.check(bool(cast.get("ok", false)), "火球可将巢穴格作为落点")
	fireball.start_round()
	t.eq(int(fireball.nest["hp"]), Balance.NEST_DURABILITY - 1, "火球原始 4 伤通过守口门槛，但巢穴只掉 1 耐久")
