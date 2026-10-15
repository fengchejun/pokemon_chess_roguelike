class_name ElementAttachmentResolver
extends RefCounted

## 附着与反应的唯一判定入口。伤害先计算本次加成，再执行反应的状态/爆炸。
## 附着层各自到期；未知组合不反应。

const REACTIONS := {
	"fire|water": {"id": "蒸发", "bonus_element": "water"},
	"grass|water": {"id": "绽放", "bonus_element": "grass"},
	"electric|water": {"id": "导电", "bonus_element": "electric"},
	"ice|water": {"id": "冻结", "effect": "freeze"},
	"fire|grass": {"id": "燃烧", "bonus_element": "fire"},
	"fire|ice": {"id": "融化", "bonus_element": "fire"},
	"electric|fire": {"id": "过载", "effect": "overload"},
}


static func _pair_key(a: String, b: String) -> String:
	var pair := [a, b]
	pair.sort()
	return "%s|%s" % pair


static func stack_count(unit: CombatUnit, element: String) -> int:
	return (unit.attachments.get(element, []) as Array).size()


static func add(state: BattleState, target: CombatUnit, element: String, source: CombatUnit = null, direct_hit: bool = false) -> Dictionary:
	var result := {"reaction": "", "bonus": 0, "effect": "", "cell": target.cell if target != null else Vector2i.ZERO}
	if target == null or not target.is_alive() or element == "" or element == "wind" or not Elements.LIST.has(element):
		return result
	var layers: Array = (target.attachments.get(element, []) as Array).duplicate()
	# 敌方施法者自身的火/水附着留给下一次我方阶段反制；
	# 命中目标及地形附着仍在本轮末转化，保持原有异常时点。
	var self_cast := source != null and source.uid == target.uid
	var conversion_delay := 1 if self_cast and (element == "fire" or element == "water") and state.phase == BattleState.PHASE_ENEMY else 0
	layers.append(state.round + 2 + conversion_delay)
	target.attachments[element] = layers
	state.log_event("%s 获得 1 层%s附着（现有 %d 层）。" % [target.display_name, Elements.name_of(element), layers.size()])
	var others: Array = target.attachments.keys()
	others.sort_custom(func(a: String, b: String) -> bool: return Elements.order_index(a) < Elements.order_index(b))
	for other in others:
		if other == element or stack_count(target, String(other)) <= 0:
			continue
		var rule: Dictionary = REACTIONS.get(_pair_key(element, String(other)), {})
		if rule.is_empty():
			continue
		_consume_one(target, element)
		_consume_one(target, String(other))
		result["reaction"] = String(rule["id"])
		result["effect"] = String(rule.get("effect", ""))
		if direct_hit and String(rule.get("bonus_element", "")) == element:
			result["bonus"] = 2
		state.log_event("%s 触发%s，消耗两种附着%s。" % [target.display_name, result["reaction"], "；本次伤害 +2" if int(result["bonus"]) > 0 else ""])
		return result
	if ["grass", "electric", "ice", "rock"].has(element) and stack_count(target, element) >= 2:
		_consume_one(target, element)
		_consume_one(target, element)
		result["reaction"] = "两层" + Elements.name_of(element)
		result["effect"] = {"grass": "parasite", "electric": "paralyze", "ice": "freeze", "rock": "rock_guard"}[element]
	return result


static func _consume_one(unit: CombatUnit, element: String) -> void:
	var layers: Array = unit.attachments.get(element, [])
	if layers.is_empty():
		return
	layers.pop_front()
	if layers.is_empty():
		unit.attachments.erase(element)
	else:
		unit.attachments[element] = layers


static func consume_ready(unit: CombatUnit, element: String, settled_round: int) -> int:
	var layers: Array = unit.attachments.get(element, [])
	var remaining: Array = []
	var consumed := 0
	for expiry in layers:
		if int(expiry) <= settled_round + 2:
			consumed += 1
		else:
			remaining.append(expiry)
	if remaining.is_empty():
		unit.attachments.erase(element)
	else:
		unit.attachments[element] = remaining
	return consumed


static func clear_expired(unit: CombatUnit, settled_round: int) -> void:
	for element in unit.attachments.keys().duplicate():
		var remaining: Array = []
		for expiry in unit.attachments[element]:
			if int(expiry) > settled_round:
				remaining.append(expiry)
		if remaining.is_empty():
			unit.attachments.erase(element)
		else:
			unit.attachments[element] = remaining


static func spread_from(source: CombatUnit, targets: Array, state: BattleState) -> void:
	if source == null or source.attachments.is_empty():
		return
	var transfer: Dictionary = source.attachments.duplicate(true)
	source.attachments.clear()
	for target in targets:
		if target == null or not target.is_alive() or target.uid == source.uid:
			continue
		target.attachments = transfer.duplicate(true)
		state.log_event("%s 的附着扩散至 %s；原附着被替换。" % [source.display_name, target.display_name])
