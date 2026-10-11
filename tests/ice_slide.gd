extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_movement_and_undo() or not _test_charge_and_push() or not _test_blocking_and_order() or not _test_lethal_and_immunity() or not _test_full_round():
		return
	print("ICE_SLIDE passed")
	quit(0)


func _fresh() -> BattleState:
	var state := BattleState.new()
	state.terrain.ground.clear()
	state.terrain.objects.clear()
	return state


func _test_movement_and_undo() -> bool:
	var state := _fresh()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	state.unit_by_id("ally_rock").cell = Vector2i(0, 0)
	fire.cell = Vector2i(2, 3)
	fire.last_move_direction = Vector2i.UP
	state.terrain.set_ice(Vector2i(3, 3))
	if not state.try_player_move(fire.unit_id, Vector2i(3, 3)) or fire.last_move_direction != Vector2i.RIGHT:
		return _fail("Player movement did not record the last step")
	if not state.undo_last_move() or fire.cell != Vector2i(2, 3) or fire.last_move_direction != Vector2i.UP:
		return _fail("Undo did not restore the prior direction")
	if not state.try_player_move(fire.unit_id, Vector2i(3, 3)):
		return _fail("Player could not move after undo")
	state._settle_ice_slides()
	if fire.cell != Vector2i(4, 3) or fire.last_move_direction != Vector2i.ZERO:
		return _fail("Ice did not slide one cell and clear direction")
	state.terrain.set_ice(fire.cell)
	state._settle_ice_slides()
	if fire.cell != Vector2i(4, 3):
		return _fail("Ice slid again without a new move")
	return true


func _test_charge_and_push() -> bool:
	var state := _fresh()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	state.unit_by_id("ally_rock").cell = Vector2i(0, 0)
	fire.cell = Vector2i(2, 3)
	state.terrain.set_ice(Vector2i(4, 3))
	if not state.try_use_skill(fire.unit_id, "flame_charge", Vector2i(4, 3)) or fire.last_move_direction != Vector2i.RIGHT:
		return _fail("Flame charge did not record direction")
	state._settle_ice_slides()
	if fire.cell != Vector2i(5, 3):
		return _fail("Charge landing on ice did not slide")
	state = _fresh()
	var rock: CombatUnit = state.unit_by_id("ally_rock")
	var victim: CombatUnit = state.unit_by_id("wild_a")
	rock.cell = Vector2i(2, 3)
	victim.cell = Vector2i(3, 3)
	state.terrain.set_ice(Vector2i(4, 3))
	if not state.try_use_skill(rock.unit_id, "rock_push", victim.cell) or victim.cell != Vector2i(4, 3) or victim.last_move_direction != Vector2i.RIGHT:
		return _fail("Push onto ice did not record direction")
	state._settle_ice_slides()
	if victim.cell != Vector2i(5, 3):
		return _fail("Pushed target did not slide")
	return true


func _test_blocking_and_order() -> bool:
	var state := _fresh()
	var trainer: CombatUnit = state.unit_by_id("trainer")
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	trainer.cell = Vector2i(4, 3)
	fire.cell = Vector2i(3, 3)
	trainer.last_move_direction = Vector2i.RIGHT
	fire.last_move_direction = Vector2i.RIGHT
	state.terrain.set_ice(trainer.cell)
	state.terrain.set_ice(fire.cell)
	state._settle_ice_slides()
	if trainer.cell != Vector2i(5, 3) or fire.cell != Vector2i(4, 3):
		return _fail("Units did not slide in unit-list order")
	state = _fresh()
	fire = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 3)
	fire.last_move_direction = Vector2i.RIGHT
	state.terrain.set_ice(fire.cell)
	state.terrain.objects[Vector2i(4, 3)] = TerrainManager.make_rock()
	state._settle_ice_slides()
	if fire.cell != Vector2i(3, 3) or fire.hp != fire.max_hp:
		return _fail("Blocked slide moved or damaged unit")
	fire.cell = Vector2i(7, 3)
	fire.last_move_direction = Vector2i.RIGHT
	state.terrain.set_ice(fire.cell)
	state._settle_ice_slides()
	if fire.cell != Vector2i(7, 3) or fire.hp != fire.max_hp:
		return _fail("Board edge caused slide collision")
	return true


func _test_lethal_and_immunity() -> bool:
	for lethal_ground in ["deep_water", "collapsed"]:
		var state := _fresh()
		var trainer: CombatUnit = state.unit_by_id("trainer")
		trainer.cell = Vector2i(3, 3)
		trainer.last_move_direction = Vector2i.RIGHT
		state.terrain.set_ice(trainer.cell)
		state.terrain.ground[Vector2i(4, 3)] = lethal_ground
		state._settle_ice_slides()
		if trainer.is_alive() or trainer.cell != Vector2i(4, 3) or state.outcome != "defeat":
			return _fail("Ice did not apply %s entry death" % lethal_ground)
	var flying_state := _fresh()
	var fire: CombatUnit = flying_state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 3)
	fire.last_move_direction = Vector2i.RIGHT
	fire.flying = true
	flying_state.terrain.set_ice(fire.cell)
	flying_state._settle_ice_slides()
	if fire.cell != Vector2i(3, 3):
		return _fail("Flying unit slid on ice")
	fire.flying = false
	fire.frozen = true
	fire.last_move_direction = Vector2i.RIGHT
	flying_state._settle_ice_slides()
	if fire.cell != Vector2i(4, 3):
		return _fail("Frozen unit resisted forced ice slide")
	return true


func _test_full_round() -> bool:
	var state := _fresh()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	fire.cell = Vector2i(3, 3)
	fire.last_move_direction = Vector2i.RIGHT
	state.terrain.set_ice(fire.cell)
	state.terrain.set_ice(Vector2i(4, 3))
	state.reward_cell = fire.cell
	state.reward_state = "ground"
	if not state._claim_reward("player") or state.reward_state != "claimed" or fire.cell != Vector2i(3, 3):
		return _fail("Reward was not claimed before ice movement")
	var chosen: String = state.reward_choices[0] if state.reward_choices[0] != "flying" else state.reward_choices[1]
	if not state.choose_reward_buff(chosen):
		return _fail("Reward choice did not resume round settlement")
	if fire.cell != Vector2i(4, 3) or fire.last_move_direction != Vector2i.ZERO or state.turn_number != 2:
		return _fail("Full round did not slide once before continuing")
	state._settle_round_and_continue()
	if fire.cell != Vector2i(4, 3):
		return _fail("Next full round slid without movement")
	return true


func _fail(message: String) -> bool:
	push_error("ICE_SLIDE failed: " + message)
	quit(1)
	return false
