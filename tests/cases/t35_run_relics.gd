extends RefCounted


func run(t: TestContext) -> void:
	t.begin("旧遗物删除与空池兼容")
	_empty_pool(t)
	_legacy_data_filtering(t)
	_effects_removed(t)
	t.finish()


func _empty_pool(t: TestContext) -> void:
	t.eq(RelicDB.DEFINITIONS, {}, "旧遗物定义已全部删除")
	t.eq(RelicDB.ids(), [], "遗物候选池为空")
	t.eq(RelicDB.offer(1, 0, 0, {}), [], "空池不会生成遗物候选")
	var run := RunState.new_run(35001)
	run.pending_reward_choices = 2
	t.eq(run.reward_choices(), [], "待领次数存在时仍不伪造遗物")
	t.eq(run.choose_reward("fire_mark"), false, "旧遗物 ID 不能领取")
	t.eq(run.discard_unavailable_reward_choices(), 2, "空池会清理全部待领遗物机会")
	t.eq(run.pending_reward_choices, 0, "清理后不会阻塞结算继续")


func _legacy_data_filtering(t: TestContext) -> void:
	var old_data := RunState.new_run(35002).to_dict()
	old_data["relic_stacks"] = {"fire_mark": 3, "rock_armor": 2, "wind_pressure": 1}
	var loaded := RunState.from_dict(old_data)
	t.eq(loaded.relic_stacks, {}, "旧存档中的遗物栈读取时清空")
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.relic_stacks = {"fire_mark": 3, "first_strike": 2}
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	t.eq(restored.relic_stacks, {}, "旧战斗快照中的遗物栈读取时清空")


func _effects_removed(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	target.max_hp = 100
	target.hp = 100
	state.relic_stacks = {"fire_mark": 3, "burn_chaser": 3, "first_strike": 3}
	var hit := state.damage_unit(caster, target, 10, {"skill_direct": true, "element": "fire"})
	t.eq(int(hit["amount"]), Elements.direct_damage(10, "fire", "grass"), "旧遗物不再增加技能直伤")
	t.check(not hit.has("relic_healed"), "旧余烬回血结算字段已删除")
	t.eq(target.burn_ticks, 0, "旧火印不再附加灼烧")

	var terrain := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.OBSTACLE]])
	var push_state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]], terrain)
	push_state.relic_stacks = {"wall_crash": 3}
	var pushed := PushResolver.push(push_state, push_state.unit_by_uid(100), Vector2i.RIGHT, 1, 0, "测试", "player", 1, "rock_push")
	t.eq(int(pushed["collisions"][0]["target_damage"]), Balance.COLLISION_DAMAGE, "旧冲壁不再增加碰撞伤害")
