extends SceneTree

## 1280×720 升级、整备、战斗技能栏视觉验收。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(2310)
	MonsterProgression.award_xp(app.run.record_by_uid(1), 4)
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 4, "monster_exp": []}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	var learn_type: Button = app.current_screen.find_child("MonsterGrowth_learn_1_2", true, false)
	learn_type.pressed.emit()
	await _shot("res://artifacts/skill_library_upgrade.png")
	var learn_skill: Button = app.current_screen.find_child("MonsterLearn_1_2_trial_fire_1", true, false)
	learn_skill.pressed.emit()
	app.show_prep()
	await _shot("res://artifacts/skill_library_prep.png")
	app.show_preview([1])
	var begin: Button = app.current_screen.find_child("StartBattleButton", true, false)
	begin.pressed.emit()
	# 截图用固定站位：让刚学会的试招有一个合法目标，便于观察按钮状态。
	app.current_screen.state.unit_by_uid(1).cell = Vector2i(5, 2)
	app.current_screen.refresh_all()
	app.current_screen.select_unit(1)
	var trial_button: Button = app.current_screen.find_child("SkillButton_trial_fire_1", true, false)
	if trial_button == null or trial_button.disabled:
		push_error("视觉验收：试招按钮未在合法射程内启用。")
	await _shot("res://artifacts/skill_library_battle.png")
	app.queue_free()
	await process_frame
	quit(0)


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
