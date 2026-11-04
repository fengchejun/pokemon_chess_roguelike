class_name EnemyAI
extends RefCounted

## 确定性敌方 AI：有即时收益的辅助先行，直接击杀优先，其他动作按登记顺序，
## 先移动后技能；威胁预告与实际执行使用同一份计划。

const PRIORITY_TRAINER := 150
const PRIORITY_POKEMON := 100


static func plan(state: BattleState) -> Array:
	var work := state.clone()
	var actions: Array = []
	var cast_counts: Dictionary = {}
	var pending := _action_order(work)
	while not pending.is_empty() and not work.ended:
		var opening := _next_action(work, pending, cast_counts)
		var uid := int(opening.get("uid", pending[0]))
		pending.erase(uid)
		# 同一单位最多两次施法；第二次必须来自友军已给予的额外机会。
		for cast_index in range(2):
			var unit := work.unit_by_uid(uid)
			if unit == null or not unit.is_on_board() or work.ended:
				break
			if cast_index > 0 and (not unit.skill_used or unit.extra_casts <= 0 or not unit.can_act_skill()):
				break
			var action := opening if cast_index == 0 else _decide(work, unit, cast_counts)
			var has_effect: bool = not (action["move_path"] as Array).is_empty() or not (action["skill"] as Dictionary).is_empty() or action.has("guard")
			if not has_effect or (cast_index > 0 and (action["skill"] as Dictionary).is_empty()):
				break
			_execute_on(work, action)
			actions.append(action)
			if not (action["skill"] as Dictionary).is_empty():
				cast_counts[uid] = int(cast_counts.get(uid, 0)) + 1
			work.check_battle_end()
	# 后续获得的额外施法也可由已行动友军兑现，仍遵守每单位两次的规划上限。
	for uid in _action_order(work):
		if work.ended or int(cast_counts.get(uid, 0)) >= 2:
			continue
		var unit := work.unit_by_uid(uid)
		if unit == null or not unit.skill_used or unit.extra_casts <= 0 or not unit.can_act_skill():
			continue
		var action := _decide(work, unit, cast_counts)
		if (action["skill"] as Dictionary).is_empty():
			continue
		_execute_on(work, action)
		actions.append(action)
		cast_counts[uid] = int(cast_counts.get(uid, 0)) + 1
		work.check_battle_end()
	return actions


static func _next_action(state: BattleState, pending: Array, cast_counts: Dictionary) -> Dictionary:
	var first := state.unit_by_uid(int(pending[0]))
	if first == null or not first.is_on_board():
		return {"uid": pending[0], "move_path": [], "skill": {}}
	var ordinary := _decide(state, first, cast_counts)
	if int(ordinary.get("lethal", 0)) > 0:
		return ordinary
	var best := ordinary if _is_support_action(ordinary) else {}
	for uid in pending:
		if int(uid) == first.uid:
			continue
		var unit := state.unit_by_uid(int(uid))
		if unit == null or not unit.can_act_skill() or not (unit.skills.has("tailwind") or unit.skills.has("double_cast")):
			continue
		var candidate := _decide(state, unit, cast_counts)
		if int(candidate.get("lethal", 0)) > 0:
			return candidate
		if _is_support_action(candidate) and int(candidate.get("score", 0)) > 0 and _better(candidate, best, (candidate.get("move_path", []) as Array).size()):
			best = candidate
	return best if not best.is_empty() else ordinary


static func _is_support_action(action: Dictionary) -> bool:
	return String(action.get("skill", {}).get("id", "")) in ["tailwind", "double_cast"]


static func _action_order(state: BattleState) -> Array:
	var enemies: Array = []
	for unit in state.units:
		if unit.side == "enemy" and unit.is_on_board() and not unit.fresh_spawn and unit.channel_lock_round != state.round:
			enemies.append(unit)
	enemies.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return a.reg_index < b.reg_index)
	var order: Array = []
	for unit in enemies:
		order.append(unit.uid)
	return order


static func _decide(work: BattleState, unit: CombatUnit, cast_counts: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var repair_best: Dictionary = {}
	var positions: Array = [unit.cell]
	var paths: Dictionary = {unit.cell: []}
	var free_paths: Dictionary = {unit.cell: false}
	if work.can_move_unit_now(unit):
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
			free_paths[cell] = bool(options[cell].get("terrain_travel", false))
	for position in positions:
		var base := work.clone()
		var base_unit := base.unit_by_uid(unit.uid)
		if base_unit == null or not base_unit.is_alive():
			continue
		var path: Array = paths[position]
		base_unit.cell = position
		if not path.is_empty():
			base_unit.moved = unit.moved if bool(free_paths.get(position, false)) else true
			base.apply_vine_on_landing(base_unit)
		if not unit.fresh_spawn and unit.can_act_skill():
			for skill_id in unit.skills:
				var entries := _dedupe_entries(base, base_unit, skill_id)
				for entry in entries:
					if skill_id == "double_cast":
						var ids: Array = entry.get("units", [entry.get("unit", -1)])
						if not ids.any(func(uid): return int(cast_counts.get(uid, 0)) < 2):
							continue
					var sim := base.clone()
					var sim_unit := sim.unit_by_uid(unit.uid)
					if sim_unit == null:
						continue
					var result := SkillResolver.apply(sim, sim_unit, skill_id, entry, false)
					if not bool(result.get("ok", false)):
						continue
					if _harms_own_nest(base, sim):
						continue
					var score := _score(base, sim, unit.uid, cast_counts)
					var channel_score := _channel_score(base, base_unit, skill_id, entry)
					var route_score := _route_opening_score(base, sim, unit.uid)
					var skill_score := int(score["total"]) + channel_score + route_score + (30 if skill_id == "tree_man" else 0)
					var repair_only := skill_score <= 0
					if repair_only:
						if base.reinforcement_pool.is_empty():
							continue
						var projected := sim
						if sim.pending_casts.size() > base.pending_casts.size():
							projected = sim.clone()
							var cast: Dictionary = sim.pending_casts.back()
							SkillResolver.resolve_channel(projected, projected.unit_by_uid(unit.uid), skill_id, cast["cells"])
						skill_score = _nest_spawn_repair_score(base, projected, unit.uid)
						if skill_score <= 0:
							continue
					var candidate := {
						"uid": unit.uid,
						"move_path": path,
						"free_terrain_move": bool(free_paths.get(position, false)),
						"skill": {"id": skill_id, "target": entry},
						"score": skill_score - _pending_hazard(base, position, "player"),
						"meta": result,
						"lethal": score["kills"],
					}
					if repair_only:
						candidate["nest_spawn_repair"] = true
						if _better(candidate, repair_best, path.size()):
							repair_best = candidate
					elif _better(candidate, best, path.size()):
						best = candidate
	var guard_scores := {}
	for current in work.all_nests():
		guard_scores[current["cell"]] = _nest_guard_score(work, current)
	for position in positions:
		var guard_state := work.clone()
		var defender := guard_state.unit_by_uid(unit.uid)
		defender.cell = position
		for current in guard_state.all_nests():
			var cell: Vector2i = current["cell"]
			if not guard_state.can_guard_nest(defender, cell):
				continue
			var value := int(guard_scores.get(cell, 0)) - _pending_hazard(guard_state, position, "player")
			if value <= 0:
				continue
			var candidate := {"uid": unit.uid, "move_path": paths[position], "free_terrain_move": bool(free_paths.get(position, false)), "skill": {}, "guard": cell, "score": value, "lethal": 0}
			if _better(candidate, best, (paths[position] as Array).size()):
				best = candidate
	if not best.is_empty() and int(best["score"]) > 0:
		return best
	if not repair_best.is_empty() and int(repair_best["score"]) > 0:
		return repair_best
	# 没有可得分攻击或出生格疏通任务：向最近的己方单位接近。
	return _approach_action(work, unit, positions, paths, free_paths)


static func _spawn_terrain_options(state: BattleState, cell: Vector2i, terrain: int) -> int:
	var count := 0
	if state.is_interaction_cell(cell) or state.is_nest_cell(cell) or TerrainDB.blocks_move(terrain):
		return 0
	for species_id in state.reinforcement_pool:
		if TerrainDB.can_stand(terrain, SpeciesDB.element_of(species_id)):
			count += 1
	return count


static func _nest_spawn_repair_score(before: BattleState, after: BattleState, actor_uid: int) -> int:
	if before.reinforcement_pool.is_empty() or _harms_own_nest(before, after):
		return 0
	var actor := before.unit_by_uid(actor_uid)
	if actor == null:
		return 0
	# 工程任务不以误伤、牺牲友军换取产怪空格。
	for ally in before.alive_units("enemy"):
		var later := after.unit_by_uid(ally.uid)
		if later == null or not later.is_on_board() or later.hp < ally.hp:
			return 0
	var score := 0
	var checked := {}
	for current in before.all_nests():
		if not bool(current.get("alive", false)) or GridSpec.manhattan(actor.cell, current["cell"]) > 4:
			continue
		for cell in GridSpec.neighbors4(current["cell"]):
			if checked.has(cell) or before.unit_at(cell) != null or after.unit_at(cell) != null:
				continue
			checked[cell] = true
			var old_options := _spawn_terrain_options(before, cell, before.terrain_at(cell))
			var new_options := _spawn_terrain_options(after, cell, after.terrain_at(cell))
			if new_options < old_options:
				score -= 20
			elif new_options > old_options:
				score += 10
			elif before.obstacle_durability.has(cell) and int(after.obstacle_durability.get(cell, 0)) < int(before.obstacle_durability[cell]):
				# 允许分两次拆障，但障碍下面也必须是增援能站立的地形。
				var origin := int(before.obstacle_origin.get(cell, TerrainDB.PLAIN))
				if _spawn_terrain_options(before, cell, origin) > old_options:
					score += 4
	return mini(score, 16)


static func _nest_guard_score(state: BattleState, nest: Dictionary) -> int:
	# 健康巢穴优先进攻；受损后才按附近威胁投入守军，避免无限叠护。
	var hp := int(nest.get("hp", 0))
	var shelter := state.sheltered_boss() != null
	var max_hp := int(nest.get("max_hp", Balance.nest_max_hp(state.battle_index)))
	if hp * 3 >= max_hp * 2 and not shelter:
		return 0
	var pressure := 0
	for target in state.alive_units("player"):
		if target.frozen or target.paralyzed_ticks > 0 or target.fresh_spawn:
			continue
		var offensive := false
		for skill_id in target.skills:
			if SkillDB.damage_of(skill_id) > 0 and target.can_use_in_battle(skill_id):
				offensive = true
				break
		if not offensive:
			continue
		var distance := 1 << 30
		for near in GridSpec.neighbors4(nest["cell"]):
			distance = mini(distance, PathFinder.path_distance(state, target.cell, near, target.element, target.has_buff("flight")))
		if distance <= 3:
			pressure += 1
	var charges := state.nest_guard_charges(nest["cell"])
	if pressure <= charges:
		return 0
	var value := (8 if hp * 3 > max_hp else 42) + mini(pressure, 3) * 6 + (22 if shelter else 0) - charges * 12
	return value


static func _dedupe_entries(state: BattleState, unit: CombatUnit, skill_id: String) -> Array:
	## 射线类只保留“最近命中”和“最远落点”两个代表性选项，避免重复克隆。
	var entries := SkillResolver.targets(state, unit, skill_id)
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
	if skill_id == "fire_burst":
		var sim := state.clone()
		SkillResolver.resolve_channel(sim, sim.unit_by_uid(caster.uid), skill_id, [entry["cell"]])
		if _harms_own_nest(state, sim):
			return -1000000
		return int(_score(state, sim, caster.uid)["total"]) + _route_opening_score(state, sim, caster.uid)
	if skill_id == "herbal_heal":
		var healing := 0
		for ally in state.alive_units(caster.side):
			if GridSpec.manhattan(ally.cell, caster.cell) <= 2:
				healing += mini(Balance.HERBAL_HEAL + int(caster.upgrades.get("herbal_heal_amount", 0)), ally.max_hp - ally.hp)
		return healing * 2
	if not ["fire_burst", "lightning", "rock_slide", "tsunami", "earth_shake"].has(skill_id):
		return 0
	var areas: Array = []
	if skill_id == "lightning":
		for target in state.alive_units("player" if caster.side == "enemy" else "enemy"):
			areas.append(target.cell)
	elif skill_id == "rock_slide":
		areas = [entry["cell"]]
	elif skill_id == "tsunami":
		areas = SkillResolver.tsunami_cells(caster.cell, entry["dir"])
	elif skill_id == "earth_shake":
		areas = SkillResolver.front_area_cells(caster.cell, entry["dir"], 3)
	else:
		var center: Vector2i = entry["cell"]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cell := center + Vector2i(dx, dy)
				if GridSpec.is_inside(cell):
					areas.append(cell)
	var projected := state.clone()
	SkillResolver.resolve_channel(projected, projected.unit_by_uid(caster.uid), skill_id, areas)
	if _harms_own_nest(state, projected):
		return -1000000
	var score := 0
	for target in state.alive_units():
		if not areas.has(target.cell):
			continue
		if skill_id == "tsunami" and not TerrainDB.is_water_body(state.terrain_at(target.cell)):
			continue
		if target.side == caster.side:
			if skill_id != "tsunami" and (skill_id != "earth_shake" or (state.terrain_at(target.cell) == TerrainDB.FRAGILE and not target.has_buff("flight"))):
				score -= 70
		else:
			score += 48 + (25 if target.is_trainer else 0)
	return score


static func _pending_hazard(state: BattleState, cell: Vector2i, source_side: String) -> int:
	for strike in state.storm_strikes:
		if strike["cell"] == cell and int(strike["due_round"]) <= state.round:
			return 200
	for cast in state.pending_casts:
		if String(cast["side"]) != source_side:
			continue
		for center in cast["cells"]:
			if String(cast["skill_id"]) == "earth_shake" and cell == center:
				return 120
			if (String(cast["skill_id"]) == "lightning" or String(cast["skill_id"]) == "rock_slide") and cell == center:
				return 120
			if String(cast["skill_id"]) == "tsunami" and cell == center and TerrainDB.is_water_body(state.terrain_at(cell)):
				return 120
			if String(cast["skill_id"]) == "fire_burst" and absi(cell.x - center.x) <= 1 and absi(cell.y - center.y) <= 1:
				return 120
	return 0


static func _score(before: BattleState, after: BattleState, actor_uid: int, cast_counts: Dictionary = {}) -> Dictionary:
	if after.ended and after.end_reason == "forced_retreat":
		# 训练家被击倒后直接结束本局，单纯比较前后 HP 会漏判胜利。
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
			total += (unit.hp - later.hp) + _damage_priority(before, unit)
		if later != null and later.is_alive():
			if later.root_pending and not unit.root_pending:
				total += 14
			if later.parasite_source_uid >= 0 and unit.parasite_source_uid < 0:
				total += 25
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
				# 击退与交换位置即使没有碰撞伤害，也能改变下一次交火位置。
				total += 6
	if actor_before != null and actor_before.is_alive():
		if actor_after == null or not actor_after.is_alive():
			total -= 100000
		elif actor_after.hp < actor_before.hp:
			total -= (actor_before.hp - actor_after.hp) * 5
		elif actor_after.hp > actor_before.hp:
			total += _heal_score(actor_before, actor_after, before)
		if actor_after != null and actor_after.is_alive():
			if actor_after.fire_amp_stacks > actor_before.fire_amp_stacks:
				total += actor_after.fire_amp_stacks - actor_before.fire_amp_stacks
			if actor_after.ice_glide_until_round > actor_before.ice_glide_until_round and before.terrain_at(actor_after.cell) == TerrainDB.ICE:
				total += 13
			if actor_after.surf_until_round > actor_before.surf_until_round and TerrainDB.is_water_body(before.terrain_at(actor_after.cell)):
				total += 13
	for unit in before.units:
		if unit.side != "enemy" or unit.uid == actor_uid or not unit.is_alive():
			continue
		var later := after.unit_by_uid(unit.uid)
		if later == null or not later.is_alive():
			total -= 500
		elif later.hp < unit.hp:
			total -= unit.hp - later.hp
		elif later.hp > unit.hp:
			total += _heal_score(unit, later, before)
		if later != null and later.haste_ticks > unit.haste_ticks:
			# 已行动的友军本阶段无法利用加速；未来移动机会仍有少量价值。
			total += _haste_value(before, unit, later)
		if later != null and later.extra_casts > unit.extra_casts and int(cast_counts.get(unit.uid, 0)) < 2 and _bonus_cast_available(before, actor_before, unit):
			total += 23
	total += _terrain_setup_score(before, after)
	return {"total": total, "kills": kills}


static func _haste_value(state: BattleState, before: CombatUnit, after: CombatUnit) -> int:
	if not state.can_move_unit_now(before) or before.guard_nest.x >= 0:
		return 0
	var distance := 1 << 30
	for target in state.alive_units("player"):
		for cell in GridSpec.neighbors4(target.cell):
			if state.unit_at(cell) != null and cell != before.cell:
				continue
			distance = mini(distance, PathFinder.path_distance(state, before.cell, cell, before.element, before.has_buff("flight")))
	if distance <= 0 or distance >= (1 << 29):
		return 0
	var old_reach := mini(distance, before.effective_move())
	var new_reach := mini(distance, after.effective_move())
	if new_reach <= old_reach:
		return 0
	return 12 + (18 if before.effective_move() < distance and after.effective_move() >= distance else 0)


static func _bonus_cast_available(state: BattleState, actor: CombatUnit, target: CombatUnit) -> bool:
	if actor == null or target.extra_casts > 0 or target.guard_nest.x >= 0:
		return false
	if target.fresh_spawn or target.frozen or target.paralyzed_ticks > 0 or target.channel_lock_round == state.round:
		return false
	var available := target.dup()
	available.extra_casts += 1
	for skill_id in available.skills:
		if not _dedupe_entries(state, available, String(skill_id)).is_empty():
			return true
	return false


static func _heal_score(before_unit: CombatUnit, after_unit: CombatUnit, state: BattleState) -> int:
	var score := roundi(float(after_unit.hp - before_unit.hp) * 1.5)
	if before_unit.hp_ratio() <= 0.4:
		for threat in state.alive_units("player"):
			if GridSpec.manhattan(before_unit.cell, threat.cell) <= 3:
				return score + 14
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


static func _route_opening_score(before: BattleState, after: BattleState, actor_uid: int) -> int:
	## 破障、造冰和藤蔓若让被困友军重新接敌，计入技能选择。
	var ally_repositioned := false
	for ally in before.alive_units("enemy"):
		var later := after.unit_by_uid(ally.uid)
		if later != null and later.cell != ally.cell:
			ally_repositioned = true
			break
	if not ally_repositioned and before.obstacle_durability == after.obstacle_durability:
		if before.terrain == after.terrain:
			return 0
		var passability_changed := false
		for cell in GridSpec.all_cells():
			var old_terrain := before.terrain_at(cell)
			var new_terrain := after.terrain_at(cell)
			if old_terrain == new_terrain:
				continue
			for ally in before.alive_units("enemy"):
				if TerrainDB.can_stand(old_terrain, ally.element) != TerrainDB.can_stand(new_terrain, ally.element):
					passability_changed = true
					break
			if passability_changed:
				break
		if not passability_changed:
			return 0
	var score := 0
	var damaged_cells: Array = []
	for cell in before.obstacle_durability:
		if int(after.obstacle_durability.get(cell, 0)) < int(before.obstacle_durability[cell]):
			damaged_cells.append(cell)
	var opened: BattleState = null
	for ally in before.alive_units("enemy"):
		var later := after.unit_by_uid(ally.uid)
		if later == null or not later.is_on_board():
			continue
		var old_distance := _nearest_player_distance(before, ally)
		# 有正常接敌通路时，单纯缩短路线或打掉附近障碍不构成施法理由。
		if old_distance < (1 << 30):
			continue
		var new_distance := _nearest_player_distance(after, later)
		if new_distance < (1 << 30):
			score += 36 if ally.uid == actor_uid else 48
			continue
		if damaged_cells.is_empty():
			continue
		# 只奖励打通后确实接通玩家的障碍，保留分两次拆岩障的能力。
		if opened == null:
			opened = after.clone()
			for cell in damaged_cells:
				if opened.obstacle_durability.has(cell):
					opened.damage_obstacle(cell, int(opened.obstacle_durability[cell]))
		var opened_ally := opened.unit_by_uid(ally.uid)
		if _nearest_player_distance(opened, opened_ally) < (1 << 30):
			score += 12
	return mini(score, 72)


static func _nearest_player_distance(state: BattleState, unit: CombatUnit) -> int:
	var distance := 1 << 30
	for target in state.alive_units("player"):
		distance = mini(distance, PathFinder.path_distance(state, unit.cell, target.cell, unit.element, unit.has_buff("flight")))
	return distance


static func _harms_own_nest(before: BattleState, after: BattleState) -> bool:
	for current in before.all_nests():
		if not bool(current.get("alive", false)):
			continue
		var later := after.nest_at_cell(current["cell"])
		if later.is_empty() or not bool(later.get("alive", false)) or int(later.get("hp", 0)) < int(current.get("hp", 0)):
			return true
	return false


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
		"unit_pair":
			var ids: Array = entry.get("units", []).duplicate()
			ids.sort()
			return "%s|pair|%08d,%08d" % [skill_id, int(ids[0]), int(ids[1])]
		"unit":
			return "%s|unit|%08d" % [skill_id, int(entry["unit"])]
		"dir":
			var dir: Vector2i = entry["dir"]
			return "%s|dir|%d,%d" % [skill_id, dir.x, dir.y]
		_:
			var cell: Vector2i = entry["cell"]
			return "%s|cell|%03d,%03d" % [skill_id, cell.y, cell.x]


static func _approach_action(work: BattleState, unit: CombatUnit, positions: Array, paths: Dictionary, free_paths: Dictionary) -> Dictionary:
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
	var pursuit_uid := -1
	var pursuit_distance := 1 << 30
	for target in targets:
		var distance := PathFinder.path_distance(work, best_cell, target.cell, unit.element, unit.has_buff("flight"))
		if distance < pursuit_distance:
			pursuit_distance = distance
			pursuit_uid = target.uid
	return {"uid": unit.uid, "move_path": path, "free_terrain_move": bool(free_paths.get(best_cell, false)), "skill": {}, "pursuit_uid": pursuit_uid}


static func _execute_on(work: BattleState, action: Dictionary) -> void:
	var unit := work.unit_by_uid(int(action["uid"]))
	if unit == null or not unit.is_alive():
		return
	for cell in action.get("move_path", []):
		unit.last_move_direction = cell - unit.cell
		unit.cell = cell
	if not action.get("move_path", []).is_empty():
		unit.moved = unit.moved if bool(action.get("free_terrain_move", false)) else true
		work.apply_vine_on_landing(unit)
	if action.has("guard"):
		work.begin_nest_guard(unit, action["guard"])
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty():
		var skill_used_before := unit.skill_used
		var result := SkillResolver.apply(work, unit, String(skill["id"]), skill["target"], false)
		if bool(result.get("ok", false)):
			if skill_used_before and unit.extra_casts > 0:
				unit.extra_casts -= 1
			else:
				unit.skill_used = true
	unit.fresh_spawn = false


static func describe(action: Dictionary, state: BattleState) -> String:
	var unit := state.unit_by_uid(int(action.get("uid", -1)))
	var name := unit.display_name if unit != null else "?"
	var parts: Array = []
	if bool(action.get("nest_spawn_repair", false)):
		parts.append("疏通巢穴出生格")
	if action.has("guard"):
		parts.append("守护巢穴（消耗技能机会）")
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
		if String(entry.get("type", "")) == "unit_pair":
			var names: Array = []
			for uid in entry["units"]:
				var target := state.unit_by_uid(int(uid))
				if target != null:
					names.append(target.display_name)
			parts.append("施放%s → %s" % [SkillDB.name_of(String(skill["id"])), "、".join(names)])
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
