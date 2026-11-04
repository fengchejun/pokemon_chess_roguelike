extends RefCounted


func run(t: TestContext) -> void:
	t.begin("岩系扩充技能池")
	_definition_and_learning(t)
	_attack_obstacle_rule(t)
	_mountain_chain(t)
	_mountain_form(t)
	_guard_rock(t)
	_rock_blast(t)
	_water_drop_stone(t)
	_imprint(t)
	t.finish()


func _definition_and_learning(t: TestContext) -> void:
	var expected := ["imprint", "mountain_chain", "mountain_form", "guard_rock", "rock_blast", "water_drop_stone"]
	for skill_id in expected:
		t.check(not SkillDB.get_def(skill_id).is_empty(), "%s 有技能定义" % skill_id)
		t.check(SkillDB.ROCK_SKILL_POOL.has(skill_id), "%s 进入岩系技能池" % skill_id)
		t.eq(SkillDB.element_of(skill_id), "rock", "%s 为岩系技能" % skill_id)
	for skill_id in ["imprint", "mountain_chain", "guard_rock", "rock_blast", "water_drop_stone"]:
		t.check(SkillDB.learnable_ids_for("rock").has(skill_id), "%s 进入岩系普通学习池" % skill_id)
		t.check(not SpeciesDB.skills_of("rock_starter").has(skill_id), "%s 不自动加入初始技能表" % skill_id)
	t.check(not SkillDB.is_special("imprint"), "拓印是岩系普通技能")
	t.check(not SkillDB.special_ids_for("rock").has("imprint"), "拓印不出现在岩系特殊技能列表")
	t.check(not SkillDB.is_copyable("imprint"), "拓印不能被另一拓印复制，避免递归")
	t.check(SkillDB.is_special("mountain_form"), "山岳形态归为特殊技能")
	t.check(SkillDB.special_ids_for("rock").has("mountain_form"), "山岳形态出现在岩系特殊技能列表")
	t.check(not SkillDB.learnable_ids_for("rock").has("mountain_form"), "山岳形态不能通过普通学习池获得")
	t.check(not SkillDB.is_copyable("mountain_form"), "山岳形态不能被拓印复制")
	t.check(not SkillDB.is_special("guard_rock"), "守岩是普通技能")
	t.check(SkillDB.has_tag("mountain_chain", "continuous"), "山脉连袭标记为连续伤害")
	t.eq(RunState.upgrade_id_for_skill("imprint"), "imprint_mastery", "拓印拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("mountain_chain"), "mountain_chain_segments", "山脉连袭拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("mountain_form"), "mountain_form_radius", "山岳形态拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("guard_rock"), "guard_rock_reinforcement", "守岩拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("rock_blast"), "rock_blast_damage", "岩爆弹拥有专属强化")
	t.eq(RunState.upgrade_id_for_skill("water_drop_stone"), "water_drop_stone_damage", "水滴石穿拥有专属强化")


func _attack_obstacle_rule(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 3), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(5, 3)]], terrain)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	t.check(not _has_unit(state.skill_targets(caster, "rock_blast"), 100), "岩爆弹被中间岩石阻挡")
	var water_drop := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
		[Vector2i(3, 3), TerrainDB.OBSTACLE],
	]))
	var water_caster := water_drop.unit_by_uid(1)
	water_caster.cell = Vector2i(1, 3)
	water_caster.skills.append("water_drop_stone")
	t.check(_has_unit(water_drop.skill_targets(water_caster, "water_drop_stone"), 100), "水滴石穿以连续岩石格延伸射程")


func _mountain_chain(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(1, 2), TerrainDB.OBSTACLE],
		[Vector2i(2, 2), TerrainDB.OBSTACLE],
		[Vector2i(3, 2), TerrainDB.OBSTACLE],
	])
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	caster.skills.append("mountain_chain")
	target.hp = 500
	target.max_hp = 500
	t.eq(SkillResolver.mountain_chain_segment_count(state, caster), 5, "基础 2 段加周围三格岩石")
	var result := state.cast_skill(caster, "mountain_chain", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "山脉连袭成功施放")
	t.eq((result["hits"] as Array).size(), 5, "连续伤害逐段进入结算")
	t.eq(target.hp, 480, "五段各四点，合计二十点伤害")
	for hit in result["hits"]:
		t.eq(int(hit.get("damage", 0)), 4, "每段独立结算")
		t.check(bool(hit.get("continuous", false)), "每段带有连续伤害标记")
	t.eq(caster.last_skill_id, "mountain_chain", "山脉连袭记录为最后使用技能")
	var empty := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var empty_caster := empty.unit_by_uid(1)
	empty_caster.cell = Vector2i(2, 3)
	t.eq(SkillResolver.mountain_chain_segment_count(empty, empty_caster), 2, "无岩石时固定两段")
	var upgraded := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.cell = Vector2i(2, 3)
	upgraded_caster.upgrades["mountain_chain_segments"] = 1
	t.eq(SkillResolver.mountain_chain_segment_count(upgraded, upgraded_caster), 6, "强化后基础段数加一")


func _mountain_form(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	ally.cell = Vector2i(3, 3)
	caster.hp = 100
	caster.max_hp = 100
	ally.hp = 50
	ally.max_hp = 50
	caster.skills.append("mountain_form")
	var result := state.cast_skill(caster, "mountain_form", {"type": "cell", "cell": caster.cell})
	t.check(bool(result.get("ok", false)), "山岳形态以自身发动")
	t.eq(caster.mountain_form_ticks, 1, "山岳形态持续一回合")
	state.damage_unit(enemy, ally, 9, {"no_element": true, "cause": "测试"})
	t.eq(ally.hp, 50, "3×3 内友军不再承担实际伤害")
	t.eq(caster.hp, 94, "友军九点伤害减免为六点并转移给施法者")
	caster.burn_ticks = 2
	t.check(state.clear_debuff_status(caster), "解药可清除异常状态")
	t.eq(caster.mountain_form_ticks, 1, "解药不会清除山岳形态")
	state.settle_round()
	t.eq(caster.mountain_form_ticks, 0, "整轮结束移除山岳形态")

	var self_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var self_caster := self_state.unit_by_uid(1)
	var attacker := self_state.unit_by_uid(100)
	self_caster.cell = Vector2i(2, 3)
	self_caster.hp = 100
	self_caster.max_hp = 100
	self_caster.skills.append("mountain_form")
	self_state.cast_skill(self_caster, "mountain_form", {"type": "cell", "cell": self_caster.cell})
	self_state.damage_unit(attacker, self_caster, 12, {"no_element": true, "cause": "测试"})
	t.eq(self_caster.hp, 92, "自身十二点伤害减免三分之一为八点")

	var outside := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var form_caster := outside.unit_by_uid(1)
	var far_ally := outside.unit_by_uid(2)
	var outside_attacker := outside.unit_by_uid(100)
	form_caster.cell = Vector2i(2, 3)
	far_ally.cell = Vector2i(6, 3)
	form_caster.hp = 100
	far_ally.hp = 50
	form_caster.skills.append("mountain_form")
	outside.cast_skill(form_caster, "mountain_form", {"type": "cell", "cell": form_caster.cell})
	outside.damage_unit(outside_attacker, far_ally, 5, {"no_element": true, "cause": "测试"})
	t.eq(far_ally.hp, 45, "3×3 外友军不受吸收")
	t.eq(form_caster.hp, 100, "范围外伤害不会转移")
	var loaded := BattleSnapshot.load_state(BattleSnapshot.save_state(outside))
	t.eq(loaded.unit_by_uid(1).mountain_form_ticks, form_caster.mountain_form_ticks, "山岳形态随战场快照保存")
	var upgraded := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(3, 2)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_ally := upgraded.unit_by_uid(2)
	var upgraded_enemy := upgraded.unit_by_uid(100)
	upgraded_caster.cell = Vector2i(2, 3)
	upgraded_ally.cell = Vector2i(4, 3)
	upgraded_caster.upgrades["mountain_form_radius"] = 1
	upgraded_caster.skills.append("mountain_form")
	upgraded.cast_skill(upgraded_caster, "mountain_form", {"type": "cell", "cell": upgraded_caster.cell})
	t.eq(SkillResolver.mountain_form_area(upgraded_caster).size(), 25, "强化后覆盖五乘五")
	var ally_hp := upgraded_ally.hp
	upgraded.damage_unit(upgraded_enemy, upgraded_ally, 9, {"no_element": true, "cause": "测试"})
	t.eq(upgraded_ally.hp, ally_hp, "强化范围可吸收五乘五内友军伤害")


func _guard_rock(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 5), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["rock_starter", "water_starter"], [
		["rock_wild1", Vector2i(3, 2)],
		["rock_wild1", Vector2i(4, 3)],
		["rock_wild1", Vector2i(3, 4)],
		["rock_wild1", Vector2i(2, 3)],
		["rock_wild1", Vector2i(4, 2)],
	], terrain)
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	caster.cell = Vector2i(1, 3)
	ally.cell = Vector2i(3, 3)
	caster.skills.append("guard_rock")
	t.check(_has_unit(state.skill_targets(caster, "guard_rock"), caster.uid), "守岩可选择自己")
	t.check(_has_unit(state.skill_targets(caster, "guard_rock"), ally.uid), "守岩可选择曼哈顿三格内友军")
	t.check(not _has_unit(state.skill_targets(caster, "guard_rock"), 100), "守岩不能选择敌人")
	ally.cell = Vector2i(1, 7)
	t.check(not _has_unit(state.skill_targets(caster, "guard_rock"), ally.uid), "守岩不能选择曼哈顿四格友军")
	ally.cell = Vector2i(3, 3)

	var result := state.cast_skill(caster, "guard_rock", {"type": "unit", "unit": ally.uid, "cell": ally.cell})
	t.check(bool(result.get("ok", false)), "守岩成功施放")
	t.eq(ally.shield_hp, Balance.GUARD_ROCK_SHIELD, "守岩施加十点护盾")
	t.eq(ally.shield_ticks, Balance.SHIELD_TICKS, "护盾持续两回合")
	t.eq(ally.shield_source_uid, caster.uid, "护盾记录施法者")
	var snapshot := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(snapshot.unit_by_uid(ally.uid).shield_hp, 10, "护盾耐久随战场快照保存")
	t.eq(snapshot.unit_by_uid(ally.uid).shield_ticks, 2, "护盾回合数随战场快照保存")

	var ally_hp := ally.hp
	var enemy_hp_before := {}
	for uid in [100, 101, 102, 103, 104]:
		enemy_hp_before[uid] = state.unit_by_uid(uid).hp
	var obstacle_hp := int(state.obstacle_durability.get(Vector2i(3, 5), 0))
	var partial := state.damage_unit(state.unit_by_uid(100), ally, 4, {"no_element": true, "cause": "测试"})
	t.eq(ally.hp, ally_hp, "护盾完整抵挡四点伤害")
	t.eq(ally.shield_hp, 6, "护盾耐久扣除四点")
	t.eq(int(partial.get("shield_absorbed", 0)), 4, "伤害结果记录护盾吸收量")
	t.check(not bool(partial.get("shield_broken", true)), "护盾未耗尽时不会触发破盾冲击")

	var broken := state.damage_unit(state.unit_by_uid(100), ally, 8, {"no_element": true, "cause": "测试"})
	t.check(bool(broken.get("shield_broken", false)), "护盾耗尽后被破坏")
	t.eq(int(broken.get("shield_absorbed", 0)), 6, "破盾前吸收剩余六点伤害")
	t.eq(int(broken.get("amount", 0)), 2, "超过护盾的两点伤害作用于生命")
	t.eq(ally.hp, ally_hp - 2, "超出护盾的两点伤害继续作用于生命")
	t.eq(ally.shield_hp, 0, "破坏后的护盾耐久归零")
	t.eq(ally.shield_ticks, 0, "破坏后的护盾不再计时")
	t.eq((broken.get("shield_burst_hits", []) as Array).size(), 4, "破盾冲击命中四邻格四名敌人")
	for uid in [100, 101, 102, 103]:
		t.eq(state.unit_by_uid(uid).hp, int(enemy_hp_before[uid]) - 4, "破盾对四邻格敌人造成四点伤害")
	t.eq(state.unit_by_uid(104).hp, int(enemy_hp_before[104]), "破盾不影响斜角敌人")
	t.eq(int(state.obstacle_durability.get(Vector2i(3, 5), 0)), obstacle_hp, "破盾冲击不伤害障碍")

	var refreshed := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var refresh_caster := refreshed.unit_by_uid(1)
	var refresh_ally := refreshed.unit_by_uid(2)
	refresh_caster.cell = Vector2i(1, 3)
	refresh_ally.cell = Vector2i(2, 3)
	refreshed.apply_guard_rock_shield(refresh_ally, 10, refresh_caster.uid)
	refreshed.apply_guard_rock_shield(refresh_ally, 10, refresh_caster.uid)
	t.eq(refresh_ally.shield_hp, 10, "重复施放不会叠加护盾耐久")
	t.eq(refresh_ally.shield_ticks, 2, "重复施放刷新护盾回合")
	refreshed.settle_round()
	t.eq(refresh_ally.shield_ticks, 1, "第一次整轮结束后护盾剩余一回合")
	refreshed.settle_round()
	t.eq(refresh_ally.shield_hp, 0, "两回合后未被破坏的护盾消失")

	var upgraded := TestScenario.make_state(["rock_starter", "water_starter"], [["rock_wild1", Vector2i(7, 7)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_ally := upgraded.unit_by_uid(2)
	upgraded_caster.cell = Vector2i(1, 3)
	upgraded_ally.cell = Vector2i(2, 3)
	upgraded_caster.skills.append("guard_rock")
	upgraded_caster.upgrades["guard_rock_shield_bonus"] = 5
	upgraded.cast_skill(upgraded_caster, "guard_rock", {"type": "unit", "unit": upgraded_ally.uid, "cell": upgraded_ally.cell})
	t.eq(upgraded_ally.shield_hp, 15, "磐岩加固将护盾提高至十五点")


func _rock_blast(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [
		["rock_wild1", Vector2i(5, 3)],
		["rock_wild1", Vector2i(5, 2)],
		["rock_wild1", Vector2i(5, 4)],
	])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	var upper := state.unit_by_uid(101)
	var lower := state.unit_by_uid(102)
	caster.cell = Vector2i(2, 3)
	caster.skills.append("rock_blast")
	target.hp = 50
	target.max_hp = 50
	t.check(_has_unit(state.skill_targets(caster, "rock_blast"), target.uid), "岩爆弹可选择正交三格敌人")
	var result := state.cast_skill(caster, "rock_blast", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "岩爆弹成功施放")
	t.eq(target.hp, 38, "主弹造成十二点伤害")
	t.eq(target.cell, Vector2i(6, 3), "主弹命中后推后一格")
	t.eq(upper.hp, upper.max_hp - 3, "垂直上方首个单位受到三伤害")
	t.eq(lower.hp, lower.max_hp - 3, "垂直下方首个单位受到三伤害")
	t.eq((result["hits"] as Array).size(), 3, "主弹和两侧分裂分别结算")
	target.cell = Vector2i(7, 3)
	t.check(not _has_unit(state.skill_targets(caster, "rock_blast"), target.uid), "岩爆弹不能攻击三格外的敌人")
	var upgraded := TestScenario.make_state(["rock_starter"], [
		["rock_wild1", Vector2i(5, 3)],
		["rock_wild1", Vector2i(5, 2)],
	])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_target := upgraded.unit_by_uid(100)
	var upgraded_fragment := upgraded.unit_by_uid(101)
	upgraded_caster.cell = Vector2i(2, 3)
	upgraded_caster.skills.append("rock_blast")
	upgraded_caster.upgrades["rock_blast_damage"] = 5
	upgraded_target.hp = 50
	upgraded_target.max_hp = 50
	upgraded.cast_skill(upgraded_caster, "rock_blast", {"type": "unit", "unit": 100, "cell": upgraded_target.cell})
	t.eq(upgraded_target.hp, 33, "强化主弹造成十七点伤害")
	t.eq(upgraded_fragment.hp, upgraded_fragment.max_hp - 5, "强化分裂弹各提高两点")


func _water_drop_stone(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]])
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 3)
	caster.skills.append("water_drop_stone")
	target.hp = 50
	target.max_hp = 50
	t.check(state.apply_wet(target), "目标获得浸湿")
	t.eq(target.slow_ticks, 2, "浸湿默认持续两回合")
	var result := state.cast_skill(caster, "water_drop_stone", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "水滴石穿成功施放")
	t.eq(int(state.obstacle_durability.get(Vector2i(2, 3), 0)), Balance.OBSTACLE_DURABILITY - 1, "延伸路径岩石耐久减一")
	t.eq(target.hp, 35, "十二点岩系伤害加三点水属性追加伤害")
	t.eq((result["hits"] as Array).size(), 2, "主伤害与浸湿追加独立生效")
	var long_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
		[Vector2i(3, 3), TerrainDB.OBSTACLE],
	]))
	var long_caster := long_state.unit_by_uid(1)
	long_caster.cell = Vector2i(1, 3)
	long_caster.skills.append("water_drop_stone")
	long_state.cast_skill(long_caster, "water_drop_stone", {"type": "unit", "unit": 100, "cell": Vector2i(4, 3)})
	t.eq(int(long_state.obstacle_durability.get(Vector2i(2, 3), 0)), Balance.OBSTACLE_DURABILITY - 1, "第一格岩石扣耐久")
	t.eq(int(long_state.obstacle_durability.get(Vector2i(3, 3), 0)), Balance.OBSTACLE_DURABILITY - 1, "第二格岩石扣耐久")
	var gap := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
		[Vector2i(4, 3), TerrainDB.OBSTACLE],
	])
	var gap_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(5, 3)]], gap)
	var gap_caster := gap_state.unit_by_uid(1)
	gap_caster.cell = Vector2i(1, 3)
	gap_caster.skills.append("water_drop_stone")
	t.check(not _has_unit(gap_state.skill_targets(gap_caster, "water_drop_stone"), 100), "岩石不连续时空地会阻断延伸")
	var upgraded := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_target := upgraded.unit_by_uid(100)
	upgraded_caster.cell = Vector2i(1, 3)
	upgraded_caster.skills.append("water_drop_stone")
	upgraded_caster.upgrades["water_drop_stone_damage"] = 4
	upgraded_target.hp = 50
	upgraded_target.max_hp = 50
	upgraded.apply_wet(upgraded_target)
	upgraded.cast_skill(upgraded_caster, "water_drop_stone", {"type": "unit", "unit": 100, "cell": upgraded_target.cell})
	t.eq(upgraded_target.hp, 29, "强化主伤害十六并追加五点水属性伤害")


func _imprint(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [
		["fire_wild1", Vector2i(4, 3)],
		["rock_wild1", Vector2i(6, 3)],
	])
	var caster := state.unit_by_uid(1)
	var source := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 3)
	caster.hp = 100
	source.hp = 50
	source.max_hp = 50
	caster.skills.append("imprint")
	source.last_skill_id = "fire_seed"
	source.last_skill_from = Vector2i(4, 3)
	source.last_skill_target = {"type": "cell", "cell": Vector2i(6, 3)}
	var source_hp := source.hp
	t.check(_has_unit(state.skill_targets(caster, "imprint"), source.uid), "拓印可选择五格内技能来源")
	var result := state.cast_skill(caster, "imprint", {"type": "unit", "unit": source.uid, "cell": source.cell})
	t.check(bool(result.get("ok", false)), "拓印复制技能并打出")
	t.eq(String(result.get("copied_skill_id", "")), "fire_seed", "拓印读取来源最后使用的火种")
	t.eq(source.hp, source_hp - SkillDB.damage_of("fire_seed"), "复制技能按原方向命中首个单位")
	t.check(not caster.skills.has("fire_seed"), "拓印后不保留复制技能")
	t.eq(caster.last_skill_id, "imprint", "拓印自身仍为最后使用技能")

	var upgraded := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_source := upgraded.unit_by_uid(100)
	upgraded_caster.cell = Vector2i(1, 3)
	upgraded_caster.skills.append("imprint")
	upgraded_source.last_skill_id = "fire_seed"
	upgraded_source.last_skill_upgraded = true
	upgraded_source.last_skill_from = Vector2i(4, 3)
	upgraded_source.last_skill_target = {"type": "cell", "cell": Vector2i(6, 3)}
	t.check(not _has_unit(upgraded.skill_targets(upgraded_caster, "imprint"), upgraded_source.uid), "未强化拓印不能复制已强化技能")
	upgraded_caster.upgrades["imprint_upgraded"] = 1
	t.check(_has_unit(upgraded.skill_targets(upgraded_caster, "imprint"), upgraded_source.uid), "拓印精通后可以复制已强化技能")

	var recursive := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var recursive_caster := recursive.unit_by_uid(1)
	var recursive_source := recursive.unit_by_uid(100)
	recursive_caster.cell = Vector2i(1, 3)
	recursive_caster.skills.append("imprint")
	recursive_source.last_skill_id = "imprint"
	recursive_source.last_skill_from = Vector2i(4, 3)
	recursive_source.last_skill_target = {"type": "unit", "unit": 1, "cell": Vector2i(1, 3)}
	t.check(recursive.skill_targets(recursive_caster, "imprint").is_empty(), "拓印不能复制另一拓印")
	var special := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]])
	var special_caster := special.unit_by_uid(1)
	var special_source := special.unit_by_uid(100)
	special_caster.cell = Vector2i(1, 3)
	special_caster.skills.append("imprint")
	special_source.last_skill_id = "mirror_water_moon"
	special_source.last_skill_from = Vector2i(4, 3)
	special_source.last_skill_target = {"type": "cell", "cell": Vector2i(4, 3)}
	t.check(special.skill_targets(special_caster, "imprint").is_empty(), "拓印不能复制其他特殊技能")

	var blocked := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(4, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.OBSTACLE]]))
	var blocked_caster := blocked.unit_by_uid(1)
	var blocked_source := blocked.unit_by_uid(100)
	blocked_caster.cell = Vector2i(1, 3)
	blocked_caster.skills.append("imprint")
	blocked_source.last_skill_id = "fire_seed"
	blocked_source.last_skill_from = Vector2i(4, 3)
	blocked_source.last_skill_target = {"type": "cell", "cell": Vector2i(6, 3)}
	t.check(blocked.skill_targets(blocked_caster, "imprint").is_empty(), "拓印打出的攻击仍受障碍阻挡")

	var range_ok := TestScenario.make_state(["rock_starter"], [["fire_wild1", Vector2i(6, 3)]])
	var range_caster := range_ok.unit_by_uid(1)
	var range_source := range_ok.unit_by_uid(100)
	range_caster.cell = Vector2i(1, 3)
	range_caster.skills.append("imprint")
	range_source.last_skill_id = "fire_seed"
	range_source.last_skill_from = Vector2i(6, 3)
	range_source.last_skill_target = {"type": "cell", "cell": Vector2i(7, 3)}
	t.check(_has_unit(range_ok.skill_targets(range_caster, "imprint"), range_source.uid), "拓印可选择曼哈顿五格目标")
	range_source.cell = Vector2i(7, 3)
	t.check(not _has_unit(range_ok.skill_targets(range_caster, "imprint"), range_source.uid), "拓印不能选择曼哈顿六格目标")

	var loaded := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(loaded.unit_by_uid(1).last_skill_id, "imprint", "最后技能随战场快照保存")
	t.eq(loaded.unit_by_uid(1).last_skill_target, caster.last_skill_target, "最后技能目标随快照保存")

	var trace := TestScenario.make_state(["electric_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var tracer := trace.unit_by_uid(1)
	tracer.cell = Vector2i(2, 3)
	tracer.skills.append("volt_step")
	trace.cast_skill(tracer, "volt_step", {"type": "cell", "cell": Vector2i(3, 3)})
	t.eq(tracer.last_skill_from, Vector2i(2, 3), "位移技能保留施放前坐标")

	var upgraded_trace := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var upgraded_tracer := upgraded_trace.unit_by_uid(1)
	upgraded_tracer.cell = Vector2i(2, 3)
	upgraded_tracer.skills.append("rock_create")
	upgraded_tracer.upgrades["rock_create_width"] = 4
	upgraded_trace.cast_skill(upgraded_tracer, "rock_create", {"type": "dir", "dir": Vector2i(0, 1), "cell": Vector2i(2, 4)})
	t.check(upgraded_tracer.last_skill_upgraded, "最后技能记录是否已强化")


func _has_unit(entries: Array, uid: int) -> bool:
	for entry in entries:
		if String(entry.get("type", "")) == "unit" and int(entry.get("unit", -1)) == uid:
			return true
		if String(entry.get("type", "")) == "unit_pair" and (entry.get("units", []) as Array).has(uid):
			return true
	return false
