extends RefCounted

func run(t: TestContext) -> void:
	t.begin("方向技能点击伤害目标实际结算")
	_check_skill(t, "flame_jet", Vector2i(6, 3), 10)
	_check_skill(t, "ice_breath", Vector2i(5, 3), 8)
	_check_skill(t, "electric_spark", Vector2i(6, 3), 8)
	_check_skill(t, "windfire_breath", Vector2i(5, 2), 10)
	t.finish()


func _check_skill(t: TestContext, skill: String, enemy_cell: Vector2i, expected_damage: int) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8100 + skill.length())
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", enemy_cell]])
	state.nest["cell"] = Vector2i(7, 7)
	state.trainer().cell = Vector2i(0, 7)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	caster.skills = [skill]
	var target := state.unit_by_uid(100)
	target.element = ""
	target.max_hp = 100
	target.hp = 100
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	screen.action_mode = "skills"
	screen._on_skill_pressed(skill)
	t.check(screen.board.area_cells.has(enemy_cell), "%s伤害目标显示在技能范围内" % skill)
	screen._try_cast_at(enemy_cell)
	t.eq(target.hp, 100 - expected_damage, "%s点击范围内敌人后实际扣血" % skill)
	t.check(caster.skill_used, "%s成功施放并消耗行动" % skill)
	screen.playback.finish_all()
	t.eq(screen.playback.visual.unit_by_uid(target.uid).hp, target.hp, "%s播放后的显示生命与实际一致" % skill)
	app.queue_free()
