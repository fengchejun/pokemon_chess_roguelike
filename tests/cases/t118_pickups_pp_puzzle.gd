extends RefCounted
const Flow = preload("res://scripts/run/exploration_flow.gd")

func run(t: TestContext) -> void:
	t.begin("解谜左岸岩障可实际推桥、技能PP独立显示")
	var run_state := RunState.new_run(118)
	run_state.options["exploration_v2"] = true
	var region: RegionState = run_state.get_region()
	region.active_node = "battle_4"
	for variant in 4:
		region.nodes["battle_4"]["puzzle"] = variant
		run_state.region_data = region.to_dict()
		var map := MapGenerator.generate(118, 0)
		Flow.prepare_map(run_state, map)
		for y in [2, 6]:
			t.eq(map["terrain"][GridSpec.index(Vector2i(2, y))], TerrainDB.OBSTACLE, "左岸有可推岩障")
		if variant != 2: continue
		var actor := CombatUnit.make("rock_starter", "player", 1)
		actor.skills = ["rock_push", "rock_break"]
		var state := BattleState.new()
		state.setup(map, {"enemies": []}, 118, 0, [actor], {}, {}, [])
		Flow.prepare_state(run_state, state)
		actor.cell = Vector2i(0, 4)
		for x in [1, 2, 3]:
			var rock := Vector2i(x, 4)
			var outcome := state.cast_skill(actor, "rock_push", {"type": "cell", "cell": rock})
			t.check(outcome.get("ok", false), "可连续推击断桥备用岩障")
			t.check(state.terrain_at(rock) != TerrainDB.OBSTACLE, "岩障被推走或填沟后原位可站")
			t.check(state.move_unit(actor, rock), "推击后可实际跟进到岩障原位")
		t.eq(state.terrain_at(Vector2i(4, 4)), TerrainDB.FRAGILE, "三次推击实际填上第二格深坑")
		t.eq(state.terrain_at(Vector2i(5, 4)), TerrainDB.ICE, "保留原有对岸冰面")
		t.check(state.move_unit(actor, Vector2i(5, 4)), "补桥后岩系可实际走到对岸")
		var screen = load("res://scripts/ui/battle_screen.gd").new()
		screen.state = state
		screen.selected_uid = actor.uid
		screen.action_mode = "skills"
		screen.skill_box = VBoxContainer.new()
		screen.add_child(screen.skill_box)
		screen._rebuild_skill_buttons()
		var label: Label = screen.skill_box.find_child("SkillPP_rock_push", true, false)
		t.check(label != null and label.text == "PP  %d / %d" % [actor.pp_remaining("rock_push"), actor.max_pp("rock_push")], "技能下方直接显示当前与最大PP")
		t.eq(label.get_theme_font_size("font_size"), 18, "PP使用醒目字号")
		screen.free()
	t.finish()
