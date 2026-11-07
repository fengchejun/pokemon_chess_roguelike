extends RefCounted

const DIRECTIONAL_SKILLS := [
	"flame_jet",
	"tsunami",
	"ice_breath",
	"frozen_ground",
	"rock_create",
	"earth_shake",
	"windfire_breath",
	"wild_vines",
	"electric_spark",
]

func run(t: TestContext) -> void:
	t.begin("方向技能瞄准范围显示")
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(8001)
	var state := TestScenario.make_state(
		["water_starter", "fire_starter", "grass_starter", "electric_starter"],
		[
			["rock_wild1", Vector2i(3, 2)],
			["rock_wild1", Vector2i(4, 3)],
			["rock_wild1", Vector2i(3, 4)],
			["rock_wild1", Vector2i(2, 3)],
			["rock_wild1", Vector2i(5, 3)],
		]
	)
	state.nest["cell"] = Vector2i(7, 7)
	state.unit_by_uid(Balance.TRAINER_UID).cell = Vector2i(0, 7)
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 3)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	for skill in DIRECTIONAL_SKILLS:
		caster.skills = [skill]
		caster.moved = false
		caster.skill_used = false
		caster.battle_skill_uses.clear()
		screen._clear_aim()
		screen.action_mode = "skills"
		screen._on_skill_pressed(skill)
		var expected := _preview_area(state, caster, skill)
		if skill == "frozen_ground":
			expected = _frozen_ground_area(state, caster)
		t.check(not expected.is_empty(), "%s存在可显示范围" % skill)
		t.eq(_cell_keys(screen.board.area_cells), _cell_keys(expected), "%s瞄准时显示完整方向范围" % skill)
		t.check(screen.hint_label.text.contains("橙色作用格"), "%s提示可点击橙色作用格" % skill)
	app.queue_free()
	t.finish()


func _preview_area(state: BattleState, caster: CombatUnit, skill: String) -> Array:
	var cells: Array = []
	for entry in state.skill_targets(caster, skill):
		if String(entry.get("type", "")) != "dir":
			continue
		var preview := state.preview_skill(caster, skill, entry)
		if not bool(preview.get("ok", false)):
			continue
		for key in ["area_cells", "ray_cells"]:
			for cell in preview.get(key, []):
				if not cells.has(cell):
					cells.append(cell)
	return cells


func _frozen_ground_area(state: BattleState, caster: CombatUnit) -> Array:
	var cells: Array = []
	for direction in GridSpec.DIRS4:
		for cell in SkillResolver.frozen_ground_cells(state, caster, direction):
			if not cells.has(cell):
				cells.append(cell)
	return cells


func _cell_keys(cells: Array) -> Array:
	var keys: Array = []
	for cell in cells:
		keys.append("%d,%d" % [cell.x, cell.y])
	keys.sort()
	return keys
