extends RefCounted

func _state() -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(3, 3)
	state.nest["hp"] = 10
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	return state

func run(t: TestContext) -> void:
	t.begin("巢穴阻挡、邻格生成与任意伤害")
	for skill in ["fire_seed", "water_flow", "flame_charge", "rock_push", "discharge", "drain", "ice_shard", "tree_wrath", "rock_break", "trial_fire_1", "electric_arc", "flame_jet", "rock_create", "fire_burst", "rock_slide", "earth_shake", "lightning", "tsunami"]:
		var state := _state()
		var caster := state.unit_by_uid(1)
		var def := SkillDB.get_def(skill)
		var cell: Vector2i = state.nest["cell"]
		if skill in ["fire_seed", "flame_charge"]:
			caster.cell = Vector2i(1, 3)
		var entry := {"type": "cell", "cell": cell}
		if def["kind"] == "unit":
			entry["type"] = "nest"
		elif def["kind"] == "direction":
			entry = {"type": "dir", "dir": Vector2i.RIGHT, "cell": cell}
		if skill == "tsunami":
			state.set_terrain(cell, TerrainDB.WATER)
		var result: Dictionary
		if bool(def.get("channel", false)):
			var cells: Array = [cell]
			if skill == "earth_shake":
				cells = SkillResolver.front_area_cells(caster.cell, Vector2i.RIGHT, 3)
			result = SkillResolver.resolve_channel(state, caster, skill, cells)
		else:
			result = SkillResolver.apply(state, caster, skill, entry, false)
		t.check(bool(result.get("ok", false)), "%s可命中空置巢穴" % skill)
		t.eq(state.nest["hp"], 9, "%s每次命中仅扣1耐久" % skill)
	var state := _state()
	var unit := state.unit_by_uid(1)
	t.check(not state.move_options(unit).has(state.nest["cell"]), "普通移动不能停在巢穴")
	unit.battle_buffs["flight"] = true
	t.check(not state.move_options(unit).has(state.nest["cell"]), "飞行也不能停在巢穴")
	var victim := state.unit_by_uid(100)
	victim.cell = Vector2i(2, 3)
	unit.cell = Vector2i(1, 3)
	var pushed := PushResolver.push(state, victim, Vector2i.RIGHT, 1, 0, "测试")
	t.eq(victim.cell, Vector2i(2, 3), "击退不能把单位推上巢穴")
	t.eq(pushed["collisions"].size(), 1, "撞巢穴按障碍发生碰撞")
	t.check(not SkillResolver.targets(state, unit, "volt_step").any(func(e): return e["cell"] == state.nest["cell"]), "瞬移不能选择巢穴")
	var slide := _state()
	var slider := slide.unit_by_uid(1)
	slide.set_terrain(slider.cell, TerrainDB.ICE)
	slider.last_move_direction = Vector2i.RIGHT
	slide._settle_ice_slides()
	t.eq(slider.cell, Vector2i(2, 3), "冰面滑行被巢穴阻挡")
	var spawn := _state()
	spawn.nest["pending_waves"] = 2
	spawn._try_spawn_wave()
	t.eq(GridSpec.manhattan(spawn.units.back().cell, spawn.nest["cell"]), 1, "增援在上下左右生成")
	t.check(spawn.units.back().fresh_spawn, "出生待机")
	t.eq(spawn.nest["pending_waves"], 1, "一次补产一只")
	spawn._try_spawn_wave()
	t.eq(spawn.nest["pending_waves"], 0, "另一空邻格可继续生成")
	var legacy := _state()
	legacy.unit_by_uid(100).cell = legacy.nest["cell"]
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(legacy))
	t.eq(restored.unit_at(restored.nest["cell"]), null, "旧快照占巢单位恢复时迁移")
	t.eq(restored.unit_by_uid(100).hp, legacy.unit_by_uid(100).hp, "旧单位迁移不改变生命")
	var burning := _state()
	burning.burning_cells[burning.nest["cell"]] = 1
	burning.burning_sources[burning.nest["cell"]] = "player"
	burning._settle_burning_cells()
	t.eq(burning.nest["hp"], 9, "环境伤害仍可削减巢穴耐久")
	t.finish()
