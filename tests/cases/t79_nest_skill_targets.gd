extends RefCounted

func run(t: TestContext) -> void:
	t.begin("新技能攻巢目标、范围与真实预览一致")
	_direct(t)
	_areas(t)
	_limits(t)
	_special(t)
	_nest_healing(t)
	t.finish()

func _state(skill: String, origin: Vector2i = Vector2i(3, 3)) -> BattleState:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 0)]])
	state.nest["cell"] = Vector2i(4, 3)
	state.nest["hp"] = 200
	state.nest["max_hp"] = 200
	state.unit_by_uid(1).cell = origin
	state.unit_by_uid(1).skills = [skill]
	return state

func _entry(state: BattleState, skill: String) -> Dictionary:
	for entry in state.skill_targets(state.unit_by_uid(1), skill):
		if entry.get("type", "") == "nest" and entry.get("cell") == state.nest["cell"]:
			return entry
	return {}

func _compare(t: TestContext, state: BattleState, skill: String, entry: Dictionary, damage: int) -> void:
	var caster := state.unit_by_uid(1)
	var before := int(state.nest["hp"])
	var preview := state.preview_skill(caster, skill, entry)
	t.eq(state.nest["hp"], before, "%s预览不改变原状态" % skill)
	var result := SkillResolver.apply(state, caster, skill, entry, false)
	t.check(bool(result.get("ok", false)), "%s可实际施放" % skill)
	t.eq(before - int(state.nest["hp"]), damage, "%s按正确威力伤巢" % skill)
	t.eq(result.get("nests_damaged", []), preview.get("nests_damaged", []), "%s巢穴预览一致" % skill)
	t.eq(result.get("hits", []), preview.get("hits", []), "%s守护/单位预览一致" % skill)

func _direct(t: TestContext) -> void:
	for pair in [["furnace_fist", 10], ["combustion", 8], ["leaf_wind", 8], ["mountain_chain", 8], ["water_drop_stone", 12], ["electromagnetic_laser", 12], ["tree_wrath", 10], ["rock_blast", 12]]:
		var skill := String(pair[0])
		var state := _state(skill, Vector2i(1, 3) if skill == "rock_blast" else Vector2i(3, 3))
		var entry := _entry(state, skill)
		t.check(not entry.is_empty(), "%s可选择巢穴" % skill)
		if not entry.is_empty():
			_compare(t, state, skill, entry, int(pair[1]))

func _areas(t: TestContext) -> void:
	for pair in [["skyfire", 8], ["water_magic_burst", 11], ["ice_breath", 8], ["electric_spark", 8], ["windfire_breath", 10], ["flame_rush", 10]]:
		var skill := String(pair[0])
		var state := _state(skill)
		var entry: Dictionary = {"type": "cell", "cell": Vector2i(4, 3)}
		if SkillDB.kind_of(skill) == "direction":
			entry = {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(4, 3)}
		if skill == "flame_rush":
			state.burning_cells[Vector2i(3, 2)] = {"expire_round": 5, "source_side": "player"}
			entry = {"type": "cell", "cell": Vector2i(3, 2)}
		t.check(state.skill_targets(state.unit_by_uid(1), skill).has(entry), "%s仅有巢穴也可选择攻击区域" % skill)
		_compare(t, state, skill, entry, int(pair[1]))
	var edge := _state("water_magic_burst")
	edge.nest["cell"] = Vector2i(4, 2)
	_compare(t, edge, "water_magic_burst", {"type": "cell", "cell": Vector2i(4, 3)}, 8)

func _limits(t: TestContext) -> void:
	var blast := _state("rock_blast")
	t.check(_entry(blast, "rock_blast").is_empty(), "岩爆弹不能攻击一格近巢")
	blast.unit_by_uid(1).cell = Vector2i(2, 2)
	t.check(_entry(blast, "rock_blast").is_empty(), "岩爆弹不能斜射三格巢穴")
	for skill in ["rock_blast", "electromagnetic_laser"]:
		var blocked := _state(skill, Vector2i(1, 3))
		blocked.place_temp_obstacle(Vector2i(2, 3), TerrainDB.PLAIN, 9)
		t.check(_entry(blocked, skill).is_empty(), "%s仍被中间岩障阻挡" % skill)
		var unit_blocked := _state(skill, Vector2i(1, 3))
		unit_blocked.unit_by_uid(100).cell = Vector2i(2, 3)
		t.check(_entry(unit_blocked, skill).is_empty(), "%s仍被中间单位阻挡" % skill)
	for skill in ["first_aid", "leech_seed", "volt_replace", "freeze_ray", "guard_rock"]:
		var state := _state(skill)
		t.check(_entry(state, skill).is_empty(), "%s不新增巢穴单位效果目标" % skill)
	var enemy := _state("leaf_wind")
	enemy.unit_by_uid(100).cell = Vector2i(4, 2)
	enemy.unit_by_uid(100).skills = ["leaf_wind"]
	t.check(not enemy.skill_targets(enemy.unit_by_uid(100), "leaf_wind").any(func(e): return e.get("type", "") == "nest"), "敌人不主动选己巢")
	var lanes := _state("ice_breath")
	var cells := SkillResolver.ice_breath_cells(lanes, lanes.unit_by_uid(1), Vector2i.RIGHT)
	t.check(cells.has(Vector2i(4, 3)) and not cells.has(Vector2i(5, 3)), "冰息命中巢穴后截断该列")

func _special(t: TestContext) -> void:
	var grass := _state("leaf_wind")
	grass.set_terrain(Vector2i(3, 3), TerrainDB.GRASS)
	_compare(t, grass, "leaf_wind", _entry(grass, "leaf_wind"), 12)
	var route := _state("water_drop_stone", Vector2i(1, 3))
	for cell in [Vector2i(2, 3), Vector2i(3, 3)]:
		route.place_temp_obstacle(cell, TerrainDB.PLAIN, 9)
	_compare(t, route, "water_drop_stone", _entry(route, "water_drop_stone"), 12)
	t.eq(route.obstacle_durability[Vector2i(2, 3)], 1, "水滴石穿对攻巢途中的岩障扣耐久")
	var burn := _state("burn_out")
	var sacrifice := ceili(burn.unit_by_uid(1).max_hp * 0.5)
	burn.unit_by_uid(1).hp = sacrifice
	_compare(t, burn, "burn_out", _entry(burn, "burn_out"), sacrifice)
	t.eq(burn.unit_by_uid(1).hp, 0, "燃尽攻巢保留献祭死亡代价")
	var shared := _state("water_magic_burst")
	var guard := shared.unit_by_uid(100)
	guard.cell = Vector2i(4, 2)
	guard.hp = 100
	guard.max_hp = 100
	shared.begin_nest_guard(guard, shared.nest["cell"])
	_compare(t, shared, "water_magic_burst", {"type": "cell", "cell": Vector2i(4, 3)}, 6)
	t.check(guard.hp < 100, "范围攻巢沿用守军分伤")
	var fragments := _state("rock_blast", Vector2i(1, 3))
	fragments.unit_by_uid(100).cell = Vector2i(4, 2)
	fragments.unit_by_uid(100).hp = 100
	fragments.unit_by_uid(100).max_hp = 100
	_compare(t, fragments, "rock_blast", _entry(fragments, "rock_blast"), 12)
	t.eq(fragments.unit_by_uid(100).hp, 97, "岩爆弹攻巢仍向侧面分裂")
	var side_nest := _state("rock_blast", Vector2i(1, 3))
	side_nest.unit_by_uid(100).cell = Vector2i(4, 2)
	side_nest.unit_by_uid(100).hp = 100
	side_nest.unit_by_uid(100).max_hp = 100
	side_nest.nest["cell"] = Vector2i(4, 3)
	var target := side_nest.unit_by_uid(100)
	# Main impact travels along row 2; its side fragment reaches the nest in row 3.
	side_nest.unit_by_uid(1).cell = Vector2i(1, 2)
	_compare(t, side_nest, "rock_blast", {"type": "unit", "unit": target.uid, "cell": target.cell}, 3)

func _nest_healing(t: TestContext) -> void:
	for skill in ["furnace_fist"]:
		var state := _state(skill)
		var caster := state.unit_by_uid(1)
		caster.hp = 5
		if skill == "furnace_fist":
			caster.upgrades["furnace_fist_healing"] = 3
		var entry := _entry(state, skill)
		t.check(not entry.is_empty(), "%s可选择巢穴并触发自身回复" % skill)
		if entry.is_empty():
			continue
		state.preview_skill(caster, skill, entry)
		t.eq(caster.hp, 5, "%s预攻巢不提前回复生命" % skill)
		var result := SkillResolver.apply(state, caster, skill, entry, false)
		var expected_heal := 8
		t.eq(caster.hp, 5 + expected_heal, "%s攻巢后按技能规则回复生命" % skill)
		var heal = result.get("heal")
		var healed := int(heal.get("amount", 0)) if heal is Dictionary else 0
		t.eq(healed, expected_heal, "%s攻巢结果记录回复量" % skill)
