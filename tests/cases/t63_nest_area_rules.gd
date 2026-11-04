extends RefCounted


func run(t: TestContext) -> void:
	t.begin("巢穴、区域目标与冰冻火伤联动")
	_frozen_fire_wet(t)
	_objective_either_route(t)
	_player_cannot_occupy_nest(t)
	_enemy_nest_guard(t)
	_nest_experience(t)
	_vine_and_root_terrain(t)
	t.finish()


func _frozen_fire_wet(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	state.apply_freeze(target)
	var result := state.cast_skill(caster, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "火系技能可命中冰冻目标")
	t.check(not target.frozen, "火系实际伤害解除冰冻")
	t.eq(target.slow_ticks, 1, "冰冻目标受到火系技能伤害后获得一层浸湿")
	var zero := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var zero_caster := zero.unit_by_uid(1)
	var zero_target := zero.unit_by_uid(100)
	zero_target.cell = Vector2i(3, 3)
	zero_caster.cell = Vector2i(2, 3)
	zero.apply_freeze(zero_target)
	zero_target.battle_buffs["direct_guard"] = true
	var zero_hit := zero.damage_unit(zero_caster, zero_target, 1, {"skill_direct": true, "element": "fire", "cause": "零伤火系测试"})
	t.eq(int(zero_hit.get("amount", -1)), 0, "减伤可将火系技能伤害降到零")
	t.check(zero_target.frozen and zero_target.slow_ticks == 0, "没有实际火系伤害时不融冰、不附加浸湿")
	var aquatic := TestScenario.make_state(["fire_starter"], [["water_wild1", Vector2i(3, 3)]])
	var aquatic_caster := aquatic.unit_by_uid(1)
	var aquatic_target := aquatic.unit_by_uid(100)
	aquatic_caster.cell = Vector2i(2, 3)
	aquatic.apply_freeze(aquatic_target)
	aquatic.damage_unit(aquatic_caster, aquatic_target, 5, {"skill_direct": true, "element": "fire", "cause": "融冰水系测试"})
	t.check(not aquatic_target.frozen, "水系目标受到实际火系技能伤害仍会解冻")
	t.eq(aquatic_target.slow_ticks, 0, "水系目标不会获得融冰浸湿")


func _objective_either_route(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.node_kind = "battle"
	state.nest["hp"] = 1
	state.damage_nest(1, "player")
	t.check(not state.battle_objective_met(), "只毁巢仍需清场")
	state.kill_unit(state.unit_by_uid(100), "清场", "player", 1)
	t.check(state.battle_objective_met() and state.can_leave_node(), "清场并毁巢后可离开")

func _player_cannot_occupy_nest(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "water_starter"], [["rock_wild1", Vector2i(7, 7)]])
	state.node_kind = "battle"
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	var nest_cell: Vector2i = state.nest["cell"]
	nest_cell = Vector2i(3, 3)
	state.nest["cell"] = nest_cell
	t.check(not state.move_options(caster).has(nest_cell), "普通移动不能把巢穴作为落点")
	t.check(not state.move_unit(caster, nest_cell), "普通移动执行入口拒绝巢穴落点")
	t.check(not SkillResolver.targets(state, caster, "volt_step").any(func(entry): return entry.get("cell") == nest_cell), "瞬移不能选择我方不可占据的巢穴")
	state.burning_cells[nest_cell] = 1
	caster.skills.append("flame_rush")
	t.check(not SkillResolver.targets(state, caster, "flame_rush").any(func(entry): return entry.get("cell") == nest_cell), "炎袭不能跃迁到我方不可占据的巢穴")
	var blocker := state.unit_by_uid(100)
	blocker.cell = nest_cell
	caster.skills.append("volt_replace")
	t.check(not SkillResolver.targets(state, caster, "volt_replace").any(func(entry): return int(entry.get("unit", -1)) == blocker.uid), "换位不能让施法者落入敌人占据的巢穴")
	blocker.cell = Vector2i(7, 7)
	caster.skills.append("tree_man")
	t.check(not SkillResolver.targets(state, caster, "tree_man").any(func(entry): return entry.get("cell") == nest_cell), "我方召唤物不能占据巢穴")
	var pushed := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var pushed_unit := pushed.unit_by_uid(1)
	pushed.nest["cell"] = Vector2i(3, 3)
	pushed_unit.cell = Vector2i(2, 3)
	var push := PushResolver.push(pushed, pushed_unit, Vector2i.RIGHT, 1, 0, "巢穴边界测试")
	t.check(bool(push.get("blocked", false)) and pushed_unit.cell == Vector2i(2, 3), "击退也不能把己方单位推上巢穴")
	var slide := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var slider := slide.unit_by_uid(1)
	slide.nest["cell"] = Vector2i(3, 3)
	slider.cell = Vector2i(2, 3)
	slide.set_terrain(slider.cell, TerrainDB.ICE)
	slider.last_move_direction = Vector2i.RIGHT
	t.check(bool(slide.ice_slide_outcome(slider).get("blocked", false)), "冰面滑行不能把己方单位滑入巢穴")
	var captured := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	captured.nest["cell"] = Vector2i(3, 3)
	captured.capture_options["capture_field_join"] = true
	var captured_enemy := captured.unit_by_uid(100)
	captured.on_captured(captured_enemy, captured_enemy.species_id, captured_enemy.hp)
	t.check(captured_enemy.side == "player" and captured_enemy.cell != captured.nest["cell"], "原地转阵营捕获会先移出巢穴格")
	t.check(bool(captured.captured[0]["on_field"]), "捕获记录仍标记战场加入")
	var legacy := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	legacy.unit_by_uid(1).cell = legacy.nest["cell"]
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(legacy))
	t.check(restored.unit_by_uid(1).cell != restored.nest["cell"], "旧存档中的我方占巢会迁移到附近合法格")
	var resume_source := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	resume_source.node_kind = "battle"
	var region := RegionState.create_floor(0, "grass")
	region.nodes["battle_1"]["snapshot"] = BattleSnapshot.save_state(resume_source)
	var returning_player := CombatUnit.make("fire_starter", "player", 1)
	var resumed := region.resume_node("battle_1", [returning_player])
	t.check(resumed != null and returning_player.cell != resumed.nest["cell"], "重新进入区域时不会把返回的我方单位部署到巢穴")


func _enemy_nest_guard(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.unit_by_uid(100).cell = state.nest["cell"]
	state.relocate_nest_occupants()
	t.check(not state.is_nest_cell(state.unit_by_uid(100).cell), "敌人同样不能站在巢穴格")

func _nest_experience(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.node_kind = "battle"
	state.nest["hp"] = 1
	state.damage_nest(1, "player")
	t.check(state.all_rewards().any(func(p): return p.get("state") == "map" and p.get("cell") == state.nest["cell"]), "毁巢原地生成需要拾取的奖励点")
	t.eq(int(state.nest.get("destroyed_unborn_xp", 0)), 0, "没有未出生怪物经验")

func _vine_and_root_terrain(t: TestContext) -> void:
	t.check(String(SkillDB.get_def("wild_vines").get("desc", "")).contains("禁锢"), "疯狂藤蔓说明使用禁锢")
	t.check(String(TerrainDB.DESCRIPTIONS.get(TerrainDB.VINES, "")).contains("禁锢"), "藤蔓地形说明使用禁锢")
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	state.relic_stacks["root_bind"] = 1
	target.imprison_ticks = 2
	var with_imprison := RelicDB.damage_bonus(state, caster, target, {"element": "grass", "skill_id": "leaf_wind", "skill_direct": true})
	target.imprison_ticks = 0
	var without_imprison := RelicDB.damage_bonus(state, caster, target, {"element": "grass", "skill_id": "leaf_wind", "skill_direct": true})
	t.eq(with_imprison - without_imprison, 5, "缠根遗物按禁锢状态提供伤害")
	caster.cell = Vector2i(3, 3)
	caster.skills.append("rooted_grass")
	var root := state.cast_skill(caster, "rooted_grass", {"type": "cell", "cell": caster.cell})
	t.check(bool(root.get("ok", false)) and state.terrain_at(caster.cell) == TerrainDB.GRASS, "落地生根实际改变地形")
