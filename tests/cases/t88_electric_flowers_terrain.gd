extends RefCounted

const FLOWER := Vector2i(3, 3)
const STRAIGHT := Vector2i(3, 2)
const DIAGONAL := Vector2i(4, 4)

func flower_battle(base: int, species: String) -> BattleState:
	var state := TestScenario.make_state([species], [
		["rock_wild1", STRAIGHT], ["rock_wild1", DIAGONAL],
	], TestScenario.with_cells(TestScenario.plain_terrain(), [[FLOWER, base]]))
	state.electric_flowers[FLOWER] = true
	state.obstacle_durability[FLOWER] = state.electric_flower_max_hp(FLOWER)
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	return state

func run(t: TestContext) -> void:
	t.begin("浅草覆水、蒸汽、电电花叠层与蓝火")
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[FLOWER, TerrainDB.SHALLOW_GRASS], [STRAIGHT, TerrainDB.GRASS], [DIAGONAL, TerrainDB.VINES],
	])
	var rain := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(7, 6)]], terrain)
	var caster := rain.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills = ["rain_call"]
	var rain_entry := {"type": "cell", "cell": FLOWER}
	t.check(rain.preview_skill(caster, "rain_call", rain_entry).get("ok", false), "造雨可预览")
	t.eq(rain.terrain_at(FLOWER), TerrainDB.SHALLOW_GRASS, "预览不会改变底层")
	SkillResolver.apply(rain, caster, "rain_call", rain_entry, false)
	t.eq(rain.terrain_at(FLOWER), TerrainDB.GRASS, "水将浅草养成草丛")
	t.eq(rain.terrain_at(STRAIGHT), TerrainDB.GRASS, "水不覆盖草丛")
	t.eq(rain.terrain_at(DIAGONAL), TerrainDB.VINES, "水不覆盖藤蔓")
	caster.cell = FLOWER
	t.eq(rain.damage_unit(null, caster, 20, {"no_element": true})["amount"], 18, "草丛实际减伤10%")
	var jet := TestScenario.make_state(["fire_wild1"], [], TestScenario.with_cells(TestScenario.plain_terrain(), [
		[FLOWER, TerrainDB.WATER], [Vector2i(4, 3), TerrainDB.DEEP],
	]))
	caster = jet.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	var jet_entry := {"type": "dir", "dir": Vector2i.RIGHT, "cell": FLOWER}
	t.check(SkillResolver.apply(jet, caster, "flame_jet", jet_entry, false).get("ok", false), "喷射火焰正常施放")
	t.eq(jet.terrain_at(FLOWER), TerrainDB.PLAIN, "喷射火焰蒸干浅水")
	t.eq(jet.terrain_at(Vector2i(4, 3)), TerrainDB.DEEP, "喷射火焰保留深水底层")
	t.check(jet.steam_cells.has(FLOWER) and jet.steam_cells.has(Vector2i(4, 3)), "两种水都产生蒸汽")
	var burst := TestScenario.make_state(["fire_wild1"], [], TestScenario.with_cells(TestScenario.plain_terrain(), [[FLOWER, TerrainDB.WATER]]))
	SkillResolver.resolve_channel(burst, burst.unit_by_uid(1), "fire_burst", [FLOWER])
	t.check(burst.terrain_at(FLOWER) == TerrainDB.PLAIN and burst.steam_cells.has(FLOWER), "火球术同样蒸干浅水")

	var grass_flower := flower_battle(TerrainDB.GRASS, "water_starter")
	t.eq(grass_flower.obstacle_durability[FLOWER], 2, "草地电电花有两点耐久")
	t.check(not PathFinder.stop_cells(grass_flower, grass_flower.unit_by_uid(1)).has(FLOWER), "地面单位不能站在花上")
	t.check(grass_flower.is_blocking_ray(FLOWER), "电电花阻挡射线")
	var water_entry := {"type": "cell", "cell": FLOWER}
	var hit := SkillResolver.apply(grass_flower, grass_flower.unit_by_uid(1), "water_flow", water_entry, false)
	t.check(hit.get("ok", false) and grass_flower.electric_flowers.has(FLOWER), "水炮命中草地花但未破坏")
	t.eq(grass_flower.obstacle_durability[FLOWER], 1, "命中消耗一点耐久")
	t.eq(grass_flower.unit_by_uid(100).paralyzed_ticks, 1, "未破坏也麻痹正交邻居")
	t.eq(grass_flower.unit_by_uid(101).paralyzed_ticks, 0, "非水底层不麻痹对角邻居")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(grass_flower))
	t.check(restored.electric_flowers.has(FLOWER) and restored.obstacle_durability[FLOWER] == 1, "叠层及受损耐久可存读档")
	restored.damage_obstacle(FLOWER, 1, "player", "water_flow")
	t.check(not restored.electric_flowers.has(FLOWER) and restored.terrain_at(FLOWER) == TerrainDB.GRASS, "花毁后底层草丛保留")

	var wet_flower := flower_battle(TerrainDB.WATER, "water_starter")
	SkillResolver.apply(wet_flower, wet_flower.unit_by_uid(1), "water_flow", water_entry, false)
	t.eq(wet_flower.unit_by_uid(101).paralyzed_ticks, 1, "水底层电电花麻痹八邻")
	t.eq(wet_flower.terrain_at(FLOWER), TerrainDB.WATER, "花毁后底层水面保留")
	var fire_flower := flower_battle(TerrainDB.WATER, "fire_wild1")
	var diagonal := fire_flower.unit_by_uid(101)
	var hp := diagonal.hp
	var preview := fire_flower.preview_skill(fire_flower.unit_by_uid(1), "flame_jet", jet_entry)
	t.check(preview.get("hits", []).any(func(entry): return entry["uid"] == diagonal.uid and entry["damage"] == ceili(diagonal.max_hp * 0.10)), "技能预览显示爆燃的八邻伤害")
	t.eq(diagonal.hp, hp, "预览不伤害实际单位")
	SkillResolver.apply(fire_flower, fire_flower.unit_by_uid(1), "flame_jet", jet_entry, false)
	t.eq(diagonal.hp, hp - ceili(diagonal.max_hp * 0.10), "火系击花造成最大生命10%伤害")
	t.eq(diagonal.paralyzed_ticks, 0, "爆燃替代麻痹")
	t.check(fire_flower.terrain_at(FLOWER) == TerrainDB.PLAIN and fire_flower.steam_cells.has(FLOWER), "火系击花时也蒸干其底层浅水")

	var flame := TestScenario.make_state(["water_starter"], [], TestScenario.with_cells(TestScenario.plain_terrain(), [
		[FLOWER, TerrainDB.BLUE_FIRE], [STRAIGHT, TerrainDB.SHALLOW_GRASS],
	]))
	caster = flame.unit_by_uid(1)
	caster.cell = FLOWER
	t.check(flame.apply_burning_ground(caster), "蓝火沿用地面灼烧")
	for i in 8:
		flame._settle_burning_cells()
	t.check(flame.is_burning_ground(FLOWER) and flame.terrain_at(FLOWER) == TerrainDB.BLUE_FIRE, "蓝火不会随回合熄灭")
	t.eq(flame.terrain_at(STRAIGHT), TerrainDB.PLAIN, "蓝火可以烧尽相邻浅草")
	SkillResolver._convert_to_water(flame, FLOWER, {"terrain_changes": []})
	t.check(not flame.is_burning_ground(FLOWER) and flame.terrain_at(FLOWER) == TerrainDB.WATER, "地形覆盖会熄灭蓝火")

	var total_flowers := 0
	var total_blue := 0
	var other_blue := 0
	for seed_value in range(1, 41):
		var fire_map := MapGenerator.generate(seed_value, 0, 0, [], "fire")
		var grass_map := MapGenerator.generate(seed_value, 0, 0, [], "grass")
		total_blue += fire_map["terrain"].count(TerrainDB.BLUE_FIRE)
		other_blue += grass_map["terrain"].count(TerrainDB.BLUE_FIRE)
		var flowers: Dictionary = fire_map["electric_flowers"]
		total_flowers += flowers.size()
		for cell in flowers:
			t.check(not Balance.DEPLOY_AREA.has(cell) and not fire_map["nest_cells"].has(cell), "随机花避开部署区与巢穴")
	t.check(total_flowers > 0 and total_blue > 0, "普通生成入口能产生花和火谷蓝火")
	t.eq(other_blue, 0, "密林的普通地图不生成蓝火")
	t.finish()
