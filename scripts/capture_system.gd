class_name CaptureSystem
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")


static func can_capture(state: BattleState, target: CombatUnit) -> bool:
	var trainer: CombatUnit = state.unit_by_id("trainer")
	if state.phase != "player" or state.outcome != "" or trainer == null or not state.can_act_now(trainer) or trainer.capture_points <= 0:
		return false
	if target == null or target.team != "enemy" or not target.is_alive():
		return false
	var delta: Vector2i = target.cell - trainer.cell
	return maxi(absi(delta.x), absi(delta.y)) == 1 and float(target.hp) / float(target.max_hp) <= CombatConfig.CAPTURE_MAX_HP_RATIO


static func chance(target: CombatUnit) -> float:
	if target == null or not target.is_alive():
		return 0.0
	if target.hp <= CombatConfig.CAPTURE_GUARANTEED_HP or (target.hp <= CombatConfig.CAPTURE_DEBUFF_GUARANTEED_HP and target.has_debuff()):
		return 1.0
	return clampf(CombatConfig.CAPTURE_BASE_CHANCE + (1.0 - float(target.hp) / float(target.max_hp)) * CombatConfig.CAPTURE_LOW_HP_BONUS, 0.0, 1.0)
