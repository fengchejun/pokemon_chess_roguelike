extends RefCounted

## 战损与持久化：持续战损、濒死与基地休养、结算口径、存档往返

const SAVE_PATH := "res://.test_save.json"


func run(t: TestContext) -> void:
	t.begin("结算与存档")
	_t_new_run(t)
	_t_sustained_damage(t)
	_t_victory_rewards(t)
	_t_bonus_reward_credit(t)
	_t_monster_experience(t)
	_t_attributed_and_shared_kills(t)
	_t_capture_nest_and_reward_xp(t)
	_t_battle_recovery(t)
	_t_supply(t)
	_t_capture_resolution(t)
	_t_forced_retreat(t)
	_t_escape_flow(t)
	_t_faint_and_recover(t)
	_t_storage_overflow(t)
	t.finish()


func _t_new_run(t: TestContext) -> void:
	var run := RunState.new_run(1001)
	t.eq(run.carried.size(), 5, "初始队伍 5 只")
	t.eq(run.trainer_hp, int(SpeciesDB.get_species("trainer").get("hp", 7)), "训练家满生命")
	t.eq(run.supply_due(), false, "开局不进入补给点")
	t.eq(run.cards.size(), 0, "新局不再免费获得站位卡")
	t.eq(run.reward_inventory.size(), 0, "新局奖励背包为空")
	t.eq(run.mod_points(), 0, "未使用改造工具时无免费地形改造")
	t.eq(run.exp, 0, "初始经验 0")


func _t_sustained_damage(t: TestContext) -> void:
	var run := RunState.new_run(2002)
	var state := TestScenario.make_state(["fire_starter"], [])
	run.mark_deployed([1])
	state.unit_by_uid(1).hp = 2
	run.sync_from_battle(state)
	t.eq(int(run.record_by_uid(1)["hp"]), 2, "战斗后生命不回满（持续战损）")


func _t_victory_rewards(t: TestContext) -> void:
	var run := RunState.new_run(3003)
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(2, 3)]])
	run.mark_deployed([1])
	state.unit_by_uid(100).hp = 2
	state.unit_by_uid(1).cell = Vector2i(0, 3)
	state.unit_by_uid(1).skills.append("fire_seed")
	state.cast_skill(state.unit_by_uid(1), "fire_seed", {"type": "cell", "cell": Vector2i(2, 3)})
	run.sync_from_battle(state)
	var outcome := run.settle_battle(state)
	t.eq(state.end_reason, "victory", "胜利结束")
	t.eq(int(outcome["exp"]), 2, "击败经验 2")
	t.eq(outcome.has("carrier_exp"), false, "局内 Buff 不再提供携带者经验")
	t.eq(run.exp, 0, "废弃的全队经验不再累积")
	t.eq(run.pending_reward_choices, 1, "正常结算获得一次战后奖励三选一")
	t.eq(int(run.record_by_uid(1)["xp"]), 2, "实际击败者获得本局经验")
	t.eq(int(run.record_by_uid(1)["affinity"]), 1, "出战怪物完成非失败战斗获得永久亲密度")
	t.eq(run.in_battle, false, "结算后离开战斗态")
	t.eq(int(run.stats["victories"]), 1, "统计胜利")


func _t_bonus_reward_credit(t: TestContext) -> void:
	var run := RunState.new_run(3004)
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var holder := state.unit_by_uid(1)
	holder.cell = state.reward["cell"]
	state.begin_enemy_phase()
	state.end_enemy_phase()
	state.end_battle("victory")
	var outcome := run.settle_battle(state)
	t.check(bool(outcome.get("bonus_choice_earned", false)), "守点者存活到战后，记录一次额外选择")
	t.eq(run.pending_reward_choices, 2, "常规一次加守点一次，战后共可选择两次")
	t.eq(run.pending_bonus_choices, 0, "守点额外奖励在本场战后兑现")
	var repeated := run.settle_battle(state)
	t.eq(repeated, outcome, "同一场战斗重复结算复用原结果")
	t.eq(run.pending_reward_choices, 2, "重复结算不再增加奖励次数")
	var save_path := "res://.test_bonus_reward_save.json"
	t.check(SaveSystem.save_run(run, save_path), "待领战后奖励可写入本局存档")
	var loaded := SaveSystem.load_run(save_path)
	t.check(loaded != null and loaded.pending_reward_choices == 2, "读档恢复两次待领奖励")
	SaveSystem.delete_save(save_path)
	var legacy := RunState.from_dict({"version": RunState.SAVE_VERSION})
	t.eq(legacy.pending_reward_choices, 0, "旧存档缺少奖励字段时默认为零")


func _t_monster_experience(t: TestContext) -> void:
	var run := RunState.new_run(3005)
	var battle := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [
		["fire_wild1", Vector2i(5, 2)], ["water_wild1", Vector2i(6, 3)],
	])
	run.mark_deployed([1, 2, 3])
	battle.kill_unit(battle.unit_by_uid(2), "测试濒死", "enemy")
	for enemy in battle.alive_units("enemy"):
		battle.kill_unit(enemy, "测试击败", "player")
	battle.check_battle_end()
	run.sync_from_battle(battle)
	var outcome := run.settle_battle(battle)
	t.eq(int(outcome["exp"]), 6, "两次无归属击败让原出战三怪各得两点经验")
	t.eq(int(run.record_by_uid(1)["xp"]), 2, "首位出战怪物获得共享击败经验")
	t.eq(int(run.record_by_uid(2)["xp"]), 2, "濒死的原出战怪物仍获得共享击败经验")
	t.eq(int(run.record_by_uid(3)["xp"]), 2, "第三只出战怪物获得相同共享经验")
	t.eq(int(run.record_by_uid(2)["hp"]), 0, "获得经验不会立即救活濒死怪物")
	t.eq((outcome["monster_exp"] as Array).size(), 3, "战后报告列出每只出战怪物的经验")
	for uid in [1, 2, 3]:
		t.eq(int(run.record_by_uid(uid)["affinity"]), 1, "原出战怪物 %d 均增加亲密度，濒死也计" % uid)
	run.settle_battle(battle)
	t.eq(int(run.record_by_uid(2)["xp"]), 2, "重复结算不重复发放怪物经验")
	t.eq(int(run.record_by_uid(2)["affinity"]), 1, "重复结算不重复发放亲密度")


func _t_attributed_and_shared_kills(t: TestContext) -> void:
	var run := RunState.new_run(3011)
	var battle := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [
		["fire_wild1", Vector2i(5, 2)], ["water_wild1", Vector2i(6, 3)],
	])
	run.mark_deployed([1, 2, 3])
	battle.kill_unit(battle.unit_by_uid(100), "测试直接击败", "player", 1)
	battle.kill_unit(battle.unit_by_uid(101), "测试共享击败", "player", -1)
	battle.end_battle("victory")
	var outcome := run.settle_battle(battle)
	t.eq(int(run.record_by_uid(1)["xp"]), 3, "归属击败者得两点，另获共享一点")
	t.eq(int(run.record_by_uid(2)["xp"]), 1, "其他原出战怪物仅获共享一点")
	t.eq(int(run.record_by_uid(3)["xp"]), 1, "第三只原出战怪物仅获共享一点")
	t.eq(int(outcome["exp"]), 5, "结算经验汇总以个人实际所得为准")
	t.eq((outcome["monster_exp"] as Array).size(), 3, "结算明细按原出战实例记录")


func _t_capture_nest_and_reward_xp(t: TestContext) -> void:
	var run := RunState.new_run(3012)
	var battle := TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [
		["rock_wild1", Vector2i(6, 6)],
	])
	run.mark_deployed([1, 2, 3])
	battle.kill_unit(battle.unit_by_uid(2), "测试濒死", "enemy")
	battle.captured.append({"species_id": "rock_wild1", "hp": 1, "uid": 100, "on_field": false})
	battle.nest["destroyed_by_player"] = true
	battle.reward["state"] = "carried"
	battle.reward["owner_uid"] = 1
	battle.end_battle("victory")
	run.sync_from_battle(battle)
	var outcome := run.settle_battle(battle)
	t.eq(int(run.record_by_uid(1)["xp"]), 6, "存活原出战怪物获得捕获2、毁巢3、奖励1经验")
	t.eq(int(run.record_by_uid(2)["xp"]), 0, "濒死原出战怪物不获得三项存活共享奖励")
	t.eq(int(run.record_by_uid(3)["xp"]), 6, "另一存活原出战怪物同得共享经验")
	t.eq(int(outcome["exp"]), 12, "三项共享奖励按实际存活人数汇总")
	t.eq(run.pending_captures.size(), 1, "捕获怪物进入待收容队列")
	t.eq(int(run.pending_captures[0]["xp"]), 0, "新捕获怪物不追溯领取本场经验")
	for uid in [1, 2, 3]:
		t.eq(int(run.record_by_uid(uid)["affinity"]), 1, "原出战怪物 %d 在非失败结算仍增加亲密度" % uid)
	t.eq(int(run.pending_captures[0]["affinity"]), 0, "本场新捕获怪物不追溯增加亲密度")


func _t_battle_recovery(t: TestContext) -> void:
	var run := RunState.new_run(9101)
	run.trainer_hp = 2
	run.carried[0]["hp"] = SpeciesDB.hp_of("fire_starter")
	run.carried[1]["hp"] = SpeciesDB.hp_of("water_starter") - 1
	run.carried[2]["hp"] = 1
	var battle := TestScenario.make_state(["fire_starter"], [])
	run.mark_deployed([1])
	var outcome := run.settle_battle(battle)
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	t.eq(run.trainer_hp, trainer_max, "训练家每次出征回满")
	t.eq(int(outcome["trainer_from"]), 2, "记录训练家回满前生命")
	t.eq(int(run.carried[1]["hp"]), SpeciesDB.hp_of("water_starter"), "留守基地成员回满 100%")
	t.eq(int(run.carried[2]["hp"]), SpeciesDB.hp_of("grass_starter"), "留守残血成员回满")
	t.eq((outcome["base_rest"] as Array).size(), 2, "基地休养明细 2 条")
	# 出战成员的 30% 恢复（非失败结局）
	run.carried[0]["hp"] = 3
	var next_battle := TestScenario.make_state(["fire_starter"], [])
	run.mark_deployed([1])
	var outcome2 := run.settle_battle(next_battle)
	var fire_max := SpeciesDB.hp_of("fire_starter")
	t.eq(int(run.carried[0]["hp"]), mini(fire_max, 3 + RunState.recovery_amount(fire_max)), "出战成员战后恢复 30%")
	t.eq((outcome2["recovery"] as Array).size(), 1, "出战恢复明细 1 条")
	var run2 := RunState.new_run(9102)
	var battle2 := TestScenario.make_state(["fire_starter"], [])
	run2.mark_deployed([1])
	battle2.kill_unit(battle2.unit_by_uid(1), "测试倒下", "enemy")
	run2.sync_from_battle(battle2)
	run2.settle_battle(battle2)
	t.eq(run2.carried.size(), 5, "濒死成员保留在名单")
	t.eq(int(run2.record_by_uid(1)["hp"]), 0, "出战濒死不享受 30% 恢复，等待基地休养")


func _t_supply(t: TestContext) -> void:
	var run := RunState.new_run(9201)
	t.eq(run.supply_due(), false, "完成 0 场时不安排补给")
	run.battle_index = Balance.SUPPLY_INTERVAL
	t.eq(run.supply_due(), true, "每 %d 场后有补给点" % Balance.SUPPLY_INTERVAL)
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	var amount := maxi(1, roundi(float(trainer_max) * Balance.SUPPLY_TRAINER_RECOVERY_RATIO))
	run.trainer_hp = 2
	var summary := run.apply_supply_recovery()
	t.eq(run.trainer_hp, mini(trainer_max, 2 + amount), "训练家补给恢复 50%% 上限")
	t.eq(int(summary["trainer_to"]), run.trainer_hp, "补给明细一致")
	run.apply_supply_recovery()
	t.eq(run.trainer_hp, trainer_max, "补给不超过上限")
	run.battle_index = Balance.BATTLES_PER_RUN
	t.eq(run.supply_due(), false, "最后一场后不再安排补给")
	run.battle_index = Balance.SUPPLY_INTERVAL
	run.pending_supply = true
	t.check(SaveSystem.save_run(run, "res://.test_supply_save.json"), "写入存档")
	var loaded := SaveSystem.load_run("res://.test_supply_save.json")
	t.check(loaded != null and loaded.pending_supply, "补给待办随存档持久化")
	SaveSystem.delete_save("res://.test_supply_save.json")


func _t_capture_resolution(t: TestContext) -> void:
	var run := RunState.new_run(9301)
	t.eq(run.carried.size(), 5, "初始出战名单 5 只")
	# 战斗中的捕获先进入待处理队列（同步时不立即入队）
	var battle := TestScenario.make_state(["fire_starter"], [])
	run.mark_deployed([1])
	battle.captured.append({"species_id": "water_wild1", "hp": 3})
	run.sync_from_battle(battle)
	t.eq(run.pending_captures.size(), 1, "捕获进入待处理队列")
	t.check((run.pending_captures[0] as Dictionary).has("uid"), "待处理捕获自带 uid")
	t.eq(run.carried.size(), 5, "名单暂不变动")
	# 名单未满：直接入队
	t.eq(run.capture_join_team(), true, "名单未满时捕获直接入队")
	t.eq(run.carried.size(), 6, "名单增长到 6")
	t.eq(int(run.carried[5]["hp"]), 3, "捕获保留剩余生命")
	t.check(run.carried[5].has("uid"), "入队记录带 uid")
	# 名单满：替换（被替换者入仓库）
	run.pending_captures.append({"species_id": "fire_wild1", "hp": 4})
	var old_uid := int(run.carried[0]["uid"])
	t.eq(run.capture_replace(old_uid), true, "替换成功")
	t.eq(run.carried.size(), 6, "名单仍为 6")
	t.eq(run.record_by_uid(old_uid).is_empty(), true, "被替换者离开名单")
	t.eq(run.storage.size(), 1, "被替换者进入仓库")
	t.eq(SpeciesDB.name_of(String(run.carried[5]["species_id"])), "六尾", "捕获进入名单末位")
	t.check(run.carried[5].has("uid"), "替换进入的记录带 uid")
	# 名单满：放入仓库
	run.pending_captures.append({"species_id": "grass_wild1", "hp": 2})
	t.eq(run.capture_to_storage(), true, "放入仓库成功")
	t.eq(run.storage.size(), 2, "仓库增长")
	t.eq(run.pending_captures.size(), 0, "队列清空")
	# 放弃捕获
	run.pending_captures.append({"species_id": "rock_wild1", "hp": 1})
	run.capture_discard()
	t.eq(run.pending_captures.size(), 0, "放弃后队列清空")
	t.eq(run.storage.size(), 2, "放弃不影响仓库")
	# 名单空则本局结束
	var run2 := RunState.new_run(9302)
	run2.carried = []
	t.eq(run2.run_lost(), true, "名单为空即本局结束")
	# 读档修复：历史/异常记录缺少 uid 时自动补齐（修复崩溃来源存档）
	var data := RunState.new_run(9311).to_dict()
	(data["carried"] as Array).append({"species_id": "fire_wild1", "hp": 4})
	data["pending_captures"] = [{"species_id": "water_wild1", "hp": 3}]
	var repaired := RunState.from_dict(data)
	var all_have_uid := true
	for group in [repaired.carried, repaired.storage, repaired.pending_captures]:
		for record in (group as Array):
			if not (record as Dictionary).has("uid"):
				all_have_uid = false
	t.eq(all_have_uid, true, "读档自动补齐缺失的 uid")


func _t_forced_retreat(t: TestContext) -> void:
	var run := RunState.new_run(5005)
	run.carried[1]["hp"] = 1
	run.carried[2]["hp"] = 2
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(2, 3)]])
	run.mark_deployed([1, 2])
	state.unit_by_uid(100).hp = 2
	state.unit_by_uid(1).cell = Vector2i(0, 3)
	state.unit_by_uid(1).skills.append("fire_seed")
	state.cast_skill(state.unit_by_uid(1), "fire_seed", {"type": "cell", "cell": Vector2i(2, 3)})
	# 敌人已死则战斗结束；改用一个新敌人避免干扰
	var state2 := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(5, 3)]])
	run2_setup(t, state2, run)
	state2.damage_unit(state2.unit_by_uid(100), state2.trainer(), 99, {"cause": "测试", "no_element": true})
	t.eq(state2.end_reason, "forced_retreat", "训练家倒下强制撤退")
	var exp_before := run.exp
	run.sync_from_battle(state2)
	var outcome := run.settle_battle(state2)
	t.eq(int(outcome["exp"]), 0, "强制撤退不结算本场经验")
	t.eq(run.exp, exp_before, "经验不变")
	t.eq((outcome["flee_penalty"] as Array).size(), 1, "强制撤退同样按失败减半（1 血不产生变化）")
	t.eq(int(run.record_by_uid(1)["hp"]), ceili(float(SpeciesDB.hp_of("fire_starter")) * 0.5), "出战宝可梦生命减半且不享受 30% 恢复")
	t.eq(int(run.record_by_uid(2)["hp"]), 1, "低血量减半不致死（下限 1）")
	t.eq((outcome["recovery"] as Array).size(), 0, "失败结局不享受出战 30% 恢复")
	t.eq(int(run.record_by_uid(3)["hp"]), SpeciesDB.hp_of("grass_starter"), "留守基地的成员回满 100%")
	t.eq((outcome["base_rest"] as Array).size(), 1, "基地休养明细 1 条")
	t.eq(run.trainer_hp, int(SpeciesDB.get_species("trainer").get("hp", 7)), "训练家回满")


func run2_setup(t: TestContext, state: BattleState, run: RunState) -> void:
	run.mark_deployed([1, 2])
	t.check(true, "准备强制撤退场景")


func _t_escape_flow(t: TestContext) -> void:
	var run := RunState.new_run(6006)
	var state := TestScenario.make_state(["fire_starter"], [["fire_wild1", Vector2i(5, 7)]])
	run.mark_deployed([1])
	state.round = Balance.MAX_ROUNDS
	state.settle_round()
	t.eq(state.end_reason, "escape", "野生逃离结束")
	var outcome := run.settle_battle(state)
	t.eq(run.pending_reward_choices, 1, "野生逃离仍获得一次常规战后奖励选择")
	t.eq(outcome.has("carrier_exp"), false, "逃离也不结算旧携带者经验")


func _t_faint_and_recover(t: TestContext) -> void:
	var run := RunState.new_run(7007)
	var state := TestScenario.make_state(["fire_starter"], [])
	state.kill_unit(state.unit_by_uid(1), "测试倒下", "enemy")
	run.sync_from_battle(state)
	t.eq(run.carried.size(), 5, "倒下不再移出名单")
	t.eq(int(run.record_by_uid(1)["hp"]), 0, "濒死状态生命为 0")
	t.eq(run.deaths.size(), 1, "写入战损记录")
	t.eq(int(run.deaths[0]["uid"]), 1, "档案记录实例")
	t.check(SaveSystem.save_run(run, SAVE_PATH), "写入存档")
	var loaded := SaveSystem.load_run(SAVE_PATH)
	t.check(loaded != null, "读档成功")
	if loaded != null:
		t.eq(loaded.carried.size(), 5, "读档后濒死成员仍在名单")
		t.eq(int(loaded.record_by_uid(1)["hp"]), 0, "读档濒死状态不变（不自动复活）")
		t.eq(loaded.deaths.size(), 1, "读档后战损记录保留")
	SaveSystem.delete_save(SAVE_PATH)
	# 基地休养复活
	var run2 := RunState.new_run(7008)
	var battle2 := TestScenario.make_state(["fire_starter", "water_starter"], [])
	battle2.kill_unit(battle2.unit_by_uid(1), "测试倒下", "enemy")
	run2.sync_from_battle(battle2)
	t.eq(int(run2.record_by_uid(1)["hp"]), 0, "小火龙濒死")
	run2.mark_deployed([2])
	var outcome := run2.settle_battle(battle2)
	t.eq(int(run2.record_by_uid(1)["hp"]), SpeciesDB.hp_of("fire_starter"), "留守一个冒险周期后濒死恢复满血")
	t.eq((outcome["base_rest"] as Array).size(), 1, "基地休养明细包含濒死恢复")
	# 全员濒死 → 本局结束
	var run3 := RunState.new_run(7009)
	for record in run3.carried:
		record["hp"] = 0
	t.eq(run3.run_lost(), true, "全员濒死即本局结束")


func _t_storage_overflow(t: TestContext) -> void:
	var run := RunState.new_run(8008)
	while run.carried.size() < Balance.CARRIED_LIMIT:
		run._add_capture("fire_wild1", 4)
	t.eq(run.carried.size(), Balance.CARRIED_LIMIT, "名单满员")
	run._add_capture("water_wild1", 4)
	t.eq(run.storage.size(), 1, "满员注入进入仓库")
	while run.storage.size() < Balance.STORAGE_LIMIT:
		run._add_capture("fire_wild1", 4)
	t.eq(run.storage.size(), Balance.STORAGE_LIMIT, "仓库满员")
	run.pending_captures.append({"species_id": "water_wild1", "hp": 5})
	t.eq(run.capture_to_storage(), false, "仓库满时不能放入")
	t.eq(run.capture_replace(int(run.carried[0]["uid"])), false, "仓库满时不能替换")
	var release_uid := int(run.storage[0]["uid"])
	t.eq(run.release_storage(release_uid), true, "放生一名仓库成员")
	t.eq(run.capture_to_storage(), true, "腾出空间后可放入仓库")
	t.eq(run.pending_captures.size(), 0, "处理后进入下一场")
	t.eq(run.storage.size(), Balance.STORAGE_LIMIT, "放生一只后补入新捕获")
	t.eq(run.record_by_uid(release_uid).is_empty(), true, "被放生的成员离开仓库")
