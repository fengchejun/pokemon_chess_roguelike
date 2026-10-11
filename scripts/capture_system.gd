class_name CaptureSystem
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")


static func can_capture(state: BattleState, target: CombatUnit) -> bool:
	var trainer: CombatUnit = state.unit_by_id("trainer")
	return state.phase == "player" and state.outcome == "" and trainer != null and state.can_act_now(trainer) and trainer.capture_points > 0 and target != null and target.team == "enemy" and target.is_alive() and state.distance(trainer.cell, target.cell) == 1 and float(target.hp) / float(target.max_hp) <= CombatConfig.CAPTURE_MAX_HP_RATIO


static func chance(target: CombatUnit) -> float:
	if target == null or not target.is_alive():
		return 0.0
	return clampf(CombatConfig.CAPTURE_BASE_CHANCE + (1.0 - float(target.hp) / float(target.max_hp)) * CombatConfig.CAPTURE_LOW_HP_BONUS, 0.0, 1.0)
