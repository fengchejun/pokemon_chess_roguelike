extends Control

## 应用路由：主菜单 → 编队 → 地图预览与改造 → 战斗 → 战后结算 → 下一场 / 本局结束。

const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const PrepScreen = preload("res://scripts/ui/prep_screen.gd")
const PreviewScreen = preload("res://scripts/ui/preview_screen.gd")
const BattleScreen = preload("res://scripts/ui/battle_screen.gd")
const SettlementScreen = preload("res://scripts/ui/settlement_screen.gd")
const SupplyScreen = preload("res://scripts/ui/supply_screen.gd")
const RunEndScreen = preload("res://scripts/ui/run_end_screen.gd")

var run: RunState = null
var current_screen: Control = null
var pending_settlement: Dictionary = {}
var battle_settled := false
var prep_deploy_preset: Array = []


func _ready() -> void:
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


func show_menu() -> void:
	_switch(MenuScreen.new())


func start_new_run() -> void:
	run = RunState.new_run()
	autosave()
	show_prep()


func continue_run() -> void:
	var loaded := SaveSystem.load_run()
	if loaded == null:
		show_menu()
		return
	run = loaded
	if run.pending_supply and not run.run_lost():
		show_supply()
	else:
		show_prep()


func autosave() -> void:
	if run != null:
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
	state.setup(final_map, cfg, run.seed, run.battle_index, player_units, run.effects(), run.upgrades, cfg.get("reinforce", []))
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
	_switch(RunEndScreen.new())


func end_run_to_menu() -> void:
	SaveSystem.delete_save()
	run = null
	show_menu()


func quit_game() -> void:
	get_tree().quit()
