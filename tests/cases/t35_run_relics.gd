extends RefCounted


func run(t: TestContext) -> void:
	t.begin("新版固定遗物池与核心效果")
	_pool(t)
	_cycle(t)
	_position_and_status(t)
	_terrain_and_targets(t)
	_journey_and_risk(t)
	t.finish()


func _state(player_species: Array, enemies: Array, relics: Dictionary) -> BattleState:
	var state := TestScenario.make_state(player_species, enemies)
	state.relic_stacks = relics.duplicate()
	return state


func _pool(t: TestContext) -> void:
	t.eq(RelicDB.DEFINITIONS.size(), 24, "新版遗物共24项")
	var categories := {}
	for relic_id in RelicDB.DEFINITIONS:
		var definition: Dictionary = RelicDB.DEFINITIONS[relic_id]
		categories[String(definition.get("category", ""))] = int(categories.get(String(definition.get("category", "")), 0)) + 1
		t.check(String(definition.get("name", "")) != "" and String(definition.get("description", "")) != "", "%s有名称与文本" % relic_id)
	for category in ["cycle", "formation", "status", "terrain", "journey", "risk"]:
		t.eq(int(categories.get(category, 0)), 4, "%s流派有4项遗物" % category)
	var offered := RelicDB.offer(35001, 0, 0, {})
	t.eq(offered.size(), 3, "遗物三选一提供三项")
	t.eq({offered[0]: true, offered[1]: true, offered[2]: true}.size(), 3, "候选不重复")
	var offered_categories := {}
	for id in offered:
		offered_categories[RelicDB.category_of(String(id))] = true
	t.check(offered_categories.size() >= 2, "三选一覆盖至少两个流派")
	var owned := {String(offered[0]): 1}
	t.check(not RelicDB.offer(35001, 0, 0, owned).has(offered[0]), "已获得遗物退出候选池")
	var run := RunState.new_run(35001)
	run.pending_reward_choices = 1
	var choice := String(run.reward_choices()[0])
	t.check(run.choose_reward(choice), "可以领取新版遗物")
	t.eq(int(run.relic_stacks[choice]), 1, "固定遗物只记录已获得")
	t.eq(run.pending_reward_choices, 0, "领取后消耗一次奖励机会")
	t.check(not run.reward_choices().has(choice), "已领取遗物不会再次出现")
	var old_data := run.to_dict()
	old_data["relic_stacks"]["fire_mark"] = 1
	var loaded := RunState.from_dict(old_data)
	t.check(not loaded.relic_stacks.has("fire_mark"), "旧遗物ID不会进入新版池")


func _cycle(t: TestContext) -> void:
	var state := _state(["wind_starter"], [], {"echo_gear": 1})
	var caster := state.unit_by_uid(1)
	caster.skills = ["tailwind"]
	var entries := state.skill_targets(caster, "tailwind")
	var maximum := caster.max_pp("tailwind")
	for index in 3:
		t.check(bool(state.cast_skill(caster, "tailwind", entries[0]).get("ok", false)), "回响齿轮施法%d成功" % (index + 1))
		caster.skill_used = false
	t.eq(caster.pp_remaining("tailwind"), maximum - 2, "每第3次成功施法免除PP")

	state = _state(["wind_starter"], [], {"still_chant": 1})
	caster = state.unit_by_uid(1)
	caster.skills = ["tailwind"]
	entries = state.skill_targets(caster, "tailwind")
	maximum = caster.max_pp("tailwind")
	for index in 2:
		state.cast_skill(caster, "tailwind", entries[0])
		caster.moved = false
		caster.skill_used = false
	t.eq(caster.pp_remaining("tailwind"), maximum, "静咏刻印前两次原地施法免费")

	state = _state(["water_starter"], [["rock_wild1", Vector2i(5, 5)]], {"overload_coil": 1})
	caster = state.unit_by_uid(1)
	caster.skills = ["mirror_water_moon"]
	caster.battle_skill_uses["mirror_water_moon"] = 4
	var mirror_entries := state.skill_targets(caster, "mirror_water_moon")
	state.cast_skill(caster, "mirror_water_moon", mirror_entries[0])
	t.check(caster.shield_hp >= 8 and caster.pp_remaining("mirror_water_moon") == 0, "过载线圈在技能耗尽时提供护盾")

	state = _state(["fire_starter"], [["rock_wild1", Vector2i(5, 5)]], {"echo_hourglass": 1})
	caster = state.unit_by_uid(1)
	caster.skills = ["fire_burst"]
	var burst_entries := state.skill_targets(caster, "fire_burst")
	var before := caster.pp_remaining("fire_burst")
	state.cast_skill(caster, "fire_burst", burst_entries[0])
	state.cancel_channel(caster, "测试打断")
	t.eq(caster.pp_remaining("fire_burst"), before, "残响沙漏返还被打断吟唱的PP")

	state = _state(["rock_starter"], [["rock_wild1", Vector2i(5, 3)]], {"watch_line": 1})
	caster = state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	caster.skills = ["rock_break"]
	t.check(not state.skill_targets(caster, "rock_break").is_empty(), "守望刻线让原本射程外的目标可选")
	state.cast_skill(caster, "rock_break", state.skill_targets(caster, "rock_break")[0])
	t.eq(int((state.relic_state.get("watch_used", {}) as Dictionary).get(str(caster.uid), -1)), state.round, "守望刻线实际施法后标记本轮已用")


func _position_and_status(t: TestContext) -> void:
	var state := _state(["rock_starter", "fire_starter"], [["grass_wild1", Vector2i(3, 3)]], {"flank_prism": 1})
	var source := state.unit_by_uid(1)
	var ally := state.unit_by_uid(2)
	var target := state.unit_by_uid(100)
	source.cell = Vector2i(2, 3)
	ally.cell = Vector2i(4, 3)
	target.cell = Vector2i(3, 3)
	target.max_hp = 100
	target.hp = 100
	var first := state.damage_unit(source, target, 5, {"skill_direct": true, "skill_id": "rock_push", "no_element": true})
	t.eq(int(first["amount"]), 10, "夹击棱镜提高包夹目标直伤")

	state = _state(["rock_starter", "fire_starter"], [["grass_wild1", Vector2i(3, 3)]], {"weakness_ledger": 1})
	source = state.unit_by_uid(1)
	ally = state.unit_by_uid(2)
	target = state.unit_by_uid(100)
	source.cell = Vector2i(2, 3)
	ally.cell = Vector2i(4, 3)
	target.cell = Vector2i(3, 3)
	target.max_hp = 100
	target.hp = 100
	state.damage_unit(source, target, 5, {"skill_direct": true, "skill_id": "rock_push", "no_element": true})
	var marked := state.damage_unit(ally, target, 5, {"skill_direct": true, "skill_id": "flame_jet", "no_element": true})
	t.eq(int(marked["amount"]), 8, "弱点账本让后续不同单位攻击获得增伤")

	state = _state(["fire_starter", "water_starter"], [], {"relay_sigil": 1})
	var caster := state.unit_by_uid(1)
	var recipient := state.unit_by_uid(2)
	caster.cell = Vector2i(2, 3)
	recipient.cell = Vector2i(3, 3)
	caster.skills = ["tailwind"]
	state.cast_skill(caster, "tailwind", state.skill_targets(caster, "tailwind")[0])
	t.eq(recipient.relay_move_bonus, 1, "接力徽记给相邻友军下一次移动+1")

	state = _state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)], ["water_wild1", Vector2i(5, 3)]], {"status_aftershock": 1})
	var dead := state.unit_by_uid(100)
	var near := state.unit_by_uid(101)
	dead.burn_ticks = 1
	state.kill_unit(dead, "测试", "player", 1)
	t.check(near.burn_ticks > 0, "连锁余波将灼烧传给附近敌人")

	state = _state(["fire_starter"], [], {"suppression_lock": 1})
	var victim := state.unit_by_uid(1)
	victim.skills = ["fire_burst"]
	var used_before := victim.pp_used("fire_burst")
	state.apply_freeze(victim)
	t.eq(victim.pp_used("fire_burst"), used_before + 1, "压制枷锁削减被控制目标最高PP技能")

	var cleanse := _state(["fire_starter"], [], {"cleanse_circuit": 1})
	var healed := cleanse.unit_by_uid(1)
	healed.burn_ticks = 1
	cleanse.clear_debuff_status(healed)
	t.check(healed.shield_hp >= 4 and healed.relay_move_bonus == 1, "净化回路提供护盾与移动")

	var crack := _state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)], ["water_wild1", Vector2i(5, 3)]], {"freeze_crack": 1})
	var frozen := crack.unit_by_uid(100)
	var neighbor := crack.unit_by_uid(101)
	frozen.frozen = true
	frozen.frozen_ticks = 1
	frozen.max_hp = 50
	frozen.hp = 50
	neighbor.max_hp = 50
	neighbor.hp = 50
	crack.damage_unit(crack.unit_by_uid(1), frozen, 5, {"skill_direct": true, "element": "water"})
	t.eq(neighbor.hp, 48, "冻结裂响对冰冻目标四邻造成2点固定伤害")


func _terrain_and_targets(t: TestContext) -> void:
	var state := _state(["water_starter"], [], {"terrain_resonance": 1, "overwrite_compass": 1})
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills = ["rain_call"]
	var pp_before := caster.pp_remaining("rain_call")
	state.cast_skill(caster, "rain_call", {"type": "cell", "cell": caster.cell})
	t.eq(caster.pp_remaining("rain_call"), pp_before, "覆写罗盘免除首次地形技能PP")
	t.eq(caster.shield_hp, 3, "地貌共鸣为站在新地形上的友军提供护盾")

	state = _state(["fire_starter"], [], {"migration_tracks": 1})
	caster = state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	state.set_terrain(caster.cell, TerrainDB.GRASS)
	state.start_round()
	t.eq(caster.relay_move_bonus, 1, "迁徙足印让草丛上的友军获得移动")

	state = _state(["grass_starter"], [], {"symbiotic_roots": 1})
	caster = state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills = ["tree_man"]
	var summon := state.summon_tree(caster, Vector2i(4, 3))
	t.eq(summon.max_hp, 20, "共生根系提高召唤物最大生命")
	caster.battle_skill_uses["tree_man"] = 1
	state.kill_unit(summon, "测试", "enemy")
	t.eq(caster.pp_remaining("tree_man"), caster.max_pp("tree_man"), "共生根系在召唤物离场时恢复最低PP技能")

	state = _state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], {"last_stand_ember": 1})
	caster = state.unit_by_uid(1)
	caster.max_hp = 30
	caster.hp = 30
	state.damage_unit(state.unit_by_uid(100), caster, 21, {"skill_direct": true, "no_element": true})
	t.check(caster.hp > 0 and caster.shield_hp >= 8, "背水火种在首次濒危时提供护盾")


func _journey_and_risk(t: TestContext) -> void:
	var camp_run := RunState.new_run(35010)
	camp_run.region_mode = true
	camp_run.choose_floor_theme(String(camp_run.offered_floor_themes[0]))
	camp_run.relic_stacks = {"camp_ember": 1, "homeward_waypoint": 1, "merchant_credentials": 1}
	t.eq(camp_run.camp_rest_cost("basic"), 2, "篝火余温降低营地休息成本")
	var camp_region = camp_run.get_region()
	camp_region.visits = 3
	camp_run.region_data = camp_region.to_dict()
	t.check(camp_run.enter_region_node("camp"), "可返回营地")
	t.eq(camp_run.get_region().visits, 3, "归途路标让本层首次返回营地不增加压力")
	camp_run.carried[0]["hp"] = 0
	var rest := camp_run.rest_with_food({"basic": 2})
	t.check(bool(rest.get("ok", false)), "篝火余温可用2份食物休息")
	t.eq(int(camp_run.carried[0]["hp"]), ceili(camp_run.monster_max_hp(camp_run.carried[0]) * 0.75), "篝火余温把濒死成员恢复到75%")
	t.eq(Merchant.item_price(camp_run, "potion"), 3, "行商凭据降低商人道具价格")
	t.eq(camp_run.merchant_skill_upgrade_cost(camp_run.carried[0]), 10, "行商凭据降低技能强化费用")

	var run := RunState.new_run(35011)
	var units := run.build_deploy_units([1])
	var state := BattleState.new()
	var map := TestScenario.make_map(TestScenario.plain_terrain(), Vector2i(7, 7))
	state.setup(map, {"enemies": [["rock_wild1", Vector2i(5, 5)]]}, 35011, 0, units, {}, {}, [], {}, {"herb_satchel": 1})
	t.check(not state.fruits.is_empty(), "采药袋每场额外生成果实")
	var picker := state.unit_by_uid(1)
	picker.cell = state.fruits[0]
	picker.max_hp = 30
	picker.hp = 10
	state.try_pickup_fruit(picker)
	t.eq(picker.hp, 22, "采药袋让果实恢复12生命")

	state = _state(["fire_starter"], [["rock_wild1", Vector2i(5, 5)]], {"pressure_breaker": 1})
	state.corruption_active = true
	var caster := state.unit_by_uid(1)
	caster.skills = ["tailwind"]
	var pp_before := caster.pp_remaining("tailwind")
	state.cast_skill(caster, "tailwind", state.skill_targets(caster, "tailwind")[0])
	t.eq(caster.pp_remaining("tailwind"), pp_before, "逆压者在黑化战斗中免除每轮首次施法PP")
	caster.skill_used = false
	state.cast_skill(caster, "tailwind", state.skill_targets(caster, "tailwind")[0])
	t.eq(caster.pp_remaining("tailwind"), pp_before - 1, "逆压者同轮后续施法正常消耗PP")

	state = _state(["rock_starter"], [], {"nest_wedge": 1})
	caster = state.unit_by_uid(1)
	caster.cell = state.nest["cell"] + Vector2i(-2, 0)
	caster.skills = ["rock_break"]
	var nest_hit := state.cast_skill(caster, "rock_break", {"type": "nest", "cell": state.nest["cell"]})
	t.eq(int(nest_hit.get("nest_damaged", {}).get("damage", 0)), 16, "破巢楔提高每轮首次拆巢伤害")

	state = _state(["fire_starter"], [["rock_wild1", Vector2i(5, 5)]], {"boss_hunt": 1})
	var boss := state.unit_by_uid(100)
	boss.is_boss = true
	boss.max_hp = 100
	boss.hp = 100
	state.boss_uid = boss.uid
	var boss_hit := state.damage_unit(state.unit_by_uid(1), boss, 10, {"skill_direct": true, "no_element": true})
	t.eq(int(boss_hit["amount"]), 16, "猎首令提高每轮首次首领直伤")
	state._trigger_inspiration()
	t.check(not state.inspiration_triggered and int(state.relic_state.get("boss_inspiration_due_round", 0)) == state.round + 1, "猎首令延后首领鼓舞")
	state.start_round()
	t.check(state.inspiration_triggered, "猎首令延后的鼓舞在下一轮开始生效")
