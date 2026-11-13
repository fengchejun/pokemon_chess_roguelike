extends SceneTree
const Flow = preload("res://scripts/run/exploration_flow.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.run = RunState.new_run(118)
	app.run.options["exploration_v2"] = true
	var region = app.run.get_region()
	region.active_node = "battle_4"
	region.nodes["battle_4"]["puzzle"] = 2
	app.run.region_data = region.to_dict()
	var map := MapGenerator.generate(118, 0)
	Flow.prepare_map(app.run, map)
	map["food_cells"] = [Vector2i(2, 3), Vector2i(5, 5)]
	var actor := CombatUnit.make("rock_starter", "player", 1)
	actor.battle_skill_uses["rock_push"] = 20
	var state := BattleState.new()
	state.setup(map, {"enemies": []}, 118, 0, [actor], {}, {}, [])
	Flow.prepare_state(app.run, state)
	state.food_cells = [Vector2i(2, 3), Vector2i(5, 5)]
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.battle_notice.finish_all()
	screen.select_unit(1)
	screen._on_choose_skill_pressed()
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://sample/pickups-pp-puzzle.png")
	print("PICKUPS_PP_PUZZLE_RENDERED")
	quit()
