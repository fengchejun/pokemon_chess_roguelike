extends SceneTree

## 本场奖励二选一的实际界面截图，输出到被忽略的 artifacts 目录。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(20261013)
	app.begin_battle([1, 2, 3], TestScenario.make_map(TestScenario.plain_terrain()))
	var battle = app.current_screen
	var state: BattleState = battle.state
	var owner := state.unit_by_uid(1)
	owner.cell = state.reward["cell"]
	state.phase = BattleState.PHASE_ENEMY
	state.end_enemy_phase()
	battle.select_unit(owner.uid)
	battle.refresh_all()
	await process_frame
	await process_frame
	var out := ProjectSettings.globalize_path("res://artifacts/reward_buff_choice.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var error := root.get_texture().get_image().save_png(out)
	print("REWARD_BUFF_SHOT %s size=%s error=%d" % [out, root.get_visible_rect().size, error])
	quit(0 if error == OK else 1)
