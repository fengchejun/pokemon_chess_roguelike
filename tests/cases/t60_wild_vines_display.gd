extends RefCounted


func run(t: TestContext) -> void:
	t.begin("疯狂藤蔓显示范围")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(6001)
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(7, 6)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	screen.action_mode = "skills"
	screen._on_skill_pressed("wild_vines")
	var expected := [
		Vector2i(3, 2), Vector2i(3, 1),
		Vector2i(3, 4), Vector2i(3, 5),
		Vector2i(2, 3), Vector2i(1, 3),
		Vector2i(4, 3), Vector2i(5, 3),
	]
	t.eq(screen.board.area_cells.size(), 8, "基础显示四向前方两格共八格")
	for cell in expected:
		t.check(screen.board.area_cells.has(cell), "显示范围包含 %s" % str(cell))
	var button: Button = screen.skill_box.find_child("SkillButton_wild_vines", true, false)
	t.check(button != null and button.text.contains("前方 2 格"), "技能栏显示基础两格范围")
	screen._clear_aim()
	caster.upgrades["wild_vines_reach"] = 1
	screen.action_mode = "skills"
	screen._on_skill_pressed("wild_vines")
	t.eq(screen.board.area_cells.size(), 12, "强化后显示四向前方三格共十二格")
	button = screen.skill_box.find_child("SkillButton_wild_vines", true, false)
	t.check(button != null and button.text.contains("前方 3 格"), "技能栏显示强化后三格范围")
	app.queue_free()
	t.finish()
