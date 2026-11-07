extends Control
const Deployment = preload("res://scripts/rules/deployment.gd")
const BattleSnapshot = preload("res://scripts/run/battle_snapshot.gd")

## 应用路由：主菜单 → 编队 → 地图预览与改造 → 战斗 → 战后结算 → 下一场 / 本局结束。

const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const CollectionScreen = preload("res://scripts/ui/collection_screen.gd")
const PrepScreen = preload("res://scripts/ui/prep_screen.gd")
const BattleScreen = preload("res://scripts/ui/battle_screen.gd")
const SettlementScreen = preload("res://scripts/ui/settlement_screen.gd")
const SupplyScreen = preload("res://scripts/ui/supply_screen.gd")
const RunEndScreen = preload("res://scripts/ui/run_end_screen.gd")
const SkillStatsScreen = preload("res://scripts/ui/skill_stats_screen.gd")
const FloorThemeScreen = preload("res://scripts/ui/floor_theme_screen.gd")
const RegionScreen = preload("res://scripts/ui/region_screen.gd")
const CampScreen = preload("res://scripts/ui/camp_screen.gd")
const DebugConsoleScreen = preload("res://scripts/ui/debug_console.gd")
const MusicDirectorScript = preload("res://scripts/ui/music_director.gd")

var battle_playback_speed := 1.0 # Session-only presentation preference.
var run: RunState = null
var collection: CollectionState = null
var current_screen: Control = null
var music_director: MusicDirector = null
var pending_settlement: Dictionary = {}
var battle_settled := false
var prep_deploy_preset: Array = []
var autosave_enabled: bool = true # UI 自动化在挂载场景前设为 false，避免覆盖玩家单槽存档。
var debug_console: Control = null
var music_percent: int = 100
var music_muted: bool = false


func _ready() -> void:
	OS.set_use_file_access_save_and_swap(true)
	collection = CollectionState.load_profile() if autosave_enabled else CollectionState.defaults()
	music_director = MusicDirectorScript.new()
	add_child(music_director)
	_load_settings()
	_fit_to_window()
	if not get_window().size_changed.is_connected(_fit_to_window):
		get_window().size_changed.connect(_fit_to_window)
	UIKit.setup_theme(get_window())
	show_menu()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://game_settings.cfg") == OK:
		music_percent = clampi(int(config.get_value("audio", "music_percent", 100)), 0, 100)
		music_muted = bool(config.get_value("audio", "muted", false))
		if bool(config.get_value("display", "fullscreen", false)):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_apply_music_settings()


func _apply_music_settings() -> void:
	music_director.volume_db = -80.0 if music_muted or music_percent <= 0 else -10.0 + linear_to_db(float(music_percent) / 100.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_percent", music_percent)
	config.set_value("audio", "muted", music_muted)
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.save("user://game_settings.cfg")


func set_music_percent(value: int) -> void:
	music_percent = clampi(value, 0, 100)
	_apply_music_settings()
	_save_settings()


func set_music_muted(value: bool) -> void:
	music_muted = value
	_apply_music_settings()
	_save_settings()


func set_fullscreen(value: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


func _fit_to_window() -> void:
	var target := get_viewport_rect().size
	if size != target:
		size = target
	if current_screen != null:
		current_screen.size = size


func _switch(screen: Control) -> void:
	if debug_console != null:
		debug_console.hide()
	if current_screen != null:
		remove_child(current_screen)
		current_screen.queue_free()
	screen.app = self
	add_child(screen)
	screen.size = size
	current_screen = screen
	if music_director != null:
		music_director.play_track(_track_for_screen(screen.name))


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey):
		return
	if event.pressed and not event.echo and event.keycode == KEY_F7:
		get_viewport().set_input_as_handled()
		toggle_debug_console()


func toggle_debug_console() -> void:
	if not OS.is_debug_build() or current_screen == null or not ["PrepScreen", "BattleScreen"].has(current_screen.name):
		return
	if debug_console == null:
		debug_console = DebugConsoleScreen.new()
		debug_console.app = self
		add_child(debug_console)
		return
	if debug_console.visible:
		debug_console.hide()
	else:
		debug_console.rebuild()
		debug_console.show()
		debug_console.move_to_front()


func _track_for_screen(screen_name: String) -> String:
	if screen_name == "MenuScreen":
		return "title"
	if screen_name == "BattleScreen":
		return "battle"
	return "prep"


func show_menu() -> void:
	_switch(MenuScreen.new())


func show_skill_stats() -> void:
	_switch(SkillStatsScreen.new())


func start_new_run() -> void:
	## 主菜单放弃旧存档时只登记携带队伍；未在最终结算勾选的仓库成员视为抛弃。
	if autosave_enabled and SaveSystem.has_save():
		var previous := SaveSystem.load_run()
		if previous != null:
			collection.settle_run(previous)
			collection.save()
		else:
			# 当前流程无法续读的旧本局文件必须先留底，避免新局自动存档覆盖。
			if SaveSystem.backup_old_save() == "":
				return
	_switch(CollectionScreen.new())


func begin_new_run_with_collection(chosen: Array) -> void:
	if chosen.size() != Balance.DEPLOY_LIMIT:
		return
	run = RunState.new_run(0, chosen)
	run.region_mode = true
	autosave()
	show_prep()


func continue_run(path: String = SaveSystem.DEFAULT_PATH) -> void:
	var loaded := SaveSystem.load_run(path)
	if loaded == null:
		show_menu()
		return
	run = loaded
	if run.region_mode and run.battle_snapshot.is_empty() and not run.pending_region_entry_backup.is_empty() and not run.settlement_pending:
		run.cancel_region_entry()
		if autosave_enabled:
			SaveSystem.save_run(run, path)
	if run.run_failed or run.run_finished():
		show_run_end()
	elif not run.battle_snapshot.is_empty():
		var restored := BattleSnapshot.load_state(run.battle_snapshot)
		if restored == null:
			show_prep()
		else:
			var screen: Control = BattleScreen.new()
			screen.state = restored
			_switch(screen)
	elif run.settlement_pending:
		pending_settlement = {"battle": null, "outcome": run.last_settlement.duplicate(true)}
		battle_settled = true
		_switch(SettlementScreen.new())
	elif run.pending_supply and not run.run_lost():
		show_supply()
	elif run.needs_theme_choice():
		show_floor_theme()
	elif run.region_mode:
		show_camp() if run.get_region().at_camp_scene else show_region()
	else:
		show_prep()


func autosave() -> void:
	if run != null and autosave_enabled:
		SaveSystem.save_run(run)


func sync_and_save(battle: BattleState) -> void:
	## 敌方动画期间保留上一稳定的我方节点，避免从半步动作恢复。
	if run != null and battle != null:
		if battle.phase == BattleState.PHASE_ENEMY or battle.phase == BattleState.PHASE_SETTLE:
			return
		run.sync_from_battle(battle)
		if battle.phase == BattleState.PHASE_PLAYER and not battle.ended:
			run.battle_snapshot = BattleSnapshot.save_state(battle)
		autosave()


func save_battle_and_return(battle: BattleState) -> bool:
	if run == null or battle == null or battle.phase != BattleState.PHASE_PLAYER or battle.ended:
		return false
	var snapshot := BattleSnapshot.save_state(battle)
	var previous := run.battle_snapshot
	run.battle_snapshot = snapshot
	if autosave_enabled and not SaveSystem.save_run(run):
		run.battle_snapshot = previous
		return false
	show_menu()
	return true


func merchant_trade(state: BattleState, operation: String, id: String, quantity: int = 1, save_path: String = SaveSystem.DEFAULT_PATH) -> Dictionary:
	run.sync_from_battle(state)
	var previous := run.to_dict()
	var battle_before := BattleSnapshot.save_state(state)
	var result := Merchant.trade(run, state, operation, id, quantity)
	if not bool(result["ok"]):
		return result
	var region = run.get_region()
	region.nodes[region.active_node]["merchant"] = state.merchant.duplicate(true)
	region.nodes[region.active_node]["merchant"]["cell"] = [state.merchant["cell"].x, state.merchant["cell"].y]
	run.region_data = region.to_dict()
	run.battle_snapshot = BattleSnapshot.save_state(state)
	if autosave_enabled and not SaveSystem.save_run(run, save_path):
		run = RunState.from_dict(previous)
		var restored := BattleSnapshot.load_state(battle_before)
		state.units = restored.units
		state.merchant = restored.merchant
		state.relic_stacks = restored.relic_stacks
		return {"ok": false, "reason": "存档写入失败，交易已撤回。"}
	if collection != null:
		collection.absorb_run(run)
		if autosave_enabled:
			collection.save()
	return result


func purchase_skill_upgrade(state: BattleState, uid: int, skill_id: String, save_path: String = SaveSystem.DEFAULT_PATH) -> Dictionary:
	run.sync_from_battle(state)
	var previous := run.to_dict()
	var battle_before := BattleSnapshot.save_state(state)
	var result := Merchant.upgrade_skill(run, state, uid, skill_id)
	if not bool(result["ok"]):
		return result
	run.battle_snapshot = BattleSnapshot.save_state(state)
	if autosave_enabled and not SaveSystem.save_run(run, save_path):
		run = RunState.from_dict(previous)
		var restored := BattleSnapshot.load_state(battle_before)
		state.units = restored.units
		state.relic_stacks = restored.relic_stacks
		return {"ok": false, "reason": "存档写入失败，技能强化已撤回。"}
	if collection != null:
		collection.absorb_run(run)
		if autosave_enabled:
			collection.save()
	return result


func show_prep() -> void:
	if run != null and run.needs_theme_choice():
		show_floor_theme()
		return
	battle_settled = false
	_switch(PrepScreen.new())


func show_floor_theme() -> void:
	_switch(FloorThemeScreen.new())


func show_region() -> void:
	battle_settled = false
	_switch(RegionScreen.new())


func cancel_region_entry() -> void:
	if run != null:
		run.cancel_region_entry()
		autosave()
	show_region()


func show_camp() -> void:
	battle_settled = false
	_switch(CampScreen.new())


func leave_camp() -> void:
	var region = run.get_region()
	region.at_camp_scene = false
	var notices: Array = region.complete_visit()
	region.notifications.append_array(notices)
	run.region_data = region.to_dict()
	autosave()
	show_region()


func enter_region_node(id: String) -> void:
	if not run.enter_region_node(id):
		return
	autosave()
	if run.get_region().node_mode(id) == "camp":
		show_camp()
	else:
		show_prep()


func show_preview(deploy_uids: Array) -> void:
	prep_deploy_preset = deploy_uids.duplicate()
	show_prep()


func back_to_prep(deploy_uids: Array) -> void:
	## 兼容旧入口，在合并页恢复已选编成和本场预览。
	prep_deploy_preset = deploy_uids.duplicate()
	show_prep()


func begin_battle(deploy_uids: Array, final_map: Dictionary) -> void:
	if run.needs_theme_choice():
		show_floor_theme()
		return
	var cfg := run.battle_config()
	if run.region_mode:
		var region = run.get_region()
		if region.node_mode(region.active_node) == "event":
			cfg = cfg.duplicate(true)
			cfg["enemies"] = []
			cfg["reinforce"] = []
			cfg["boss_index"] = -1
	if run.region_mode:
		cfg = run.place_region_enemies(cfg, final_map)
	var player_units := run.build_deploy_units(deploy_uids)
	var state := BattleState.new()
	if run.region_mode:
		state.node_kind = run.get_region().node_mode(run.get_region().active_node)
	var card_effects := run.effects()
	state.setup(final_map, cfg, run.seed, run.battle_index, player_units, card_effects, {}, cfg.get("reinforce", []), run.options, run.relic_stacks)
	if run.region_mode:
		run.captured_applied = 0
		var region = run.get_region()
		var node_id: String = region.active_node
		if not (region.nodes[node_id]["snapshot"] as Dictionary).is_empty():
			state = region.resume_node(node_id, run.build_deploy_units(deploy_uids), cfg)
			if state == null:
				cancel_region_entry()
				return
		state.node_kind = region.node_mode(node_id)
		state.exploration_started = false
		state.reinforcement_pool = (cfg.get("reinforce", []) as Array).duplicate()
		if bool(region.nodes[node_id].get("pending_garrison", false)):
			region.nodes[node_id]["pending_garrison"] = false
		if bool(region.nodes[node_id].get("pending_replenish", false)):
			region.nodes[node_id]["pending_replenish"] = false
		state.set_enemy_level_bonus(run.invasion_level_bonus)
		state.boss_power_percent = 0
		if (region.nodes[node_id]["snapshot"] as Dictionary).is_empty():
			state.seed_initial_food()
		if state.node_kind == "event":
			state.stop_nests()
			# 收集区允许宝箱掉落的奖励点。
		run.region_data = region.to_dict()
	if run.region_mode:
		var current = run.get_region()
		var node: Dictionary = current.nodes[current.active_node]
		if node.has("merchant"):
			if state.merchant.is_empty():
				state.merchant = node["merchant"].duplicate(true)
				var coordinates: Array = state.merchant["cell"]
				state.merchant["cell"] = Vector2i(int(coordinates[0]), int(coordinates[1]))
			if not GridSpec.is_inside(state.merchant["cell"]):
				state.merchant["cell"] = Merchant.choose_battle_cell(state, final_map.get("deploy_positions", {}))
			node["merchant"] = state.merchant.duplicate(true)
			node["merchant"]["cell"] = [state.merchant["cell"].x, state.merchant["cell"].y]
			run.region_data = current.to_dict()
	if final_map.has("deploy_positions"):
		var enemies := state.alive_units("enemy")
		var players := state.alive_units("player")
		var positions: Dictionary = final_map["deploy_positions"]
		if not Deployment.valid(final_map, enemies, players, positions):
			push_error("部署位置无效，已停止开战。")
			return
		state.deploy_area = final_map["deploy_area"].duplicate()
		for player in players:
			player.cell = positions[player.uid]
	state.extraction_cells = state.deploy_area.duplicate()
	state.repair_food()
	run.battle_snapshot = BattleSnapshot.save_state(state)
	run.pending_region_entry_backup.clear()
	run.pending_invasion_bonus = 0
	## 消耗品已经在预览页使用时扣除；开战不再二次扣卡。
	run.selected_reward_item = ""
	run.mark_deployed(deploy_uids)
	autosave()
	var screen: Control = BattleScreen.new()
	screen.state = state
	screen.deploy_uids = deploy_uids
	_switch(screen)


func finish_battle(battle: BattleState) -> void:
	if battle_settled or run == null:
		return
	battle_settled = true
	run.battle_snapshot = {}
	run.sync_from_battle(battle)
	if run.region_mode:
		var region = run.get_region()
		battle.reward["node_reward_available"] = false # 奖励只来自实际拾取的奖励点。
	var outcome := run.settle_battle(battle)
	if run.region_mode:
		if battle.node_kind != "event" and not run.run_failed:
			run.add_food("basic", 1)
		var region = run.get_region()
		region.store_battle(region.active_node, battle)
		if bool(battle.reward.get("node_reward_available", false)):
			region.nodes[region.active_node]["reward_claimed"] = true
		run.region_data = region.to_dict()
	if collection != null and not run.debug_tainted:
		var collection_changed := collection.record_battle_skill_usage(battle)
		collection_changed = collection.credit_boss_capture(run, outcome) or collection_changed
		if collection_changed and autosave_enabled:
			collection.save()
	pending_settlement = {"battle": battle, "outcome": outcome}
	autosave()
	if run.run_failed:
		show_run_end()
		return
	var screen: Control = SettlementScreen.new()
	_switch(screen)


func continue_after_settlement() -> void:
	if run == null:
		show_menu()
		return
	if not run.pending_captures.is_empty() or run.pending_upgrades() or run.pending_reward_choices > 0:
		return
	if collection != null:
		collection.absorb_run(run)
		if autosave_enabled:
			collection.save()
	if run.region_mode:
		run.settlement_pending = false
		run.last_settlement = {}
		var region = run.get_region()
		var boss_cleared: bool = region.active_node == "boss" and bool(region.nodes["boss"]["cleared"])
		if boss_cleared:
			run.battle_index = (region.floor_index + 1) * 6
			run.region_data = {}
			run.refresh_theme_offers()
		else:
			var notices: Array = region.complete_visit()
			region.notifications.append_array(notices)
			if region.active_node == "camp" and region.node_mode("camp") == "camp":
				region.at_camp_scene = true
			run.region_data = region.to_dict()
		autosave()
		if run.run_finished() or run.run_lost():
			show_run_end()
		elif run.needs_theme_choice():
			show_floor_theme()
		else:
			show_camp() if run.get_region().at_camp_scene else show_region()
		return
	run.advance_battle()
	autosave()
	if run.run_finished() or run.run_lost():
		show_run_end()
	elif run.supply_due():
		run.pending_supply = true
		autosave()
		show_supply()
	else:
		show_prep()


func show_supply() -> void:
	_switch(SupplyScreen.new())


func leave_supply() -> void:
	if run != null:
		if run.supply_choices().size() > 0:
			return
		run.pending_supply = false
		autosave()
	if run != null and run.needs_theme_choice():
		show_floor_theme()
	else:
		show_prep()


func show_run_end() -> void:
	if run != null and collection != null:
		collection.absorb_run(run)
		if autosave_enabled:
			collection.save()
			autosave()
	_switch(RunEndScreen.new())


func resolve_run_end_storage(retained_storage_uids: Array) -> Dictionary:
	## 最终结局确认：携带队伍必然保留，仓库只有明确勾选者进入永久收藏。
	if run == null or collection == null:
		return {"ok": false, "reason": "本局或永久收藏尚未就绪。"}
	var retained: Array = []
	for record in run.storage:
		var uid := int(record.get("uid", -1))
		if retained_storage_uids.has(uid) and not retained.has(uid):
			retained.append(uid)
	var discarded := run.storage.size() - retained.size()
	var added := 0
	if not run.debug_tainted:
		added = collection.settle_run(run, retained)
		if autosave_enabled and not collection.save():
			return {"ok": false, "reason": "永久收藏写入失败，请重试。"}
	run.storage.clear()
	autosave()
	return {"ok": true, "added": added, "retained": retained.size(), "discarded": discarded}


func end_run_to_menu() -> void:
	if autosave_enabled:
		SaveSystem.delete_save()
	run = null
	show_menu()


func quit_game() -> void:
	get_tree().quit()
