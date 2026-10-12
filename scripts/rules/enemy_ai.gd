class_name EnemyAI
extends RefCounted

## 确定性敌方 AI：固定行动顺序（火、水、草、电、岩、增援），
## 先移动后技能；威胁预告与实际执行使用同一份计划。

const PRIORITY_CARRIER := 300
const PRIORITY_TRAINER := 150
const PRIORITY_POKEMON := 100


static func plan(state: BattleState) -> Array:
	var work := state.clone()
	var actions: Array = []
	for uid in _action_order(work):
		var unit := work.unit_by_uid(uid)
		if unit == null or not unit.is_alive():
			continue
		var action := _decide(work, unit)
		var has_effect: bool = not (action["move_path"] as Array).is_empty() or not (action["skill"] as Dictionary).is_empty()
		if not has_effect:
			continue
		_execute_on(work, action)
		actions.append(action)
	return actions


static func _action_order(state: BattleState) -> Array:
	var enemies: Array = []
	for unit in state.units:
		if unit.side == "enemy" and unit.is_alive():
			enemies.append(unit)
	enemies.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		var a_spawn := 1 if a.fresh_spawn else 0
		var b_spawn := 1 if b.fresh_spawn else 0
		if a_spawn != b_spawn:
			return a_spawn < b_spawn
		var a_elem := Elements.order_index(a.element)
		var b_elem := Elements.order_index(b.element)
		if a_elem != b_elem:
			return a_elem < b_elem
		return a.reg_index < b.reg_index
	)
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
		if not unit.fresh_spawn:
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
					var candidate := {
						"uid": unit.uid,
						"move_path": path,
						"skill": {"id": skill_id, "target": entry},
						"score": score["total"],
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
	## 射线类只保留“最近命中”和“最远落点”两个代表性选项，避免重复克隆。
	var entries := SkillResolver.targets(state, unit, skill_id)
	if SkillDB.kind_of(skill_id) != "ray":
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


static func _score(before: BattleState, after: BattleState, actor_uid: int) -> Dictionary:
	var total := 0
	var kills := 0
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
			if later.root_pending and not unit.root_pending:
				total += 6
			if later.slow_ticks > unit.slow_ticks:
				total += 6
			if later.burn_ticks > unit.burn_ticks:
				total += 6
	var actor_before := before.unit_by_uid(actor_uid)
	var actor_after := after.unit_by_uid(actor_uid)
	if actor_before != null and actor_before.is_alive():
		if actor_after == null or not actor_after.is_alive():
			total -= 100000
		elif actor_after.hp < actor_before.hp:
			total -= (actor_before.hp - actor_after.hp) * 50
	for unit in before.units:
		if unit.side != "enemy" or unit.uid == actor_uid or not unit.is_alive():
			continue
		var later := after.unit_by_uid(unit.uid)
		if later == null or not later.is_alive():
			total -= 500
		elif later.hp < unit.hp:
			total -= (unit.hp - later.hp) * 10
	return {"total": total, "kills": kills}


static func _priority(state: BattleState, unit: CombatUnit) -> int:
	if unit.is_trainer:
		return PRIORITY_TRAINER
	if state.carrier_uid() == unit.uid:
		return PRIORITY_CARRIER
	return PRIORITY_POKEMON


static func _damage_priority(state: BattleState, unit: CombatUnit) -> int:
	if state.carrier_uid() == unit.uid:
		return 40
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
		var distance := 1 << 30
		for target in targets:
			var value := PathFinder.path_distance(work, position, target.cell, unit.element)
			distance = mini(distance, value)
		var cost: int = (paths[position] as Array).size()
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
		unit.cell = cell
		if work.terrain_at(cell) == TerrainDB.WATER or work.terrain_at(cell) == TerrainDB.DEEP:
			unit.burn_ticks = 0
	if not action.get("move_path", []).is_empty():
		unit.moved = true
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty():
		SkillResolver.apply(work, unit, String(skill["id"]), skill["target"], false)
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
		var target_cell: Vector2i = entry.get("cell", Vector2i.ZERO)
		if String(entry.get("type", "")) == "unit":
			var victim := state.unit_by_uid(int(entry["unit"]))
			if victim != null:
				target_cell = victim.cell
		parts.append("施放%s → (%d,%d)" % [SkillDB.name_of(String(skill["id"])), target_cell.x, target_cell.y])
	if parts.is_empty():
		return "%s 待命" % name
	return "%s：" % name + "，".join(parts)
