extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")
const PushResolver = preload("res://scripts/push_resolver.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


func move_phase(state: RefCounted, group_ids: Array[String] = []) -> void:
	for enemy in state.units:
		if state.outcome != "":
			return
		if enemy.team != "enemy" or not enemy.is_alive() or (not group_ids.is_empty() and not group_ids.has(enemy.unit_id)):
			continue
		var path: Array[Vector2i] = plan_move(state, enemy)
		if not path.is_empty():
			state.enemy_move_path(enemy, path)


func plan_move(state: RefCounted, enemy: CombatUnit) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if enemy == null or not enemy.is_alive() or enemy.move_points <= 0:
		return empty
	var targets: Array[CombatUnit] = []
	var trainer: CombatUnit = state.unit_by_id("trainer")
	if trainer != null and trainer.is_alive() and not targets.has(trainer):
		targets.append(trainer)
	for unit in state.units:
		if unit.team == "player" and unit.is_alive() and not targets.has(unit):
			targets.append(unit)
	if targets.is_empty():
		return empty
	var paths: Dictionary = _reachable_paths(state, enemy)
	if state.reward_state == "ground" and state.unit_at(state.reward_cell) == null and paths.has(state.reward_cell) and (not state.terrain.is_burning(state.reward_cell) or enemy.element_type == "fire" or enemy.flying or enemy.debuff_immune):
		var reward_route: Dictionary = paths[state.reward_cell]
		if int(reward_route["steps"]) <= enemy.move_points:
			return reward_route["path"]
	var best: Dictionary = {}
	for target in targets:
		if _is_engaged(state, enemy, target):
			return empty
		for cell in paths.keys():
			if cell == enemy.cell:
				continue
			if not state.can_enter_voluntarily(enemy, cell):
				continue
			var route: Dictionary = paths[cell]
			var original: Vector2i = enemy.cell
			enemy.cell = cell
			var engaged: bool = _is_engaged(state, enemy, target)
			enemy.cell = original
			if engaged and (best.is_empty() or _path_less(route, best)):
				best = route
		if not best.is_empty():
			break
	if best.is_empty():
		var target: CombatUnit = targets[0]
		var best_distance: int = 999
		for cell in paths.keys():
			if cell == enemy.cell:
				continue
			if not state.can_enter_voluntarily(enemy, cell):
				continue
			var route: Dictionary = paths[cell]
			var distance: int = state.distance(cell, target.cell)
			if distance < best_distance or (distance == best_distance and (best.is_empty() or _path_less(route, best))):
				best_distance = distance
				best = route
	if best.is_empty():
		return empty
	var full_path: Array[Vector2i] = best["path"]
	for index in mini(enemy.move_points, full_path.size()):
		empty.append(full_path[index])
	return empty


func _is_engaged(state: RefCounted, enemy: CombatUnit, target: CombatUnit) -> bool:
	if enemy.element_type == "rock":
		return state.distance(enemy.cell, target.cell) == 1
	return not _best_offense(state, enemy, target).is_empty()


func attack_phase(state: RefCounted, group_ids: Array[String] = []) -> void:
	for enemy in state.units:
		if state.outcome != "":
			return
		if enemy.team != "enemy" or not enemy.is_alive() or enemy.skill_points <= 0 or (not group_ids.is_empty() and not group_ids.has(enemy.unit_id)):
			continue
		var action: Dictionary = _best_offense(state, enemy, state.unit_by_id("trainer"))
		if action.is_empty():
			for ally in state.units:
				if ally.team == "player" and ally.is_alive() and ally.unit_id != "trainer":
					var candidate: Dictionary = _best_offense(state, enemy, ally)
					if not candidate.is_empty() and (action.is_empty() or candidate["score"] > action["score"]):
						action = candidate
		if action.is_empty():
			action = _setup_action(state, enemy, state.unit_by_id("trainer"))
		if action.is_empty():
			state.add_event("%s 没有合法技能目标，待机。" % enemy.display_name)
		else:
			state.try_use_skill(enemy.unit_id, action["skill_id"], action["cell"])


func _best_offense(state: RefCounted, enemy: CombatUnit, victim: CombatUnit) -> Dictionary:
	if victim == null or not victim.is_alive():
		return {}
	var best: Dictionary = {}
	for skill_id in enemy.skill_ids:
		var skill: Dictionary = CombatConfig.SKILLS[skill_id]
		if enemy.skill_points < int(skill["cost"]) or state.terrain.is_steam(enemy.cell) or skill_id == "rain_call":
			continue
		if int(skill.get("uses_per_battle", 0)) > 0 and int(enemy.battle_skill_uses.get(skill_id, 0)) >= int(skill["uses_per_battle"]):
			continue
		var candidates: Array[Vector2i] = _all_cells()
		if skill_id == "rock_create":
			candidates.clear()
			for direction in DIRECTIONS:
				candidates.append(enemy.cell + direction)
		for target_cell in candidates:
			var impact: Vector2i = state.projected_skill_impact(enemy, skill_id, target_cell)
			if impact == Vector2i(-1, -1):
				continue
			if skill_id == "flame_charge" and (state.terrain.is_deep_water(impact) or state.terrain.is_collapsed(impact) or state.terrain.is_burning(impact)):
				continue
			if skill_id == "flame_charge" and (victim.burned or victim.element_type == "fire"):
				continue
			var area: Array[Vector2i] = EnvironmentResolver.skill_area(state, skill_id, impact, enemy.cell)
			if not area.has(victim.cell) or skill_id == "flame_charge" and area[0] != victim.cell:
				continue
			var score: int = int(CombatConfig.SKILLS[skill_id]["damage"]) * 10
			if skill_id == "fire_burst" and impact == victim.cell:
				score += 12
			elif skill_id == "fire_burst":
				score -= 5 # Save the one-use fireball when another attack can reach.
			if skill_id == "flame_jet" and not victim.burned and victim.element_type != "fire":
				score += 6
			if skill_id == "flame_charge":
				score = 5 if not victim.burned and victim.element_type != "fire" else -100
			if skill_id == "rock_create" and state.terrain.is_fragile(victim.cell):
				score += 100
			if skill_id in ["rock_push", "water_flow"] and impact == victim.cell:
				var result: Dictionary = state.preview_skill_push(enemy, skill_id, target_cell)
				if result.is_empty():
					continue
				score = int(result["target_damage"]) * 10
				if state.terrain.is_deep_water(result["destination"]) and victim.element_type != "water" and not victim.flying:
					score += 100
			if skill_id == "electric_arc" and state.terrain.is_water(impact):
				score += 2
			if enemy.upgraded_skill_id == skill_id:
				score += 5
			for ally in state.units:
				if ally.team == "enemy" and ally.is_alive() and ally.unit_id != enemy.unit_id and area.has(ally.cell):
					score -= 8
			if best.is_empty() or score > int(best["score"]):
				best = {"skill_id": skill_id, "cell": target_cell, "score": score}
	return best


func _setup_action(state: RefCounted, enemy: CombatUnit, trainer: CombatUnit) -> Dictionary:
	var best: Dictionary = {}
	for skill_id in enemy.skill_ids:
		if skill_id in ["rock_create", "flame_charge", "fire_burst"]:
			continue
		for cell in _all_cells():
			if not state.can_use_skill(enemy, skill_id, cell):
				continue
			var impact: Vector2i = state.projected_skill_impact(enemy, skill_id, cell)
			if skill_id != "rain_call" and (state.unit_at(impact) != null or state.is_nest_at(impact)):
				continue
			var object: Dictionary = state.terrain.object_at(impact)
			var useful := false
			var converted_cells := 0
			match skill_id:
				"rain_call":
					for affected in EnvironmentResolver.skill_area(state, skill_id, impact):
						if not state.is_nest_at(affected) and state.terrain.object_at(affected).is_empty() and state.terrain.ground_at(affected) in ["ground", "grass", "fragile"]:
							converted_cells += 1
					useful = converted_cells > 0
				"water_flow":
					useful = not object.is_empty() or state.terrain.ground_at(impact) in ["ground", "grass"]
				"rock_break":
					useful = object.get("type", "") == "rock" and state.distance(enemy.cell, impact) + state.distance(impact, trainer.cell) <= state.distance(enemy.cell, trainer.cell) + 2
			if useful:
				var rank: Array[int] = [state.distance(impact, trainer.cell), -converted_cells, impact.y, impact.x]
				if best.is_empty() or _rank_less(rank, best["rank"]):
					best = {"skill_id": skill_id, "cell": cell, "rank": rank}
	return best


func _reachable_paths(state: RefCounted, enemy: CombatUnit) -> Dictionary:
	var start: Vector2i = enemy.cell
	var paths: Dictionary = {start: {"cell": start, "path": [] as Array[Vector2i], "hazards": 0, "steps": 0}}
	var frontier: Array[Dictionary] = [paths[start]]
	while not frontier.is_empty():
		var index := 0
		for candidate in range(1, frontier.size()):
			if _path_less(frontier[candidate], frontier[index]):
				index = candidate
		var entry: Dictionary = frontier.pop_at(index)
		var cell: Vector2i = entry["cell"]
		if int(entry["hazards"]) != int(paths[cell]["hazards"]) or int(entry["steps"]) != int(paths[cell]["steps"]):
			continue
		for direction in DIRECTIONS:
			var next_cell: Vector2i = cell + direction
			if not state.can_traverse_voluntarily(enemy, next_cell):
				continue
			var hazards: int = int(entry["hazards"]) + (2 if state.terrain.is_shallow_water(next_cell) and enemy.element_type != "water" and not enemy.flying else 0) + (3 if state.terrain.is_burning(next_cell) and enemy.element_type != "fire" and not enemy.flying else 0)
			var route: Array[Vector2i] = entry["path"].duplicate()
			route.append(next_cell)
			var next_entry: Dictionary = {"cell": next_cell, "path": route, "hazards": hazards, "steps": route.size()}
			if paths.has(next_cell) and not _path_less(next_entry, paths[next_cell]):
				continue
			paths[next_cell] = next_entry
			frontier.append(next_entry)
	return paths


func _all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in GridSpec.HEIGHT:
		for x in GridSpec.WIDTH:
			cells.append(Vector2i(x, y))
	return cells


func _path_less(left: Dictionary, right: Dictionary) -> bool:
	if int(left["hazards"]) != int(right["hazards"]):
		return int(left["hazards"]) < int(right["hazards"])
	if int(left["steps"]) != int(right["steps"]):
		return int(left["steps"]) < int(right["steps"])
	var a: Vector2i = left["cell"]
	var b: Vector2i = right["cell"]
	return a.y < b.y or (a.y == b.y and a.x < b.x)


func _rank_less(left: Array[int], right: Array[int]) -> bool:
	for index in left.size():
		if left[index] != right[index]:
			return left[index] < right[index]
	return false
