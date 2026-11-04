extends RefCounted


func run(t: TestContext) -> void:
	t.begin("火系扩充技能池")
	_definition_and_learning(t)
	_flame_rush(t)
	_windfire_breath(t)
	_furnace_fist(t)
	_skyfire(t)
	_combustion(t)
	_burn_out(t)
	t.finish()


func _definition_and_learning(t: TestContext) -> void:
	var ids := ["flame_rush", "windfire_breath", "furnace_fist", "skyfire", "combustion", "burn_out"]
	for skill_id in ids:
		t.check(not SkillDB.get_def(skill_id).is_empty(), "%s 有技能定义" % skill_id)
		t.check(SkillDB.learnable_ids_for("fire").has(skill_id), "%s 进入火系可学技能池" % skill_id)
		t.eq(RunState.upgrade_id_for_skill(skill_id), skill_id + "_damage" if skill_id != "furnace_fist" else "furnace_fist_training", "%s 有专属强化" % skill_id)
	t.check(not SpeciesDB.skills_of("fire_starter").has("flame_rush"), "扩充技能不自动加入小火龙初始技能")
	t.eq(SkillResolver.half_circle_cells(Vector2i(3, 3), Vector2i.RIGHT).size(), 8, "半圆范围固定为八格")


func _flame_rush(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 2), TerrainDB.GRASS]])
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(2, 3)],
		["rock_wild1", Vector2i(3, 3)],
	], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("flame_rush")
	var fire_cell := Vector2i(2, 2)
	state.ignite(fire_cell, "player")
	var first := state.unit_by_uid(100)
	var second := state.unit_by_uid(101)
	var first_hp := first.hp
	var second_hp := second.hp
	var result := state.cast_skill(caster, "flame_rush", {"type": "cell", "cell": fire_cell})
	t.check(bool(result.get("ok", false)), "炎袭可跃迁到燃烧格")
	t.eq(caster.cell, fire_cell, "炎袭落点正确")
	t.eq(first.hp, first_hp - 10, "落点周围一格敌人受到十点伤害")
	t.eq(second.hp, second_hp - 10, "斜角一格敌人也受到伤害")
	t.check(caster.moved, "炎袭作为技能消耗普通移动机会")
	var no_fire := state.unit_by_uid(100).cell
	t.check(not state.skill_targets(caster, "flame_rush").any(func(entry): return entry.get("cell") == no_fire), "非燃烧格不能作为炎袭落点")


func _windfire_breath(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(4, 2)],
		["rock_wild1", Vector2i(5, 5)],
	])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills.append("windfire_breath")
	var first := state.unit_by_uid(100)
	var second := state.unit_by_uid(101)
	var first_hp := first.hp
	var second_hp := second.hp
	var result := state.cast_skill(caster, "windfire_breath", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(4, 3)})
	t.check(bool(result.get("ok", false)), "风怒炎息可朝前方施放")
	t.eq((result.get("area_cells", []) as Array).size(), 8, "风怒炎息覆盖前方八格")
	t.eq(first.hp, first_hp - 12, "前排气格敌人受到十二点伤害")
	t.eq(second.hp, second_hp - 12, "第二排远处敌人也受到伤害")
	t.eq(first.cell, Vector2i(5, 1), "前排气格敌人沿远离施法者方向被推开")
	t.eq(second.cell, Vector2i(6, 6), "第二排敌人沿远离施法者方向被推开")


func _furnace_fist(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	caster.hp = 10
	caster.skills.append("furnace_fist")
	state.apply_burn(target, state.unit_by_uid(1))
	var target_hp := target.hp
	var result := state.cast_skill(caster, "furnace_fist", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "炎炉拳可攻击相邻敌人")
	t.eq(target.hp, target_hp - 10, "炎炉拳造成十点伤害")
	t.eq(caster.hp, 20, "灼烧目标使炎炉拳回复十点生命")
	t.eq(target.burn_ticks, 0, "炎炉拳清除目标灼烧")
	t.eq(target.burn_source_uid, -1, "清除灼烧时清空来源")
	var normal := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var normal_caster := normal.unit_by_uid(1)
	normal_caster.cell = Vector2i(2, 3)
	normal_caster.hp = 10
	normal_caster.skills.append("furnace_fist")
	normal.cast_skill(normal_caster, "furnace_fist", {"type": "unit", "unit": 100, "cell": Vector2i(3, 3)})
	t.eq(normal_caster.hp, 15, "未灼烧目标时炎炉拳恢复五点生命")


func _skyfire(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "rock_starter"], [
		["rock_wild1", Vector2i(3, 3)],
	])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(0, 3)
	var ally := state.unit_by_uid(2)
	ally.cell = Vector2i(3, 4)
	var enemy := state.unit_by_uid(100)
	var enemy_hp := enemy.hp
	var ally_hp := ally.hp
	caster.skills.append("skyfire")
	var center := Vector2i(3, 3)
	var result := state.cast_skill(caster, "skyfire", {"type": "cell", "cell": center})
	t.check(bool(result.get("ok", false)), "天火可在全图选择中心")
	t.eq(state.burning_cells.size(), 5, "天火生成中心与四向共五格火焰")
	t.eq(enemy.hp, enemy_hp - 8, "天火命中十字内敌人")
	t.eq(ally.hp, ally_hp - 8, "天火按命中规则也会灼伤友军")
	t.check(enemy.burn_ticks > 0 and ally.burn_ticks > 0, "天火赋予活着的命中目标灼烧")
	var water_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(7, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 3), TerrainDB.WATER]]))
	water_state.unit_by_uid(1).cell = Vector2i(0, 3)
	water_state.ignite(Vector2i(3, 3), "player", true)
	t.check(water_state.burning_cells.has(Vector2i(3, 3)), "魔法火焰可生成在不可燃水格")
	water_state._settle_burning_cells()
	water_state._settle_burning_cells()
	t.eq(water_state.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "魔法火焰到期后恢复底层水格")


func _combustion(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("combustion")
	state.apply_burn(target, caster)
	var target_hp := target.hp
	var result := state.cast_skill(caster, "combustion", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "爆燃可攻击两格内敌人")
	t.eq(target.hp, target_hp - 16, "爆燃对灼烧目标造成十六点伤害")
	t.eq(target.burn_ticks, 0, "爆燃消耗目标灼烧")
	var normal := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var normal_caster := normal.unit_by_uid(1)
	normal_caster.cell = Vector2i(0, 3)
	normal_caster.skills.append("combustion")
	var normal_hp := normal.unit_by_uid(100).hp
	normal.cast_skill(normal_caster, "combustion", {"type": "unit", "unit": 100, "cell": Vector2i(2, 3)})
	t.eq(normal.unit_by_uid(100).hp, normal_hp - 8, "爆燃对未灼烧目标造成八点伤害")


func _burn_out(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(5, 3)],
		["rock_wild1", Vector2i(7, 3)],
	])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	var far_target := state.unit_by_uid(101)
	caster.cell = Vector2i(0, 3)
	caster.skills.append("burn_out")
	var entries := state.skill_targets(caster, "burn_out")
	t.check(entries.any(func(entry): return int(entry.get("unit", -1)) == target.uid), "燃尽可选择曼哈顿五格内敌人")
	t.check(not entries.any(func(entry): return int(entry.get("unit", -1)) == far_target.uid), "燃尽不能选择曼哈顿五格外敌人")
	var target_hp := target.hp
	var far_hp := far_target.hp
	var result := state.cast_skill(caster, "burn_out", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "燃尽对五格内单体敌人结算")
	t.eq(target.hp, target_hp - 15, "燃尽对目标造成施法者最大生命一半的基础直伤")
	t.eq(far_target.hp, far_hp, "五格外敌人不受燃尽影响")
	t.eq(caster.hp, 15, "燃尽损失施法者最大生命一半的当前生命")
	t.check(target.burn_ticks > 0, "燃尽为存活目标附加灼烧")
	t.eq(far_target.burn_ticks, 0, "燃尽不会为非目标附加灼烧")
	var lethal := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(5, 3)]])
	lethal.unit_by_uid(1).cell = Vector2i(0, 3)
	lethal.unit_by_uid(1).hp = 15
	lethal.unit_by_uid(1).skills.append("burn_out")
	var lethal_caster := lethal.unit_by_uid(1)
	lethal.cast_skill(lethal_caster, "burn_out", {"type": "unit", "unit": 100, "cell": Vector2i(5, 3)})
	t.eq(lethal_caster.hp, 0, "生命不足一半时燃尽可以令施法者倒下")
	t.check(not lethal_caster.is_alive(), "燃尽的自损会触发倒下")
