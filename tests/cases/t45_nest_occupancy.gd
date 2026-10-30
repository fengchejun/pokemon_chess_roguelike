extends RefCounted

func _state() -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(3, 3)
	state.nest["hp"] = 10
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	return state

func run(t: TestContext) -> void:
	t.begin("巢穴本格生成、覆盖与任意伤害")
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
	for skill in ["fire_burst", "earth_shake", "rock_create", "flame_jet"]:
		var state := _state()
		var caster := state.unit_by_uid(1)
		var blocker := state.unit_by_uid(100)
		blocker.cell = state.nest["cell"]
		blocker.hp = 1
		if skill in ["fire_burst", "earth_shake"]:
			SkillResolver.resolve_channel(state, caster, skill, [blocker.cell])
		else:
			SkillResolver.apply(state, caster, skill, {"type": "dir", "dir": Vector2i.RIGHT, "cell": blocker.cell}, false)
		t.check(not blocker.is_alive(), "%s击杀覆盖者" % skill)
		t.eq(state.nest["hp"], 10, "%s击杀当次不穿透巢穴" % skill)
		state.damage_nest(99, "player")
		t.eq(state.nest["hp"], 9, "%s之后的新攻击可以伤巢穴" % skill)
	var pushed := _state()
	var blocker := pushed.unit_by_uid(100)
	blocker.cell = pushed.nest["cell"]
	blocker.hp = 999
	SkillResolver.apply(pushed, pushed.unit_by_uid(1), "water_flow", {"type": "cell", "cell": blocker.cell}, false)
	t.eq(blocker.cell, Vector2i(4, 3), "水炮移开覆盖者")
	t.eq(pushed.nest["hp"], 10, "移开当次不伤及巢穴")
	var state := _state()
	var unit := state.unit_by_uid(1)
	t.check(state.move_options(unit).has(state.nest["cell"]), "普通移动可停在巢穴格")
	t.check(state.move_unit(unit, state.nest["cell"]), "执行移动到巢穴格")
	t.check(state.nest_covered(), "己方站巢覆盖巢穴")
	state.damage_nest(99, "player")
	t.eq(state.nest["hp"], 10, "己方覆盖同样保护巢穴")
	state.nest["pending_waves"] = 2
	var before := state.units.size()
	state._try_spawn_wave()
	t.eq(state.units.size(), before, "己方占巢阻止生成")
	t.eq(state.nest["pending_waves"], 2, "阻挡时保留队列")
	unit.cell = Vector2i(2, 3)
	state._try_spawn_wave()
	var spawn: CombatUnit = state.units.back()
	t.eq(spawn.cell, state.nest["cell"], "敌人直接从巢穴格生成")
	t.check(spawn.fresh_spawn and not spawn.can_move_now(), "出生轮不能行动")
	t.eq(state.nest["pending_waves"], 1, "一次只生成一只")
	state._try_spawn_wave()
	t.eq(state.nest["pending_waves"], 1, "生成的敌人覆盖巢穴也会阻挡下一只")
	state.damage_nest(99)
	t.eq(state.nest["hp"], 10, "生成的敌人保护巢穴")
	var snapshot := BattleSnapshot.save_state(state)
	# Simulate a pre-change snapshot with an adjacent exit.
	snapshot["fields"]["nest"] = BattleSnapshot.encode(state.nest.merged({"exits": [Vector2i(2, 2)]}, true))
	var restored := BattleSnapshot.load_state(snapshot)
	t.eq(restored.nest["exits"], [], "旧存档出口失效")
	t.eq(restored.nest["hp"], 10, "兼容读取保留巢穴耐久")
	t.eq(restored.nest["pending_waves"], 1, "兼容读取保留待产队列")
	var forced := _state()
	var victim := forced.unit_by_uid(100)
	victim.cell = Vector2i(2, 3)
	forced.unit_by_uid(1).cell = Vector2i(1, 3)
	var result := PushResolver.push(forced, victim, Vector2i.RIGHT, 1, 0, "测试")
	t.eq(victim.cell, forced.nest["cell"], "击退可将单位推上巢穴")
	t.eq(result["collisions"].size(), 0, "空巢不触发碰撞")
	var teleport := _state()
	var teleporter := teleport.unit_by_uid(1)
	teleporter.cell = Vector2i(1, 3)
	t.check(SkillResolver.targets(teleport, teleporter, "volt_step").any(func(e): return e["cell"] == teleport.nest["cell"]), "瞬移可选空巢")
	var no_damage := _state()
	SkillResolver.apply(no_damage, no_damage.unit_by_uid(1), "freeze_ray", {"type": "cell", "cell": no_damage.nest["cell"]}, false)
	t.eq(no_damage.nest["hp"], 10, "无伤害冻结技能不扣耐久")
	no_damage.damage_nest(0)
	t.eq(no_damage.nest["hp"], 10, "零伤害不扣耐久")
	var slide := _state()
	var slider := slide.unit_by_uid(1)
	slide.set_terrain(slider.cell, TerrainDB.ICE)
	slider.last_move_direction = Vector2i.RIGHT
	slide._settle_ice_slides()
	t.eq(slider.cell, slide.nest["cell"], "冰面滑行可进入巢穴格")
	var burning := _state()
	burning.burning_cells[burning.nest["cell"]] = 1
	burning.burning_sources[burning.nest["cell"]] = "player"
	burning._settle_burning_cells()
	t.eq(burning.nest["hp"], 9, "环境燃烧可削减空巢耐久")
	var covered := _state()
	covered.unit_by_uid(100).cell = covered.nest["cell"]
	t.check(not SkillResolver.targets(covered, covered.unit_by_uid(1), "discharge").any(func(e): return e["type"] == "nest"), "覆盖者存活时不能绕过单位选中巢穴")
	t.finish()
