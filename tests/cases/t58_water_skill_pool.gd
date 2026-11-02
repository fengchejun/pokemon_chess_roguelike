extends RefCounted


func run(t: TestContext) -> void:
	t.begin("水系技能池扩充：水魔爆与冰之息")
	_definition_and_learning(t)
	_water_magic_burst(t)
	_ice_breath(t)
	t.finish()


func _definition_and_learning(t: TestContext) -> void:
	t.check(SkillDB.learnable_ids_for("water").has("water_magic_burst"), "水魔爆进入水系普通学习池")
	t.check(SkillDB.learnable_ids_for("water").has("ice_breath"), "冰之息进入水系普通学习池")
	t.eq(RunState.upgrade_id_for_skill("water_magic_burst"), "water_magic_burst_damage", "水魔爆拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("ice_breath"), "ice_breath_damage", "冰之息拥有专属强化")
	t.check(not SkillDB.is_special("water_magic_burst") and not SkillDB.is_special("ice_breath"), "两个新增技能均为普通技能")


func _water_magic_burst(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["water_starter"], [
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(3, 4)],
		["rock_wild1", Vector2i(3, 2)],
	], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("water_magic_burst")
	var center := state.unit_by_uid(100)
	var lower := state.unit_by_uid(101)
	var upper := state.unit_by_uid(102)
	var center_hp := center.hp
	var lower_hp := lower.hp
	var upper_hp := upper.hp
	var target := Vector2i(3, 3)
	t.check(state.skill_targets(caster, "water_magic_burst").any(func(entry): return entry.get("cell") == target), "水魔爆可越过障碍选择落点")
	var result := state.cast_skill(caster, "water_magic_burst", {"type": "cell", "cell": target})
	t.check(bool(result.get("ok", false)), "水魔爆成功施放")
	t.eq((result.get("area_cells", []) as Array).size(), 5, "水魔爆覆盖五格十字")
	t.eq(center.hp, center_hp - 11, "中心敌人受到八点基础伤害并额外受三点")
	t.eq(center.cell, target, "中心敌人不会被推动")
	t.eq(lower.hp, lower_hp - 8, "外侧敌人受到八点伤害")
	t.eq(upper.hp, upper_hp - 8, "另一外侧敌人受到八点伤害")
	t.eq(lower.cell, Vector2i(3, 5), "下方敌人沿远离中心方向被推一格")
	t.eq(upper.cell, Vector2i(3, 1), "上方敌人沿远离中心方向被推一格")


func _ice_breath(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("ice_breath")
	state.apply_slow(target)
	var hp_before := target.hp
	var result := state.cast_skill(caster, "ice_breath", {"type": "cell", "cell": target.cell})
	t.check(bool(result.get("ok", false)), "冰之息可攻击正交六格内目标")
	t.eq(target.hp, hp_before - 8, "冰之息造成八点基础直伤")
	t.eq(target.slow_ticks, 0, "冰之息清除目标浸湿")
	t.check(target.frozen, "冰之息对浸湿目标施加冰冻")
	var dry := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var dry_caster := dry.unit_by_uid(1)
	var dry_target := dry.unit_by_uid(100)
	dry_caster.cell = Vector2i(0, 3)
	dry_caster.skills.append("ice_breath")
	dry.cast_skill(dry_caster, "ice_breath", {"type": "cell", "cell": dry_target.cell})
	t.check(not dry_target.frozen, "未浸湿目标不会因冰之息冰冻")
	var blocked_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var blocked := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]], blocked_terrain)
	var blocked_caster := blocked.unit_by_uid(1)
	blocked_caster.cell = Vector2i(0, 3)
	blocked_caster.skills.append("ice_breath")
	t.check(not blocked.skill_targets(blocked_caster, "ice_breath").any(func(entry): return entry.get("cell") == Vector2i(4, 3)), "障碍会截断冰之息射线")
