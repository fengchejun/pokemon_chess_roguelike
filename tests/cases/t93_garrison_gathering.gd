extends RefCounted

const Flow = preload("res://scripts/run/exploration_flow.gd")
const Invasion = preload("res://scripts/run/floor_invasion.gd")

func run(t: TestContext) -> void:
	t.begin("驻守采集、有限储量、存档与加固")
	var state := RunState.new_run(93001)
	state.region_mode = true
	state.options["exploration_v2"] = true
	state.floor_themes = ["grass"]
	var region := Flow.generate(0, "grass", state.seed)
	for id in ["battle_1", "battle_2", "elite_1"]:
		region.nodes[id]["unlocked"] = true
	state.region_data = region.to_dict()
	var a := state._make_record("grass_wild1")
	var b := state._make_record("rock_wild1")
	state.storage.append_array([a, b])
	var uid := int(a["uid"])
	t.check(not Invasion.assign(state, "battle_1", uid, "gather"), "未打通不能采集")
	region.nodes["battle_1"]["passable"] = true
	region.nodes["elite_1"]["passable"] = true
	state.region_data = region.to_dict()
	t.check(Invasion.assign(state, "battle_1", uid, "gather"), "仓库伙伴可采集")
	var food_before := state.total_food()
	_step(state)
	t.eq(state.get_region().nodes["battle_1"].get("gather_progress", 0), 0, "到达当次不采集")
	_step(state)
	_step(state)
	state = RunState.from_dict(state.to_dict())
	t.eq(state.get_region().nodes["battle_1"]["gather_progress"], 2, "读档保留未完成进度")
	_step(state)
	t.eq(state.total_food(), food_before + 1, "三次采集产出一份基础食物")
	region = state.get_region()
	Invasion.collect(state, region)
	t.eq(state.total_food(), food_before + 1, "重复结算不产出")
	var points := Invasion.breakdown(region, region.garrisons[str(uid)], state.owned_record_by_uid(uid))
	t.eq(points["base"], 13, "采集守备基础减半")
	t.eq(points["specialty"] + points["preparation"], 0, "采集没有适配与准备奖励")
	t.check(Invasion.assign(state, "battle_1", int(b["uid"]), "gather"), "第二人共用资源储量")
	_step(state)
	_step(state)
	_step(state)
	t.eq(state.total_food(), food_before + 2, "多人加速但最多两批")
	t.eq(state.get_region().nodes["battle_1"]["gather_progress"], 0, "耗尽后清空进度")
	t.check(not Invasion.assign(state, "battle_1", uid, "gather"), "耗尽不能再派采集")
	t.check(Invasion.assign(state, "elite_1", uid, "gather"), "可改派建材点")
	_step(state)
	_step(state)
	_step(state)
	_step(state)
	t.eq(state.building_materials, 1, "建材产出入库")
	var before := Invasion.chance(state, state.get_region(), "camp")
	t.check(Invasion.fortify(state, "camp"), "建材可加固营地")
	t.eq(state.building_materials, 0, "加固消耗一份")
	t.eq(Invasion.chance(state, state.get_region(), "camp"), before, "营地无人时仍受入侵压力抵消")
	state.building_materials = 3
	t.check(Invasion.fortify(state, "camp"), "允许第二次加固")
	t.check(not Invasion.fortify(state, "camp"), "加固两次封顶")
	t.check(not Invasion.fortify(state, "boss"), "首领不可加固")
	state = RunState.from_dict(state.to_dict())
	t.eq(state.get_region().nodes["camp"]["fortification"], 2, "存档保留加固")
	t.eq(state.building_materials, 2, "存档保留建材")
	region = state.get_region()
	region.invaded = true
	region.visits += 10
	Invasion.collect(state, region)
	t.eq(state.building_materials, 2, "入侵后停止采集")
	state.region_data = region.to_dict()
	t.check(not Invasion.fortify(state, "camp"), "入侵后不可加固")
	var legacy := state.to_dict()
	legacy.erase("building_materials")
	t.eq(RunState.from_dict(legacy).building_materials, 0, "旧存档默认无建材")
	var fresh := RunState.new_run(93002)
	fresh.region_mode = true
	fresh.options["exploration_v2"] = true
	fresh.floor_themes = ["grass"]
	var fresh_region := Flow.generate(0, "grass", fresh.seed)
	fresh_region.nodes["battle_1"]["passable"] = true
	fresh_region.nodes["battle_1"]["unlocked"] = true
	fresh.region_data = fresh_region.to_dict()
	var fresh_uid := int(fresh.carried[0]["uid"])
	t.check(Invasion.assign(fresh, "battle_1", fresh_uid, "gather"), "随身伙伴可远程采集")
	t.check(fresh.enter_region_node("battle_1"), "正常入口进入待结算战斗")
	fresh.cancel_region_entry()
	t.eq(fresh.get_region().visits, 0, "取消进入还原行动")
	t.eq(fresh.total_food(), 3, "取消进入无采集产出")
	fresh_region = fresh.get_region()
	fresh_region.garrisons[str(fresh_uid)].erase("duty")
	t.eq(Invasion.breakdown(fresh_region, fresh_region.garrisons[str(fresh_uid)], fresh.carried[0])["base"], 26, "旧驻军默认完整警戒贡献")
	fresh_region.nodes["battle_1"]["gather_progress"] = 2
	fresh_region.visits = 12
	t.check(Invasion.resolve(fresh, fresh_region), "入侵正常结算")
	t.eq(fresh_region.nodes["battle_1"]["gather_progress"], 0, "入侵丢弃未完成批次")
	t.finish()

func _step(state: RunState) -> void:
	var region = state.get_region()
	region.visits += 1
	region.visit_pending = true
	var food_before := state.total_food()
	Invasion.collect(state, region)
	assert(state.total_food() == food_before)
	region.notifications.append_array(region.complete_visit(state))
	state.region_data = region.to_dict()
