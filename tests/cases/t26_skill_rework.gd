extends RefCounted


func run(t: TestContext) -> void:
	t.begin("岩电技能改动与树人召唤")
	_rock(t)
	_tree(t)
	_electric(t)
	t.finish()


func _rock(t: TestContext) -> void:
	var frozen := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := frozen.unit_by_uid(1)
	var target := frozen.unit_by_uid(100)
	caster.cell = Vector2i(1, 2)
	target.max_hp = 12
	target.hp = 12
	target.frozen = true
	target.battle_buffs["direct_guard"] = true
	caster.fire_amp_stacks = 2
	var hit := frozen.cast_skill(caster, "rock_break", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(hit.get("ok", false)), "碎岩曼哈顿两格可命中")
	t.eq(target.hp, 6, "冰冻碎岩在增伤与直伤减免后乘三")
	t.check(not target.frozen and target.paralyzed_ticks > 0, "碎岩解除冰冻但仍保留本轮行动限制")
	var obstacle := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(7, 6)]],
		TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 2), TerrainDB.OBSTACLE]]))
	obstacle.unit_by_uid(1).cell = Vector2i(1, 2)
	obstacle.obstacle_durability[Vector2i(3, 2)] = 5
	t.check(bool(obstacle.cast_skill(obstacle.unit_by_uid(1), "rock_break", {"type": "cell", "cell": Vector2i(3, 2)}).get("ok", false)), "碎岩可选障碍")
	t.eq(int(obstacle.obstacle_durability.get(Vector2i(3, 2), 0)), 4, "碎岩命中高耐久障碍也只扣一点")
	var slide := TestScenario.make_state(["rock_starter", "water_starter"], [["fire_wild1", Vector2i(4, 2)]])
	var rock := slide.unit_by_uid(1)
	rock.cell = Vector2i(1, 2)
	rock.skills.append("rock_slide")
	var ally := slide.unit_by_uid(2)
	ally.cell = Vector2i(2, 4)
	ally.hp = 10
	ally.max_hp = 10
	t.check(slide.skill_targets(rock, "rock_slide").has({"type": "cell", "cell": Vector2i(4, 2)}), "岩崩曼哈顿第三格可选")
	t.check(not slide.skill_targets(rock, "rock_slide").has({"type": "cell", "cell": Vector2i(5, 2)}), "岩崩第四格不可选")
	var cast := slide.cast_skill(rock, "rock_slide", {"type": "cell", "cell": Vector2i(4, 2)})
	t.check(bool(cast.get("ok", false)) and slide.unit_by_uid(100).hp == slide.unit_by_uid(100).max_hp, "岩崩宣告时不造成伤害")
	slide.unit_by_uid(100).cell = Vector2i(6, 4)
	ally.cell = Vector2i(4, 2)
	slide.start_round()
	t.eq(ally.hp, 2, "岩崩固定落点对走入的友军造成八点伤害")
	var wall := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(2, 1)]])
	wall.unit_by_uid(1).cell = Vector2i(1, 1)
	var wall_hp := wall.unit_by_uid(100).hp
	SkillResolver.apply(wall, wall.unit_by_uid(1), "rock_create", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 1)}, false)
	t.eq(wall.unit_by_uid(100).hp, wall_hp - 1, "造岩命中单位只造成一点伤害")
	t.check(SkillDB.learnable_ids_for("rock").has("rock_slide"), "岩崩进入岩系学习池")
	var storm := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 1)], ["rock_wild1", Vector2i(5, 2)],
		["rock_wild1", Vector2i(6, 3)], ["rock_wild1", Vector2i(7, 4)]])
	storm.unit_by_uid(1).cell = Vector2i(1, 1)
	storm.cast_skill(storm.unit_by_uid(1), "lightning", {"type": "cell", "cell": Vector2i(1, 1)})
	t.eq(storm.pending_casts[0]["cells"].size(), 4, "打雷锁定数不受原三格上限限制")


func _tree(t: TestContext) -> void:
	t.check(SkillDB.learnable_ids_for("grass").has("tree_man"), "树人进入草系学习池")
	for spec in [[TerrainDB.PLAIN, 1], [TerrainDB.WATER, 3], [TerrainDB.GRASS, 4]]:
		var terrain_type: int = spec[0]
		var expected_hp: int = spec[1]
		var cell := Vector2i(3, 2)
		var state := TestScenario.make_state(["grass_starter", "grass_starter"], [["rock_wild1", Vector2i(6, 5)]],
			TestScenario.with_cells(TestScenario.plain_terrain(), [[cell, terrain_type]]))
		var caster := state.unit_by_uid(1)
		caster.cell = Vector2i(1, 2)
		caster.skills.append("tree_man")
		var preview := state.preview_skill(caster, "tree_man", {"type": "cell", "cell": cell})
		t.check(bool(preview.get("ok", false)) and state.active_summon(caster.uid) == null, "树人预览不污染真实战场")
		t.check(bool(state.cast_skill(caster, "tree_man", {"type": "cell", "cell": cell}).get("ok", false)), "树人可在合法空格召唤")
		var summon := state.active_summon(caster.uid)
		t.eq(summon.max_hp, expected_hp, "树人按落点地形获得生命")
		t.eq(summon.move_points, 2, "树人基础移动力为二")
		t.eq(summon.skills, ["tree_wrath"], "树人只拥有大树之怒")
		t.check(summon.fresh_spawn and not summon.can_move_now() and not summon.can_act_skill(), "树人出生轮不能移动或施法")
		t.check(state.skill_targets(caster, "tree_man").is_empty(), "同一施法者已有树人时不能再召唤")
		var other_owner := state.unit_by_uid(2)
		other_owner.cell = Vector2i(5, 2)
		other_owner.skills.append("tree_man")
		t.check(bool(state.cast_skill(other_owner, "tree_man", {"type": "cell", "cell": Vector2i(5, 3)}).get("ok", false)), "另一施法者仍能拥有自己的树人")
		state._finish_round()
		t.check(not summon.fresh_spawn and summon.can_move_now() and summon.can_act_skill(), "下一轮树人恢复移动和施法")
		state.kill_unit(summon, "测试")
		t.check(state.deaths.is_empty(), "树人消散不产生局外濒死记录")
		t.check(not state.skill_targets(caster, "tree_man").is_empty(), "树人死亡后施法者可以重新召唤")
	var wrath := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(4, 2)]])
	var owner := wrath.unit_by_uid(1)
	owner.cell = Vector2i(1, 2)
	var tree := wrath.summon_tree(owner, Vector2i(3, 2))
	wrath._finish_round()
	wrath.unit_by_uid(100).hp = 1
	var hp := wrath.unit_by_uid(100).hp
	t.check(bool(wrath.cast_skill(tree, "tree_wrath", {"type": "unit", "unit": 100, "cell": Vector2i(4, 2)}).get("ok", false)), "玩家可手动命令树人使用大树之怒")
	t.eq(wrath.unit_by_uid(100).hp, hp - 1, "大树之怒对邻格敌人造成一点伤害")
	t.eq(wrath.enemy_kills[0]["killer_uid"], owner.uid, "树人击杀由施法者获得击杀归属")
	var wild := TestScenario.make_state(["rock_starter"], [["grass_wild1", Vector2i(5, 4)]])
	wild.trainer().cell = Vector2i(1, 1)
	var enemy_tree := wild.summon_tree(wild.unit_by_uid(100), Vector2i(2, 1))
	t.check(not CaptureSystem.can_attempt(wild, wild.trainer(), enemy_tree), "敌方树人不能被捕获")
	wild.kill_unit(enemy_tree, "测试", "player", 1)
	t.check(wild.enemy_kills.is_empty(), "击败敌方树人不计普通击杀或经验")


func _electric(t: TestContext) -> void:
	var step := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(6, 5)]],
		TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 2), TerrainDB.OBSTACLE]]))
	var caster := step.unit_by_uid(1)
	caster.cell = Vector2i(1, 2)
	var dest := Vector2i(3, 2)
	t.check(step.skill_targets(caster, "volt_replace").has({"type": "cell", "cell": dest}), "伏特替换可越过障碍选择空格")
	t.check(bool(step.cast_skill(caster, "volt_replace", {"type": "cell", "cell": dest}).get("ok", false)) and caster.cell == dest, "伏特替换确实位移到空格")
	var dry := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 2)]])
	dry.unit_by_uid(1).cell = Vector2i(1, 2)
	var enemy := dry.unit_by_uid(100)
	var hp := enemy.hp
	t.check(dry.skill_targets(dry.unit_by_uid(1), "electric_arc").has({"type": "cell", "cell": enemy.cell}), "范围内无水时放电可选敌方单位")
	dry.cast_skill(dry.unit_by_uid(1), "electric_arc", {"type": "cell", "cell": enemy.cell})
	t.eq(enemy.hp, hp - 1, "无水放电造成一点伤害")
	var wet := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 2)]],
		TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 3), TerrainDB.WATER]]))
	wet.unit_by_uid(1).cell = Vector2i(1, 2)
	t.check(not wet.skill_targets(wet.unit_by_uid(1), "electric_arc").has({"type": "cell", "cell": Vector2i(3, 2)}), "范围内有水时仍使用水域传导规则")
