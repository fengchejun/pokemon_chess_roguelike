extends Control

## 应用路由：主菜单 → 编队 → 地图预览与改造 → 战斗 → 战后结算 → 下一场 / 本局结束。

const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const CollectionScreen = preload("res://scripts/ui/collection_screen.gd")
const PrepScreen = preload("res://scripts/ui/prep_screen.gd")
const PreviewScreen = preload("res://scripts/ui/preview_screen.gd")
const BattleScreen = preload("res://scripts/ui/battle_screen.gd")
const SettlementScreen = preload("res://scripts/ui/settlement_screen.gd")
const SupplyScreen = preload("res://scripts/ui/supply_screen.gd")
const RunEndScreen = preload("res://scripts/ui/run_end_screen.gd")
const MusicDirectorScript = preload("res://scripts/ui/music_director.gd")

var run: RunState = null
var collection: CollectionState = null
var current_screen: Control = null
var music_director: MusicDirector = null
var pending_settlement: Dictionary = {}
var battle_settled := false
var prep_deploy_preset: Array = []
var autosave_enabled: bool = true # UI 自动化在挂载场景前设为 false，避免覆盖玩家单槽存档。


func _ready() -> void:
	collection = CollectionState.load_profile() if autosave_enabled else CollectionState.defaults()
	music_director = MusicDirectorScript.new()
	add_child(music_director)
	_fit_to_window()
	if not get_window().size_changed.is_connected(_fit_to_window):
		get_window().size_changed.connect(_fit_to_window)
	UIKit.setup_theme(get_window())
	show_menu()


func _fit_to_window() -> void:
	var target := get_viewport_rect().size
	if size != target:
		size = target
	if current_screen != null:
		current_screen.size = size


func _switch(screen: Control) -> void:
	if current_screen != null:
		remove_child(current_screen)
		current_screen.queue_free()
	screen.app = self
	add_child(screen)
	screen.size = size
	current_screen = screen
	if music_director != null:
		music_director.play_track(_track_for_screen(screen.name))


func _track_for_screen(screen_name: String) -> String:
	if screen_name == "MenuScreen":
		return "title"
	if screen_name == "BattleScreen":
		return "battle"
	return "prep"


func show_menu() -> void:
	_switch(MenuScreen.new())


func start_new_run() -> void:
	## 主菜单放弃旧存档时，先登记身上与仓库的成员，避免覆盖单槽本局存档后丢失已收容的怪物。
	if autosave_enabled and SaveSystem.has_save():
		var previous := SaveSystem.load_run()
		if previous != null:
			collection.absorb_run(previous)
			collection.save()
	_switch(CollectionScreen.new())


func begin_new_run_with_collection(chosen: Array) -> void:
	if chosen.size() != Balance.DEPLOY_LIMIT:
		return
	run = RunState.new_run(0, chosen)
	autosave()
	show_prep()


func continue_run() -> void:
	var loaded := SaveSystem.load_run()
	if loaded == null:
		show_menu()
		return
	run = loaded
	if run.settlement_pending:
		pending_settlement = {"battle": null, "outcome": run.last_settlement.duplicate(true)}
		battle_settled = true
		_switch(SettlementScreen.new())
	elif run.pending_supply and not run.run_lost():
		show_supply()
	else:
		show_prep()


func autosave() -> void:
	if run != null and autosave_enabled:
		SaveSystem.save_run(run)


func sync_and_save(battle: BattleState) -> void:
	## 战斗中的死亡与捕获即时写回并落盘（死亡当帧写入）。
	if run != null and battle != null:
		run.sync_from_battle(battle)
		autosave()


func show_prep() -> void:
	battle_settled = false
	_switch(PrepScreen.new())


func show_preview(deploy_uids: Array) -> void:
	var screen: Control = PreviewScreen.new()
	screen.deploy_uids = deploy_uids
	_switch(screen)


func back_to_prep(deploy_uids: Array) -> void:
	## 从地图预览返回整备：保留已选编成。
	prep_deploy_preset = deploy_uids.duplicate()
	show_prep()


func begin_battle(deploy_uids: Array, final_map: Dictionary) -> void:
	var cfg := BattleDB.config_for(run.battle_index)
	var player_units := run.build_deploy_units(deploy_uids)
	var state := BattleState.new()
	var card_effects := run.effects()
	state.setup(final_map, cfg, run.seed, run.battle_index, player_units, card_effects, {}, cfg.get("reinforce", []), run.options)
	run.consume_selected_reward_item()
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
	run.sync_from_battle(battle)
	var outcome := run.settle_battle(battle)
	pending_settlement = {"battle": battle, "outcome": outcome}
	autosave()
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
		run.pending_supply = false
		autosave()
	show_prep()


func show_run_end() -> void:
	if run != null and collection != null:
		collection.absorb_run(run)
		if autosave_enabled:
			collection.save()
			autosave()
	_switch(RunEndScreen.new())


func end_run_to_menu() -> void:
	if autosave_enabled:
		SaveSystem.delete_save()
	run = null
	show_menu()


func quit_game() -> void:
	get_tree().quit()
