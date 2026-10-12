class_name CaptureSystem
extends RefCounted

## 捕获（概率制）：成功率随目标生命值百分比降低而升高；
## 训练家与目标曼哈顿距离 ≤ CAPTURE_RANGE（2 格），每回合 1 次尝试。


static func capture_chance(target: CombatUnit) -> float:
	## 基础 30%，目标每损失 1% 生命增加 0.55%；夹在 5% 至 95% 之间。
	var chance := Balance.CAPTURE_CHANCE_BASE + (1.0 - target.hp_ratio()) * Balance.CAPTURE_CHANCE_SLOPE
	return clampf(chance, Balance.CAPTURE_CHANCE_MIN, Balance.CAPTURE_CHANCE_MAX)


static func chance_percent(target: CombatUnit) -> int:
	return roundi(capture_chance(target) * 100.0)


static func can_attempt(state, trainer: CombatUnit, target: CombatUnit) -> bool:
	if trainer == null or target == null:
		return false
	if state.phase != "player" or state.ended:
		return false
	if not trainer.is_alive() or not target.is_alive():
		return false
	if trainer.capture_used:
		return false
	if target.side != "enemy":
		return false
	return GridSpec.manhattan(trainer.cell, target.cell) <= Balance.CAPTURE_RANGE


static func attempt(state, trainer: CombatUnit, target: CombatUnit, forced_roll: float = -1.0) -> Dictionary:
	## forced_roll ≥ 0 时使用指定骰值（测试用），否则从战斗内可复现的捕获随机数取。
	if not can_attempt(state, trainer, target):
		return {"ok": false}
	var chance := capture_chance(target)
	var roll := forced_roll
	if roll < 0.0:
		roll = state.capture_roll()
	trainer.capture_used = true
	if roll < chance:
		var species_id := target.species_id
		var keep_hp := maxi(1, target.hp)
		var percent := chance_percent(target)
		target.hp = 0
		state.log_event("训练家捕获成功：%s（成功率 %d%%）。" % [target.display_name, percent])
		state.on_captured(target, species_id, keep_hp)
		return {"ok": true, "success": true, "chance": chance, "roll": roll, "species_id": species_id, "hp": keep_hp}
	state.log_event("训练家捕获失败：%s（成功率 %d%%）。" % [target.display_name, chance_percent(target)])
	return {"ok": true, "success": false, "chance": chance, "roll": roll}
