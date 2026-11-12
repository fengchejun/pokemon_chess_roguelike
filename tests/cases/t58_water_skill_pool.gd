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
	t.check(SkillDB.has_tag("ice_breath", "freeze_combo"), "冰冻连携显式标记在冰之息")
	t.check(not SkillDB.has_tag("freeze_ray", "freeze_combo"), "急冻光线不参与浸湿冰冻连携")


func _water_magic_burst(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 1), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["water_starter"], [
		["rock_wild1", Vector2i(2, 3)],
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(2, 2)],
		["rock_wild1", Vector2i(2, 4)],
	], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("water_magic_burst")
	var center := state.unit_by_uid(100)
	var front := state.unit_by_uid(101)
	var stuck_side := state.unit_by_uid(102)
	var free_side := state.unit_by_uid(103)
	var hp_before := [center.hp, front.hp, stuck_side.hp, free_side.hp]
	var entry := {"type": "cell", "cell": Vector2i(2, 3)}
	t.check(state.skill_targets(caster, "water_magic_burst").has(entry), "水魔爆可选择正交四格内落点")
	t.check(not state.skill_targets(caster, "water_magic_burst").has({"type": "cell", "cell": Vector2i(2, 2)}), "水魔爆不能用斜角格作为十字中心")
	var result := state.cast_skill(caster, "water_magic_burst", entry)
	t.check(bool(result.get("ok", false)), "水魔爆成功施放")
	t.eq((result.get("area_cells", []) as Array).size(), 5, "水魔爆覆盖以落点为中心的五格十字")
	t.eq(center.hp, int(hp_before[0]) - 11, "落点中心敌人受到十一点伤害")
	t.eq(center.cell, Vector2i(2, 3), "落点中心敌人不会被推动")
	t.eq(front.hp, int(hp_before[1]) - 8, "攻击方向前后两格敌人受到八点伤害")
	t.eq(front.cell, Vector2i(3, 3), "前后方向格不会横向推动")
	t.eq(stuck_side.hp, int(hp_before[2]) - 13, "不可推动的侧面敌人受到八点伤害和五点碰撞伤害")
	t.eq(stuck_side.cell, Vector2i(2, 2), "被障碍挡住时留在原格")
	t.eq(free_side.hp, int(hp_before[3]) - 8, "可推动的侧面敌人只受到八点技能伤害")
	t.eq(free_side.cell, Vector2i(2, 5), "下方侧面敌人继续向外推一格")
	var pushes := {}
	for hit in result["hits"]:
		pushes[int(hit["uid"])] = hit.get("push")
	t.check(pushes.get(center.uid) == null and pushes.get(front.uid) == null, "中心与前后方向格不产生推击")
	var stuck_push = pushes.get(stuck_side.uid)
	var free_push = pushes.get(free_side.uid)
	t.check(stuck_push is Dictionary and not bool(stuck_push.get("moved", false)), "受阻侧翼推击记录为未移动")
	t.check(free_push is Dictionary and bool(free_push.get("moved", false)), "空侧翼记录成功推动")


func _ice_breath(t: TestContext) -> void:
	var state := TestScenario.make_state(["water_starter"], [
		["rock_wild1", Vector2i(2, 3)],
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(2, 4)],
		["rock_wild1", Vector2i(3, 2)],
		["rock_wild1", Vector2i(4, 3)],
	])
	var caster := state.unit_by_uid(1)
	var wet_front := state.unit_by_uid(100)
	var dry_behind := state.unit_by_uid(101)
	var wet_side := state.unit_by_uid(102)
	var dry_side := state.unit_by_uid(103)
	var outside := state.unit_by_uid(104)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("ice_breath")
	state.apply_slow(wet_front)
	state.apply_slow(wet_side)
	var hp_before := [wet_front.hp, dry_behind.hp, wet_side.hp, dry_side.hp, outside.hp]
	var area := SkillResolver.ice_breath_cells(state, caster, Vector2i.RIGHT)
	t.eq(area.size(), 6, "冰之息覆盖前方 3 格宽、2 格深共六格")
	for cell in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4)]:
		t.check(area.has(cell), "冰之息范围包含 %s" % str(cell))
	var result := state.cast_skill(caster, "ice_breath", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)})
	t.check(bool(result.get("ok", false)), "冰之息可朝正交方向施放")
	t.eq((result.get("area_cells", []) as Array).size(), 6, "冰之息结算完整三乘二范围")
	t.eq(wet_front.hp, int(hp_before[0]) - 8, "冰之息命中第一排中央列浸湿目标")
	t.eq(dry_behind.hp, int(hp_before[1]) - 8, "冰之息命中第二排中央列敌人")
	t.eq(wet_side.hp, int(hp_before[2]) - 8, "冰之息命中第一排侧列浸湿目标")
	t.eq(dry_side.hp, int(hp_before[3]) - 8, "冰之息命中第二排另一侧列敌人")
	t.eq(outside.hp, int(hp_before[4]), "冰之息不命中第三排目标")
	t.eq(wet_front.slow_ticks, 0, "冰之息清除前排目标浸湿")
	t.check(wet_front.frozen, "前排浸湿目标获得冰冻")
	t.eq(wet_front.frozen_ticks, Balance.FREEZE_TICKS, "冰之息冰冻持续一回合")
	t.check(wet_side.frozen, "另一列浸湿目标也获得冰冻")
	t.check(not dry_behind.frozen and not dry_side.frozen, "未浸湿目标不会因冰之息冰冻")
	var blocked_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var blocked := TestScenario.make_state(["water_starter"], [
		["rock_wild1", Vector2i(3, 3)],
		["rock_wild1", Vector2i(3, 4)],
	], blocked_terrain)
	var blocked_caster := blocked.unit_by_uid(1)
	blocked_caster.cell = Vector2i(1, 3)
	blocked_caster.skills.append("ice_breath")
	var blocked_lane := SkillResolver.ice_breath_cells(blocked, blocked_caster, Vector2i.RIGHT)
	t.check(not blocked_lane.has(Vector2i(2, 3)), "障碍格不会被冰之息覆盖")
	t.check(blocked_lane.has(Vector2i(3, 4)), "障碍只阻断中央列，其余列继续延伸")
	var blocked_result := blocked.cast_skill(blocked_caster, "ice_breath", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)})
	t.check(bool(blocked_result.get("ok", false)), "另一列有敌人时冰之息仍可施放")
	t.eq(blocked.unit_by_uid(100).hp, SpeciesDB.hp_of("rock_wild1"), "障碍后的敌人不受伤")
	t.eq(blocked.unit_by_uid(101).hp, SpeciesDB.hp_of("rock_wild1") - 8, "未阻挡列敌人正常受伤")
