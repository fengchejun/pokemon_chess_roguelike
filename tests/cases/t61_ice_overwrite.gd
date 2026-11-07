extends RefCounted

func run(t: TestContext) -> void:
	t.begin("冰面被水、藤蔓、岩石与种草覆盖")
	_water(t)
	_vines(t)
	_rocks(t)
	_modification(t)
	t.finish()

func _state(species: String) -> BattleState:
	var cells := [[Vector2i(3, 3), TerrainDB.ICE], [Vector2i(4, 3), TerrainDB.ICE]]
	var state := TestScenario.make_state([species], [["rock_wild1", Vector2i(6, 6)]], TestScenario.with_cells(TestScenario.plain_terrain(), cells))
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	return state

func _water(t: TestContext) -> void:
	var state := _state("water_starter")
	var actor := state.unit_by_uid(1)
	var entry := {"type": "cell", "cell": Vector2i(3, 3)}
	var preview := state.preview_skill(actor, "water_flow", entry)
	t.check(preview.get("ok", false), "水炮可以选冰格")
	t.check((preview["terrain_changes"] as Array).any(func(c): return c["cell"] == Vector2i(3, 3) and c["to"] == TerrainDB.WATER), "水炮预览显示冰转水")
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.ICE, "预览不改写冰面")
	SkillResolver.apply(state, actor, "water_flow", entry, false)
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "水炮实际覆盖冰面")
	var ice: Array = []
	ice.resize(GridSpec.W * GridSpec.H)
	ice.fill(TerrainDB.ICE)
	var rain := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(6, 6)]], ice)
	var caster := rain.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("rain_call")
	t.check(rain.skill_targets(caster, "rain_call").has(entry), "全冰地图仍允许选择造雨中心")
	var forecast := rain.preview_skill(caster, "rain_call", entry)
	t.eq(forecast["terrain_changes"].size(), 9, "造雨预览显示九格冰转水")
	SkillResolver.apply(rain, caster, "rain_call", entry, false)
	t.eq(rain.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "造雨实际覆盖冰面")
	var vine := _state("grass_starter")
	vine.place_temp_vines(Vector2i(3, 3))
	SkillResolver._convert_to_water(vine, Vector2i(3, 3), {"terrain_changes": []})
	t.check(vine.vine_origin.has(Vector2i(3, 3)), "铺水保留临时藤蔓及其冰面底层")
	vine.round = 2
	vine._settle_temp_vines()
	t.eq(vine.terrain_at(Vector2i(3, 3)), TerrainDB.ICE, "未被铺水覆盖的藤蔓到期后恢复冰面")

func _vines(t: TestContext) -> void:
	var state := _state("grass_starter")
	var actor := state.unit_by_uid(1)
	var entry := {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(3, 3)}
	var preview := state.preview_skill(actor, "wild_vines", entry)
	t.check(preview.get("ok", false), "疯狂藤蔓预览可施放")
	SkillResolver.apply(state, actor, "wild_vines", entry, false)
	for cell in [Vector2i(3, 3), Vector2i(4, 3)]:
		t.eq(state.terrain_at(cell), TerrainDB.VINES, "技能藤蔓覆盖冰面")
		t.eq(state.vine_origin[cell], TerrainDB.ICE, "保存冰面底层")
	var walker := state.trainer()
	walker.cell = Vector2i(3, 3)
	walker.last_move_direction = Vector2i.RIGHT
	state.apply_vine_on_landing(walker)
	t.check(walker.imprison_ticks > 0, "冰面上的藤蔓同样施加束缚")
	t.check(state.ice_slide_outcome(walker).is_empty(), "藤蔓覆盖后不按冰面滑行")
	state.round = 2
	state._settle_temp_vines()
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.ICE, "临时藤蔓到期恢复冰面")
	t.eq(walker.imprison_ticks, 3, "恢复冰面不提前清除已施加禁锢")
	t.check(not state.ice_slide_outcome(walker).is_empty(), "恢复冰面后重新符合滑行地形条件")
	var grass := _state("grass_starter")
	var caster := grass.unit_by_uid(1)
	caster.skills.append("seed_sow")
	var sow := {"type": "cell", "cell": Vector2i(3, 3)}
	t.check(grass.skill_targets(caster, "seed_sow").has(sow), "播种也允许选冰面")
	SkillResolver.apply(grass, caster, "seed_sow", sow, false)
	t.eq(grass.terrain_at(Vector2i(3, 3)), TerrainDB.GRASS, "播种实际将冰面变草丛")

func _rocks(t: TestContext) -> void:
	var state := _state("rock_starter")
	var actor := state.unit_by_uid(1)
	var cell := Vector2i(3, 3)
	var entry := {"type": "dir", "dir": Vector2i.RIGHT, "cell": cell}
	var preview := state.preview_skill(actor, "rock_create", entry)
	t.check((preview["terrain_changes"] as Array).any(func(c): return c["cell"] == Vector2i(3, 3) and c["to"] == TerrainDB.OBSTACLE), "造岩预览包含冰面落点")
	t.eq(state.terrain_at(cell), TerrainDB.ICE, "造岩预览不改变实战冰面")
	SkillResolver.apply(state, actor, "rock_create", entry, false)
	t.eq(state.terrain_at(cell), TerrainDB.OBSTACLE, "造岩实际覆盖冰面")
	t.eq(state.obstacle_origin[cell], TerrainDB.ICE, "临时岩石保留冰面底层")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	restored.settle_round()
	t.eq(restored.terrain_at(cell), TerrainDB.ICE, "存读档后临时岩石到期仍恢复冰面")
	state.damage_obstacle(cell, Balance.OBSTACLE_DURABILITY, "player")
	t.eq(state.terrain_at(cell), TerrainDB.ICE, "提前破坏临时岩石也恢复冰面")

func _modification(t: TestContext) -> void:
	for pair in [["water", TerrainDB.WATER], ["grass", TerrainDB.GRASS], ["rock", TerrainDB.OBSTACLE]]:
		var cell := Vector2i(3, 3)
		var map := TestScenario.make_map(TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.ICE]]))
		t.check(MapGenerator.apply_modification(map, cell, pair[0]), "战前改造允许覆盖冰格")
		t.eq(map["terrain"][GridSpec.index(cell)], pair[1], "战前改造结果正确")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.run.preview_used_reward_item = RewardDB.MOD_ITEM
	app.show_preview([1, 2, 3])
	var screen = app.current_screen
	var cell := Vector2i(3, 3)
	screen.map = TestScenario.make_map(TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, TerrainDB.ICE]]))
	for kind in ["water", "grass", "rock"]:
		screen._set_mod_kind(kind)
		t.check(not screen._mod_hover_text(cell).contains("该格不能改造"), "预览页提示不再拒绝冰格")
		t.check(screen._mod_hover_text(cell).contains("冰面 →"), "有工具时准确显示冰面改造来源")
	app.free()
