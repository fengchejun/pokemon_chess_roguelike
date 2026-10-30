extends RefCounted

## 撼地的固定范围、破障、逐级塌陷与敌我判定。

func run(t: TestContext) -> void:
	t.begin("撼地蓄力与地形塌陷")
	_main_resolution(t)
	_fixed_area_and_edges(t)
	t.finish()


func _main_resolution(t: TestContext) -> void:
	t.check(SkillDB.learnable_ids_for("rock").has("earth_shake"), "撼地加入岩系局内学习池")
	t.check(not SpeciesDB.skills_of("rock_starter").has("earth_shake"), "撼地不占用小拳石开局技能栏")
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 2), TerrainDB.FRAGILE], [Vector2i(3, 2), TerrainDB.OBSTACLE],
		[Vector2i(4, 2), TerrainDB.TREE], [Vector2i(3, 3), TerrainDB.WATER],
		[Vector2i(2, 4), TerrainDB.FRAGILE], [Vector2i(4, 4), TerrainDB.GRASS]])
	var state := TestScenario.make_state(["rock_starter", "grass_starter", "water_starter"],
		[["rock_wild1", Vector2i(4, 3)], ["rock_wild1", Vector2i(2, 2)]], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("earth_shake")
	var falling_ally := state.unit_by_uid(2)
	falling_ally.cell = Vector2i(2, 4)
	var safe_ally := state.unit_by_uid(3)
	safe_ally.cell = Vector2i(3, 4)
	var safe_hp := safe_ally.hp
	var staying_enemy := state.unit_by_uid(100)
	staying_enemy.max_hp = 100
	staying_enemy.hp = 100
	var falling_enemy := state.unit_by_uid(101)
	falling_enemy.max_hp = 100
	falling_enemy.hp = 100
	state.obstacle_durability[Vector2i(3, 2)] = 9
	state.nest["cell"] = Vector2i(4, 4)
	var nest_hp := int(state.nest["hp"])
	var entry := {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)}
	t.check(state.skill_targets(caster, "earth_shake").has(entry), "可以选择前方方向")
	var preview := state.preview_skill(caster, "earth_shake", entry)
	t.eq(preview.get("area_cells", []), SkillResolver.front_area_cells(caster.cell, Vector2i.RIGHT, 3), "预览显示前方三乘三固定范围")
	t.eq(state.terrain_at(Vector2i(2, 2)), TerrainDB.FRAGILE, "预览不修改真实地形")
	var cast := state.cast_skill(caster, "earth_shake", entry)
	t.check(bool(cast.get("ok", false)), "成功宣告撼地")
	t.eq(state.pending_casts[0]["cells"].size(), 9, "宣告时锁定九个格子")
	t.eq(staying_enemy.hp, 100, "宣告回合不提前造成伤害")
	t.eq(int(state.obstacle_durability[Vector2i(3, 2)]), 9, "宣告回合不提前破障")
	state.start_round()
	t.eq(staying_enemy.hp, 100 - SkillDB.damage_of("earth_shake"), "范围内敌人受到撼地基础伤害")
	t.eq(safe_ally.hp, safe_hp, "范围内友军不受直接伤害")
	t.eq(state.terrain_at(Vector2i(3, 4)), TerrainDB.FRAGILE, "普通平地变为易碎地块")
	t.eq(state.terrain_at(Vector2i(2, 2)), TerrainDB.PIT, "易碎地块变为深坑")
	t.check(not falling_enemy.is_alive() and not falling_ally.is_alive(), "塌陷使格上的敌我地面单位立即坠落")
	t.check(not state.obstacle_durability.has(Vector2i(3, 2)) and not state.obstacle_durability.has(Vector2i(4, 2)), "岩障和树木均被直接摧毁")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.PLAIN, "破障露出的平地本次不再碎裂")
	t.eq(state.terrain_at(Vector2i(4, 2)), TerrainDB.PLAIN, "树木破坏后的格子本次不再碎裂")
	t.eq(state.terrain_at(Vector2i(3, 3)), TerrainDB.WATER, "水面不受地形变化")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.GRASS, "巢穴格不受地形变化")
	t.eq(int(state.nest["hp"]), nest_hp - 1, "撼地命中空置巢穴扣1耐久")
	t.check(caster.moved and caster.skill_used and state.pending_casts.is_empty(), "结算轮施法者失去行动并清除预警")


func _fixed_area_and_edges(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 1)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 1)
	caster.skills.append("earth_shake")
	var enemy := state.unit_by_uid(100)
	var hp := enemy.hp
	state.cast_skill(caster, "earth_shake", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 1)})
	enemy.cell = Vector2i(5, 1)
	state.start_round()
	t.eq(enemy.hp, hp, "敌人离开宣告时的固定范围即可躲避直接伤害")
	t.eq(state.terrain_at(Vector2i(3, 1)), TerrainDB.FRAGILE, "敌人移走后固定格仍会碎裂")
	t.eq(state.terrain_at(Vector2i(5, 1)), TerrainDB.PLAIN, "范围不会追踪敌人新位置")
	var edge := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var edge_caster := edge.unit_by_uid(1)
	edge_caster.cell = Vector2i(0, 0)
	edge_caster.skills.append("earth_shake")
	t.check(not edge.skill_targets(edge_caster, "earth_shake").has({"type": "dir", "dir": Vector2i.UP, "cell": Vector2i(0, -1)}), "地图边缘不能选择完全出界的方向")
	t.eq(SkillResolver.front_area_cells(edge_caster.cell, Vector2i.RIGHT, 3).size(), 6, "地图边缘自动裁剪前方范围")
