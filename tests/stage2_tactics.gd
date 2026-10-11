extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")
const TurnTestHelper = preload("res://tests/turn_test_helper.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_trainer_priority():
		return
	if not _test_push_for_both_teams():
		return
	if not _test_route_and_hazard():
		return
	await _test_ui()


func _test_trainer_priority() -> bool:
	var state := BattleState.new()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var ally: CombatUnit = state.unit_by_id("ally_rock")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	trainer.cell = Vector2i(3, 4)
	ally.cell = Vector2i(4, 3)
	enemy.cell = Vector2i(3, 2)
	state.finish_player_turn()
	if trainer.hp != trainer.max_hp - 2 or ally.hp != ally.max_hp:
		return _fail("Enemy did not prefer the trainer when both targets were in range")
	state = BattleState.new()
	trainer = state.unit_by_id("trainer")
	ally = state.unit_by_id("ally_rock")
	enemy = state.unit_by_id("wild_a")
	state.unit_by_id("wild_b").hp = 0
	state.unit_by_id("wild_c").hp = 0
	trainer.cell = Vector2i(0, 0)
	ally.cell = Vector2i(4, 3)
	enemy.cell = Vector2i(2, 3)
	enemy.move_points = 0
	state.finish_player_turn()
	if trainer.hp != trainer.max_hp or ally.hp != ally.max_hp - 2:
		return _fail("Enemy did not fall back to an allied monster")
	state = BattleState.new()
	enemy = state.unit_by_id("wild_a")
	state.unit_by_id("ally_fire").cell = Vector2i(0, 2)
	state.unit_by_id("trainer").cell = Vector2i(2, 2)
	enemy.cell = Vector2i(6, 2)
	state.phase = "enemy_move"
	EnemyAI.new().move_phase(state, [enemy.unit_id])
	if enemy.cell != Vector2i(6, 2):
		return _fail("Enemy moved despite a legal long-range cross attack on trainer")
	state.phase = "enemy_attack"
	EnemyAI.new().attack_phase(state, [enemy.unit_id])
	if state.unit_by_id("trainer").hp != CombatConfig.TRAINER_HP - 2:
		return _fail("Fire cross attack did not prioritize trainer")
	return true


func _test_push_for_both_teams() -> bool:
	var state := BattleState.new()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(3, 3)
	enemy.move_points = 0
	enemy.skill_points = 0
	TurnTestHelper.advance_to_player(state, "ally_rock")
	var preview: Dictionary = state.preview_push(rock, enemy)
	if preview.get("destination") != Vector2i(4, 3) or preview.get("target_damage") != 2:
		return _fail("Player push preview was wrong")
	if not state.try_use_skill("ally_rock", "rock_push", enemy.cell) or enemy.cell != Vector2i(4, 3) or enemy.hp != enemy.max_hp - 2 or rock.skill_points != 0:
		return _fail("Player push was not resolved as a skill")
	state = BattleState.new()
	state.unit_by_id("wild_a").hp = 0
	state.unit_by_id("wild_b").hp = 0
	var trainer: CombatUnit = state.unit_by_id("trainer")
	trainer.cell = Vector2i(4, 3)
	var wild_rock: CombatUnit = state.unit_by_id("wild_c")
	wild_rock.cell = Vector2i(3, 3)
	TurnTestHelper.finish_round(state)
	if trainer.hp != trainer.max_hp - int(CombatConfig.SKILLS["rock_push"]["damage"]) - CombatConfig.COLLISION_DAMAGE or trainer.cell != Vector2i(4, 3) or state.terrain.object_at(Vector2i(5, 3)).get("hp", 0) != 1:
		return _fail("Enemy rock push did not share the player collision rules")
	return true


func _test_route_and_hazard() -> bool:
	var state := BattleState.new()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 3)
	var route: Array[Vector2i] = state.get_move_path(fire, Vector2i(4, 5))
	if route.size() != 3 or not state.try_player_move("ally_fire", Vector2i(4, 5)) or fire.hp != fire.max_hp:
		return _fail("Crossing intact fragile ground changed movement or HP")
	state = BattleState.new()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 1)
	fire.hp = 1
	state.terrain.ground[Vector2i(4, 1)] = "collapsed"
	if not state.get_move_path(fire, Vector2i(5, 1)).is_empty() or state.try_player_move("ally_fire", Vector2i(5, 1)) or not fire.is_alive() or fire.cell != Vector2i(3, 1) or fire.move_points == 0:
		return _fail("Voluntary movement crossed a collapsed pit or consumed the move")
	return true


func _test_ui() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		_fail("Battle UI could not load")
		return
	await process_frame
	await process_frame
	var battle: Control = current_scene
	battle.set("state", BattleState.new())
	var test_state: BattleState = battle.get("state")
	TurnTestHelper.advance_to_player(test_state, "trainer")
	battle.set("selected_unit_id", "trainer")
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	if board == null or preview == null or battle.find_child("IntentLabel", true, false) != null:
		_fail("Battle UI controls are wrong")
		return
	board.cell_hovered.emit(Vector2i(0, 1))
	if not preview.text.contains("移动预览：3 格"):
		_fail("Movement route preview is missing")
		return
	var state: BattleState = battle.get("state")
	TurnTestHelper.advance_to_player(state, "ally_rock")
	board.cell_pressed.emit(state.unit_by_id("ally_rock").cell)
	state.unit_by_id("wild_a").cell = Vector2i(3, 3)
	var skill_button := battle.find_child("SkillButton_rock_push", true, false) as Button
	skill_button.pressed.emit()
	board.cell_hovered.emit(Vector2i(3, 3))
	if not preview.text.contains("目标受 2 点技能直伤"):
		_fail("Push preview did not separate direct and collision damage")
		return
	print("STAGE2_TACTICS passed")
	quit(0)


func _fail(message: String) -> bool:
	push_error("STAGE2_TACTICS failed: " + message)
	quit(1)
	return false
