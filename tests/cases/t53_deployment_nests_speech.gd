extends RefCounted
const Deployment = preload("res://scripts/rules/deployment.gd")

func run(t: TestContext) -> void:
	t.begin("自由部署、右半场双巢穴与气泡")
	_maps(t)
	_nests(t)
	_deployment(t)
	_speech(t)
	t.finish()

func _maps(t: TestContext) -> void:
	var locations := {}
	for seed_value in range(30):
		var map := MapGenerator.generate(seed_value, 5, 0, [], "", 2)
		var cells: Array = map["nest_cells"]
		t.eq(cells.size(), 2, "显式双巢穴地图保留两个巢穴")
		t.check(GridSpec.manhattan(cells[0], cells[1]) >= 3, "双巢穴保持三格间距")
		t.check(MapGenerator._validate(map["terrain"], cells), "两个巢穴均可达")
		for cell in cells:
			locations[cell] = true
			t.check(cell.x >= 4 and not Balance.DEPLOY_AREA.has(cell), "巢穴只在右半场")
			t.check(cell != map["reward_cell"], "巢穴避开奖励")
			t.check(MapGenerator.mod_protected(map, cell), "两个巢穴都禁止战前改造")
		for cell in Balance.DEPLOY_AREA:
			t.eq(map["terrain"][GridSpec.index(cell)], TerrainDB.PLAIN, "八格部署区均受保护")
	t.check(locations.size() >= 10, "多种子巢穴位置充分变化")
	var cfg := BattleDB.config_for(5)
	cfg["nest_count"] = 2
	var fallback := MapGenerator._fallback(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	t.check(MapGenerator.randomize_nests(fallback, cfg, rng), "兜底地图也能放置两个巢穴")

func _nests(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]], [], {}, {}, ["rock_wild1"])
	state.node_kind = "battle"
	state.nest["cell"] = Vector2i(4, 2)
	var second := state.nest.duplicate(true)
	second["cell"] = Vector2i(7, 4)
	state.extra_nests = [second]
	state.start_round()
	t.check(state.unit_at(state.nest["cell"]) != null and state.unit_at(second["cell"]) != null, "两个巢穴独立生成")
	t.eq(second["pending_waves"], 0, "第二巢穴独立扣除积压")
	second["pending_waves"] = 1
	state._try_spawn_wave(second)
	t.eq(second["pending_waves"], 1, "占据第二巢穴时保留积压")
	state.unit_at(second["cell"]).cell = Vector2i(7, 5)
	state._try_spawn_wave(second)
	t.eq(second["pending_waves"], 0, "第二巢穴腾空后兑现积压")
	# Distinct nests in a single area attack are each hit once.
	state.units = state.units.filter(func(unit): return unit.side == "player")
	second["cell"] = Vector2i(5, 2)
	var caster := state.unit_by_uid(1)
	SkillResolver.resolve_channel(state, caster, "fire_burst", [Vector2i(4, 2)])
	t.eq(state.nest["hp"], 2, "范围技能命中主巢穴一次")
	t.eq(second["hp"], 2, "同一范围技能也命中第二巢穴一次")
	var before := state.essence_earned
	state.damage_nest(1, "player", second["cell"])
	state.damage_nest(1, "player", second["cell"])
	t.check(not second["alive"] and state.nest["alive"], "只摧毁指定巢穴")
	var earned := state.essence_earned
	state.damage_nest(1, "player", second["cell"])
	t.eq(state.essence_earned, earned, "摧毁奖励不会重复")
	t.check(earned > before, "第二巢穴有摧毁奖励")
	state.food_cells = [state.nest["cell"], second["cell"], Balance.DEPLOY_AREA[0]]
	state.repair_food()
	t.eq(state.food_cells.size(), 3, "重叠粮食迁移时保留数量")
	t.check(state.food_cells.all(func(cell): return state.food_cell_valid(cell)), "所有粮食迁移到合法格")
	var snapshot := BattleSnapshot.save_state(state)
	var restored := BattleSnapshot.load_state(snapshot)
	t.eq(restored.all_nests(), state.all_nests(), "双巢穴状态存档完整恢复")
	var legacy := snapshot.duplicate(true)
	legacy.erase("version")
	legacy["fields"].erase("extra_nests")
	t.eq(BattleSnapshot.load_state(legacy).all_nests().size(), 1, "旧单巢穴快照只恢复原有巢穴")
	for i in range(2):
		state.damage_nest(1, "player", state.nest["cell"])
	t.eq(state.essence_earned, earned + 8, "两个巢穴分别结算摧毁奖励")
	state.stop_nests()
	t.check(not state.has_live_nests() and second["pending_waves"] == 0, "清场停止所有巢穴")

func _deployment(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(4242)
	app.run.region_mode = false
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_preview([1, 2, 3])
	var screen = app.current_screen
	t.eq(screen.map["deploy_area"].size(), 8, "默认部署区有八格")
	var trainer_cell: Vector2i = screen.deploy_positions[Balance.TRAINER_UID]
	var first_cell: Vector2i = screen.deploy_positions[1]
	screen._on_cell_clicked(trainer_cell)
	screen._on_cell_clicked(first_cell)
	t.eq(screen.deploy_positions[Balance.TRAINER_UID], first_cell, "点击交换训练师和宝可梦")
	t.eq(screen.deploy_positions[1], trainer_cell, "交换后对方位置正确")
	var free_cell := Vector2i(1, 5)
	screen._on_cell_clicked(first_cell)
	screen._on_cell_clicked(free_cell)
	t.eq(screen.deploy_positions[Balance.TRAINER_UID], free_cell, "训练师可在八格内自由移动")
	t.eq(screen.mod_used, 0, "部署不消耗改造次数")
	var saved := RunState.from_dict(app.run.to_dict())
	t.eq(saved.preview_deploy_positions, screen.deploy_positions, "部署位置可随本局存档恢复")
	var desired: Dictionary = screen.deploy_positions.duplicate()
	screen._on_start()
	var battle: BattleState = app.current_screen.state
	for uid in desired:
		t.eq(battle.unit_by_uid(uid).cell, desired[uid], "实际出生位置与部署一致")
	var map := TestScenario.make_map(TestScenario.plain_terrain())
	var enemies: Array = []
	for cell in Balance.DEPLOY_AREA:
		var enemy := CombatUnit.make("rock_wild1", "enemy", 100 + enemies.size())
		enemy.cell = cell
		enemies.append(enemy)
	var players: Array = app.run.build_deploy_units([1, 2, 3])
	var placement := Deployment.prepare(map, enemies, players, {})
	map["deploy_area"] = placement["area"]
	t.check(Deployment.valid(map, enemies, players, placement["positions"]), "重访部署区被占时可扩展部署")
	t.check((placement["positions"] as Dictionary).values().all(func(cell): return not Balance.DEPLOY_AREA.has(cell)), "扩展部署不移动或覆盖原敌人")
	app.queue_free()

func _speech(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	state.node_kind = "event"
	state.merchant = {"cell": Vector2i(6, 5)}
	var events: Array = []
	state.feedback.connect(func(event): events.append(event))
	state.enable_feedback()
	state.check_speech_events()
	t.check(state.speech_seen.has("trainer_start") and state.speech_seen.has("merchant_help"), "开战鼓舞和遇敌呼救触发")
	t.check(not state.speech_seen.has("merchant_sell"), "危险中优先呼救")
	var count := events.size()
	state.check_speech_events()
	t.eq(events.size(), count, "重复刷新不重复喊话")
	state.unit_by_uid(100).cell = Vector2i(2, 0)
	state.check_speech_events()
	t.check(state.speech_seen.has("merchant_sell"), "脱离危险后商人吆喝")
	state.node_kind = "battle"
	state.round = 7
	state.check_speech_events()
	t.check(state.speech_seen.has("trainer_warning"), "第七回合提醒撤退")
	var clone := state.clone()
	clone.say_once("preview_only", 1, Vector2i.ZERO, "不得显示")
	t.check(not clone.speech_seen.has("preview_only") and not state.speech_seen.has("preview_only"), "预览不得生成气泡")
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	restored.enable_feedback()
	restored.feedback.connect(func(event): events.append(event))
	count = events.size()
	restored.check_speech_events()
	t.eq(events.size(), count, "读档不重复喊话")
	state.boss_uid = 100
	var boss := state.unit_by_uid(100)
	state.damage_unit(state.unit_by_uid(1), boss, ceili(boss.hp / 2.0), {"no_element": true})
	t.check(state.speech_seen.has("boss_roar"), "Boss 半血怒吼")
	state.round = Balance.MAX_ROUNDS
	state.end_battle("escape")
	t.check(not state.speech_seen.has("trainer_escape"), "主动撤离不再发表旧版限时逃跑宣言")
