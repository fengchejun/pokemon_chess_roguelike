extends RefCounted


func run(t: TestContext) -> void:
	t.begin("草系技能池扩充：急救、落地生根、叶之风与解药")
	_definition_and_learning(t)
	_first_aid(t)
	_rooted_grass(t)
	_leaf_wind(t)
	_antidote(t)
	_free_exploration_block(t)
	_ai_evaluation(t)
	_ui_display(t)
	t.finish()


func _definition_and_learning(t: TestContext) -> void:
	var expected_upgrades := {
		"first_aid": "first_aid_healing",
		"rooted_grass": "rooted_grass_radius",
		"leaf_wind": "leaf_wind_damage",
		"antidote": "antidote_healing",
	}
	for skill_id in expected_upgrades:
		t.check(not SkillDB.get_def(skill_id).is_empty(), "%s 有技能定义" % skill_id)
		t.check(SkillDB.learnable_ids_for("grass").has(skill_id), "%s 进入草系普通学习池" % skill_id)
		t.check(not SkillDB.is_special(skill_id), "%s 是普通技能" % skill_id)
		t.eq(RunState.upgrade_id_for_skill(skill_id), expected_upgrades[skill_id], "%s 有专属强化" % skill_id)
		t.check(RunState.MONSTER_UPGRADES.has(expected_upgrades[skill_id]), "%s 强化已登记" % skill_id)
	t.check(not SpeciesDB.skills_of("grass_starter").has("first_aid"), "急救不自动进入初始技能表")


func _first_aid(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter", "rock_starter", "water_starter"], [
		["fire_wild1", Vector2i(3, 2)],
	])
	var caster := state.unit_by_uid(1)
	var near_ally := state.unit_by_uid(2)
	var far_ally := state.unit_by_uid(3)
	var enemy := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	near_ally.cell = Vector2i(4, 3)
	far_ally.cell = Vector2i(5, 3)
	caster.hp = caster.max_hp - 20
	near_ally.hp = near_ally.max_hp - 20
	far_ally.hp = far_ally.max_hp - 20
	enemy.hp = enemy.max_hp - 20
	caster.skills.append("first_aid")
	var entries := state.skill_targets(caster, "first_aid")
	t.check(_has_unit_entry(entries, caster.uid), "急救允许选择自己")
	t.check(_has_unit_entry(entries, near_ally.uid), "急救可选择两格内受伤友军")
	t.check(not _has_unit_entry(entries, far_ally.uid), "急救不能选择三格外的友军")
	t.check(not _has_unit_entry(entries, enemy.uid), "急救不能选择敌人")
	var self_hp := caster.hp
	var self_result := state.cast_skill(caster, "first_aid", {"type": "unit", "unit": caster.uid, "cell": caster.cell})
	t.check(bool(self_result.get("ok", false)), "急救可对自己施放")
	t.eq(caster.hp, self_hp + 8, "急救基础恢复八点生命")
	t.check(caster.moved, "急救成功施放后消耗普通移动机会")
	caster.skill_used = false
	caster.moved = false
	var ally_hp := near_ally.hp
	var ally_result := state.cast_skill(caster, "first_aid", {"type": "unit", "unit": near_ally.uid, "cell": near_ally.cell})
	t.check(bool(ally_result.get("ok", false)), "急救可治疗两格内友军")
	t.eq(near_ally.hp, ally_hp + 8, "急救治疗友军八点生命")
	caster.skill_used = false
	caster.moved = false
	near_ally.hp = near_ally.max_hp - 3
	state.cast_skill(caster, "first_aid", {"type": "unit", "unit": near_ally.uid, "cell": near_ally.cell})
	t.eq(near_ally.hp, near_ally.max_hp, "急救不会超过生命上限")
	caster.skill_used = false
	caster.moved = false
	caster.battle_skill_uses.clear()
	caster.upgrades["first_aid_healing"] = 5
	near_ally.hp = near_ally.max_hp - 20
	var upgraded_hp := near_ally.hp
	state.cast_skill(caster, "first_aid", {"type": "unit", "unit": near_ally.uid, "cell": near_ally.cell})
	t.eq(near_ally.hp, upgraded_hp + 13, "急救专属强化将回复量提高到十三点")
	var healthy := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]])
	healthy.unit_by_uid(1).skills.append("first_aid")
	t.check(not _has_unit_entry(healthy.skill_targets(healthy.unit_by_uid(1), "first_aid"), 2), "满血友军不能作为急救目标")


func _rooted_grass(t: TestContext) -> void:
	var center := Vector2i(3, 3)
	var nest_cell := Vector2i(4, 2)
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [
		[Vector2i(2, 3), TerrainDB.OBSTACLE],
		[Vector2i(4, 3), TerrainDB.TREE],
		[Vector2i(3, 2), TerrainDB.WATER],
		[Vector2i(2, 2), TerrainDB.FRAGILE],
		[Vector2i(2, 4), TerrainDB.VINES],
		[Vector2i(4, 4), TerrainDB.GRASS],
	])
	var state := TestScenario.make_state(["grass_starter"], [["fire_wild1", Vector2i(7, 6)]], terrain)
	state.nest["cell"] = nest_cell
	var caster := state.unit_by_uid(1)
	caster.cell = center
	caster.skills.append("rooted_grass")
	t.eq(SkillResolver.rooted_grass_area(caster).size(), 9, "基础落地生根覆盖自身周围 3×3")
	t.eq(SkillResolver.rooted_grass_cells(state, caster).size(), 4, "仅平地、易碎地块与藤蔓会被转换")
	var entries := state.skill_targets(caster, "rooted_grass")
	t.check(entries.size() == 1 and entries[0].get("cell") == center, "落地生根以自身所在格发动")
	var result := state.cast_skill(caster, "rooted_grass", {"type": "cell", "cell": center})
	t.check(bool(result.get("ok", false)), "落地生根成功施放")
	t.eq((result.get("area_cells", []) as Array).size(), 9, "结算反馈包含完整九格范围")
	t.eq((result.get("terrain_changes", []) as Array).size(), 4, "只记录实际发生转换的格子")
	for cell in [center, Vector2i(3, 4), Vector2i(2, 2), Vector2i(2, 4)]:
		t.eq(state.terrain_at(cell), TerrainDB.GRASS, "%s 转为草丛" % str(cell))
	t.eq(state.terrain_at(Vector2i(2, 3)), TerrainDB.OBSTACLE, "障碍不会被覆盖")
	t.eq(state.terrain_at(Vector2i(4, 3)), TerrainDB.TREE, "树木不会被覆盖")
	t.eq(state.terrain_at(Vector2i(3, 2)), TerrainDB.WATER, "水域不会被覆盖")
	t.eq(state.terrain_at(nest_cell), TerrainDB.PLAIN, "巢穴格不会被覆盖")
	t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.GRASS, "原有草丛保持草丛")
	var upgraded := TestScenario.make_state(["grass_starter"], [["fire_wild1", Vector2i(7, 6)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	upgraded_caster.cell = center
	upgraded_caster.skills.append("rooted_grass")
	upgraded_caster.upgrades["rooted_grass_radius"] = 1
	t.eq(SkillResolver.rooted_grass_area(upgraded_caster).size(), 25, "强化后覆盖自身周围 5×5")
	var upgraded_result := upgraded.cast_skill(upgraded_caster, "rooted_grass", {"type": "cell", "cell": center})
	t.eq((upgraded_result.get("terrain_changes", []) as Array).size(), 25, "强化后转换完整二十五格")
	for cell in SkillResolver.rooted_grass_area(upgraded_caster):
		t.eq(upgraded.terrain_at(cell), TerrainDB.GRASS, "5×5 范围内 %s 为草丛" % str(cell))


func _leaf_wind(t: TestContext) -> void:
	_leaf_wind_case(t, TestScenario.plain_terrain(), 0, 8, "普通地面造成八点基础伤害")
	_leaf_wind_case(t, TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.GRASS]]), 0, 12, "施法者位于草丛时造成十二点基础伤害")
	_leaf_wind_case(t, TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.VINES]]), 0, 12, "施法者位于藤蔓时造成十二点基础伤害")
	_leaf_wind_case(t, TestScenario.plain_terrain(), 4, 12, "普通地面强化后造成十二点基础伤害")
	_leaf_wind_case(t, TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(2, 3), TerrainDB.GRASS]]), 4, 16, "草丛强化后造成十六点基础伤害")
	var state := TestScenario.make_state(["grass_starter", "rock_starter"], [["grass_wild1", Vector2i(4, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(3, 4), TerrainDB.OBSTACLE]]))
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	state.unit_by_uid(2).cell = Vector2i(3, 3)
	state.nest["cell"] = Vector2i(3, 2)
	caster.skills.append("leaf_wind")
	var entries := state.skill_targets(caster, "leaf_wind")
	t.check(entries.size() == 2 and _has_unit_entry(entries, 100) and entries.has({"type": "nest", "cell": Vector2i(3, 2)}), "叶之风可选两格内敌人与巢穴，不选择友军与岩障")
	state.unit_by_uid(100).cell = Vector2i(5, 3)
	t.check(not state.skill_targets(caster, "leaf_wind").any(func(entry): return _has_unit_entry([entry], 100)), "叶之风不能选择三格外敌人")


func _leaf_wind_case(t: TestContext, terrain: Array, damage_bonus: int, expected: int, label: String) -> void:
	var state := TestScenario.make_state(["grass_starter"], [["grass_wild1", Vector2i(4, 3)]], terrain)
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	caster.skills.append("leaf_wind")
	if damage_bonus > 0:
		caster.upgrades["leaf_wind_damage"] = damage_bonus
	var hp_before := target.hp
	var result := state.cast_skill(caster, "leaf_wind", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "叶之风成功施放")
	t.eq(target.hp, hp_before - expected, label)


func _antidote(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]])
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	caster.cell = Vector2i(2, 3)
	ally.cell = Vector2i(4, 3)
	ally.hp = ally.max_hp - 10
	ally.burn_ticks = 2
	ally.burn_source_uid = caster.uid
	ally.burn_source_side = "player"
	ally.slow_ticks = 2
	ally.shock_ticks = 2
	ally.paralyzed_ticks = 2
	ally.root_pending = true
	ally.move_cancelled = true
	ally.imprison_ticks = 2
	ally.vine_sources[ally.cell] = 2
	ally.vine_ticks = 2
	ally.vine_reapply_round = state.round + 2
	ally.vine_reapply_cell = ally.cell
	ally.parasite_source_uid = caster.uid
	ally.parasite_source_side = "player"
	ally.frozen = true
	ally.frozen_ticks = 1
	ally.paralyzed_ticks = 2
	ally.haste_ticks = 2
	ally.mirror_until_round = state.round + 2
	ally.battle_buffs["direct_guard"] = true
	caster.skills.append("antidote")
	var entries := state.skill_targets(caster, "antidote")
	t.check(_has_unit_entry(entries, ally.uid), "解药可选择带异常且受伤的两格内友军")
	var hp_before := ally.hp
	var result := state.cast_skill(caster, "antidote", {"type": "unit", "unit": ally.uid, "cell": ally.cell})
	t.check(bool(result.get("ok", false)), "解药成功施放")
	t.check(bool(result.get("status_cleansed", false)), "解药返回异常已清除标记")
	t.eq(ally.hp, hp_before + 3, "解药基础恢复三点生命")
	t.eq(ally.burn_ticks, 0, "解药清除灼烧")
	t.eq(ally.burn_source_uid, -1, "解药清除灼烧来源")
	t.eq(ally.slow_ticks, 0, "解药清除浸湿")
	t.eq(ally.shock_ticks, 0, "解药清除感电")
	t.eq(ally.paralyzed_ticks, 0, "解药清除麻痹")
	t.check(not ally.root_pending and not ally.move_cancelled, "解药清除定身")
	t.eq(ally.imprison_ticks, 0, "解药清除禁锢")
	t.eq(ally.vine_ticks, 0, "解药清除藤蔓束缚")
	t.check(ally.vine_sources.is_empty(), "解药清空藤蔓束缚来源")
	t.eq(ally.vine_reapply_round, 0, "解药取消藤蔓延迟触发")
	t.eq(ally.parasite_source_uid, -1, "解药清除寄生")
	t.check(ally.frozen, "解药不会解除冰冻")
	t.eq(ally.frozen_ticks, 1, "解药保留冰冻剩余回合")
	t.eq(ally.haste_ticks, 2, "解药保留正向加速状态")
	t.eq(ally.mirror_until_round, state.round + 2, "解药保留镜花水月")
	t.check(ally.has_buff("direct_guard"), "解药保留正向战斗 Buff")
	t.check(caster.moved, "解药成功施放后消耗普通移动机会")
	var frozen_only := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]])
	frozen_only.unit_by_uid(1).cell = Vector2i(2, 3)
	frozen_only.unit_by_uid(2).cell = Vector2i(4, 3)
	frozen_only.unit_by_uid(1).skills.append("antidote")
	frozen_only.unit_by_uid(2).frozen = true
	t.check(not _has_unit_entry(frozen_only.skill_targets(frozen_only.unit_by_uid(1), "antidote"), 2), "满血且仅有冰冻的友军不是有效目标")
	var frozen_injured := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]])
	var frozen_caster := frozen_injured.unit_by_uid(1)
	var frozen_ally := frozen_injured.unit_by_uid(2)
	frozen_caster.cell = Vector2i(2, 3)
	frozen_ally.cell = Vector2i(4, 3)
	frozen_ally.hp = frozen_ally.max_hp - 10
	frozen_ally.frozen = true
	frozen_caster.skills.append("antidote")
	var frozen_hp := frozen_ally.hp
	frozen_injured.cast_skill(frozen_caster, "antidote", {"type": "unit", "unit": frozen_ally.uid, "cell": frozen_ally.cell})
	t.check(frozen_ally.frozen, "受伤的冰冻友军可接受解药治疗但不会解冻")
	t.eq(frozen_ally.hp, frozen_hp + 3, "冰冻目标仍获得解药生命回复")
	var upgraded := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]])
	var upgraded_caster := upgraded.unit_by_uid(1)
	var upgraded_ally := upgraded.unit_by_uid(2)
	upgraded_caster.cell = Vector2i(2, 3)
	upgraded_ally.cell = Vector2i(4, 3)
	upgraded_ally.hp = upgraded_ally.max_hp - 20
	upgraded_ally.burn_ticks = 2
	upgraded_caster.skills.append("antidote")
	upgraded_caster.upgrades["antidote_healing"] = 5
	var upgraded_hp := upgraded_ally.hp
	upgraded.cast_skill(upgraded_caster, "antidote", {"type": "unit", "unit": upgraded_ally.uid, "cell": upgraded_ally.cell})
	t.eq(upgraded_ally.hp, upgraded_hp + 8, "解药专属强化将回复量提高到八点")
	var self_state := TestScenario.make_state(["grass_starter"], [["fire_wild1", Vector2i(3, 2)]])
	var self_caster := self_state.unit_by_uid(1)
	self_caster.cell = Vector2i(2, 3)
	self_caster.hp = self_caster.max_hp - 5
	self_caster.burn_ticks = 2
	self_caster.skills.append("antidote")
	t.check(_has_unit_entry(self_state.skill_targets(self_caster, "antidote"), self_caster.uid), "解药允许选择自己")
	var self_hp := self_caster.hp
	self_state.cast_skill(self_caster, "antidote", {"type": "unit", "unit": self_caster.uid, "cell": self_caster.cell})
	t.eq(self_caster.burn_ticks, 0, "对自己使用解药可清除异常")
	t.eq(self_caster.hp, self_hp + 3, "对自己使用解药可恢复生命")
	var vine_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.VINES]])
	var vine_state := TestScenario.make_state(["grass_starter", "rock_starter"], [["fire_wild1", Vector2i(3, 2)]], vine_terrain)
	var vine_caster := vine_state.unit_by_uid(1)
	var vine_ally := vine_state.unit_by_uid(2)
	vine_caster.cell = Vector2i(2, 3)
	vine_ally.cell = Vector2i(4, 3)
	vine_ally.imprison_ticks = 2
	vine_caster.skills.append("antidote")
	vine_state.cast_skill(vine_caster, "antidote", {"type": "unit", "unit": vine_ally.uid, "cell": vine_ally.cell})
	t.eq(vine_ally.imprison_ticks, 0, "解药立即解除藤蔓格上的禁锢")
	t.eq(vine_ally.vine_reapply_round, vine_state.round + 2, "停留在藤蔓格时重新安排隔回合触发")
	t.eq(vine_ally.vine_reapply_cell, vine_ally.cell, "延迟触发记录净化后的当前藤蔓格")


func _free_exploration_block(t: TestContext) -> void:
	var state := TestScenario.make_state(["grass_starter", "rock_starter"], [])
	var caster := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	caster.cell = Vector2i(2, 3)
	ally.cell = Vector2i(4, 3)
	caster.hp = caster.max_hp - 10
	ally.hp = ally.max_hp - 10
	ally.burn_ticks = 2
	caster.skills.append("first_aid")
	caster.skills.append("antidote")
	state.node_kind = "event"
	t.check(state.recovery_skill_blocked("first_aid"), "自由探索禁用急救")
	t.check(state.recovery_skill_blocked("antidote"), "自由探索禁用解药")
	t.check(state.skill_targets(caster, "first_aid").is_empty(), "自由探索中急救没有有效目标")
	t.check(state.skill_targets(caster, "antidote").is_empty(), "自由探索中解药没有有效目标")


func _ai_evaluation(t: TestContext) -> void:
	var heal_state := TestScenario.make_state(["rock_starter"], [["grass_wild1", Vector2i(6, 3)]])
	var healer := heal_state.unit_by_uid(100)
	healer.hp -= 10
	var heal_before := heal_state.clone()
	var heal_after := heal_state.clone()
	heal_after.unit_by_uid(100).hp += 8
	t.check(int(EnemyAI._score(heal_before, heal_after, 100)["total"]) > 0, "AI 会评估急救的友方治疗收益")
	var cleanse_state := TestScenario.make_state(["rock_starter"], [
		["grass_wild1", Vector2i(5, 3)],
		["grass_wild1", Vector2i(6, 3)],
	])
	var cleanse_target := cleanse_state.unit_by_uid(101)
	cleanse_target.burn_ticks = 2
	cleanse_target.imprison_ticks = 2
	var cleanse_before := cleanse_state.clone()
	var cleanse_after := cleanse_state.clone()
	cleanse_after.clear_debuff_status(cleanse_after.unit_by_uid(101))
	t.check(int(EnemyAI._score(cleanse_before, cleanse_after, 100)["total"]) > 0, "AI 会评估解药清除异常的收益")
	var grass_state := TestScenario.make_state(["rock_starter"], [["grass_wild1", Vector2i(4, 3)]])
	var grass_caster := grass_state.unit_by_uid(100)
	grass_caster.skills = ["rooted_grass", "leaf_wind"]
	var grass_before := grass_state.clone()
	var grass_after := grass_state.clone()
	for cell in SkillResolver.rooted_grass_area(grass_after.unit_by_uid(100)):
		grass_after.set_terrain(cell, TerrainDB.GRASS)
	t.check(int(EnemyAI._score(grass_before, grass_after, 100)["total"]) > 0, "AI 会评估落地生根为叶之风铺地的收益")


func _ui_display(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(6201)
	var state := TestScenario.make_state(["grass_starter"], [["fire_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills.append("rooted_grass")
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	screen.action_mode = "skills"
	screen._on_skill_pressed("rooted_grass")
	t.eq(screen.board.area_cells.size(), 9, "落地生根瞄准时显示基础九格范围")
	var button: Button = screen.skill_box.find_child("SkillButton_rooted_grass", true, false)
	t.check(button != null and button.text.contains("3×3"), "技能栏显示基础 3×3 范围")
	screen._clear_aim()
	caster.upgrades["rooted_grass_radius"] = 1
	screen.action_mode = "skills"
	screen._on_skill_pressed("rooted_grass")
	t.eq(screen.board.area_cells.size(), 25, "落地生根强化后瞄准时显示二十五格范围")
	button = screen.skill_box.find_child("SkillButton_rooted_grass", true, false)
	t.check(button != null and button.text.contains("5×5"), "技能栏显示强化后 5×5 范围")
	app.queue_free()


func _has_unit_entry(entries: Array, uid: int) -> bool:
	return entries.any(func(entry): return String(entry.get("type", "")) == "unit" and int(entry.get("unit", -1)) == uid)
