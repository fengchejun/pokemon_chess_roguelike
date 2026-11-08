extends RefCounted

const Flow = preload("res://scripts/run/exploration_flow.gd")
const Invasion = preload("res://scripts/run/floor_invasion.gd")
const Loot = preload("res://scripts/run/battle_loot.gd")


func run(t: TestContext) -> void:
	t.begin("驻防时序、限时携带者与分级战利品")
	_defense(t)
	_carrier(t)
	_loot(t)
	t.finish()


func _defense(t: TestContext) -> void:
	var run_state := RunState.new_run(92001)
	run_state.region_mode = true
	run_state.options["exploration_v2"] = true
	run_state.floor_themes = ["grass"]
	var region := Flow.generate(0, "grass", run_state.seed)
	run_state.region_data = region.to_dict()
	var uid := int(run_state.carried[0]["uid"])
	var stored_a := run_state._make_record("rock_wild1")
	var stored_b := run_state._make_record("grass_wild1")
	run_state.storage.append_array([stored_a, stored_b])
	t.check(Invasion.assign(run_state, "camp", uid), "当前节点可指派随身伙伴")
	region = run_state.get_region()
	t.eq(region.garrisons[str(uid)]["ready"], 0, "当前节点随身成员立即就位")
	var reserve_uid := int(stored_a["uid"])
	t.check(Invasion.assign(run_state, "camp", reserve_uid), "仓库伙伴可远程指派")
	region = run_state.get_region()
	t.eq(region.garrisons[str(reserve_uid)]["ready"], 1, "仓库伙伴即使守当前点也须一次移动")
	var neighbor: String = region.nodes["camp"]["links"][0]
	t.check(Invasion.assign(run_state, neighbor, reserve_uid), "可以远程改派")
	t.check(Invasion.recall(run_state, reserve_uid) and Invasion.assign(run_state, "camp", reserve_uid), "召回后可以重新派驻")
	t.check(Invasion.assign(run_state, "camp", int(stored_b["uid"])), "第三只可以派驻")
	t.check(not Invasion.assign(run_state, "camp", int(run_state.carried[1]["uid"])), "第四只不能派到同一节点")
	t.eq(run_state.build_deploy_units([uid]).size(), 1, "驻军不进入出战名单")
	region = run_state.get_region()
	region.visits = 1
	region.visit_pending = true
	t.eq(Invasion.contribution(region, region.garrisons[str(reserve_uid)], stored_a), 0, "已进入但还没结算的移动不算就位")
	region.visit_pending = false
	t.check(Invasion.contribution(region, region.garrisons[str(reserve_uid)], stored_a) > 0, "节点结算后正式就位")
	region.visits = 12
	t.eq(Invasion.chance(run_state, region, "camp"), 100, "提前准备的三只伙伴可稳守营地")
	t.check(Invasion.resolve(run_state, region), "12次行动后结算入侵")
	t.check(not Invasion.resolve(run_state, region), "不能重复结算")
	t.check(region.nodes["camp"]["defense"]["held"] and region.garrisons.is_empty(), "守住营地并释放所有驻军")
	t.check(run_state.record_by_uid(uid).is_empty() and not run_state.owned_record_by_uid(uid).is_empty(), "随身驻军完整返回仓库")
	t.eq(stored_a["xp"], 6, "成功驻守获得固定经验")
	t.check(stored_a.get("defense_locked_levels", []).has(2) and run_state.monster_level_choices(reserve_uid, 2).is_empty(), "驻防升级暂不解锁学招")
	var restored := RunState.from_dict(run_state.to_dict())
	t.check(restored.get_region().invaded and restored.owned_record_by_uid(reserve_uid).get("defense_locked_levels", []).has(2), "入侵状态与学招锁读档保留")
	run_state.storage.erase(stored_a)
	run_state.carried.append(stored_a)
	run_state.mark_deployed([reserve_uid])
	var battle := BattleState.new()
	battle.node_kind = "battle"
	battle.exploration_v2 = true
	battle.exploration_role = "recapture"
	battle.units = run_state.build_deploy_units([reserve_uid])
	battle.end_battle("escape")
	run_state.settle_battle(battle)
	t.check(not stored_a.has("defense_locked_levels"), "该成员实际参战并撤退结算后解锁学招")


func _carrier(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 5)], ["fire_wild1", Vector2i(6, 6)]])
	state.node_kind = "battle"
	state.exploration_v2 = true
	state.exploration_role = "battle"
	state.stop_nests()
	state.reward = {"state": "absent"}
	state.carrier_tier = "medium"
	state.carrier_turns_left = 3
	var courier := state.unit_by_uid(101)
	courier.reward_carrier = true
	state.kill_unit(state.unit_by_uid(100), "测试", "player", 1)
	t.check(not state.check_battle_end() and not state.is_free_exploration(), "剩携带者仍不算清场")
	var killed := state.clone()
	killed.kill_unit(killed.unit_by_uid(101), "测试", "player", 1)
	t.eq(killed.reward.get("tier"), "medium", "限时击杀只留下对应等级的一个奖励点")
	state.end_enemy_phase()
	t.eq(state.carrier_turns_left, 2, "第一个敌方阶段后剩两回合")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.carrier_turns_left, 2, "战斗读档保留撤退时限")
	var node := Flow.generate(0, "grass", 92)
	var left := state.clone()
	left.end_battle("escape")
	t.check(node.store_battle("battle_1", left), "撤退保存携带者所在节点")
	var resumed := node.resume_node("battle_1", [left.trainer().dup()])
	t.check(resumed != null and resumed.carrier_turns_left == 2 and resumed.unit_by_uid(101).reward_carrier, "撤退重访不会重置计时或刷新目标")
	restored.end_enemy_phase()
	t.check(restored.unit_by_uid(101).is_alive(), "第二轮后仍可继续追打")
	restored.end_enemy_phase()
	t.check(restored.is_free_exploration() and not restored.all_rewards().any(func(point): return point.get("id", "") == "enemy:101"), "第三轮末撤退，无掉落且可清场")

	var storm := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 5)]])
	storm.node_kind = "battle"
	storm.exploration_v2 = true
	storm.exploration_role = "recapture"
	storm.mark_storm(1)
	var ally := storm.unit_by_uid(1)
	storm.trainer().cell = Vector2i(1, 1)
	var start_hp := ally.hp
	storm.end_enemy_phase()
	t.eq(ally.hp, start_hp - ceili(ally.max_hp * 0.5), "夺回战首轮末落雷扣一半最大生命")
	t.check(storm.storm_strikes.any(func(strike): return strike["due_round"] == 2), "首轮落雷后继续预告第二轮")


func _loot(t: TestContext) -> void:
	var saw_upgrade := {"common": false, "medium": false}
	var saw_bonus := {"common": false, "medium": false}
	for tier in ["common", "medium", "high"]:
		var first := RunState.new_run(92)
		var copy := RunState.new_run(92)
		t.eq(Loot.redeem(first, tier, "same"), Loot.redeem(copy, tier, "same"), "同一种子与来源固定掉落")
		for i in 60:
			var run_state := RunState.new_run(92)
			run_state.essence = 0
			Loot.redeem(run_state, tier, str(i))
			match tier:
				"common":
					t.check(run_state.essence in range(3, 8) and run_state.relic_stacks.size() == 1 and run_state.pending_reward_choices == 0, "普通点自动发遗物及3–7原质")
					saw_upgrade[tier] = saw_upgrade[tier] or RelicDB.rarity_of(run_state.relic_stacks.keys()[0]) == RelicDB.RARE
					saw_bonus[tier] = saw_bonus[tier] or run_state.trainer_items.has("xp_candy_small")
				"medium":
					t.check(run_state.essence in range(7, 13) and run_state.relic_stacks.size() == 1 and run_state.pending_reward_choices == 0, "中级点自动发遗物及7–12原质")
					saw_upgrade[tier] = saw_upgrade[tier] or RelicDB.rarity_of(run_state.relic_stacks.keys()[0]) == RelicDB.LEGENDARY
					saw_bonus[tier] = saw_bonus[tier] or not run_state.trainer_items.is_empty()
				"high":
					var offers := run_state.reward_choices()
					t.check(run_state.essence in range(12, 21) and run_state.pending_reward_choices == 1 and not run_state.trainer_items.is_empty(), "高级点发原质、道具及传奇选择")
					t.check(offers.size() == 3 and offers.all(func(id): return RelicDB.rarity_of(id) == RelicDB.LEGENDARY), "高级点候选均为传奇")
	t.check(saw_upgrade.values().all(func(value): return value) and saw_bonus.values().all(func(value): return value), "两档奖励的升稀有和道具概率分支均可触发")
	var exhausted := RunState.new_run(92)
	for id in RelicDB.ids():
		exhausted.relic_stacks[id] = RelicDB.MAX_RANK
	Loot.redeem(exhausted, "high", "maxed")
	var reloaded := RunState.from_dict(exhausted.to_dict())
	var before := reloaded.essence
	t.check(reloaded.choose_reward(reloaded.reward_choices()[0]), "传奇候选满级时仍可结算")
	t.eq(reloaded.essence, before + 16, "满级传奇折算16原质")
