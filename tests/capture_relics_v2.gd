extends SceneTree

var app = null
var screen = null


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + name + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(9901)
	app.run.relic_stacks = {
		"fire_carbon": 1,
		"healing_berry": 1,
		"holy_shield_fragment": 1,
		"collision_expert": 1,
		"ice_age": 1,
		"dawn_lord_radiance": 1,
		"dead_poem": 1,
		"blood_dragon_dance": 1,
	}
	var state := TestScenario.make_state(
		["fire_starter", "water_starter"],
		[["rock_wild1", Vector2i(6, 2)], ["water_wild1", Vector2i(6, 4)]],
		[],
		{},
		{},
		[],
		9901,
		app.run.relic_stacks
	)
	state.node_kind = "battle"
	screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.playback.finish_all()
	screen.refresh_all()
	screen.select_unit(1)
	await create_timer(1.25).timeout
	await _shot("relics_v2_battle_1280")

	state.node_kind = "event"
	state.merchant = {
		"cell": Vector2i(4, 3),
		"stock": {
			"potion": 2,
			"relic:prism_mirror": 1,
			"relic:crimson_heart": 1,
		},
	}
	state.trainer().cell = Vector2i(3, 3)
	screen.playback.finish_all()
	screen.refresh_all()
	screen._show_merchant()
	await create_timer(1.25).timeout
	await _shot("relics_v2_merchant_1280")
	quit(0)
