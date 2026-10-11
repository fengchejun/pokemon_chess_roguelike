extends SceneTree

const TerrainManager = preload("res://scripts/terrain_manager.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_team_phase_and_enemy_order():
		return
	if not _test_nest_timing():
		return
	print("TEAM_TURN_ORDER passed")
	quit(0)


func _test_team_phase_and_enemy_order() -> bool:
	var state := BattleState.new()
	if state.current_player_ids() != ["trainer", "ally_fire", "ally_water", "ally_rock"]:
		return _fail("All player units were not available in one phase")
	if not state.can_act_now(state.unit_by_id("ally_rock")) or state.can_act_now(state.unit_by_id("wild_a")):
		return _fail("Team phase eligibility is wrong")
	state.unit_by_id("trainer").hp = 99
	state.unit_by_id("wild_a").speed = 0
	state.unit_by_id("wild_b").speed = 99
	if not TurnTestHelper.finish_round(state) or state.turn_number != 2 or state.phase != "player":
		return _fail("A full player and enemy turn did not settle once")
	var previous_skill := -1
	for enemy_id in ["wild_a", "wild_b", "wild_c"]:
		var enemy: CombatUnit = state.unit_by_id(enemy_id)
		var start_index: int = state.events.find("%s 开始行动：先移动。" % enemy.display_name)
		var skill_index: int = state.events.find("%s 准备施放技能。" % enemy.display_name)
		if start_index <= previous_skill or skill_index <= start_index:
			return _fail("Enemies did not each move then cast in deployment order")
		previous_skill = skill_index
	return true


func _test_nest_timing() -> bool:
	var state := BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.unit_by_id("trainer").hp = 99
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("wild_b").move_points = 0
	state.unit_by_id("wild_b").skill_points = 0
	if not TurnTestHelper.finish_round(state) or state.turn_number != 2:
		return _fail("Nest fixture did not reach round two")
	var newborn: CombatUnit = state.unit_by_id("nest_2_1")
	if newborn == null or newborn.cell == Vector2i(6, 1) or newborn.eligible_round != 3 or newborn.skill_points != 0 or state.can_act_now(newborn):
		return _fail("Round-two newborn did not move once and wait")
	if not TurnTestHelper.finish_round(state) or state.turn_number != 3 or newborn.skill_points != 1:
		return _fail("Newborn did not become eligible on its next round")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.terrain.objects[Vector2i(6, 1)] = TerrainManager.make_rock()
	state.turn_number = 2
	state._start_round()
	if state.unit_by_id("nest_2_1") != null:
		return _fail("Blocked nest exit produced an enemy")
	state = BattleState.new()
	state.nest = {"cell": Vector2i(7, 1), "exit": Vector2i(6, 1), "hp": 3}
	state.unit_by_id("trainer").hp = 99
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_c").hp = 0
	state.unit_by_id("wild_b").move_points = 0
	state.unit_by_id("wild_b").skill_points = 0
	state.turn_number = 4
	state._start_round()
	var fourth: CombatUnit = state.unit_by_id("nest_4_1")
	if fourth == null or fourth.cell == Vector2i(6, 1) or fourth.skill_points != 0 or fourth.eligible_round != 5:
		return _fail("Fourth-round newborn did not move without a skill action")
	fourth.display_name = "本轮新生"
	var event_count: int = state.events.size()
	if not TurnTestHelper.finish_round(state) or state.outcome != "escape":
		return _fail("Fourth-round escape did not follow complete enemy phase")
	for event in state.events.slice(event_count):
		if event.contains("%s 开始行动" % fourth.display_name):
			return _fail("Fourth-round newborn acted again in its birth round")
	return true


func _fail(message: String) -> bool:
	push_error("TEAM_TURN_ORDER failed: " + message)
	quit(1)
	return false
