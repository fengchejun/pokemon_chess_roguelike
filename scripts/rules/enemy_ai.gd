class_name EnemyAI
extends RefCounted

## 确定性敌方 AI：固定行动顺序（火、水、草、电、岩、增援），
## 先移动后技能；威胁预告与实际执行使用同一份计划。

const PRIORITY_TRAINER := 150
const PRIORITY_POKEMON := 100


static func plan(state: BattleState) -> Array:
	var work := state.clone()
	var actions: Array = []
	for uid in _action_order(work):
		if work.ended:
			break
		# 同一单位最多两次施法；第二次必须来自友军已给予的额外机会。
		for cast_index in range(2):
			var unit := work.unit_by_uid(uid)
			if unit == null or not unit.is_alive() or work.ended:
				break
			if cast_index > 0 and (not unit.skill_used or unit.extra_casts <= 0 or not unit.can_act_skill()):
				break
			var action := _decide(work, unit)
			var has_effect: bool = not (action["move_path"] as Array).is_empty() or not (action["skill"] as Dictionary).is_empty()
			if not has_effect or (cast_index > 0 and (action["skill"] as Dictionary).is_empty()):
				break
			_execute_on(work, action)
			actions.append(action)
			work.check_battle_end()
	return actions


static func _action_order(state: BattleState) -> Array:
	var enemies: Array = []
	for unit in state.units:
		if unit.side == "enemy" and unit.is_alive() and not unit.fresh_spawn and unit.channel_lock_round != state.round:
			enemies.append(unit)
	enemies.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return a.reg_index < b.reg_index)
	var order: Array = []
	for unit in enemies:
		order.append(unit.uid)
	return order


static func _decide(work: BattleState, unit: CombatUnit) -> Dictionary:
	var best: Dictionary = {}
	var positions: Array = [unit.cell]
	var paths: Dictionary = {unit.cell: []}
	if unit.can_move_now():
		var options := PathFinder.stop_cells(work, unit)
		var cells := options.keys()
		# 稳定枚举顺序
		var sorted_cells: Array = []
		for cell in cells:
			sorted_cells.append(cell)
		sorted_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x
		)
		for cell in sorted_cells:
			positions.append(cell)
			paths[cell] = options[cell]["path"]
	for position in positions:
		var base := work.clone()
		var base_unit := base.unit_by_uid(unit.uid)
		if base_unit == null or not base_unit.is_alive():
			continue
		var path: Array = paths[position]
		base_unit.cell = position
		if not path.is_empty():
			base_unit.moved = true
			base.apply_vine_on_landing(base_unit)
		if not unit.fresh_spawn and unit.can_act_skill():
			for skill_id in unit.skills:
				var entries := _dedupe_entries(base, base_unit, skill_id)
				for entry in entries:
					var sim := base.clone()
					var sim_unit := sim.unit_by_uid(unit.uid)
					if sim_unit == null:
						continue
					var result := SkillResolver.apply(sim, sim_unit, skill_id, entry, false)
					if not bool(result.get("ok", false)):
						continue
					var score := _score(base, sim, unit.uid)
					var channel_score := _channel_score(base, base_unit, skill_id, entry)
					var candidate := {
						"uid": unit.uid,
						"move_path": path,
						"skill": {"id": skill_id, "target": entry},
						"score": score["total"] + channel_score - _pending_hazard(base, position, "player"),
						"meta": result,
						"lethal": score["kills"],
					}
					if _better(candidate, best, path.size()):
						best = candidate
	if not best.is_empty() and int(best["score"]) > 0:
		return best
	# 没有可得分攻击：向最近的己方单位接近。
	return _approach_action(work, unit, positions, paths)


static func _dedupe_entries(state: BattleState, unit: CombatUnit, skill_id: String) -> Array:
	if skill_id == "lightning":
		if state.round >= Balance.MAX_ROUNDS:
			return []
		var max_range := int(SkillDB.get_def(skill_id).get("range", 5))
		var choices: Array = []
		for target in state.alive_units("player"):
			if GridSpec.manhattan(unit.cell, target.cell) <= max_range:
				choices.append(target)
		choices.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
			if a.is_trainer != b.is_trainer:
				return a.is_trainer
			return a.reg_index < b.reg_index
		)
		if choices.is_empty():
			return []
		var cells: Array = []
		for target in choices:
			if not cells.has(target.cell):
				cells.append(target.cell)
		for cell in GridSpec.all_cells():
			if cells.size() >= 3:
				break
			if not cells.has(cell) and GridSpec.manhattan(unit.cell, cell) <= max_range and state.unit_at(cell) == null:
				cells.append(cell)
		return [{"type": "multi", "cells": cells}] if cells.size() == 3 else []
	## 射线类只保留“最近命中”和“最远落点”两个代表性选项，避免重复克隆。
	var entries := SkillResolver.targets(state, unit, skill_id)
	if skill_id == "fire_burst" and state.round >= Balance.MAX_ROUNDS:
		return []
	if SkillDB.kind_of(skill_id) != "ray" or skill_id == "fire_burst":
		return entries
	var by_dir: Dictionary = {}
	for entry in entries:
		var cell: Vector2i = entry["cell"]
		var dir := Vector2i(signi(cell.x - unit.cell.x), signi(cell.y - unit.cell.y))
		var group: Array = by_dir.get(dir, [])
		group.append(entry)
		by_dir[dir] = group
	var reduced: Array = []
	for dir in by_dir:
		var group: Array = by_dir[dir]
		if group.size() <= 2:
			reduced.append_array(group)
		else:
			reduced.append(group[0])
			reduced.append(group[group.size() - 1])
	return reduced


static func _channel_score(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary) -> int:
	if skill_id != "fire_burst" and skill_id != "lightning":
		return 0
	var areas: Array = []
	if skill_id == "lightning":
		areas = (entry.get("cells", []) as Array).duplicate()
	else:
		var center: Vector2i = entry["cell"]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cell := center + Vector2i(dx, dy)
				if GridSpec.is_inside(cell):
					areas.append(cell)
	var score := 0
	for target in state.alive_units():
		if not areas.has(target.cell):
			continue
		if target.side == caster.side:
			score -= 70
		else:
			score += 48 + (25 if target.is_trainer else 0)
	return score


static func _pending_hazard(state: BattleState, cell: Vector2i, source_side: String) -> int:
	for cast in state.pending_casts:
		if String(cast["side"]) != source_side:
			continue
		for center in cast["cells"]:
			if String(cast["skill_id"]) == "lightning" and cell == center:
				return 120
			if String(cast["skill_id"]) == "fire_burst" and absi(cell.x - center.x) <= 1 and absi(cell.y - center.y) <= 1:
				return 120
	return 0


static func _score(before: BattleState, after: BattleState, actor_uid: int) -> Dictionary:
	if after.ended and after.end_reason == "forced_retreat":
		# 训练家被击倒后固定保留 1 HP，单纯比较前后 HP 会漏判胜利。
		return {"total": 100000, "kills": 1}
	var total := 0
	var kills := 0
	var actor_before := before.unit_by_uid(actor_uid)
	var actor_after := after.unit_by_uid(actor_uid)
	for unit in before.units:
		if unit.side != "player" or not unit.is_alive():
			continue
		var later := after.unit_by_uid(unit.uid)
		var died := later == null or not later.is_alive()
		if died:
			kills += 1
			total += 1000 + _priority(before, unit)
		elif later.hp < unit.hp:
			total += (unit.hp - later.hp) * 10 + _damage_priority(before, unit)
		if later != null and later.is_alive():
			var aura_gain := _attachment_layers(later) - _attachment_layers(unit)
			if aura_gain > 0:
				total += aura_gain * 6
			if later.parasite_until_round > unit.parasite_until_round:
				total += 20
			if later.rock_guard_until_round > unit.rock_guard_until_round:
				total -= 10
			if later.root_pending and not unit.root_pending:
				total += 14
			if later.slow_ticks > unit.slow_ticks:
				total += 10
			if later.burn_ticks > unit.burn_ticks:
				total += 9
			if later.frozen and not unit.frozen:
				total += 38 + (8 if unit.is_trainer else 0)
			if later.shock_ticks > unit.shock_ticks:
				total += 8
			if later.paralyzed_ticks > unit.paralyzed_ticks:
				total += 30
			if later.vine_ticks > unit.vine_ticks:
				total += 16
			if later.cell != unit.cell:
				# 推风与交换位置即使没有碰撞伤害，也能改变下一次交火位置。
				total += 6
	if actor_before != null and actor_before.is_alive():
		if actor_after == null or not actor_after.is_alive():
			total -= 100000
		elif actor_after.hp < actor_before.hp:
			total -= (actor_before.hp - actor_after.hp) * 50
		elif actor_after.hp > actor_before.hp:
			total += _heal_score(actor_before, actor_after, before)
	for unit in before.units:
		if unit.side != "enemy" or unit.uid == actor_uid or not unit.is_alive():
			continue
		var later := after.unit_by_uid(unit.uid)
		if later == null or not later.is_alive():
			total -= 500
		elif later.hp < unit.hp:
			total -= (unit.hp - later.hp) * 10
		elif later.hp > unit.hp:
			total += _heal_score(unit, later, before)
		if later != null and later.haste_ticks > unit.haste_ticks:
			# 已行动的友军本阶段无法利用加速；未来移动机会仍有少量价值。
			total += 12 if not unit.moved and unit.effective_move() > 0 else 3
		if later != null and later.extra_casts > unit.extra_casts and _bonus_cast_available(before, actor_before, unit):
			total += 23
		if later != null and _attachment_layers(later) > _attachment_layers(unit):
			total -= (_attachment_layers(later) - _attachment_layers(unit)) * 3
		if later != null and later.rock_guard_until_round > unit.rock_guard_until_round:
			total += 10
	total += _terrain_setup_score(before, after)
	return {"total": total, "kills": kills}


static func _attachment_layers(unit: CombatUnit) -> int:
	var count := 0
	for element in unit.attachments:
		count += ElementAttachmentResolver.stack_count(unit, String(element))
	return count


static func _bonus_cast_available(state: BattleState, actor: CombatUnit, target: CombatUnit) -> bool:
	if actor == null or target.reg_index <= actor.reg_index or target.skill_used or target.extra_casts > 0:
		return false
	if target.fresh_spawn or target.channel_lock_round == state.round or not target.can_act_skill():
		return false
	for skill_id in target.skills:
		if bool(SkillDB.get_def(String(skill_id)).get("channel", false)):
			continue
		if not _dedupe_entries(state, target, String(skill_id)).is_empty():
			return true
	return false


static func _heal_score(before_unit: CombatUnit, after_unit: CombatUnit, state: BattleState) -> int:
	var score := (after_unit.hp - before_unit.hp) * 15
	if before_unit.hp <= 2:
		for threat in state.alive_units("player"):
			if GridSpec.manhattan(before_unit.cell, threat.cell) <= 3:
				return score + 40
	return score


static func _terrain_setup_score(before: BattleState, after: BattleState) -> int:
	var score := 0
	for cell in GridSpec.all_cells():
		var old_terrain := before.terrain_at(cell)
		var new_terrain := after.terrain_at(cell)
		if old_terrain == new_terrain:
			continue
		for target in before.alive_units("player"):
			var distance := GridSpec.manhattan(cell, target.cell)
			match new_terrain:
				TerrainDB.WATER:
					if target.element != "water" and not target.has_buff("flight"):
						score += 12 if distance == 0 else 3 if distance == 1 else 0
				TerrainDB.ICE:
					if not target.has_buff("flight"):
						score += (12 if target.last_move_direction != Vector2i.ZERO else 2) if distance == 0 else 3 if distance == 1 else 0
				TerrainDB.VINES:
					if not target.has_buff("flight") and distance <= 2:
						score += 4
				TerrainDB.OBSTACLE:
					if distance <= 2:
						score += 5
	# 未来地形收益不应盖过直接击杀或大面积伤害。
	return mini(score, 24)


static func _priority(state: BattleState, unit: CombatUnit) -> int:
	if unit.is_trainer:
		return PRIORITY_TRAINER
	return PRIORITY_POKEMON


static func _damage_priority(state: BattleState, unit: CombatUnit) -> int:
	if unit.is_trainer:
		return 20
	return 10


static func _better(candidate: Dictionary, best: Dictionary, path_length: int) -> bool:
	if best.is_empty():
		return true
	if int(candidate["score"]) != int(best["score"]):
		return int(candidate["score"]) > int(best["score"])
	var candidate_cost := (candidate["move_path"] as Array).size()
	var best_cost := (best["move_path"] as Array).size()
	if candidate_cost != best_cost:
		return candidate_cost < best_cost
	var candidate_key := _skill_key(candidate)
	var best_key := _skill_key(best)
	return candidate_key < best_key


static func _skill_key(action: Dictionary) -> String:
	var skill: Dictionary = action.get("skill", {})
	if skill.is_empty():
		return "zzz"
	var entry: Dictionary = skill["target"]
	var skill_id := String(skill["id"])
	match String(entry.get("type", "")):
		"multi":
			return "%s|multi|%s" % [skill_id, str(entry.get("cells", []))]
		"unit":
			return "%s|unit|%08d" % [skill_id, int(entry["unit"])]
		"dir":
			var dir: Vector2i = entry["dir"]
			return "%s|dir|%d,%d" % [skill_id, dir.x, dir.y]
		_:
			var cell: Vector2i = entry["cell"]
			return "%s|cell|%03d,%03d" % [skill_id, cell.y, cell.x]


static func _approach_action(work: BattleState, unit: CombatUnit, positions: Array, paths: Dictionary) -> Dictionary:
	var targets := work.alive_units("player")
	if targets.is_empty():
		return {"uid": unit.uid, "move_path": [], "skill": {}}
	var best_cell := unit.cell
	var best_distance := 1 << 30
	var best_cost := 0
	var ordered: Array = positions.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x
	)
	for position in ordered:
		var hazard := _pending_hazard(work, position, "player")
		var distance := 1 << 30
		for target in targets:
			var value := PathFinder.path_distance(work, position, target.cell, unit.element, unit.has_buff("flight"))
			distance = mini(distance, value)
		var cost: int = (paths[position] as Array).size()
		distance += hazard
		if distance < best_distance or (distance == best_distance and cost < best_cost):
			best_distance = distance
			best_cell = position
			best_cost = cost
	var path: Array = paths.get(best_cell, [])
	return {"uid": unit.uid, "move_path": path, "skill": {}}


static func _execute_on(work: BattleState, action: Dictionary) -> void:
	var unit := work.unit_by_uid(int(action["uid"]))
	if unit == null or not unit.is_alive():
		return
	for cell in action.get("move_path", []):
		unit.last_move_direction = cell - unit.cell
		unit.cell = cell
		if not unit.has_buff("flight") and (work.terrain_at(cell) == TerrainDB.WATER or work.terrain_at(cell) == TerrainDB.DEEP):
			unit.burn_ticks = 0
	if not action.get("move_path", []).is_empty():
		unit.moved = true
		work.apply_vine_on_landing(unit)
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty():
		var result := SkillResolver.apply(work, unit, String(skill["id"]), skill["target"], false)
		if bool(result.get("ok", false)):
			if unit.skill_used and unit.extra_casts > 0:
				unit.extra_casts -= 1
			else:
				unit.skill_used = true
	unit.fresh_spawn = false


static func describe(action: Dictionary, state: BattleState) -> String:
	var unit := state.unit_by_uid(int(action.get("uid", -1)))
	var name := unit.display_name if unit != null else "?"
	var parts: Array = []
	var path: Array = action.get("move_path", [])
	if not path.is_empty():
		var dest: Vector2i = path[path.size() - 1]
		parts.append("移动 %d 格至 (%d,%d)" % [path.size(), dest.x, dest.y])
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty():
		var entry: Dictionary = skill["target"]
		if String(entry.get("type", "")) == "multi":
			parts.append("吟唱%s → %s" % [SkillDB.name_of(String(skill["id"])), str(entry["cells"])])
			return "%s：%s" % [name, "，".join(parts)]
		var target_cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		if String(entry.get("type", "")) == "unit":
			var victim := state.unit_by_uid(int(entry["unit"]))
			if victim != null:
				target_cell = victim.cell
		parts.append("%s%s → (%d,%d)" % ["吟唱" if String(skill["id"]) == "fire_burst" else "施放", SkillDB.name_of(String(skill["id"])), target_cell.x, target_cell.y])
	if parts.is_empty():
		return "%s 待命" % name
	return "%s：" % name + "，".join(parts)
