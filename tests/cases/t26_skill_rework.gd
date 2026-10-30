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
	var cell := Vector2i(3, 2)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[cell, TerrainDB.GRASS], [Vector2i(2, 2), TerrainDB.WATER],
		[Vector2i(4, 2), TerrainDB.DEEP], [Vector2i(3, 1), TerrainDB.VINES],
		[Vector2i(3, 3), TerrainDB.GRASS], [Vector2i(4, 3), TerrainDB.TREE]])
	var state := TestScenario.make_state(["grass_starter", "grass_starter"], [["rock_wild1", Vector2i(6, 5)]], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(1, 2)
	caster.skills.append("tree_man")
	var entry := {"type": "cell", "cell": cell}
	var signature := state._signature()
	t.check(bool(state.preview_skill(caster, "tree_man", entry).get("ok", false)), "即时召唤可预览")
	t.eq(state._signature(), signature, "召唤预览不改变实战")
	t.check(bool(state.cast_skill(caster, "tree_man", entry).get("ok", false)), "大树守卫立即召唤")
	t.check(state.pending_casts.is_empty(), "即时召唤不占吟唱位")
	var summon := state.active_summon(caster.uid)
	t.check(summon != null, "施放后立即存在树人")
	if summon == null:
		return
	t.eq(summon.max_hp, 31, "八邻格两处水+6、两处草+10、一棵树+5；中心草不计")
	t.eq(summon.hp, 31, "出生生命包含全部环境加成")
	var damage_sim := state.clone()
	var attacker := damage_sim.active_summon(caster.uid)
	attacker.fresh_spawn = false
	var victim := damage_sim.unit_by_uid(100)
	victim.cell = Vector2i(4, 2)
	damage_sim.set_terrain(victim.cell, TerrainDB.PLAIN)
	victim.max_hp = 100
	victim.hp = 100
	var hit := SkillResolver.apply(damage_sim, attacker, "tree_wrath", {"type": "unit", "unit": victim.uid, "cell": victim.cell}, false)
	t.eq(hit["hits"][0]["damage"], Elements.direct_damage(15, "grass", "rock"), "地形威力进入真实命中并继续计算属性克制")
	t.eq(summon.summon_power_bonus, 5, "对角树格提供五技能威力")
	t.eq(SkillResolver.upgraded_base_damage(summon, "tree_wrath", 10), 15, "树木加成进入真实基础伤害")
	t.check(summon.fresh_spawn and not summon.can_move_now() and not summon.can_act_skill(), "出生轮不能行动")
	t.eq(state.clone().active_summon(caster.uid).summon_power_bonus, 5, "AI副本保留召唤威力")
	t.eq(BattleSnapshot.load_state(BattleSnapshot.save_state(state)).active_summon(caster.uid).summon_power_bonus, 5, "存读档保留召唤威力")
	caster.skill_used = false
	caster.moved = false
	t.check(state.skill_targets(caster, "tree_man").is_empty(), "已有存活召唤物禁用目标")
	t.check(not bool(state.cast_skill(caster, "tree_man", {"type": "cell", "cell": Vector2i(5, 2)}).get("ok", false)), "已有存活召唤物阻止实际释放")
	t.check(state.summon_tree(caster, Vector2i(5, 2)) == null, "底层召唤入口也执行上限")
	var other := state.unit_by_uid(2)
	other.cell = Vector2i(6, 6)
	t.check(state.summon_tree(other, Vector2i(5, 5)) != null, "不同主人分别拥有召唤额度")
	state.kill_unit(summon, "测试")
	t.check(not state.skill_targets(caster, "tree_man").is_empty(), "召唤物消失后恢复额度")
	caster.upgrades["tree_man_hp_bonus"] = 10
	var replacement := state.summon_tree(caster, Vector2i(0, 0))
	t.eq(replacement.max_hp, 20, "空地基础十血加坚根十血")
	t.eq(state.terrain_at(Vector2i(4, 3)), TerrainDB.TREE, "吸收加成不消耗树格")
	var blocked := TestScenario.make_state(["grass_starter"], [["rock_wild1", cell]])
	var blocker := blocked.unit_by_uid(100)
	var blocker_hp := blocker.hp
	t.check(blocked.summon_tree(blocked.unit_by_uid(1), cell) == null, "单位覆盖落点不能召唤")
	t.eq(blocker.hp, blocker_hp, "取消召唤不造成旧版碰撞伤害")
	var edge := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(6, 5)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(1, 0), TerrainDB.DEEP], [Vector2i(0, 1), TerrainDB.VINES], [Vector2i(1, 1), TerrainDB.TREE]]))
	t.eq(edge.summon_tree(edge.unit_by_uid(1), Vector2i(0, 0)).max_hp, 23, "角落统计地图内三个邻格")
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
