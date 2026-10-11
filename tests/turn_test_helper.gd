extends RefCounted


static func advance_to_player(state: BattleState, unit_id: String) -> bool:
	return state.phase == "player" and state.current_player_ids().has(unit_id)


static func finish_round(state: BattleState) -> bool:
	var initial_round: int = state.turn_number
	return state.finish_player_turn() and (state.outcome != "" or state.turn_number > initial_round)
