extends RefCounted

const Flow = preload("res://scripts/run/exploration_flow.gd")
const Habitat = preload("res://scripts/rules/capture_encounter.gd")


func run(t: TestContext) -> void:
	t.begin("成长糖果、情报商品与一次性稀有捕捉")
	_candy_rules(t)
	_shop_and_habitat(t)
	t.finish()


func _candy_rules(t: TestContext) -> void:
	var run_state := RunState.new_run(41)
	var tiers := {"xp_candy_small": [6, 2], "xp_candy_medium": [30, 4], "xp_candy_large": [70, 6]}
	for id in tiers:
		var member := run_state._make_record("fire_starter")
		run_state.carried.append(member)
		run_state.trainer_items[id] = 1
		var growth := Merchant.use_candy(run_state, id, int(member["uid"]))
		t.eq(growth.get("gained"), tiers[id][0], "经验糖果增加固定经验")
		t.eq(member["level"], tiers[id][1], "一级成员到达糖果对应等级")
		t.eq(run_state.trainer_items[id], 0, "成功使用只扣一件糖果")
	var member: Dictionary = run_state.carried.back()
	MonsterProgression.award_xp(member, 100)
	member["hp"] = 0
	var uid := int(member["uid"])
	run_state.trainer_items[Merchant.RARE_CANDY] = 2
	t.eq(Merchant.use_candy(run_state, Merchant.RARE_CANDY, uid).get("level_after"), 10, "神奇糖果可把九级稳定升到满级")
	t.eq(member["hp"], 0, "糖果不会复活濒死成员")
	t.check(Merchant.use_candy(run_state, Merchant.RARE_CANDY, uid).is_empty(), "满级拒绝用糖")
	t.eq(run_state.trainer_items[Merchant.RARE_CANDY], 1, "满级失败不扣库存")
	var other := run_state._make_record("water_starter")
	run_state.carried.append(other)
	MonsterProgression.award_xp(other, 9)
	var other_uid := int(other["uid"])
	run_state.battle_snapshot = {"active": true}
	t.check(Merchant.use_candy(run_state, Merchant.RARE_CANDY, other_uid).is_empty(), "活动战斗中禁止吃糖")
	run_state.battle_snapshot.clear()
	var result := Merchant.use_candy(run_state, Merchant.RARE_CANDY, other_uid)
	t.eq(result.get("level_after"), 3, "未满级时也只升一级")
	t.eq(result.get("xp_after"), 19, "神奇糖果保留本级已有经验")


func _shop_and_habitat(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.begin_new_run_with_collection(CollectionState.defaults().select_records([1, 2, 3]))
	var run_state: RunState = app.run
	run_state.choose_floor_theme(String(run_state.offered_floor_themes[0]))
	run_state.essence = 150
	var region: RegionState = run_state.get_region()
	region.nodes["event_2"]["unlocked"] = true
	region.nodes["event_2"]["stock"] = {"potion": 0, "food": 4}
	run_state.region_data = region.to_dict()
	app.enter_region_node("event_2")
	var shop = app.current_screen
	region = run_state.get_region()
	t.check(not region.nodes.has(Flow.RARE_HABITAT), "购买前没有隐藏节点及连线")
	t.eq(region.nodes["event_2"]["stock"]["potion"], 0, "旧店售罄商品不会被补货")
	t.eq(region.nodes["event_2"]["stock"]["xp_candy_small"], 2, "旧店补入新商品")
	t.check(shop.find_child("Buy_rare_intel", true, false) != null, "旧店补入情报")

	var full := RegionState.from_dict(region.to_dict())
	for y in 4:
		for x in 4:
			var cell := Vector2i(x, y)
			if not full.nodes.keys().any(func(id): return Flow.position(id, full.nodes[id]) == cell):
				full.nodes["test_%d_%d" % [x, y]] = {"position": [x, y]}
	t.check(not Flow.unlock_rare_habitat(full, run_state.seed), "没有空位时不能生成情报节点")
	var exhausted := RegionState.from_dict(region.to_dict())
	exhausted.visits = Balance.EXPLORATION_ACTIONS
	t.check(not Flow.unlock_rare_habitat(exhausted, run_state.seed), "楼层行动耗尽时不能购买情报")

	shop.find_child("Buy_xp_candy_large", true, false).pressed.emit()
	t.eq(run_state.essence, 114, "大经验糖果按36原质结算")
	shop.find_child("OpenItemBag", true, false).pressed.emit()
	var bag = app.current_screen
	var member: Dictionary = run_state.carried[0]
	var uid := int(member["uid"])
	bag.find_child("UseCandy_xp_candy_large_%d" % uid, true, false).pressed.emit()
	t.eq(member["level"], 6, "商店买糖后可在非战斗背包立即升级")
	var restored := RunState.from_dict(run_state.to_dict())
	t.eq(restored.pending_monster_levels().filter(func(entry): return int(entry["uid"]) == uid).size(), 3, "读档恢复三级待处理学招")
	var old_skills: Array = member["equipped_skills"].duplicate()
	var replaced := false
	for level in [2, 4, 6]:
		var options := run_state.monster_level_choices(uid, level)
		t.check(not options.is_empty(), "每级提供立即可用的学招选择")
		if options.is_empty():
			break
		var skill: String = options[0]
		var learn: Button = bag.find_child("MonsterLearn_%d_%d_%s" % [uid, level, skill], true, false)
		t.check(learn != null, "背包按等级顺序呈现学招")
		if learn == null:
			break
		learn.pressed.emit()
		var replace: Button = bag.find_child("MonsterReplace_%d_%d_%s_%s" % [uid, level, skill, member["equipped_skills"][0]], true, false)
		if replace != null:
			replace.pressed.emit()
			replaced = true
		t.check(member["known_skills"].has(skill), "学招和满栏换招立即生效")
	t.check(replaced and member["known_skills"].has(old_skills[0]), "满栏可换招，卸下的原招式仍留在招式库")
	MonsterProgression.award_xp(member, 100)
	member["claimed_even_levels"].append(8)
	run_state.trainer_items[Merchant.RARE_CANDY] = 1
	bag.refresh()
	bag.find_child("UseCandy_rare_candy_%d" % uid, true, false).pressed.emit()
	var trait_button: Button = bag.find_child("MonsterTrait_%d_10" % uid, true, false)
	t.check(trait_button != null, "背包可领取十级特性入口")
	if trait_button != null:
		trait_button.pressed.emit()
		t.check(member["trait_upgrade_claimed"], "十级入口立即记录为已领取")
	bag.find_child("ReturnFromItemBag", true, false).pressed.emit()

	shop = app.current_screen
	shop.find_child("Buy_rare_intel", true, false).pressed.emit()
	shop.buy(Merchant.INTEL_ID)
	t.eq(run_state.essence, 86, "情报只扣一次28原质")
	t.check(not run_state.trainer_items.has(Merchant.INTEL_ID), "情报购买即生效，不占背包")
	region = run_state.get_region()
	var id := Flow.RARE_HABITAT
	var node: Dictionary = region.nodes[id]
	var species: String = node["rare_species"]
	t.eq(Merchant.rarity(species), "rare", "情报物种标记为稀有")
	var anchor: String = node["links"][0]
	t.check(GridSpec.manhattan(Flow.position(id, node), Flow.position(anchor, region.nodes[anchor])) == 1 and region.nodes[anchor]["links"].has(id), "情报节点使用合法空位和双向正交连线")
	t.eq(RunState.from_dict(run_state.to_dict()).get_region().nodes["event_2"]["stock"][Merchant.INTEL_ID], 0, "售罄状态可读档")
	shop.leave()
	var map_button: Button = app.current_screen.find_child("Node_" + id, true, false)
	t.check(map_button != null and not map_button.disabled and not map_button.text.contains(SpeciesDB.name_of(species)), "地图可进入但不泄露物种")
	var visits: int = run_state.get_region().visits
	app.enter_region_node(id)
	t.eq(run_state.get_region().visits, visits + 1, "隐藏节点消耗一次行动")
	app.cancel_region_entry()
	t.eq(run_state.get_region().visits, visits, "取消整备退回行动")
	app.enter_region_node(id)
	var deployed := run_state.carried.map(func(record): return int(record["uid"])).slice(0, 3)
	app.show_preview(deployed)
	app.current_screen._on_start()
	var state: BattleState = app.current_screen.state
	t.eq(state.alive_enemy_count(), 1, "神秘栖息地只出现一只目标")
	t.eq(state.alive_units("enemy")[0].species_id, species, "进入后揭晓同一个固定目标")
	t.eq(state.capture_deadline, 8, "稀有遭遇沿用八回合上限")

	var fleeing := state.clone()
	fleeing.capture_alerted = true
	var target: CombatUnit = fleeing.alive_units("enemy")[0]
	target.cell = fleeing.capture_exits[0]
	Habitat.act(fleeing, target, {})
	fleeing.round += 1
	Habitat.act(fleeing, target, {})
	t.check(fleeing.ended and fleeing.captured.is_empty(), "目标在撤离点待到下一次行动后逃脱")
	_check_spent(t, run_state, fleeing)
	var leaving := state.clone()
	t.check(leaving.leave_node(), "玩家可直接离开")
	_check_spent(t, run_state, leaving)
	var defeated := state.clone()
	defeated.kill_unit(defeated.alive_units("enemy")[0], "测试", "player", uid)
	defeated.check_battle_end()
	if not defeated.ended:
		defeated.leave_node()
	_check_spent(t, run_state, defeated)

	state.capture_alerted = true
	state.round = 3
	app.sync_and_save(state)
	var path := "user://.test_rare_habitat_%d.json" % OS.get_process_id()
	SaveSystem.save_run(run_state, path)
	app.continue_run(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	run_state = app.run
	state = app.current_screen.state
	t.check(state.capture_alerted and state.round == 3, "读档恢复原遭遇的回合和受惊状态")
	target = state.alive_units("enemy")[0]
	t.eq(target.species_id, species, "读档不重抽稀有物种")
	state.trainer().cell = target.cell + Vector2i.LEFT
	target.hp = 1
	t.check(state.capture_attempt(state.trainer(), target, 0.0).get("success", false), "稀有目标可用常规捕获入口捕捉")
	if not state.ended:
		state.leave_node()
	app.finish_battle(state)
	t.eq(run_state.stats["captures"], 1, "稀有目标使用原有捕获结算")
	t.check(run_state.get_region().nodes[id]["done"], "捕获后永久消耗本层遭遇")
	app.free()


func _check_spent(t: TestContext, run_state: RunState, state: BattleState) -> void:
	var region: RegionState = run_state.get_region()
	region.store_battle(Flow.RARE_HABITAT, state)
	region.complete_visit()
	var restored := RegionState.from_dict(region.to_dict())
	t.check(restored.nodes[Flow.RARE_HABITAT]["done"] and not restored.record_entry(Flow.RARE_HABITAT), "结算并读档后不能重复进入神秘栖息地")
