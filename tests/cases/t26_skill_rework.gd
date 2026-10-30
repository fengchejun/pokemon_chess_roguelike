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
	target.max_hp = 120
	target.hp = 120
	target.frozen = true
	target.battle_buffs["direct_guard"] = true
	caster.fire_amp_stacks = Balance.SKILL_DAMAGE_UPGRADE * 2
	var hit := frozen.cast_skill(caster, "rock_break", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(hit.get("ok", false)), "碎岩曼哈顿两格可命中")
	t.eq(target.hp, 120 - (SkillDB.damage_of("rock_break") + Balance.SKILL_DAMAGE_UPGRADE * 2 - Balance.DIRECT_GUARD_REDUCTION) * 3, "冰冻碎岩在增伤与直伤减免后乘三")
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
	ally.hp = 100
	ally.max_hp = 100
	t.check(slide.skill_targets(rock, "rock_slide").has({"type": "cell", "cell": Vector2i(4, 2)}), "岩崩曼哈顿第三格可选")
	t.check(not slide.skill_targets(rock, "rock_slide").has({"type": "cell", "cell": Vector2i(5, 2)}), "岩崩第四格不可选")
	var cast := slide.cast_skill(rock, "rock_slide", {"type": "cell", "cell": Vector2i(4, 2)})
	t.check(bool(cast.get("ok", false)) and slide.unit_by_uid(100).hp == slide.unit_by_uid(100).max_hp, "岩崩宣告时不造成伤害")
	slide.unit_by_uid(100).cell = Vector2i(6, 4)
	ally.cell = Vector2i(4, 2)
	slide.start_round()
	t.eq(ally.hp, 100 - SkillDB.damage_of("rock_slide"), "岩崩固定落点对走入的友军造成配置伤害")
	var wall := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(2, 1)]])
	wall.unit_by_uid(1).cell = Vector2i(1, 1)
	var wall_hp := wall.unit_by_uid(100).hp
	SkillResolver.apply(wall, wall.unit_by_uid(1), "rock_create", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 1)}, false)
	t.eq(wall.unit_by_uid(100).hp, wall_hp - SkillDB.damage_of("rock_create"), "造岩命中单位造成配置伤害")
	t.check(SkillDB.learnable_ids_for("rock").has("rock_slide"), "岩崩进入岩系学习池")
	var storm := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(4, 1)], ["rock_wild1", Vector2i(5, 2)],
		["rock_wild1", Vector2i(6, 3)], ["rock_wild1", Vector2i(7, 4)]])
	storm.unit_by_uid(1).cell = Vector2i(1, 1)
	storm.cast_skill(storm.unit_by_uid(1), "lightning", {"type": "cell", "cell": Vector2i(1, 1)})
	t.eq(storm.pending_casts[0]["cells"].size(), 5, "打雷锁定数不受原三格上限限制")


func _tree(t: TestContext) -> void:
	t.check(SkillDB.learnable_ids_for("grass").has("tree_man"), "大树守卫进入草系学习池")
	var cell := Vector2i(3, 2)
	var mixed_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[cell, TerrainDB.GRASS], [Vector2i(2, 2), TerrainDB.WATER],
		[Vector2i(4, 2), TerrainDB.DEEP], [Vector2i(3, 1), TerrainDB.VINES],
		[Vector2i(3, 3), TerrainDB.GRASS]])
	var state := TestScenario.make_state(["grass_starter", "grass_starter"], [["rock_wild1", Vector2i(6, 5)]], mixed_terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 2)
	caster.skills.append("tree_man")
	var preview := state.preview_skill(caster, "tree_man", {"type": "cell", "cell": cell})
	t.check(bool(preview.get("ok", false)) and state.active_summon(caster.uid) == null, "大树守卫预览不污染真实战场")
	var cast := state.cast_skill(caster, "tree_man", {"type": "cell", "cell": cell})
	t.check(bool(cast.get("ok", false)), "大树守卫可在三格内指定合法空格")
	t.eq(state.pending_casts[0]["cells"], [cell], "蓄力固定召唤落点")
	t.check(state.active_summon(caster.uid) == null and caster.moved and caster.skill_used, "宣告轮不立即召唤且消耗行动")
	state.start_round()
	var summon := state.active_summon(caster.uid)
	t.check(summon != null, "第二回合本方阶段开始召唤树人")
	if summon != null:
		t.eq(summon.max_hp, 55, "中心和四邻的水草地形分别累加生命上限")
		t.eq(summon.hp, 55, "地形加成同时提高当前生命")
		t.eq(summon.move_points, 2, "树人基础移动力为二")
		t.eq(summon.skills, ["tree_wrath"], "树人只拥有大树之怒")
		t.check(summon.fresh_spawn and not summon.can_move_now() and not summon.can_act_skill(), "召唤出生轮不能移动或施法")
	t.eq(state.terrain_at(Vector2i(4, 2)), TerrainDB.DEEP, "吸取地形力量不会消耗深水")
	t.eq(state.terrain_at(Vector2i(3, 1)), TerrainDB.VINES, "吸取地形力量不会消耗藤蔓")
	t.check(caster.moved and caster.skill_used, "蓄力结算轮施法者不能行动")
	state._finish_round()
	if summon != null:
		t.check(not summon.fresh_spawn and summon.can_move_now() and summon.can_act_skill(), "再下一轮树人可移动和施法")
	t.check(state.skill_targets(caster, "tree_man").has({"type": "cell", "cell": Vector2i(2, 2)}), "已有活树人不限制再次召唤")
	t.check(bool(state.cast_skill(caster, "tree_man", {"type": "cell", "cell": Vector2i(2, 2)}).get("ok", false)), "同一施法者可再次宣告大树守卫")
	state.start_round()
	var summon_count := 0
	for unit in state.units:
		if unit.summon_owner_uid == caster.uid and unit.is_alive():
			summon_count += 1
	t.eq(summon_count, 2, "同一施法者可同时维持多个树人")
	var edge := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(6, 5)]],
		TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 0), TerrainDB.DEEP], [Vector2i(0, 1), TerrainDB.VINES]]))
	var edge_tree := edge.summon_tree(edge.unit_by_uid(1), Vector2i(0, 0))
	t.eq(edge_tree.max_hp, 30, "边界格只统计地图内四邻，深水和藤蔓均生效")
	var enhanced_owner := edge.unit_by_uid(1)
	enhanced_owner.upgrades["tree_man_hp_bonus"] = 10
	var stronger_tree := edge.summon_tree(enhanced_owner, Vector2i(5, 5))
	t.eq(stronger_tree.max_hp, 25, "强化大树守卫使新召唤树人生命额外增加十点")
	var blocked := TestScenario.make_state(["grass_starter", "grass_starter"], [["rock_wild1", Vector2i(6, 5)]])
	var blocked_caster := blocked.unit_by_uid(1)
	blocked_caster.cell = Vector2i(1, 2)
	blocked_caster.skills.append("tree_man")
	var ally := blocked.unit_by_uid(2)
	ally.cell = Vector2i(5, 2)
	ally.max_hp = 100
	ally.hp = 100
	blocked.cast_skill(blocked_caster, "tree_man", {"type": "cell", "cell": cell})
	ally.cell = cell
	blocked.start_round()
	t.eq(ally.hp, 100 - int(SkillDB.get_def("tree_man")["summon_collision_damage"]), "友军占据固定落点受到召唤碰撞伤害")
	t.check(blocked.active_summon(blocked_caster.uid) == null and blocked.pending_casts.is_empty(), "落点被挡即取消召唤")
	var enemy_blocked := TestScenario.make_state(["grass_starter"], [["grass_wild1", Vector2i(6, 5)]])
	var enemy_caster := enemy_blocked.unit_by_uid(1)
	enemy_caster.cell = Vector2i(1, 2)
	enemy_caster.skills.append("tree_man")
	enemy_blocked.cast_skill(enemy_caster, "tree_man", {"type": "cell", "cell": cell})
	var enemy_blocker := enemy_blocked.unit_by_uid(100)
	enemy_blocker.hp = 100
	enemy_blocker.max_hp = 100
	enemy_blocker.cell = cell
	enemy_blocked.start_round()
	t.eq(enemy_blocker.hp, 100 - int(SkillDB.get_def("tree_man")["summon_collision_damage"]), "敌军占据落点同样受到召唤碰撞伤害")
	t.check(enemy_blocked.active_summon(enemy_caster.uid) == null, "敌军挡位也取消召唤")
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
	t.eq(enemy.hp, hp - Elements.direct_damage(SkillDB.damage_of("electric_arc"), "electric", enemy.element), "无水放电仍按属性结算直伤")
	var wet := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(3, 2)]],
		TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 3), TerrainDB.WATER]]))
	wet.unit_by_uid(1).cell = Vector2i(1, 2)
	t.check(wet.skill_targets(wet.unit_by_uid(1), "electric_arc").has({"type": "cell", "cell": Vector2i(3, 2)}), "范围内有水也允许直接选旱地单位")
