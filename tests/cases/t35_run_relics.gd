extends RefCounted


func run(t: TestContext) -> void:
	t.begin("本局遗物、补给与当前威胁")
	_rewards_and_migration(t)
	_direct_effects(t)
	_push_effects(t)
	_area_and_forecast(t)
	_floor_hit_profile(t)
	t.finish()


func _rewards_and_migration(t: TestContext) -> void:
	var run_state := RunState.new_run(35001)
	var offer := run_state.reward_choices()
	t.eq(offer, RunState.new_run(35001).reward_choices(), "同种子遗物可复现")
	t.eq(offer.size(), 3, "遗物每次给三项")
	t.eq({offer[0]: true, offer[1]: true, offer[2]: true}.size(), 3, "三项遗物互异")
	run_state.relic_stacks[offer[0]] = 3
	t.check(not run_state.reward_choices().has(offer[0]), "满三级遗物退出随机池")
	run_state.pending_reward_choices = 1
	t.check(not run_state.choose_reward(String(offer[0])), "满级遗物不能再领取")
	var choice := String(run_state.reward_choices()[0])
	t.check(run_state.choose_reward(choice), "可领取新遗物")
	t.eq(RelicDB.rank(run_state.relic_stacks, choice), 1, "遗物升至一级")
	run_state.battle_index = 2
	run_state.pending_supply = true
	var supply := run_state.supply_choices()
	t.eq(supply.size(), 3, "补给提供三张卡")
	t.eq({supply[0]: true, supply[1]: true, supply[2]: true}.size(), 3, "补给三卡互异")
	t.eq(supply, RunState.from_dict(run_state.to_dict()).supply_choices(), "补给读档不重抽")
	t.check(run_state.choose_supply_item(String(supply[0])), "领取一张免费消耗卡")
	t.check(not run_state.choose_supply_item(String(supply[1])), "同一补给点不能重复领取")
	t.eq(run_state.reward_inventory, [supply[0]], "补给卡进入旧背包")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.relic_stacks, run_state.relic_stacks, "遗物等级跨本局存档")
	t.eq(restored.claimed_supply_battles, [2], "补给领取状态跨存档")
	var v7 := run_state.to_dict()
	v7["version"] = 7
	v7.erase("relic_stacks")
	v7.erase("claimed_supply_battles")
	v7["pending_reward_choices"] = 1
	(v7["carried"] as Array)[0]["hp"] = 13
	var old := RunState.from_dict(v7)
	t.eq(int(old.carried[0]["hp"]), 13, "v7 生命不因 v8 升版再次缩放")
	t.eq(old.pending_reward_choices, 1, "旧局未领奖励转换为遗物机会")
	t.eq(old.reward_inventory, run_state.reward_inventory, "旧消耗背包原样保留")
	t.eq(old.relic_stacks, {}, "旧战次不补发遗物")
	t.eq(RunState.new_run(35002).relic_stacks, {}, "第一战以原始战力开始")
	var save_path := "res://.test_v7_relic_migration.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	t.check(file != null, "可写入隔离的 v7 迁移样本")
	if file != null:
		file.store_string(JSON.stringify(v7))
		file.close()
		var loaded := SaveSystem.load_run(save_path)
		t.check(loaded != null, "正式读档入口接受 v7")
		if loaded != null:
			t.eq(int(loaded.carried[0]["hp"]), 13, "正式读档不重复缩放 v7 生命")
		SaveSystem.delete_save(save_path)


func _direct_effects(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter", "water_starter", "electric_starter"], [["grass_wild1", Vector2i(4, 3)]])
	var fire := state.unit_by_uid(1)
	var water := state.unit_by_uid(2)
	var electric := state.unit_by_uid(3)
	var enemy := state.unit_by_uid(100)
	enemy.max_hp = 100
	enemy.hp = 100
	fire.cell = Vector2i(2, 3)
	water.cell = Vector2i(2, 4)
	electric.cell = Vector2i(3, 4)
	state.relic_stacks = {"fire_mark": 1, "burn_chaser": 1, "ember_recovery": 2, "water_mark": 1, "wet_conductor": 1, "frost_wet": 1, "first_strike": 1}
	var first := state.damage_unit(fire, enemy, 10, {"skill_direct": true, "element": "fire"})
	t.eq(int(first["amount"]), Elements.direct_damage(10, "fire", "grass") + 6, "火克草后叠加火印与满血猎手")
	t.check(enemy.burn_ticks > 0, "火印给存活敌人附灼烧")
	var next := state.damage_unit(water, enemy, 5, {"skill_direct": true, "element": "water"})
	t.eq(int(next["amount"]), 12, "潮印 +2 与灼痕 +5 联动")
	t.check(enemy.slow_ticks > 0, "潮印给存活敌人附浸湿")
	enemy.hp = enemy.max_hp
	var shock := state.damage_unit(electric, enemy, 10, {"skill_direct": true, "element": "electric"})
	t.eq(int(shock["amount"]), 25, "浸湿导雷 +6、灼痕 +5、满血猎手 +4")
	fire.hp = 5
	enemy.hp = 3
	state.damage_unit(fire, enemy, 5, {"skill_direct": true, "element": "fire"})
	t.eq(fire.hp, 13, "击倒原已灼烧敌人后余烬二级恢复 8 HP")
	var friendly := TestScenario.make_state(["fire_starter", "water_starter"], [])
	friendly.relic_stacks = {"fire_mark": 3, "burn_chaser": 3, "first_strike": 3}
	var ally := friendly.unit_by_uid(2)
	var friendly_hit := friendly.damage_unit(friendly.unit_by_uid(1), ally, 10, {"skill_direct": true, "element": "fire"})
	t.eq(int(friendly_hit["amount"]), Elements.direct_damage(10, "fire", "water"), "遗物不放大误伤友军，仍受属性影响")
	t.eq(ally.burn_ticks, 0, "火印不灼烧友军")
	var ember_preview := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	ember_preview.relic_stacks = {"ember_recovery": 2}
	var ember_caster := ember_preview.unit_by_uid(1)
	ember_caster.cell = Vector2i(2, 3)
	ember_caster.skills = ["trial_fire_1"]
	ember_caster.hp = 4
	var ember_target := ember_preview.unit_by_uid(100)
	ember_target.hp = 5
	ember_target.burn_ticks = 2
	var ember_entry := {"type": "unit", "unit": 100, "cell": ember_target.cell}
	var heal_preview := ember_preview.preview_skill(ember_caster, "trial_fire_1", ember_entry)
	var heal_actual := ember_preview.cast_skill(ember_caster, "trial_fire_1", ember_entry)
	t.eq(int(heal_preview["hits"][0]["relic_healed"]), 8, "预览显示灼烧击杀的余烬回复")
	t.eq(heal_preview["hits"], heal_actual["hits"], "余烬治疗预览与实伤一致")
	t.eq(ember_caster.hp, 12, "实战回复与预览相同")
	var wet_terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.WATER]])
	var wet_state := TestScenario.make_state(["water_starter", "ice_starter"], [["rock_wild1", Vector2i(4, 3)]], wet_terrain)
	wet_state.relic_stacks = {"water_mark": 2, "rushing_tide": 2, "frost_wet": 1}
	var wet_target := wet_state.unit_by_uid(100)
	wet_target.max_hp = 100
	wet_target.hp = 100
	var water_hit := wet_state.damage_unit(wet_state.unit_by_uid(1), wet_target, 10, {"skill_direct": true, "element": "water"})
	t.eq(int(water_hit["amount"]), 24, "潮印二级与水格激流二级叠加")
	t.check(wet_target.slow_ticks > 0, "潮印为后续冰系联动铺浸湿")
	var ice_hit := wet_state.damage_unit(wet_state.unit_by_uid(2), wet_target, 10, {"skill_direct": true, "element": "water", "skill_id": "ice_shard"})
	t.eq(int(ice_hit["amount"]), 10 + 2 * 2 + 5 * 2 + 5, "冰锥归水后叠加潮印、激流与霜寒")
	var armor := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 3)]])
	armor.relic_stacks = {"rock_armor": 2, "green_pulse": 1, "root_rest": 2, "rock_pulse": 1, "root_bind": 1, "rushing_tide": 1}
	var defender := armor.unit_by_uid(1)
	defender.cell = Vector2i(2, 3)
	armor.set_terrain(Vector2i(2, 2), TerrainDB.OBSTACLE)
	var incoming := armor.damage_unit(armor.unit_by_uid(100), defender, 10, {"skill_direct": true, "element": "rock"})
	t.eq(int(incoming["amount"]), 3, "岩甲二级减伤叠加敌方 70% 直伤")
	defender.hp = 10
	armor.set_terrain(defender.cell, TerrainDB.GRASS)
	armor.start_round()
	t.eq(defender.hp, 14, "根息二级在我方阶段开始恢复 4 HP")
	var victim := armor.unit_by_uid(100)
	victim.root_pending = true
	var boosted := armor.damage_unit(defender, victim, 5, {"skill_direct": true, "element": "rock"})
	t.eq(int(boosted["amount"]), 18, "绿脉、岩脉、缠根、猎手以外的三级联动")


func _push_effects(t: TestContext) -> void:
	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.OBSTACLE]])
	var base := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	var boosted := base.clone()
	boosted.relic_stacks = {"wall_crash": 2, "wind_pressure": 1}
	var baseline := PushResolver.push(base, base.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "rock_push")
	var enhanced := PushResolver.push(boosted, boosted.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "rock_push")
	t.eq(int(enhanced["collisions"][0]["target_damage"]) - int(baseline["collisions"][0]["target_damage"]), 8, "冲壁二级只加推击碰撞伤害")
	var wind := TestScenario.make_state(["wind_starter"], [["rock_wild1", Vector2i(3, 3)]], TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(5, 3), TerrainDB.OBSTACLE]]))
	wind.relic_stacks = {"wind_pressure": 2}
	var gust := PushResolver.push(wind, wind.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "wind_gust")
	t.eq(wind.unit_by_uid(100).cell, Vector2i(4, 3), "风压一旦拥有即额外推一格")
	t.eq(int(gust["collisions"][0]["target_damage"]), Balance.COLLISION_DAMAGE + 6, "风压二级碰撞再 +6")
	var two_enemies := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)], ["fire_wild1", Vector2i(4, 3)]])
	two_enemies.relic_stacks = {"wall_crash": 2}
	var collision := PushResolver.push(two_enemies, two_enemies.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "rock_push")
	t.eq(int(collision["collisions"][0]["other_damage"]), Balance.COLLISION_DAMAGE + 8, "被撞的另一名敌人也受冲壁加成")
	var friendly_block := TestScenario.make_state(["rock_starter", "fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	friendly_block.unit_by_uid(2).cell = Vector2i(4, 3)
	friendly_block.relic_stacks = {"wall_crash": 2}
	var blocked := PushResolver.push(friendly_block, friendly_block.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "rock_push")
	t.eq(int(blocked["collisions"][0]["other_damage"]), Balance.COLLISION_DAMAGE, "被撞友军不受遗物加伤")


func _area_and_forecast(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 2)], ["water_wild1", Vector2i(4, 4)]])
	state.relic_stacks = {"fire_mark": 2, "first_strike": 1}
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(2, 3)
	caster.skills = ["fire_seed"]
	var entry := {"type": "cell", "cell": Vector2i(4, 3)}
	var preview := state.preview_skill(caster, "fire_seed", entry)
	var actual := state.cast_skill(caster, "fire_seed", entry)
	t.check(bool(preview.get("ok", false)) and bool(actual.get("ok", false)), "范围技能可预览并实际施放")
	t.eq(preview.get("hits", []), actual.get("hits", []), "范围两目标预览与实际伤害和状态一致")
	var ai_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 3)]])
	ai_state.trainer().cell = Vector2i(0, 0)
	ai_state.unit_by_uid(1).cell = Vector2i(2, 3)
	var predicted := ai_state.forecast()
	var projection := ThreatProjection.from_plan(ai_state, predicted)
	t.check(not (projection["intentions"] as Array).is_empty(), "当前敌方目标可展示")
	t.eq(ai_state.begin_enemy_phase(), predicted, "此刻结束回合时预测计划与实际行动一致")
	var mutable := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(4, 3)]])
	mutable.trainer().cell = Vector2i(0, 0)
	mutable.unit_by_uid(1).cell = Vector2i(3, 3)
	mutable.unit_by_uid(100).moved = true
	var before := ThreatProjection.from_plan(mutable, mutable.forecast())
	t.check((before["danger"] as Array).has(Vector2i(3, 3)), "当下可受击格进入危险区")
	t.check(mutable.move_unit(mutable.unit_by_uid(1), Vector2i(2, 3)), "玩家移动改变局面")
	var after := ThreatProjection.from_plan(mutable, mutable.forecast())
	t.check(before != after, "玩家移动后目标或危险区及时更新")
	var expected_plan := mutable.forecast()
	t.eq(mutable.begin_enemy_phase(), expected_plan, "变化后的提示仍与结束回合的实际规划一致")
	var channeled := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(5, 3)], ["rock_wild1", Vector2i(4, 3)]])
	channeled.trainer().cell = Vector2i(0, 0)
	channeled.unit_by_uid(1).cell = Vector2i(2, 3)
	channeled.unit_by_uid(1).hp = 20
	channeled.unit_by_uid(100).channel_lock_round = channeled.round
	channeled.pending_casts.append({"uid": 100, "side": "enemy", "skill_id": "rock_slide", "cells": [Vector2i(2, 3)], "due_round": channeled.round})
	var after_channel_plan := channeled.forecast()
	t.eq(channeled.unit_by_uid(1).hp, 20, "预览蓄力先结算但不修改真实生命")
	t.eq(channeled.begin_enemy_phase(), after_channel_plan, "固定落点先结算后的敌方规划与提示一致")
	t.eq(channeled.unit_by_uid(1).hp, 0, "真实结束回合先受到固定落点打击")


func _floor_hit_profile(t: TestContext) -> void:
	var cases := 0
	var baseline_total := 0
	var linked_total := 0
	var lucky_total := 0
	for seed_value in [31001, 31002]:
		for battle_index in Balance.BATTLES_PER_FLOOR:
			var cfg := BattleDB.config_for(battle_index, seed_value, "fire")
			var enemies: Array = cfg["enemies"]
			for enemy_index in enemies.size():
				var species_id := String(enemies[enemy_index][0])
				var is_boss := enemy_index == int(cfg.get("boss_index", -1))
				var baseline := _hits_to_defeat(seed_value, battle_index, species_id, enemy_index, is_boss, {})
				var linked := _hits_to_defeat(seed_value, battle_index, species_id, enemy_index, is_boss, {"fire_mark": 1, "burn_chaser": 1})
				var lucky := _hits_to_defeat(seed_value, battle_index, species_id, enemy_index, is_boss, {"fire_mark": 3, "burn_chaser": 3, "first_strike": 3})
				if is_boss:
					t.check(baseline >= 4 and lucky >= 2, "首领仍不能一次普通技能秒杀")
				else:
					t.check(baseline >= 2 and baseline <= 3, "第一层普通敌人无联动时需 2–3 次命中")
					t.check(lucky >= 1 and lucky <= 2, "强运构筑通常降至 1–2 次命中")
					cases += 1
					baseline_total += baseline
					linked_total += linked
					lucky_total += lucky
	print("FIRST_FLOOR_HIT_PROFILE ordinary=%d baseline_total=%d two_link_total=%d lucky_total=%d" % [cases, baseline_total, linked_total, lucky_total])


func _hits_to_defeat(seed_value: int, battle_index: int, species_id: String, enemy_index: int, is_boss: bool, relics: Dictionary) -> int:
	var state := TestScenario.make_state(["fire_starter"], [[species_id, Vector2i(4, 3)]])
	state.battle_index = battle_index
	state.relic_stacks = relics.duplicate()
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	BattleDB.configure_enemy(target, seed_value, battle_index, enemy_index, is_boss)
	if is_boss:
		state.boss_uid = target.uid
	var hits := 0
	while target.is_alive() and hits < 12:
		state.damage_unit(caster, target, SkillDB.damage_of("flame_jet"), {"skill_direct": true, "element": "fire", "cause": "命中次数样本"})
		hits += 1
	return hits
