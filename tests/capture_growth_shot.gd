extends SceneTree

## 1280×720 战后单体升级界面截图：godot --path . --resolution 1280x720 --script res://tests/capture_growth_shot.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_script = load("res://scripts/main.gd")
	var app = main_script.new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(20261015)
	var record: Dictionary = app.run.record_by_uid(1)
	var growth: Dictionary = MonsterProgression.award_xp(record, 4)
	growth["uid"] = 1
	growth["name"] = SpeciesDB.name_of(String(record["species_id"]))
	app.run.settlement_pending = true
	app.pending_settlement = {"battle": null, "outcome": {"reason": "victory", "exp": 4, "monster_exp": [growth], "kills": 1, "captures": 0}}
	app._switch(load("res://scripts/ui/settlement_screen.gd").new())
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var path := "res://artifacts/15_growth_choice.png"
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit(0)
