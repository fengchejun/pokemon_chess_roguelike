extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func shot(id: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://outputs/exploration_v2/" + id + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/exploration_v2")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(82001)
	app.run.region_mode = true
	app.run.options["exploration_v2"] = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	app.show_region()
	await shot("01_fog")
	app.enter_region_node("camp")
	await shot("02_camp")
	app.current_screen.find_child("ReturnToRegion", true, false).pressed.emit()
	var first = app.run.get_region()
	first.nodes["event_1"]["unlocked"] = true
	app.run.region_data = first.to_dict()
	app.enter_region_node("event_1")
	await shot("03_group")
	app.current_screen.find_child("PlayGroup", true, false).pressed.emit()
	app.current_screen.find_child("ReturnToRegion", true, false).pressed.emit()
	app.enter_region_node("battle_5")
	await shot("04_request")
	app.current_screen.find_child("ReturnToRegion", true, false).pressed.emit()
	var region = app.run.get_region()
	for id in ["event_2", "battle_4", "battle_2"]:
		region.nodes[id]["unlocked"] = true
		region.nodes[id]["revealed"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node("event_2")
	await shot("05_shop")
	app.current_screen.find_child("ReturnToRegion", true, false).pressed.emit()
	app.enter_region_node("battle_4")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await create_timer(1.5).timeout
	await shot("06_treasure")
	app.run.battle_snapshot = {}
	region = app.run.get_region()
	region.complete_visit()
	app.run.region_data = region.to_dict()
	app.enter_region_node("battle_2")
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	await create_timer(1.5).timeout
	await shot("07_capture")
	var state: BattleState = app.current_screen.state
	state.damage_unit(state.unit_by_uid(1), state.alive_units("enemy")[0], 1, {"no_element": true})
	state.begin_enemy_phase()
	while not state.enemy_phase_finished(): state.step_enemy_phase()
	state.end_enemy_phase()
	app.current_screen.playback.finish_all()
	app.current_screen.battle_notice.finish_all()
	app.current_screen._refresh_after_action()
	await shot("08_escape")
	quit()
