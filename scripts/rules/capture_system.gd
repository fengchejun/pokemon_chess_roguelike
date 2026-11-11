class_name CaptureSystem
extends RefCounted

## 曼哈顿距离两格为统一范围；低血量保证与战中转阵营由本局设置控制。


static func capture_chance(target: CombatUnit, low_hp_rules: bool = false, debug_percent: int = -1) -> float:
	if target == null or not target.is_on_board():
		return 0.0
	if debug_percent >= 0:
		return clampf(float(debug_percent) / 100.0, 0.0, 1.0)
	if low_hp_rules:
		if target.hp <= Balance.CAPTURE_GUARANTEE_HP or (target.hp <= Balance.CAPTURE_DEBUFF_GUARANTEE_HP and has_debuff(target)):
			return 1.0
	## 满血 1%，随目标损失生命线性提升，常规上限 60%。
	var missing_ratio := clampf(1.0 - target.hp_ratio(), 0.0, 1.0)
	var chance := lerpf(Balance.CAPTURE_CHANCE_MIN, Balance.CAPTURE_CHANCE_MAX, missing_ratio)
	return clampf(chance, Balance.CAPTURE_CHANCE_MIN, Balance.CAPTURE_CHANCE_MAX)


static func chance_percent(target: CombatUnit, low_hp_rules: bool = false, debug_percent: int = -1) -> int:
	return roundi(capture_chance(target, low_hp_rules, debug_percent) * 100.0)


static func has_debuff(target: CombatUnit) -> bool:
	return target.burn_ticks > 0 or target.slow_ticks > 0 or target.root_pending or target.move_cancelled


static func in_range(trainer: CombatUnit, target: CombatUnit) -> bool:
	if trainer == null or target == null:
		return false
	return GridSpec.manhattan(trainer.cell, target.cell) <= Balance.CAPTURE_RANGE


static func can_attempt(state, trainer: CombatUnit, target: CombatUnit) -> bool:
	if trainer == null or target == null:
		return false
	if state.phase != "player" or state.ended:
		return false
	if not trainer.is_alive() or not target.is_on_board():
		return false
	if trainer.capture_used:
		return false
	if target.side != "enemy":
		return false
	if target.summon_owner_uid >= 0:
		return false
	if not in_range(trainer, target):
		return false
	if bool(state.capture_options.get("capture_low_hp", false)) and target.hp_ratio() > 0.5:
		return false
	return true


static func attempt(state, trainer: CombatUnit, target: CombatUnit, forced_roll: float = -1.0) -> Dictionary:
	## forced_roll ≥ 0 时使用指定骰值（测试用），否则从战斗内可复现的捕获随机数取。
	if not can_attempt(state, trainer, target):
		return {"ok": false}
	var low_hp_rules := bool(state.capture_options.get("capture_low_hp", false))
	var debug_percent := int(state.debug_capture_percent)
	var chance := capture_chance(target, low_hp_rules, debug_percent)
	chance = minf(1.0, chance + (0.2 if state.capture_aid else 0.0))
	state.capture_aid = false
	var roll := forced_roll
	if chance < 1.0 and roll < 0.0:
		roll = state.capture_roll()
	trainer.capture_used = true
	if chance >= 1.0 or roll < chance:
		var species_id := target.species_id
		var keep_hp := maxi(1, target.hp)
		var percent := roundi(chance * 100)
		state.log_event("训练家捕获成功：%s（成功率 %d%%）。" % [target.display_name, percent])
		state.on_captured(target, species_id, keep_hp)
		return {"ok": true, "success": true, "chance": chance, "roll": roll, "species_id": species_id, "hp": keep_hp}
	state.emit_feedback(target, "action", "捕获失败")
	state.log_event("训练家捕获失败：%s（成功率 %d%%）。" % [target.display_name, roundi(chance * 100)])
	return {"ok": true, "success": false, "chance": chance, "roll": roll}
