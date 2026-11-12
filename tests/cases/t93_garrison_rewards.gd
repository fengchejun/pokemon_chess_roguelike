extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")
const Invasion = preload("res://scripts/run/floor_invasion.gd")
const Rewards = preload("res://scripts/run/garrison_rewards.gd")

func fixture() -> RunState:
	var state := RunState.new_run(93001)
	state.region_mode = true
	state.options["exploration_v2"] = true
	state.floor_themes = ["grass"]
	var region := Flow.generate(0, "grass", state.seed)
	for node in region.nodes.values():
		node["unlocked"] = true
	state.region_data = region.to_dict()
	state.storage.append(state._make_record("grass_wild1"))
	return state

func elapsed(state: RunState, actions: int) -> void:
	var region = state.get_region()
	region.visits += actions
	state.region_data = region.to_dict()

func run(t: TestContext) -> void:
	t.begin("驻守结束回报、强制结算与额度去重")
	var state := fixture()
	var uid := int(state.storage[0]["uid"])
	var key := str(uid)
	t.check(Invasion.assign(state, "camp", uid), "指派仓库伙伴")
	t.check(Invasion.recall(state, uid), "立即撤回")
	t.eq(state.garrison_reward_rolls.get(key, 0), 0, "未就位无奖励")
	Invasion.assign(state, "camp", uid)
	elapsed(state, 3)
	Invasion.recall(state, uid)
	t.eq(state.garrison_reward_credits[key], 2, "到达耗一次行动，剩两点额度保留")
	t.eq(state.garrison_reward_rolls.get(key, 0), 0, "不足三点暂不抽取")
	Invasion.assign(state, "camp", uid)
	elapsed(state, 2)
	var saved := state.to_dict()
	var clone := RunState.from_dict(saved)
	Invasion.recall(state, uid)
	Invasion.recall(clone, uid)
	t.eq(state.garrison_reward_rolls[key], 1, "重复派驻累计到三点抽一份")
	t.eq(state.to_dict(), clone.to_dict(), "读档后结算结果固定")
	t.check(not Invasion.recall(state, uid), "不能重复撤回领奖")
	Invasion.assign(state, "camp", uid)
	elapsed(state, 10)
	Invasion.assign(state, "battle_1", uid)
	t.eq(state.garrison_reward_rolls[key], 4, "改派结算九次有效行动三份奖励")
	var region = state.get_region()
	region.visits += 2
	state.region_data = region.to_dict()
	region = state.get_region()
	Rewards.finish_all(state, region, "离开本层")
	t.eq(state.garrison_reward_rolls[key], 5, "跨层不足三次也结算一份")
	t.check(region.garrisons.is_empty(), "跨层释放驻军")
	Rewards.finish_all(state, region, "离开本层")
	t.eq(state.garrison_reward_rolls[key], 5, "跨层重复结算不重复奖励")
	var short_odds := Rewards.odds(1)
	var long_odds := Rewards.odds(12)
	t.check(long_odds["rare"] > short_odds["rare"] and long_odds["legendary"] > short_odds["legendary"], "久驻同时提高两档稀有概率")
	for actions in range(13):
		var odds := Rewards.odds(actions)
		t.eq(odds["common"] + odds["rare"] + odds["legendary"], 100, "概率和100")
		t.check(odds["common"] > odds["rare"] and odds["rare"] > odds["legendary"], "高级稀有度概率更低")
	var all_ids: Array = []
	for rarity in ["common", "rare", "legendary"]:
		all_ids.append_array(Rewards.reward_pool(rarity))
	for id in Merchant.ITEMS:
		t.check(all_ids.has("item:" + id), "包含商店道具 " + id)
	for id in RelicDB.ids():
		t.check(all_ids.has("relic:" + id), "包含遗物 " + id)
	for id in RewardDB.consumable_ids():
		t.check(all_ids.has("card:" + id), "包含卡片与改造 " + id)
	for id in all_ids:
		t.check(not Rewards.grant(state, id).is_empty(), "奖励均可发放 " + id)
	state.relic_stacks["fire_mark"] = RelicDB.MAX_RANK
	var before := state.essence
	Rewards.grant(state, "relic:fire_mark")
	t.eq(state.essence, before + 6, "满级遗物折算原质")
	var legacy := state.to_dict()
	legacy["building_materials"] = 2
	legacy["region_data"]["nodes"]["camp"]["fortification"] = 1
	legacy["region_data"]["nodes"]["camp"]["gathered_batches"] = 2
	var migrated := RunState.from_dict(legacy)
	t.eq(migrated.essence, state.essence + 9, "旧建材及加固补偿原质")
	t.check(not migrated.get_region().nodes["camp"].has("gathered_batches"), "移除旧节点采集状态")
	t.eq(RunState.from_dict(migrated.to_dict()).essence, migrated.essence, "迁移补偿不重复")
	state = fixture()
	uid = int(state.storage[0]["uid"])
	key = str(uid)
	Invasion.assign(state, "camp", uid)
	elapsed(state, 12)
	region = state.get_region()
	region.floor_index = 20
	t.check(Invasion.resolve(state, region), "入侵结算")
	t.check(not region.nodes["camp"]["defense"]["held"], "确保测试覆盖驻守失败")
	t.eq(state.garrison_reward_rolls[key], 4, "入侵遣返结算十一有效行动含余数")
	t.check(region.garrisons.is_empty(), "入侵释放所有驻军")
	before = int(state.garrison_reward_rolls[key])
	Invasion.resolve(state, region)
	t.eq(state.garrison_reward_rolls[key], before, "入侵不重复发奖")
	state = fixture()
	uid = int(state.storage[0]["uid"])
	key = str(uid)
	Invasion.assign(state, "camp", uid)
	elapsed(state, 4)
	t.check(state.enter_region_node("battle_1"), "进入可取消的整备")
	Invasion.recall(state, uid)
	state.cancel_region_entry()
	t.check(not state.get_region().garrisons.has(key), "取消进入保留撤回结果")
	t.eq(state.garrison_reward_rolls[key], 1, "取消进入不会回退已发放奖励")
	t.check(not Invasion.recall(state, uid), "不能通过取消恢复驻军重复领奖")
	_main_flow(t)
	t.finish()

func _main_flow(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = fixture()
	var state: RunState = app.run
	var uid := int(state.storage[0]["uid"])
	var key := str(uid)
	Invasion.assign(state, "camp", uid)
	var region = state.get_region()
	region.visits = 4
	region.visit_pending = true
	region.active_node = "boss"
	region.nodes["boss"]["cleared"] = true
	state.region_data = region.to_dict()
	app.continue_after_settlement()
	t.eq(state.battle_index, 6, "正常结算入口进入下一层")
	t.eq(state.garrison_reward_rolls[key], 1, "跨层包含已完成首领节点的行动")
	t.eq(state.garrison_reward_credits[key], 0, "跨层强制结算清空余数")
	t.check(state.region_data.is_empty(), "本层驻军结算后释放地图")
	t.check(app.current_screen.name == "FloorThemeScreen", "下一层主题选择正常打开")
	var restored := RunState.from_dict(state.to_dict())
	t.eq(restored.garrison_reward_rolls[key], 1, "跨层结算保存并恢复")
	app.run = fixture()
	state = app.run
	uid = int(state.storage[0]["uid"])
	key = str(uid)
	Invasion.assign(state, "camp", uid)
	elapsed(state, 3)
	state.run_failed = true
	app.show_run_end()
	t.eq(state.garrison_reward_rolls[key], 1, "本局被迫结束也结算剩余额度")
	app.show_run_end()
	t.eq(state.garrison_reward_rolls[key], 1, "结束页重复打开不重复发奖")
	app.run = fixture()
	state = app.run
	state.trainer_items[Merchant.INTEL_ID] = 1
	t.check(Merchant.use_intel(state), "奖励情报可以从背包使用")
	t.eq(state.trainer_items[Merchant.INTEL_ID], 0, "情报使用扣除一份")
	state.trainer_items[Merchant.INTEL_ID] = 1
	t.check(not Merchant.use_intel(state), "重复解锁本层栖息地被拒绝")
	t.eq(state.trainer_items[Merchant.INTEL_ID], 1, "无法使用时保留情报")
	app.free()
