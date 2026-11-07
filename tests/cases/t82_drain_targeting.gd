extends RefCounted

func run(t: TestContext) -> void:
	t.begin("吸取目标集合与射程强化")
	_enemy_units_only(t)
	_upgraded_range(t)
	t.finish()


func _enemy_units_only(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 2), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(
		["grass_starter", "rock_starter"],
		[["rock_wild1", Vector2i(2, 3)]],
		terrain
	)
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	ally.cell = Vector2i(1, 3)
	state.nest["cell"] = Vector2i(3, 3)
	var entries := state.skill_targets(caster, "drain")
	t.check(entries.has({"type": "unit", "unit": enemy.uid, "cell": enemy.cell}), "吸取可选择射程内敌人")
	t.check(not entries.any(func(entry): return int(entry.get("unit", -1)) == ally.uid), "吸取不能选择友军")
	t.check(not entries.any(func(entry): return String(entry.get("type", "")) == "cell"), "吸取不能选择障碍")
	var nest_state := TestScenario.make_state(["grass_starter"], [])
	var nest_caster := nest_state.unit_by_uid(1)
	nest_caster.cell = Vector2i(0, 3)
	nest_state.nest["cell"] = Vector2i(2, 3)
	t.check(not nest_state.skill_targets(nest_caster, "drain").any(func(entry): return String(entry.get("type", "")) == "nest"), "吸取不能选择巢穴")


func _upgraded_range(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	state.nest["cell"] = Vector2i(7, 7)
	var entry := {"type": "unit", "unit": enemy.uid, "cell": enemy.cell}
	t.check(not state.skill_targets(caster, "drain").has(entry), "基础吸取不能选择三格外敌人")
	caster.upgrades["drain_range"] = 1
	t.check(state.skill_targets(caster, "drain").has(entry), "蔓延吸取可选择三格外敌人")
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	t.check(screen._skill_tag("drain", caster).contains("射程 3"), "技能栏显示强化后的三格射程")
	screen.free()
