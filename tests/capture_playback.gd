extends SceneTree
var screen
var app
var wide := false

func _initialize() -> void:
	wide = OS.get_cmdline_user_args().has("wide")
	call_deferred("_run")

func _wait() -> void:
	while screen._playback_active() or screen.busy:
		await process_frame

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/playback_" + label + ("_wide" if wide else "") + ".png")

func _cast(state: BattleState, caster: CombatUnit, skill: String, entry: Dictionary) -> bool:
	var result := SkillResolver.apply(state, caster, skill, entry, false)
	if not bool(result.get("ok", false)):
		push_error("Capture fixture cast failed: " + skill)
		quit(1)
		return false
	return true

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(42)
	screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = TestScenario.make_state(["fire_starter", "water_starter", "grass_starter"], [["grass_wild1", Vector2i(4, 2)], ["rock_wild1", Vector2i(4, 4)]])
	app._switch(screen)
	var state: BattleState = screen.state
	var fire := state.unit_by_uid(1)
	var water := state.unit_by_uid(2)
	var grass := state.unit_by_uid(3)
	var first := state.unit_by_uid(100)
	var second := state.unit_by_uid(101)
	fire.cell = Vector2i(1, 2)
	water.cell = Vector2i(1, 4)
	grass.cell = Vector2i(3, 5)
	first.element = "grass"
	for unit in state.units:
		unit.max_hp = 999
		unit.hp = 999
	screen.refresh_all()
	await process_frame
	if not _cast(state, fire, "fire_seed", {"type": "cell", "cell": first.cell}):
		return
	await create_timer(0.32).timeout
	await _shot("flight")
	if screen.board.units.filter(func(u): return u.uid == first.uid)[0].hp != 999:
		push_error("Damage displayed before impact")
		quit(1)
		return
	await create_timer(0.33).timeout
	await _shot("impact")
	await _wait()
	if not _cast(state, water, "water_flow", {"type": "cell", "cell": second.cell}):
		return
	await _wait()
	if not state.move_unit(grass, Vector2i(4, 4)):
		push_error("Capture fixture move failed")
		quit(1)
		return
	await _wait()
	if not _cast(state, grass, "electric_arc", {"type": "cell", "cell": second.cell}):
		return
	await _wait()
	if not _cast(state, grass, "leech_seed", {"type": "unit", "unit": second.uid, "cell": second.cell}):
		return
	await _wait()
	SkillResolver.resolve_channel(state, first, "rock_slide", [fire.cell])
	SkillResolver.resolve_channel(state, second, "lightning", [fire.cell, water.cell])
	await create_timer(0.28).timeout
	var held: float = screen.playback.elapsed
	screen._open_menu()
	await create_timer(0.25).timeout
	if not is_equal_approx(held, screen.playback.elapsed):
		push_error("Menu did not pause playback")
		quit(1)
		return
	screen._close_modal()
	screen._toggle_speed()
	await _wait()
	grass.hp -= 15
	if not _cast(state, grass, "herbal_heal", {"type": "cell", "cell": grass.cell}):
		return
	await _wait()
	# Real enemy turn orchestration must wait for every visual action.
	screen.do_end_turn()
	await _wait()
	await _shot("after_enemy")
	if state.phase != BattleState.PHASE_PLAYER and not state.ended:
		push_error("Enemy turn did not finish")
		quit(1)
		return
	state.set_terrain(first.cell, TerrainDB.PIT)
	state.kill_unit(first, "演出坠落验证", "player", fire.uid)
	screen.refresh_all()
	await create_timer(0.08).timeout
	await _shot("fall")
	await _wait()
	state.damage_unit(null, state.trainer(), 9999, {"no_element": true})
	screen._refresh_after_action()
	await create_timer(0.1).timeout
	if app.current_screen != screen:
		push_error("Final action was skipped")
		quit(1)
		return
	await _wait()
	await _shot("final_impact")
	await create_timer(0.8).timeout
	if app.current_screen == screen:
		push_error("Final action did not lead to settlement")
		quit(1)
		return
	print("PLAYBACK_FINAL_SETTLEMENT_OK")
	print("PLAYBACK_WINDOW_OK flight impact five_elements serial_release pause speed enemy_turn falling")
	app.queue_free()
	await process_frame
	quit()
