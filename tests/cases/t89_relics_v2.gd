extends RefCounted


func run(t: TestContext) -> void:
	t.begin("新版57项遗物、获取与核心触发")
	_catalog(t)
	_acquisition(t)
	_damage_and_status(t)
	_terrain_and_collision(t)
	_summoning_and_magic(t)
	_legendary_and_risk(t)
	_merchant_and_save(t)
	t.finish()


func _state(species: Array, enemies: Array, relics: Dictionary, terrain: Array = [], seed_value: int = 8901) -> BattleState:
	return TestScenario.make_state(species, enemies, terrain, {}, {}, [], seed_value, relics)


func _catalog(t: TestContext) -> void:
	t.eq(RelicDB.DEFINITIONS.size(), 57, "遗物总数为57")
	var counts := {"common": 0, "rare": 0, "legendary": 0}
	var categories := {}
	for relic_id in RelicDB.DEFINITIONS:
		var definition: Dictionary = RelicDB.DEFINITIONS[relic_id]
		var rarity := String(definition.get("rarity", ""))
		counts[rarity] = int(counts.get(rarity, 0)) + 1
		categories[String(definition.get("category", ""))] = true
		t.check(String(definition.get("name", "")) != "" and String(definition.get("description", "")) != "", "%s有名称和说明" % relic_id)
	t.eq(counts["common"], 26, "普通遗物26项")
	t.eq(counts["rare"], 21, "稀有遗物21项")
	t.eq(counts["legendary"], 10, "传奇遗物10项")
	t.eq(categories.size(), 7, "遗物覆盖7个机制类型")
	var offered := RelicDB.offer(8901, 0, 0, {})
	t.eq(offered.size(), 3, "奖励提供三个候选")
	t.eq({String(offered[0]): true, String(offered[1]): true, String(offered[2]): true}.size(), 3, "候选不重复")
	t.check(RelicDB.all_normal_skills_for_element("fire").has("fire_burst"), "法师笔记技能池包含物种基础普通技能")


func _acquisition(t: TestContext) -> void:
	var base_pool := RelicDB.available_ids({})
	t.check(base_pool.has("holy_shield_fragment"), "圣盾碎片可初始抽取")
	t.check(not base_pool.has("nameless_shield"), "无名盾牌需要前置")
	var upgraded_pool := RelicDB.available_ids({"holy_shield_fragment": 1})
	t.check(upgraded_pool.has("nameless_shield"), "持有前置后无名盾牌进入池")
	t.check(not upgraded_pool.has("holy_shield_fragment"), "可进化前置不再重复提供")
	var run := RunState.new_run(8910)
	run.pending_reward_choices = 1
	var offered := String(run.reward_choices()[0])
	t.check(run.choose_reward(offered), "战后可领取遗物")
	t.eq(int(run.relic_stacks.get(offered, 0)), 1, "遗物写入本局")
	t.eq(run.pending_reward_choices, 0, "领取消耗一次机会")
	t.check(not run.choose_reward(offered), "同一遗物无法重复领取")
	run.relic_stacks["holy_shield_fragment"] = 1
	t.check(run.upgrade_relic("holy_shield_fragment", "nameless_shield"), "前置满足时执行进化")
	t.check(not run.relic_stacks.has("holy_shield_fragment"), "进化替换前置")
	t.check(run.relic_stacks.has("nameless_shield"), "进化获得升级版")
	var malformed := run.to_dict()
	malformed["relic_stacks"] = {"holy_shield_fragment": 1, "nameless_shield": 1, "dawn_lord_radiance": 1}
	var normalized := RunState.from_dict(malformed)
	t.eq(normalized.relic_stacks.size(), 1, "异常进化存档只保留一个等级")
	t.check(normalized.relic_stacks.has("dawn_lord_radiance"), "异常进化存档保留最高级")
	var notes_run := RunState.new_run(8911)
	notes_run.carried = [notes_run.carried[0]]
	t.check(notes_run.acquire_relic("mage_notes", "test"), "法师笔记进入待处理队列")
	var note_uids := notes_run.mage_note_eligible_uids()
	t.check(bool(notes_run.resolve_mage_notes(note_uids).get("ok", false)), "合格成员不足3名时法师笔记仍可结算")
	t.check(not notes_run.has_pending_relic_actions(), "法师笔记处理后清除待办")
	var heal_run := RunState.new_run(8912)
	heal_run.carried[0]["hp"] = 0
	t.check(heal_run.acquire_relic("bottled_dragon_blood", "test"), "瓶装龙血可即时领取")
	t.eq(int(heal_run.carried[0]["hp"]), 0, "即时生命恢复不复活濒死成员")
	var pp_sync_run := RunState.new_run(8913)
	var pp_record := pp_sync_run.record_by_uid(1)
	pp_record["known_skills"] = ["fire_burst"]
	pp_record["equipped_skills"] = ["fire_burst"]
	pp_record["skill_pp_uses"] = {"fire_burst": 2}
	var pp_units := pp_sync_run.build_deploy_units([1])
	var pp_battle := BattleState.new()
	pp_battle.setup(TestScenario.make_map(TestScenario.plain_terrain()), {"enemies": []}, 8913, 0, pp_units, {}, {}, [])
	pp_sync_run.acquire_relic("sealed_necronomicon", "test")
	pp_sync_run.sync_relic_effects_to_battle(pp_battle)
	t.eq(pp_battle.unit_by_uid(1).pp_used("fire_burst"), 6, "即时遗物PP变化同步到当前战斗")
	var hp_sync_run := RunState.new_run(8914)
	var hp_units := hp_sync_run.build_deploy_units([1])
	var hp_battle := BattleState.new()
	hp_battle.setup(TestScenario.make_map(TestScenario.plain_terrain()), {"enemies": []}, 8914, 0, hp_units, {}, {}, [])
	var hp_before_orb := int(hp_sync_run.carried[0]["hp"])
	hp_sync_run.acquire_relic("blood_orb", "test")
	hp_sync_run.sync_relic_effects_to_battle(hp_battle)
	t.check(int(hp_sync_run.carried[0]["hp"]) < hp_before_orb, "鲜血宝珠降低本局记录生命")
	t.eq(hp_battle.unit_by_uid(1).hp, int(hp_sync_run.carried[0]["hp"]), "即时遗物生命变化同步到当前战斗")


func _damage_and_status(t: TestContext) -> void:
	var plain := _state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], {})
	var target := plain.unit_by_uid(100)
	target.hp = 100
	target.max_hp = 100
	var normal := int(plain.damage_unit(plain.unit_by_uid(1), target, 10, {
		"skill_direct": true, "element": "fire", "skill_id": "flame_jet",
	}).get("amount", 0))
	var boosted := _state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], {"fire_carbon": 1})
	var boosted_target := boosted.unit_by_uid(100)
	boosted_target.hp = 100
	boosted_target.max_hp = 100
	var carbon := int(boosted.damage_unit(boosted.unit_by_uid(1), boosted_target, 10, {
		"skill_direct": true, "element": "fire", "skill_id": "flame_jet",
	}).get("amount", 0))
	t.eq(carbon, roundi(normal * 1.30), "火之碳提高火属性伤害30%")
	var mountains := _state(["rock_starter"], [["water_wild1", Vector2i(5, 5)]], {"layered_mountains": 1})
	mountains.set_terrain(Vector2i(3, 3), TerrainDB.OBSTACLE)
	mountains.obstacle_durability[Vector2i(3, 3)] = 2
	var mountain_target := mountains.unit_by_uid(100)
	mountain_target.max_hp = 100
	mountain_target.hp = 100
	var mountain_damage := int(mountains.damage_unit(mountains.unit_by_uid(1), mountain_target, 10, {
		"skill_direct": true, "no_element": true, "skill_id": "probe",
	}).get("amount", 0))
	t.eq(mountain_damage, 11, "山峦叠嶂按岩系宝可梦和岩石格数量增伤")
	var berry_battle := _state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], {"healing_berry": 1})
	t.check(not berry_battle.fruits.is_empty(), "治愈莓果在战斗中生成")
	var berry_event := TestScenario.make_state(
		["water_starter"], [], [], {}, {}, [], 8902, {"healing_berry": 1}, "event"
	)
	t.check(berry_event.fruits.is_empty(), "治愈莓果不在和平收集区生成")

	var cloak := _state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]], {"white_cloak": 1})
	var cloaked_player := cloak.unit_by_uid(1)
	cloaked_player.cell = Vector2i(3, 3)
	t.check(not cloak.apply_burn(cloaked_player, null), "纯白斗篷免疫第一次异常")
	cloak.apply_burn(cloaked_player, null)
	t.check(cloaked_player.burn_ticks > 0, "纯白斗篷只免疫一次")

	var sorrow := _state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]], {"sorrow": 1})
	var wet_target := sorrow.unit_by_uid(100)
	sorrow.apply_wet(wet_target)
	sorrow.apply_wet(wet_target)
	sorrow.apply_wet(wet_target)
	t.check(wet_target.frozen, "悲伤在第3层浸湿时转为冰冻")

	var echo := _state(["electric_starter"], [["water_wild1", Vector2i(4, 3)]], {"electric_echo": 1})
	var echo_target := echo.unit_by_uid(100)
	echo.apply_shock(echo_target)
	t.eq(echo_target.shock_layers, 2, "电能回响一次电系施加2层感电")
	echo.apply_shock(echo_target)
	t.eq(echo_target.shock_layers, 0, "第4层感电清空")
	t.check(bool(echo.relic_state.get("electric_echo_active", false)), "感电引爆后激活电系增伤")

	var soul := _state(["fire_starter"], [["water_wild1", Vector2i(4, 3)]], {"sun_totem": 1})
	var soul_target := soul.unit_by_uid(100)
	soul_target.hp = 100
	soul_target.max_hp = 100
	for index in 5:
		soul.apply_burn(soul_target, soul.unit_by_uid(1))
	t.check(soul_target.burn_ticks == 0 and soul_target.hp < 100, "太阳图腾在5层时引爆灼烧")
	var blue_flame := _state(["fire_starter"], [["water_wild1", Vector2i(5, 5)]], {"dragon_blue_flame": 1})
	var blue_caster := blue_flame.unit_by_uid(1)
	var blue_target := blue_flame.unit_by_uid(100)
	blue_flame.burning_cells[blue_caster.cell] = 2
	blue_target.max_hp = 100
	blue_target.hp = 100
	SkillResolver._hit_entry(blue_flame, blue_caster, "fire_burst", blue_target, 10)
	t.check(blue_target.burn_ticks > 0, "龙脉蓝焰使任意火系命中附加灼烧")

	var wound := _state(["fire_starter"], [["water_wild1", Vector2i(4, 3)]], {"thorn_mark": 1})
	var wounded := wound.unit_by_uid(100)
	wounded.max_hp = 100
	wounded.hp = 50
	wound.apply_imprison(wounded)
	t.eq(wound.relic_heal(wounded, 10), 7, "荆之印记使重伤目标治疗降低30%")


func _terrain_and_collision(t: TestContext) -> void:
	var obelisk := _state(["rock_starter"], [], {"terrain_obelisk": 1})
	var obelisk_unit := obelisk.unit_by_uid(1)
	obelisk_unit.cell = Vector2i(3, 3)
	obelisk.set_terrain(obelisk_unit.cell, TerrainDB.GRASS)
	t.check(obelisk_unit.shield_hp >= ceili(obelisk_unit.max_hp * 0.10), "地势方尖碑为新地形上的友军提供护盾")

	var sapphire := _state(["water_starter"], [], {"deep_sapphire": 1})
	var cell := Vector2i(2, 3)
	for index in 3:
		sapphire.set_terrain(cell, TerrainDB.WATER)
	t.eq(sapphire.terrain_at(cell), TerrainDB.DEEP, "深蓝宝石把第3次浅水转换为深水")

	var rope := _state(["grass_starter"], [], {"leyline_rope": 1})
	var vine_cell := Vector2i(3, 3)
	rope.place_temp_vines(vine_cell)
	t.check(not rope.vine_expire_round.has(vine_cell), "系脉绳使临时藤蔓永久")

	var collision := _state(["rock_starter"], [["water_wild1", Vector2i(3, 3)]], {
		"collision_expert": 1, "impact_code": 1,
	})
	var bumper := collision.unit_by_uid(100)
	bumper.cell = Vector2i(3, 3)
	bumper.max_hp = 100
	bumper.hp = 100
	collision.set_terrain(Vector2i(4, 3), TerrainDB.OBSTACLE)
	collision.obstacle_durability[Vector2i(4, 3)] = 2
	PushResolver.push(collision, bumper, Vector2i(1, 0), 1, 0, "测试", "player", 1, "rock_push")
	t.eq(bumper.hp, 80, "碰撞专家与撞击准则叠加20点碰撞伤害")

	var distance_state := _state(["rock_starter"], [["water_wild1", Vector2i(2, 3)]], {"impact_code": 1})
	var pushed := distance_state.unit_by_uid(100)
	pushed.cell = Vector2i(2, 3)
	var result := PushResolver.push(distance_state, pushed, Vector2i(1, 0), 1, 0, "测试", "player", 1, "rock_push")
	t.eq(pushed.cell, Vector2i(4, 3), "撞击准则使强制位移距离+1")
	t.check(bool(result.get("moved", false)), "撞击准则位移实际发生")


func _summoning_and_magic(t: TestContext) -> void:
	var crown := _state(["grass_starter"], [], {"summoner_crown": 1})
	var summoner := crown.unit_by_uid(1)
	summoner.cell = Vector2i(2, 3)
	summoner.skills = ["tree_man"]
	summoner.battle_skill_uses.clear()
	summoner.skill_used = false
	var summon_cell := Vector2i(4, 3)
	var summoned := crown.summon_tree(summoner, summon_cell)
	t.check(summoned != null, "召唤王权允许召唤")
	if summoned != null:
		t.check(summoned.shield_hp >= ceili(summoner.max_hp * 0.30), "召唤物获得30%最大生命护盾")
		t.eq(summoned.shield_ticks, 0, "召唤王权护盾不随时间消失")

	var magic := _state(["fire_starter"], [["water_wild1", Vector2i(4, 3)]], {})
	var caster := magic.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	caster.skills = ["ultra_death_ray"]
	caster.battle_skill_uses.clear()
	caster.skill_used = false
	var magic_target := magic.unit_by_uid(100)
	magic_target.max_hp = 100
	magic_target.hp = 100
	var hit := magic.cast_skill(caster, "ultra_death_ray", {"type": "dir", "dir": Vector2i(1, 0), "cell": Vector2i(3, 3)})
	t.check(bool(hit.get("ok", false)), "超魔死光可以施放")
	t.eq(magic_target.hp, 60, "超魔死光造成40点基础伤害")
	t.check(caster.skill_used, "超魔死光按普通施法消耗本回合施法次数")
	t.eq(caster.restore_pp(1), 0, "技能药剂不能恢复每场限次的遗物魔法")
	t.check(not caster.has_pp_deficit(), "战斗专属魔法不计入技能药剂可用目标")
	var leap := _state(["water_starter"], [["rock_wild1", Vector2i(6, 6)]], {})
	var jumper := leap.unit_by_uid(1)
	jumper.cell = Vector2i(2, 3)
	jumper.skills = ["time_mirror_leap"]
	jumper.battle_skill_uses.clear()
	jumper.skill_used = false
	var moved_before := jumper.moved
	var leap_result := leap.cast_skill(jumper, "time_mirror_leap", {"type": "cell", "cell": Vector2i(5, 5)})
	t.check(bool(leap_result.get("ok", false)), "时镜跃迁可以施放")
	t.eq(jumper.cell, Vector2i(5, 5), "时镜跃迁移动到任意合法空格")
	t.check(not jumper.skill_used and jumper.moved == moved_before, "时镜跃迁不消耗施法次数或移动机会")
	t.check(jumper.relic_attack_immune, "时镜跃迁赋予下一次攻击免疫")
	var jumper_hp := jumper.hp
	leap.damage_unit(null, jumper, 1, {"no_element": true, "cause": "环境测试"})
	t.eq(jumper.hp, jumper_hp - 1, "环境伤害不消耗时镜跃迁免伤")
	t.check(jumper.relic_attack_immune, "环境伤害后时镜免伤仍保留")
	leap.damage_unit(leap.unit_by_uid(100), jumper, 5, {"no_element": true, "cause": "攻击测试"})
	t.eq(jumper.hp, jumper_hp - 1, "施法者攻击被时镜跃迁免疫")
	t.check(not jumper.relic_attack_immune, "时镜跃迁免伤被攻击消耗")


func _legendary_and_risk(t: TestContext) -> void:
	var poem := _state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], {"dead_poem": 1})
	var revive := poem.unit_by_uid(1)
	revive.hp = 1
	poem.damage_unit(poem.unit_by_uid(100), revive, 10, {"no_element": true, "cause": "测试"})
	t.check(revive.hp > 0, "亡者诗篇复活首个阵亡友军")
	t.eq(revive.hp, ceili(revive.max_hp * 0.5), "亡者诗篇复苏到50%最大生命")
	var lethal_poem := _state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], {"dead_poem": 1})
	var lava_cell := Vector2i(2, 3)
	lethal_poem.set_terrain(lava_cell, TerrainDB.LAVA)
	var lava_victim := lethal_poem.unit_by_uid(1)
	lava_victim.cell = lava_cell
	lethal_poem.kill_unit(lava_victim, "落入熔岩")
	t.check(lava_victim.is_alive() and lava_victim.cell != lava_cell, "亡者诗篇不会让复苏单位留在致死地形")

	var cauldron := _state(["water_starter"], [["rock_wild1", Vector2i(4, 3)]], {"witch_cauldron": 1})
	var victim := cauldron.unit_by_uid(1)
	victim.burn_ticks = 2
	victim.burn_layers = 1
	cauldron.kill_unit(victim, "测试")
	t.check(cauldron.unit_by_uid(100).burn_ticks > 0, "女巫坩埚把阵亡友军异常转给最近敌人")

	var blood := _state(["fire_starter"], [["rock_wild1", Vector2i(5, 5)]], {"blood_dragon_dance": 1})
	var dancer := blood.unit_by_uid(1)
	dancer.max_hp = 100
	dancer.hp = 100
	dancer.shield_hp = 100
	dancer.shield_ticks = 2
	var hp_before := dancer.hp
	blood.start_round()
	t.check(dancer.hp < hp_before, "血龙狂舞每回合造成真实生命损失")
	t.eq(dancer.shield_hp, 100, "血龙狂舞真实伤害无视护盾")
	t.eq(blood.relic_heal(dancer, 20), 0, "血龙狂舞期间常规治疗无效")
	blood.trainer().cell = Vector2i(2, 2)
	dancer.cell = Vector2i(3, 2)
	dancer.hp = 50
	t.check(not Merchant.item_target_valid(blood, dancer, "potion"), "血龙狂舞期间治疗药不可选")

	var dawn := _state(["water_starter"], [], {"dawn_lord_radiance": 1})
	var radiant := dawn.unit_by_uid(1)
	t.check(radiant.shield_hp >= ceili(radiant.max_hp * 0.20), "晨曦开战为友军提供20%最大生命护盾")
	t.eq(radiant.shield_ticks, 0, "晨曦护盾不会随时间消失")
	var growth := _state(["water_starter"], [], {"crimson_heart": 1})
	var grower := growth.unit_by_uid(1)
	var base_level_one := MonsterProgression.max_hp("water_starter", 1)
	grower.max_hp = growth.relic_max_hp_for_side("player", base_level_one)
	grower.hp = grower.max_hp
	growth.award_battle_experience("relic_growth_probe", MonsterProgression.threshold_for_level(2))
	t.eq(grower.combat_level, 2, "遗物生命测试单位升到Lv2")
	t.eq(grower.max_hp, growth.relic_max_hp_for_side("player", MonsterProgression.max_hp("water_starter", 2)), "升级生命增长包含遗物上限倍率")

	var combo := _state(["fire_starter"], [["water_wild1", Vector2i(5, 5)]], {"combo_dagger": 1})
	var combo_target := combo.unit_by_uid(100)
	combo_target.max_hp = 100
	combo_target.hp = 100
	for index in 2:
		combo.damage_unit(combo.unit_by_uid(1), combo_target, 5, {
			"skill_direct": true, "no_element": true, "skill_id": "probe",
		})
	t.eq(combo_target.hp, 85, "连击匕首在第2次直接伤害额外加5")

	var bagua := _state(["fire_starter", "water_starter"], [["rock_wild1", Vector2i(4, 3)]], {"bagua_compass": 1})
	var compass_target := bagua.unit_by_uid(100)
	compass_target.max_hp = 100
	compass_target.hp = 100
	bagua.damage_unit(bagua.unit_by_uid(1), compass_target, 5, {"skill_direct": true, "no_element": true})
	var after_first := compass_target.hp
	bagua.damage_unit(bagua.unit_by_uid(2), compass_target, 5, {"skill_direct": true, "no_element": true})
	t.check(compass_target.hp < after_first - 5, "八卦罗盘在第2名我方单位命中时追加最大生命伤害")
	var dice_run := RunState.new_run(8930)
	var dice_record := dice_run.record_by_uid(1)
	dice_record["known_skills"] = ["fire_burst"]
	dice_record["skill_pp_uses"] = {"fire_burst": SkillDB.pp_of("fire_burst")}
	dice_run._restore_party_half(0.0, 0.5, 0)
	t.eq(dice_run.record_pp_used(dice_record, "fire_burst"), ceili(SkillDB.pp_of("fire_burst") / 2.0), "神秘骰子恢复半管已消耗PP")


func _merchant_and_save(t: TestContext) -> void:
	var run := RunState.new_run(8920)
	run.region_mode = true
	var region = run.get_region()
	var stock := {}
	for node in region.nodes.values():
		if node.has("merchant"):
			stock = node["merchant"].get("stock", {})
			break
	t.check(stock.keys().any(func(id): return String(id).begins_with("relic:")), "商人库存包含遗物")
	t.check(stock.keys().filter(func(id): return String(id).begins_with("relic:")).all(func(id): return RelicDB.merchant_allowed(String(id).trim_prefix("relic:"))), "商人不出售可能触发结算后续选择的遗物")
	var old_data := run.to_dict()
	old_data["relic_stacks"] = {"fire_carbon": 1, "sealed_necronomicon": 1}
	old_data["pending_reward_choices"] = 2
	old_data["pending_relic_actions"] = [{"kind": "mage_notes", "relic_id": "mage_notes"}]
	var loaded := RunState.from_dict(old_data)
	t.check(loaded.relic_stacks.has("fire_carbon"), "遗物随本局存档保存")
	t.eq(loaded.pending_reward_choices, 2, "待选遗物次数保存")
	t.eq(loaded.pending_relic_action().get("kind", ""), "mage_notes", "遗物后续选择保存")
	t.check(loaded.monster_max_hp(loaded.carried[0]) < MonsterProgression.max_hp_for_record(loaded.carried[0]), "死灵书降低最大生命上限")
	var snapshot_source := _state(["electric_starter"], [["water_wild1", Vector2i(5, 5)]], {
		"electric_echo": 1, "dawn_lord_radiance": 1,
	})
	var snapshot_target := snapshot_source.unit_by_uid(100)
	snapshot_source.apply_shock(snapshot_target)
	snapshot_source.relic_state["snapshot_probe"] = 17
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(BattleSnapshot.save_state(snapshot_source)))
	var snapshot_loaded: BattleState = BattleSnapshot.load_state(snapshot)
	t.check(snapshot_loaded != null and snapshot_loaded.relic_stacks.has("electric_echo"), "战斗快照保留遗物集合")
	t.eq(snapshot_loaded.unit_by_uid(100).shock_layers, 2, "战斗快照保留感电层数")
	t.eq(int(snapshot_loaded.relic_state.get("snapshot_probe", 0)), 17, "战斗快照保留场内遗物触发状态")
