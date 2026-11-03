class_name SkillResolver
extends RefCounted

## 技能瞄准与结算。预览通过「在克隆状态上真实执行」得到，
## 保证预览、结算与 AI 判断使用同一套规则。


static func targets(state: BattleState, unit: CombatUnit, skill_id: String) -> Array:
	var def := SkillDB.get_def(skill_id)
	if state.recovery_skill_blocked(skill_id):
		return []
	var entries: Array = []
	if def.is_empty() or unit == null or not unit.is_alive() or unit.channel_lock_round == state.round:
		return entries
	if bool(def.get("channel", false)) and not state.can_begin_channel(unit):
		return entries
	if skill_id == "tree_man" and state.active_summon(unit.uid) != null:
		return entries
	if state.steam_cells.has(unit.cell) and not state.is_free_exploration():
		return entries
	if not unit.can_use_in_battle(skill_id):
		return entries
	match String(def.get("kind", "")):
		"ray":
			if skill_id == "ice_breath":
				_ice_breath_targets(state, unit, entries)
			else:
				_ray_targets(state, unit, skill_id, def, entries)
		"charge":
			for dir in GridSpec.DIRS4:
				for distance in [1, 2]:
					var cell: Vector2i = unit.cell + dir * distance
					if GridSpec.is_inside(cell):
						entries.append({"type": "cell", "cell": cell})
		"unit":
			_unit_targets(state, unit, skill_id, def, entries)
			if skill_id == "volt_replace":
				_volt_empty_targets(state, unit, def, entries)
		"electric_laser":
			_electromagnetic_laser_targets(state, unit, def, entries)
		"cell":
			_cell_targets(state, unit, skill_id, def, entries)
		"teleport":
			if skill_id == "flame_rush":
				_flame_rush_targets(state, unit, entries)
			else:
				_teleport_targets(state, unit, def, entries)
		"direction":
			for dir in GridSpec.DIRS4:
				if skill_id == "tsunami" and tsunami_cells(unit.cell, dir).is_empty():
					continue
				if skill_id == "earth_shake" and front_area_cells(unit.cell, dir, 3).is_empty():
					continue
				if skill_id == "windfire_breath" and half_circle_cells(unit.cell, dir).is_empty():
					continue
				if skill_id == "wild_vines" and wild_vines_cells(state, unit, dir).is_empty():
					continue
				if skill_id == "electric_spark" and electric_spark_cells(state, unit, dir).is_empty():
					continue
				entries.append({"type": "dir", "dir": dir, "cell": unit.cell + dir})
		"self":
			if skill_id == "magnet_pull":
				if magnet_pull_target(state, unit) != null:
					entries.append({"type": "cell", "cell": unit.cell})
			elif skill_id == "glare":
				if not glare_candidates(state, unit).is_empty():
					entries.append({"type": "cell", "cell": unit.cell})
			elif skill_id == "electric_resonance":
				if not resonance_candidates(state, unit).is_empty():
					entries.append({"type": "cell", "cell": unit.cell})
			elif skill_id == "rooted_grass":
				if not rooted_grass_cells(state, unit).is_empty():
					entries.append({"type": "cell", "cell": unit.cell})
			elif skill_id == "burn_out" and state.alive_units("enemy" if unit.side == "player" else "player").is_empty():
				return entries
			elif skill_id != "lightning" or not state.alive_units("enemy" if unit.side == "player" else "player").is_empty() or (unit.side == "player" and state.has_live_nests()):
				entries.append({"type": "cell", "cell": unit.cell})
	return entries


static func _range_bonus(state: BattleState, unit: CombatUnit, skill_id: String) -> int:
	## 潮汐：我方水系技能射程 +1（环境卡增益只对我方生效）。
	if unit == null or unit.side != "player":
		return 0
	if SkillDB.element_of(skill_id) == "water" and int(state.effects.get("water_range", 0)) > 0:
		return int(state.effects["water_range"])
	return 0


static func _ray_targets(state: BattleState, unit: CombatUnit, skill_id: String, def: Dictionary, entries: Array) -> void:
	var min_range := int(def.get("min_range", 1))
	var max_range := int(def.get("max_range", 8)) + _range_bonus(state, unit, skill_id)
	if skill_id == "freeze_ray":
		max_range += int(unit.upgrades.get("freeze_ray_range", 0))
	for dir in GridSpec.DIRS4:
		for distance in range(1, max_range + 1):
			var cell: Vector2i = unit.cell + dir * distance
			if not GridSpec.is_inside(cell):
				break
			if distance >= min_range:
				entries.append({"type": "cell", "cell": cell})
			if state.is_blocking_ray(cell) and skill_id != "fire_burst":
				break


static func _ice_breath_targets(state: BattleState, unit: CombatUnit, entries: Array) -> void:
	for dir in GridSpec.DIRS4:
		for distance in range(1, 7):
			var cell: Vector2i = unit.cell + dir * distance
			if not GridSpec.is_inside(cell):
				break
			if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE or (state.is_nest_cell(cell) and state.unit_at(cell) == null):
				break
			var target := state.unit_at(cell)
			if target == null:
				continue
			if target.side != unit.side:
				entries.append({"type": "cell", "cell": cell})
			break


static func _unit_targets(state: BattleState, unit: CombatUnit, skill_id: String, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 1))
	var allows_self := skill_id in ["first_aid", "antidote"]
	if SkillDB.is_placeholder(skill_id):
		skill_range += int(unit.upgrades.get(skill_id + "_range", 0))
	if unit.side == "player" and skill_id == "drain":
		skill_range += int(unit.upgrades.get("drain_range", 0))
	if skill_id == "rock_break":
		skill_range += int(unit.upgrades.get("rock_break_range", 0))
	for other in state.units:
		if not other.is_alive() or (other.uid == unit.uid and not allows_self):
			continue
		var distance := GridSpec.manhattan(unit.cell, other.cell)
		if skill_id == "lightning" and other.side == unit.side:
			continue
		if skill_id == "volt_replace" and _player_forbidden_landing(state, unit, other.cell):
			continue
		if skill_id == "rock_push":
			if distance != 1:
				continue
		elif skill_id == "mountain_chain":
			if distance != 1 or other.side == unit.side:
				continue
			var offset: Vector2i = other.cell - unit.cell
			if offset.x != 0 and offset.y != 0:
				continue
		elif skill_id == "rock_blast":
			if distance != int(def.get("range", 3)) or other.side == unit.side:
				continue
			if not _orthogonally_aligned(unit.cell, other.cell):
				continue
			if not _rock_blast_path_clear(state, unit.cell, other.cell):
				continue
		elif skill_id == "water_drop_stone":
			if not _water_drop_reaches(state, unit, other):
				continue
		elif skill_id == "imprint":
			if distance <= 0 or distance > skill_range or not _can_imprint_source(state, unit, other):
				continue
		elif distance > skill_range:
			continue
		if skill_id in ["herbal_heal", "double_cast", "first_aid", "antidote"]:
			if other.side != unit.side:
				continue
			if skill_id == "double_cast" and other.channel_lock_round == state.round:
				continue
			if skill_id == "first_aid" and other.hp >= other.max_hp:
				continue
			if skill_id == "antidote" and other.hp >= other.max_hp and not state.has_removable_debuff(other):
				continue
		elif skill_id != "volt_replace" and skill_id != "imprint" and other.side == unit.side:
			continue
		if _concealed(state, skill_id, distance, other):
			continue
		entries.append({"type": "unit", "unit": other.uid, "cell": other.cell})
	if skill_id == "double_cast" and int(unit.upgrades.get("double_cast_range", 0)) > 0 and entries.size() >= 2:
		var adjacent_allies := entries.duplicate()
		entries.clear()
		for first_index in range(adjacent_allies.size() - 1):
			for second_index in range(first_index + 1, adjacent_allies.size()):
				entries.append({"type": "unit_pair", "units": [adjacent_allies[first_index]["unit"], adjacent_allies[second_index]["unit"]], "cell": adjacent_allies[second_index]["cell"]})
	if (
		(int(def.get("damage", 0)) > 0 or skill_id == "rock_smash" or skill_id == "rock_break")
		and skill_id not in ["furnace_fist", "combustion", "leaf_wind", "mountain_chain", "rock_blast", "water_drop_stone"]
	):
		for cell in GridSpec.all_cells():
			var distance := GridSpec.manhattan(unit.cell, cell)
			if distance == 0 or distance > skill_range:
				continue
			if state.obstacle_durability.has(cell):
				entries.append({"type": "cell", "cell": cell})
			elif state.is_nest_cell(cell) and state.unit_at(cell) == null:
				entries.append({"type": "nest", "cell": cell})
			elif skill_id == "rock_break" and unit.has_buff("rock_break") and state.terrain_at(cell) == TerrainDB.FRAGILE:
				entries.append({"type": "cell", "cell": cell})


static func _orthogonally_aligned(from: Vector2i, to: Vector2i) -> bool:
	return from.x == to.x or from.y == to.y


static func _rock_blast_path_clear(state: BattleState, from: Vector2i, to: Vector2i) -> bool:
	var distance := GridSpec.manhattan(from, to)
	if distance <= 1:
		return true
	var dir := _axis_dir(from, to)
	for step in range(1, distance):
		if state.is_blocking_ray(from + dir * step):
			return false
	return true


static func water_drop_obstacle_route(state: BattleState, caster: CombatUnit, target: CombatUnit) -> Array:
	var route: Array = []
	if caster == null or target == null or not target.is_alive():
		return route
	var distance := GridSpec.manhattan(caster.cell, target.cell)
	if distance <= 1 or not _orthogonally_aligned(caster.cell, target.cell):
		return route
	var dir := _axis_dir(caster.cell, target.cell)
	for step in range(1, distance):
		var cell := caster.cell + dir * step
		if state.terrain_at(cell) != TerrainDB.OBSTACLE:
			return []
		route.append(cell)
	return route


static func _water_drop_reaches(state: BattleState, caster: CombatUnit, target: CombatUnit) -> bool:
	var distance := GridSpec.manhattan(caster.cell, target.cell)
	if distance == 1:
		return true
	if not _orthogonally_aligned(caster.cell, target.cell):
		return false
	var route := water_drop_obstacle_route(state, caster, target)
	return route.size() == distance - 1


static func _can_imprint_source(state: BattleState, caster: CombatUnit, source: CombatUnit) -> bool:
	if source.last_skill_id == "" or not SkillDB.is_copyable(source.last_skill_id):
		return false
	if source.last_skill_upgraded and int(caster.upgrades.get("imprint_upgraded", 0)) <= 0:
		return false
	var replay := _imprint_replay_entry(state, caster, source)
	return not replay.is_empty() and _entry_valid_for_skill(state, caster, source.last_skill_id, replay)


static func _entry_valid_for_skill(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary) -> bool:
	var key := _entry_key(entry)
	for candidate in targets(state, caster, skill_id):
		if _entry_key(candidate) == key:
			return true
	return false


static func _imprint_replay_entry(state: BattleState, caster: CombatUnit, source: CombatUnit) -> Dictionary:
	var copied_id := source.last_skill_id
	if not SkillDB.is_copyable(copied_id):
		return {}
	var copied_kind := SkillDB.kind_of(copied_id)
	if copied_kind == "self":
		return {"type": "cell", "cell": caster.cell}
	var candidates := targets(state, caster, copied_id)
	if candidates.is_empty():
		return {}
	if copied_kind == "unit":
		for candidate in candidates:
			if int(candidate.get("unit", -1)) == source.uid:
				return candidate
			if (candidate.get("units", []) as Array).has(source.uid):
				return candidate
		var original_target := _entry_target_cell(source.last_skill_target, state)
		if source.last_skill_from != Vector2i(-1, -1) and original_target != Vector2i(-1, -1):
			var original_offset: Vector2i = original_target - source.last_skill_from
			var desired: Vector2i = caster.cell + original_offset
			for candidate in candidates:
				if Vector2i(candidate.get("cell", Vector2i(-1, -1))) == desired:
					return candidate
		return {}
	var original_cell := _entry_target_cell(source.last_skill_target, state)
	var original_from := source.last_skill_from
	if original_cell == Vector2i(-1, -1) or original_from == Vector2i(-1, -1):
		return candidates[0]
	var offset: Vector2i = original_cell - original_from
	var dir := Vector2i(signi(offset.x), signi(offset.y))
	if copied_kind == "ray":
		var best: Dictionary = {}
		var best_distance := -1
		for candidate in candidates:
			var cell: Vector2i = candidate.get("cell", Vector2i(-1, -1))
			if _axis_dir(caster.cell, cell) != dir:
				continue
			var distance := GridSpec.manhattan(caster.cell, cell)
			if distance > best_distance:
				best = candidate
				best_distance = distance
		return best
	if copied_kind == "direction":
		for candidate in candidates:
			if Vector2i(candidate.get("dir", Vector2i.ZERO)) == dir:
				return candidate
		return {}
	var desired: Vector2i = caster.cell + offset
	for candidate in candidates:
		if Vector2i(candidate.get("cell", Vector2i(-1, -1))) == desired:
			return candidate
	var nearest: Dictionary = {}
	var nearest_distance := 1 << 30
	for candidate in candidates:
		var cell: Vector2i = candidate.get("cell", Vector2i(-1, -1))
		var distance := GridSpec.manhattan(cell, desired)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


static func _entry_target_cell(entry: Dictionary, state: BattleState) -> Vector2i:
	if entry.has("cell"):
		return entry["cell"]
	if entry.has("unit"):
		var target := state.unit_by_uid(int(entry["unit"]))
		if target != null:
			return target.cell
	return Vector2i(-1, -1)


static func _cell_targets(state: BattleState, unit: CombatUnit, skill_id: String, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 3)) + _range_bonus(state, unit, skill_id)
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if not bool(def.get("global_range", false)) and distance > skill_range:
			continue
		if distance == 0 and (skill_id == "rock_slide" or skill_id == "tree_man"):
			continue
		if skill_id == "skyfire":
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "seed_sow":
			if state.terrain_at(cell) == TerrainDB.PLAIN:
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "rain_dance" or skill_id == "rain_call":
			if _rain_would_change(state, unit, cell):
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "herbal_heal":
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "water_magic_burst":
			if _water_magic_burst_has_enemy(state, unit, cell):
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc" and TerrainDB.is_water_body(state.terrain_at(cell)):
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc" and (state.obstacle_durability.has(cell) or (state.is_nest_cell(cell) and state.unit_at(cell) == null)):
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc":
			var target := state.unit_at(cell)
			if target != null and target.uid != unit.uid:
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "rock_slide":
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "tree_man" and state.unit_at(cell) == null and not state.is_interaction_cell(cell) and TerrainDB.can_stand(state.terrain_at(cell), "grass"):
			if not _player_forbidden_landing(state, unit, cell):
				entries.append({"type": "cell", "cell": cell})


static func _flame_rush_targets(state: BattleState, unit: CombatUnit, entries: Array) -> void:
	for cell in GridSpec.all_cells():
		if cell == unit.cell or not state.burning_cells.has(cell):
			continue
		if state.unit_at(cell) != null or state.is_interaction_cell(cell) or _player_forbidden_landing(state, unit, cell):
			continue
		if not TerrainDB.can_stand(state.terrain_at(cell), unit.element):
			continue
		entries.append({"type": "cell", "cell": cell})


static func _water_magic_burst_has_enemy(state: BattleState, caster: CombatUnit, center: Vector2i) -> bool:
	var enemy_side := "enemy" if caster.side == "player" else "player"
	var cells: Array = [center] + GridSpec.neighbors4(center)
	for cell in cells:
		var target := state.unit_at(cell)
		if target != null and target.side == enemy_side:
			return true
	return false


static func _volt_empty_targets(state: BattleState, unit: CombatUnit, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 2))
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if distance < 1 or distance > skill_range:
			continue
		if state.unit_at(cell) != null or state.is_interaction_cell(cell) or _player_forbidden_landing(state, unit, cell):
			continue
		if TerrainDB.can_stand(state.terrain_at(cell), unit.element):
			entries.append({"type": "cell", "cell": cell})


static func _teleport_targets(state: BattleState, unit: CombatUnit, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 2)) + int(unit.upgrades.get("volt_step_bonus", 0))
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if distance == 0 or distance > skill_range:
			continue
		if state.unit_at(cell) != null or state.is_interaction_cell(cell) or _player_forbidden_landing(state, unit, cell):
			continue
		if not TerrainDB.can_stand(state.terrain_at(cell), unit.element):
			continue
		if not _teleport_path_clear(state, unit.cell, cell, unit.element):
			continue
		entries.append({"type": "cell", "cell": cell})


static func magnet_pull_range(caster: CombatUnit) -> int:
	return 5 + int(caster.upgrades.get("magnet_pull_reach", 0))


static func magnet_pull_target(state: BattleState, caster: CombatUnit) -> CombatUnit:
	if caster == null or not caster.is_alive():
		return null
	var best: CombatUnit = null
	var best_distance := 1 << 30
	for enemy in state.alive_units("enemy" if caster.side == "player" else "player"):
		if enemy.cell.x != caster.cell.x and enemy.cell.y != caster.cell.y:
			continue
		var distance := GridSpec.manhattan(caster.cell, enemy.cell)
		if distance < 2 or distance > magnet_pull_range(caster):
			continue
		if not _electric_line_clear(state, caster.cell, enemy.cell, true):
			continue
		if distance < best_distance or (distance == best_distance and (best == null or enemy.reg_index < best.reg_index)):
			best = enemy
			best_distance = distance
	return best


static func glare_radius(caster: CombatUnit) -> int:
	return 1 + int(caster.upgrades.get("glare_radius", 0))


static func glare_area(caster: CombatUnit) -> Array:
	return support_area(caster.cell, glare_radius(caster), true)


static func glare_candidates(state: BattleState, caster: CombatUnit) -> Array:
	var result: Array = []
	var area := glare_area(caster)
	for enemy in state.alive_units("enemy" if caster.side == "player" else "player"):
		if area.has(enemy.cell) and enemy.paralyzed_ticks <= 0 and not enemy.has_buff("status_immune"):
			result.append(enemy)
	return result


static func resonance_area(caster: CombatUnit) -> Array:
	return support_area(caster.cell, 1, true)


static func resonance_candidates(state: BattleState, caster: CombatUnit) -> Array:
	var result: Array = []
	var area := resonance_area(caster)
	for target in state.alive_units():
		if area.has(target.cell) and (target.shock_ticks > 0 or target.paralyzed_ticks > 0):
			result.append(target)
	return result


static func electric_spark_cells(state: BattleState, caster: CombatUnit, dir: Vector2i) -> Array:
	var cells: Array = []
	var found_enemy := false
	for distance in range(1, 4):
		var cell: Vector2i = caster.cell + dir * distance
		if not GridSpec.is_inside(cell):
			break
		cells.append(cell)
		var target := state.unit_at(cell)
		if target != null and target.side != caster.side:
			found_enemy = true
		if state.is_interaction_cell(cell) or TerrainDB.blocks_move(state.terrain_at(cell)):
			break
	return cells if found_enemy else []


static func _electromagnetic_laser_targets(state: BattleState, caster: CombatUnit, def: Dictionary, entries: Array) -> void:
	var max_range := int(def.get("range", 4))
	for target in state.alive_units("enemy" if caster.side == "player" else "player"):
		if target.cell.x != caster.cell.x and target.cell.y != caster.cell.y:
			continue
		var distance := GridSpec.manhattan(caster.cell, target.cell)
		if distance < 1 or distance > max_range:
			continue
		if not _electric_line_clear(state, caster.cell, target.cell, false):
			continue
		var blocked_by_terrain := not _electric_line_clear(state, caster.cell, target.cell, true)
		if blocked_by_terrain and target.shock_ticks <= 0 and target.paralyzed_ticks <= 0:
			continue
		entries.append({"type": "unit", "unit": target.uid, "cell": target.cell, "pierces_obstacle": blocked_by_terrain})


static func _electric_line_clear(state: BattleState, from_cell: Vector2i, to_cell: Vector2i, include_terrain_blockers: bool) -> bool:
	var distance := GridSpec.manhattan(from_cell, to_cell)
	if distance <= 1:
		return true
	var dir := _axis_dir(from_cell, to_cell)
	for step in range(1, distance):
		var cell: Vector2i = from_cell + dir * step
		if state.unit_at(cell) != null or state.is_interaction_cell(cell):
			return false
		if include_terrain_blockers and TerrainDB.blocks_rays(state.terrain_at(cell)):
			return false
	return true


static func _player_forbidden_landing(state: BattleState, unit: CombatUnit, cell: Vector2i) -> bool:
	return unit.side == "player" and state.is_nest_cell(cell)


static func _concealed(state: BattleState, skill_id: String, distance: int, target: CombatUnit) -> bool:
	## 草丛隐蔽：2 格以外的远程单体技能不能选中。
	if not SkillDB.is_ranged(skill_id) or distance <= 2:
		return false
	if not GridSpec.is_inside(target.cell):
		return false
	return false


static func _rain_would_change(state: BattleState, caster: CombatUnit, center: Vector2i) -> bool:
	var radius := 1 + int(caster.upgrades.get("rain_radius_bonus", 0))
	for cell in GridSpec.all_cells():
		if absi(center.x - cell.x) > radius or absi(center.y - cell.y) > radius:
			continue
		var terrain := state.terrain_at(cell)
		if terrain == TerrainDB.PLAIN or terrain == TerrainDB.GRASS:
			return true
	return false


static func _teleport_path_clear(state: BattleState, from: Vector2i, to: Vector2i, element: String) -> bool:
	if GridSpec.manhattan(from, to) <= 1:
		return true
	var paths: Array = []
	if from.x == to.x or from.y == to.y:
		paths.append([(from + to) / 2])
	else:
		paths.append([Vector2i(to.x, from.y)])
		paths.append([Vector2i(from.x, to.y)])
	for path in paths:
		var clear := true
		for cell in path:
			var terrain := state.terrain_at(cell)
			if TerrainDB.blocks_move(terrain):
				clear = false
				break
			if terrain == TerrainDB.LAVA:
				clear = false
				break
			if terrain == TerrainDB.DEEP and element != "water":
				clear = false
				break
		if clear:
			return true
	return false


# ---------------------------------------------------------------- 执行


static func apply(state: BattleState, caster: CombatUnit, skill_id: String, target_entry: Dictionary, preview: bool) -> Dictionary:
	if state.feedback_enabled:
		state.presentation_started.emit({"kind": "skill", "uid": caster.uid if caster != null else -1, "skill": skill_id, "release": state.is_free_exploration() and bool(SkillDB.get_def(skill_id).get("channel", false)), "target": target_entry.duplicate(true)})
	var result := _apply_rules(state, caster, skill_id, target_entry, preview)
	if state.feedback_enabled:
		state.presentation_finished.emit(result)
	return result


static func _apply_rules(state: BattleState, caster: CombatUnit, skill_id: String, target_entry: Dictionary, preview: bool) -> Dictionary:
	var def := SkillDB.get_def(skill_id)
	if def.is_empty() or caster == null or not caster.is_alive() or caster.channel_lock_round == state.round:
		return {"ok": false}
	if bool(def.get("channel", false)) and not state.can_begin_channel(caster):
		return {"ok": false}
	if state.steam_cells.has(caster.cell) and not state.is_free_exploration():
		return {"ok": false}
	if target_entry.is_empty():
		return {"ok": false}
	if not caster.can_use_in_battle(skill_id):
		return {"ok": false}
	if not _entry_valid(state, caster, skill_id, target_entry):
		return {"ok": false}
	var movement_used_before := caster.moved
	var cast_origin := caster.cell
	var summary := {
		"ok": true,
		"skill_id": skill_id,
		"caster_uid": caster.uid,
		"hits": [],
		"heal": null,
		"self_move": null,
		"self_death": false,
		"terrain_changes": [],
		"obstacles_damaged": [],
		"nest_damaged": null,
		"ray_cells": [],
		"area_cells": [],
		"_nest_covered_cells": state.all_nests().filter(func(n): return state.nest_covered(n["cell"])).map(func(n): return n["cell"]), "_nest_covered": state.nest_covered(), "_nest_hit": false,
		"text": "",
	}
	if not preview:
		_record_skill_use(state, caster, skill_id, target_entry, cast_origin)
	if bool(def.get("channel", false)):
		var cells: Array = []
		if skill_id == "fire_burst" or skill_id == "rock_slide" or skill_id == "herbal_heal":
			cells = [target_entry["cell"]]
		elif skill_id == "lightning":
			for enemy in state.alive_units("enemy" if caster.side == "player" else "player"):
				if not cells.has(enemy.cell):
					cells.append(enemy.cell)
			for current in state.all_nests():
				if caster.side == "player" and bool(current.get("alive", false)) and not state.nest_covered(current["cell"]) and not cells.has(current["cell"]):
					cells.append(current["cell"])
		elif skill_id == "tsunami":
			cells = tsunami_cells(caster.cell, target_entry["dir"])
		elif skill_id == "earth_shake":
			cells = front_area_cells(caster.cell, target_entry["dir"], 3)
		if state.is_free_exploration():
			var instant := _resolve_channel_rules(state, caster, skill_id, cells)
			state.reset_exploration_actions()
			return instant
		if not state.begin_channel(caster, skill_id, cells):
			return {"ok": false}
		for cell in cells:
			if skill_id == "fire_burst":
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var area: Vector2i = cell + Vector2i(dx, dy)
						if GridSpec.is_inside(area):
							summary["area_cells"].append(area)
			else:
				summary["area_cells"].append(cell)
		if skill_id == "herbal_heal":
			summary["area_cells"] = support_area(caster.cell, 2, false)
			summary["text"] = "药草治疗吟唱中：下次本方阶段治疗固定区域内友军。"
		elif skill_id == "earth_shake":
			summary["text"] = "撼地蓄力中：第 %d 回合本方阶段开始影响前方固定的 %d 格。" % [state.round + 1, cells.size()]
		else:
			summary["text"] = "%s 吟唱中：第 %d 回合本方阶段开始命中固定落点。" % [SkillDB.name_of(skill_id), state.round + 1]
		if state.round >= Balance.MAX_ROUNDS:
			summary["text"] += "本场将在结算前结束，此次吟唱不会生效。"
		return summary
	state.emit_feedback(caster, "skill", "%s使用了%s" % [caster.display_name, SkillDB.name_of(skill_id)])
	state.log_event("%s 施放%s。" % [caster.display_name, SkillDB.name_of(skill_id)])
	if String(def.get("kind", "")) == "unit" and String(target_entry.get("type", "")) == "nest":
		_hit_nest(state, caster, target_entry["cell"], summary, int(def.get("damage", 0)))
		summary["text"] = "%s命中巢穴。" % SkillDB.name_of(skill_id)
		if SkillDB.battle_limit_of(skill_id) > 0:
			caster.battle_skill_uses[skill_id] = int(caster.battle_skill_uses.get(skill_id, 0)) + 1
		caster.moved = true
		return summary
	if String(def.get("kind", "")) == "unit" and String(target_entry.get("type", "")) == "cell" and state.obstacle_durability.has(target_entry["cell"]):
		_hit_obstacle(state, target_entry["cell"], summary, caster.side)
		if SkillDB.battle_limit_of(skill_id) > 0:
			caster.battle_skill_uses[skill_id] = int(caster.battle_skill_uses.get(skill_id, 0)) + 1
		caster.moved = true
		return summary
	match String(def.get("kind", "")):
		"ray":
			if skill_id == "fire_burst":
				_apply_fire_burst(state, caster, target_entry, summary)
			elif skill_id == "ice_breath":
				_apply_ice_breath(state, caster, target_entry, summary)
			elif skill_id == "flame_jet" or skill_id == "freeze_ray":
				_apply_line(state, caster, skill_id, target_entry, summary)
			elif skill_id == "fire_seed":
				_apply_fire_seed(state, caster, target_entry, summary)
			else:
				_apply_water_flow(state, caster, target_entry, summary)
		"charge":
			_apply_flame_charge(state, caster, target_entry, summary)
		"unit":
			if SkillDB.is_placeholder(skill_id):
				_apply_placeholder(state, caster, skill_id, target_entry, summary)
			else:
				match skill_id:
					"volt_replace":
						if String(target_entry.get("type", "")) == "cell":
							_apply_volt_replace_empty(state, caster, target_entry, summary)
						else:
							_apply_swap(state, caster, target_entry, summary)
					"double_cast":
						_apply_double_cast(state, caster, target_entry, summary)
					"discharge":
						_apply_discharge(state, caster, target_entry, summary)
					"drain":
						_apply_drain(state, caster, target_entry, summary)
					"ice_shard":
						_apply_ice_shard(state, caster, target_entry, summary)
					"furnace_fist":
						_apply_furnace_fist(state, caster, target_entry, summary)
					"combustion":
						_apply_combustion(state, caster, target_entry, summary)
					"leech_seed":
						_apply_leech_seed(state, caster, target_entry, summary)
					"push", "rock_push":
						_apply_push(state, caster, target_entry, summary)
					"rock_smash", "rock_break":
						_apply_rock_smash(state, caster, skill_id, target_entry, summary)
					"imprint":
						_apply_imprint(state, caster, target_entry, summary, preview)
					"mountain_chain":
						_apply_mountain_chain(state, caster, target_entry, summary)
					"rock_blast":
						_apply_rock_blast(state, caster, target_entry, summary)
					"water_drop_stone":
						_apply_water_drop_stone(state, caster, target_entry, summary)
					"tree_wrath":
						_apply_tree_wrath(state, caster, target_entry, summary)
					"first_aid":
						_apply_first_aid(state, caster, target_entry, summary)
					"antidote":
						_apply_antidote(state, caster, target_entry, summary)
					"leaf_wind":
						_apply_leaf_wind(state, caster, target_entry, summary)
		"cell":
			if skill_id == "skyfire":
				_apply_skyfire(state, caster, target_entry, summary)
			elif skill_id == "water_magic_burst":
				_apply_water_magic_burst(state, caster, target_entry, summary)
			elif skill_id == "electric_arc":
				_apply_electric_arc(state, caster, target_entry, summary)
			elif skill_id == "tree_man":
				_apply_tree_summon(state, caster, target_entry["cell"], summary)
			elif skill_id == "rain_dance" or skill_id == "rain_call":
				_apply_rain_dance(state, caster, target_entry, summary)
			else:
				_apply_seed_sow(state, caster, target_entry, summary)
		"electric_laser":
			_apply_electromagnetic_laser(state, caster, target_entry, summary)
		"teleport":
			if skill_id == "flame_rush":
				_apply_flame_rush(state, caster, target_entry, summary)
			else:
				_apply_volt_step(state, caster, target_entry, summary)
		"direction":
			match skill_id:
				"flame_jet", "wild_vines", "frozen_ground", "windfire_breath", "electric_spark":
					_apply_directional(state, caster, skill_id, target_entry, summary)
				"rock_create":
					_apply_rock_create(state, caster, target_entry, summary)
		"self":
			match skill_id:
				"tailwind": _apply_magnetic(state, caster, summary)
				"magnet_pull": _apply_magnet_pull(state, caster, summary)
				"glare": _apply_glare(state, caster, summary)
				"electric_resonance": _apply_electric_resonance(state, caster, summary)
				"fire_amplify": _apply_fire_amplify(state, caster, summary)
				"ice_glide", "surf": _apply_terrain_travel(state, caster, skill_id, summary)
				"mirror_water_moon": _apply_mirror_water_moon(state, caster, summary)
				"burn_out": _apply_burn_out(state, caster, summary)
				"rooted_grass": _apply_rooted_grass(state, caster, summary)
				"mountain_form": _apply_mountain_form(state, caster, summary)
				_: _apply_heal(state, caster, target_entry, summary)
	_consume_fire_amp_if_used(state, caster, summary)
	if not preview and skill_id == "imprint":
		_record_skill_use(state, caster, skill_id, target_entry, cast_origin)
	if SkillDB.battle_limit_of(skill_id) > 0:
		caster.battle_skill_uses[skill_id] = int(caster.battle_skill_uses.get(skill_id, 0)) + 1
	caster.moved = movement_used_before if skill_id in ["surf", "ice_glide", "mirror_water_moon"] else true
	return summary


static func _record_skill_use(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, from_cell: Vector2i = Vector2i(-1, -1)) -> void:
	var upgrade_id := RunState.upgrade_id_for_skill(skill_id)
	var upgrade_info := RunState.upgrade_info(upgrade_id)
	caster.last_skill_id = skill_id
	caster.last_skill_from = from_cell if from_cell != Vector2i(-1, -1) else caster.cell
	caster.last_skill_target = entry.duplicate(true)
	caster.last_skill_upgraded = (
		not upgrade_info.is_empty()
		and caster.upgrades.has(String(upgrade_info.get("key", "")))
	)


static func _entry_valid(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary) -> bool:
	var key := _entry_key(entry)
	for candidate in targets(state, caster, skill_id):
		if _entry_key(candidate) == key:
			return true
	return false


static func resolve_channel(state: BattleState, caster: CombatUnit, skill_id: String, cells: Array) -> Dictionary:
	if state.feedback_enabled:
		state.presentation_started.emit({"kind": "skill", "uid": caster.uid if caster != null else -1, "skill": skill_id, "release": true, "cells": cells.duplicate()})
	var result := _resolve_channel_rules(state, caster, skill_id, cells)
	if state.feedback_enabled:
		state.presentation_finished.emit(result)
	return result


static func _resolve_channel_rules(state: BattleState, caster: CombatUnit, skill_id: String, cells: Array) -> Dictionary:
	state.emit_feedback(caster, "skill", "%s使用了%s" % [caster.display_name, SkillDB.name_of(skill_id)])
	var summary := {"ok": true, "skill_id": skill_id, "caster_uid": caster.uid, "hits": [],
		"area_cells": [], "ray_cells": [], "terrain_changes": [], "obstacles_damaged": [], "nest_damaged": null, "_nest_covered_cells": state.all_nests().filter(func(n): return state.nest_covered(n["cell"])).map(func(n): return n["cell"]), "_nest_covered": state.nest_covered(), "_nest_hit": false, "text": ""}
	if skill_id == "fire_burst":
		_apply_fire_burst(state, caster, {"cell": cells[0]}, summary)
	elif skill_id == "lightning":
		summary["area_cells"] = cells.duplicate()
		for index in range(cells.size()):
			if state.ended:
				break
			var cell: Vector2i = cells[index]
			_hit_nest(state, caster, cell, summary, SkillDB.damage_of("lightning"))
			if state.obstacle_durability.has(cell):
				_hit_obstacle(state, cell, summary, caster.side)
			var target := state.unit_at(cell)
			if target == null:
				continue
			var hit := _hit_entry(state, caster, "lightning", target, SkillDB.damage_of("lightning"))
			summary["hits"].append(hit)
			if target.is_alive():
				var had_shock: bool = target.shock_ticks > 0
				if state.apply_shock(target, Balance.LIGHTNING_SHOCK_TICKS):
					(hit["statuses"] as Array).append("麻痹" if had_shock else "感电")
				if index == 0 and int(caster.upgrades.get("lightning_first_shock", 0)) > 0:
					if state.apply_shock(target, 1):
						(hit["statuses"] as Array).append("麻痹")
		summary["text"] = "打雷落下：%d 个单位受击。" % summary["hits"].size()
	elif skill_id == "rock_slide":
		summary["area_cells"] = cells.duplicate()
		if state.obstacle_durability.has(cells[0]):
			_hit_obstacle(state, cells[0], summary, caster.side)
		_hit_nest(state, caster, cells[0], summary, SkillDB.damage_of("rock_slide"))
		var target := state.unit_at(cells[0])
		if target != null:
			summary["hits"].append(_hit_entry(state, caster, "rock_slide", target, SkillDB.damage_of("rock_slide")))
		summary["text"] = "岩崩落下：%d 个单位受击。" % summary["hits"].size()
	elif skill_id == "tree_man":
		_apply_tree_summon(state, caster, cells[0], summary) # Legacy pending summons.
	elif skill_id == "herbal_heal":
		_apply_heal(state, caster, {"cell": cells[0]}, summary)
	elif skill_id == "earth_shake":
		_resolve_earth_shake(state, caster, cells, summary)
	elif skill_id == "tsunami":
		summary["area_cells"] = cells.duplicate()
		for cell in cells:
			if state.ended:
				break
			if state.obstacle_durability.has(cell):
				_hit_obstacle(state, cell, summary, caster.side)
			if not TerrainDB.is_water_body(state.terrain_at(cell)):
				continue
			_hit_nest(state, caster, cell, summary, SkillDB.damage_of("tsunami"))
			var target := state.unit_at(cell)
			if target != null and target.side != caster.side:
				summary["hits"].append(_hit_entry(state, caster, "tsunami", target, SkillDB.damage_of("tsunami")))
		summary["text"] = "海啸落下：%d 个水域内敌方单位受击。" % summary["hits"].size()
	_consume_fire_amp_if_used(state, caster, summary)
	return summary


static func _resolve_earth_shake(state: BattleState, caster: CombatUnit, cells: Array, summary: Dictionary) -> void:
	summary["area_cells"] = cells.duplicate()
	var destroyed_obstacles := 0
	for cell in cells:
		if state.ended:
			break
		var target := state.unit_at(cell)
		if target != null and target.side != caster.side:
			summary["hits"].append(_hit_entry(state, caster, "earth_shake", target, SkillDB.damage_of("earth_shake")))
		if state.ended:
			break
		if state.is_nest_cell(cell):
			_hit_nest(state, caster, cell, summary, SkillDB.damage_of("earth_shake"))
			continue
		if state.obstacle_durability.has(cell):
			var durability := int(state.obstacle_durability[cell])
			var destroyed := state.damage_obstacle(cell, durability, caster.side)
			summary["obstacles_damaged"].append({"cell": cell, "damage": durability, "destroyed": destroyed})
			if destroyed:
				destroyed_obstacles += 1
			continue
		var terrain_type := state.terrain_at(cell)
		if terrain_type == TerrainDB.PLAIN:
			state.set_terrain(cell, TerrainDB.FRAGILE)
			summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.PLAIN, "to": TerrainDB.FRAGILE})
		elif terrain_type == TerrainDB.FRAGILE:
			state.set_terrain(cell, TerrainDB.PIT)
			summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.FRAGILE, "to": TerrainDB.PIT})
			var fallen := state.unit_at(cell)
			if fallen != null and not fallen.has_buff("flight"):
				state.kill_unit(fallen, "撼地造成地面塌陷", caster.side, caster.uid)
	summary["text"] = "撼地结算：%d 名敌人受击，摧毁 %d 处障碍，改变 %d 格地形。" % [summary["hits"].size(), destroyed_obstacles, summary["terrain_changes"].size()]


static func tsunami_cells(origin: Vector2i, dir: Vector2i) -> Array:
	var cells: Array = []
	var sideways := Vector2i(-dir.y, dir.x)
	for length in range(1, 6):
		for offset in range(-2, 3):
			var cell: Vector2i = origin + dir * length + sideways * offset
			if GridSpec.is_inside(cell):
				cells.append(cell)
	return cells


static func _consume_fire_amp_if_used(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	for hit in summary.get("hits", []):
		if int(hit.get("damage", 0)) > 0:
			if caster.fire_amp_stacks > 0:
				state.log_event("%s 的火焰增幅 +%d 已用于本次技能。" % [caster.display_name, caster.fire_amp_stacks])
				caster.fire_amp_stacks = 0
			if caster.electric_resonance_bonus > 0:
				state.log_event("%s 的电共鸣蓄伤 +%d 已用于本次技能。" % [caster.display_name, caster.electric_resonance_bonus])
				caster.electric_resonance_bonus = 0
			return


static func _entry_key(entry: Dictionary) -> String:
	if not entry.has("cell"):
		return "invalid"
	match String(entry.get("type", "")):
		"unit":
			return "unit:%d" % int(entry["unit"])
		"unit_pair":
			var ids: Array = entry.get("units", []).duplicate()
			if ids.size() != 2:
				return "invalid"
			ids.sort()
			return "unit_pair:%d,%d" % [int(ids[0]), int(ids[1])]
		"dir":
			var dir: Vector2i = entry["dir"]
			return "dir:%d,%d" % [dir.x, dir.y]
		"nest":
			var nest_cell: Vector2i = entry["cell"]
			return "nest:%d,%d" % [nest_cell.x, nest_cell.y]
		"obstacle":
			var obstacle_cell: Vector2i = entry["cell"]
			return "obstacle:%d,%d" % [obstacle_cell.x, obstacle_cell.y]
		_:
			var cell: Vector2i = entry["cell"]
			return "cell:%d,%d" % [cell.x, cell.y]


static func _hit_obstacle(state: BattleState, cell: Vector2i, summary: Dictionary, source_side: String = "") -> void:
	var before := int(state.obstacle_durability.get(cell, 0))
	if before <= 0:
		return
	var destroyed := state.damage_obstacle(cell, 1, source_side)
	var actual := before - int(state.obstacle_durability.get(cell, 0))
	summary["obstacles_damaged"].append({"cell": cell, "damage": actual, "destroyed": destroyed})
	summary["text"] = "障碍耐久 −%d%s" % [actual, "，障碍被破坏" if destroyed else ""]
	state.log_event("(%d,%d) %s" % [cell.x, cell.y, summary["text"]])


static func _hit_nest(state: BattleState, caster: CombatUnit, cell: Vector2i, summary: Dictionary, amount: int = 1) -> bool:
	if amount <= 0 or not state.is_nest_cell(cell) or (summary.get("_nest_covered_cells", []) as Array).has(cell) or state.nest_covered(cell) or (summary.get("_nest_hit_cells", []) as Array).has(cell):
		return false
	var current := state.nest_at_cell(cell)
	var old_hp := int(current["hp"])
	var destroyed := state.damage_nest(amount, caster.side, cell)
	var actual := old_hp - int(current["hp"])
	if actual > 0:
		summary["_nest_hit"] = true
		if not summary.has("_nest_hit_cells"):
			summary["_nest_hit_cells"] = []
		summary["_nest_hit_cells"].append(cell)
		summary["nest_damaged"] = {"cell": cell, "damage": actual, "destroyed": destroyed}
		if not summary.has("nests_damaged"):
			summary["nests_damaged"] = []
		summary["nests_damaged"].append(summary["nest_damaged"])
	return destroyed


static func _hit_entry(state: BattleState, caster: CombatUnit, skill_id: String, target: CombatUnit, base: int, extra_opts: Dictionary = {}) -> Dictionary:
	var def := SkillDB.get_def(skill_id)
	var hit_element := String(extra_opts.get("element", def.get("element", "")))
	if base > 0:
		if not bool(extra_opts.get("ignore_skill_upgrade", false)):
			base = upgraded_base_damage(caster, skill_id, base)
		base += caster.fire_amp_stacks
		base += caster.electric_resonance_bonus
		if hit_element == "water" and state.mirror_water_travel_active(caster):
			base += Balance.MIRROR_WATER_DAMAGE_BONUS
	var modifier := Elements.modifier(hit_element, target.element) if base > 0 else 0
	var had_burn := target.burn_ticks > 0
	var had_wet := target.slow_ticks > 0
	var opts := {
		"skill_id": skill_id,
		"element": hit_element,
		"skill_direct": true,
		"ranged": SkillDB.is_ranged(skill_id),
		"cause": SkillDB.name_of(skill_id),
		"conductive": skill_id == "electric_arc",
	}
	opts.merge(extra_opts, true)
	var result := state.damage_unit(caster, target, base, opts)
	var relic_statuses: Array = []
	if not had_burn and target.burn_ticks > 0:
		relic_statuses.append("灼烧")
	if not had_wet and target.slow_ticks > 0:
		relic_statuses.append("浸湿")
	return {
		"uid": target.uid,
		"name": target.display_name,
		"cell": target.cell,
		"damage": int(result.get("amount", 0)),
		"modifier": modifier if int(result.get("amount", 0)) > 0 else 0,
		"killed": bool(result.get("killed", false)),
		"statuses": relic_statuses,
		"relic_healed": int(result.get("relic_healed", 0)),
		"mirror_immune": bool(result.get("mirror_immune", false)),
		"push": null,
	}


static func upgraded_base_damage(caster: CombatUnit, skill_id: String, base: int) -> int:
	if base <= 0:
		return base
	if skill_id == "tree_wrath":
		base += caster.summon_power_bonus
	var upgrade_info := RunState.upgrade_info(RunState.upgrade_id_for_skill(skill_id))
	return base + int(upgrade_info.get("damage_bonus", 0)) if not upgrade_info.is_empty() and caster.upgrades.has(String(upgrade_info.get("key", ""))) else base


static func _apply_placeholder(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, skill_id, target, SkillDB.damage_of(skill_id))
	summary["hits"].append(hit)
	summary["text"] = "%s命中%s：%d伤害。" % [SkillDB.name_of(skill_id), target.display_name, int(hit["damage"])]


static func _apply_fire_seed(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target_cell: Vector2i = entry["cell"]
	var dir := _axis_dir(caster.cell, target_cell)
	var distance := GridSpec.manhattan(caster.cell, target_cell)
	for step in range(1, distance + 1):
		summary["ray_cells"].append(caster.cell + dir * step)
	var hit_unit: CombatUnit = null
	var hit_cell := target_cell
	for step in range(1, distance + 1):
		var cell: Vector2i = caster.cell + dir * step
		var occupant := state.unit_at(cell)
		if occupant != null:
			hit_unit = occupant
			hit_cell = cell
			break
		if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE or state.is_nest_cell(cell):
			hit_cell = cell
			break
	if hit_unit != null:
		var hit := _hit_entry(state, caster, "fire_seed", hit_unit, int(SkillDB.get_def("fire_seed").get("damage", 2)))
		if hit_unit.is_alive():
			state.apply_burn(hit_unit, caster)
			(hit["statuses"] as Array).append("灼烧")
		summary["hits"].append(hit)
		summary["text"] = "火种命中 %s：%d 伤害%s" % [hit["name"], hit["damage"], "，附加灼烧" if hit_unit.is_alive() else "，直接淘汰"]
	else:
		if state.obstacle_durability.has(hit_cell):
			_hit_obstacle(state, hit_cell, summary, caster.side)
		elif state.is_nest_cell(hit_cell):
			_hit_nest(state, caster, hit_cell, summary, 2)
		var splash_cells := GridSpec.neighbors4(hit_cell)
		for cell in splash_cells:
			_hit_nest(state, caster, cell, summary, int(SkillDB.get_def("fire_seed").get("splash_damage", 0)))
			summary["area_cells"].append(cell)
			var occupant := state.unit_at(cell)
			if occupant == null:
				continue
			var hit := _hit_entry(state, caster, "fire_seed", occupant, int(SkillDB.get_def("fire_seed").get("splash_damage", 15)))
			summary["hits"].append(hit)
		summary["text"] = "火种打空，终点格相邻 4 格各受 %d 基础伤害" % int(SkillDB.get_def("fire_seed").get("splash_damage", 0))
		if not summary["hits"].is_empty():
			var names: Array = []
			for hit in summary["hits"]:
				names.append(hit["name"])
			summary["text"] += "（%s）" % ", ".join(names)


static func _apply_water_flow(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target_cell: Vector2i = entry["cell"]
	var dir := _axis_dir(caster.cell, target_cell)
	var distance := GridSpec.manhattan(caster.cell, target_cell)
	for step in range(1, distance + 1):
		summary["ray_cells"].append(caster.cell + dir * step)
	var hit_unit: CombatUnit = null
	var hit_object := ""
	var hit_cell := target_cell
	for step in range(1, distance + 1):
		var cell: Vector2i = caster.cell + dir * step
		var occupant := state.unit_at(cell)
		if occupant != null:
			hit_unit = occupant
			hit_cell = cell
			break
		if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE:
			hit_object = "obstacle"
			hit_cell = cell
			break
		if state.is_nest_cell(cell):
			hit_object = "nest"
			hit_cell = cell
			break
	if hit_unit != null:
		var hit := _hit_entry(state, caster, "water_flow", hit_unit, int(SkillDB.get_def("water_flow").get("damage", 1)))
		if hit_unit.is_alive():
			state.apply_slow(hit_unit)
			(hit["statuses"] as Array).append("减速")
			var push_distance := 1 + int(caster.upgrades.get("water_flow_push", 0)) + (1 if caster.has_buff("water_flow") else 0)
			var push_result := PushResolver.push(state, hit_unit, dir, push_distance, 0, "水炮击退", caster.side, caster.uid, "water_flow")
			hit["push"] = push_result
		summary["hits"].append(hit)
		summary["text"] = "水炮命中 %s：%d 伤害，击退并减速" % [hit["name"], hit["damage"]]
	elif hit_object == "obstacle":
		_hit_obstacle(state, hit_cell, summary, caster.side)
		var prev: Vector2i = hit_cell - dir
		if _convert_to_water(state, prev, summary):
			summary["text"] = "水炮击中障碍，在前方生成水面"
		else:
			summary["text"] = "水炮击中障碍"
	elif hit_object == "nest":
		var hit_nest: Dictionary = state.nest_at_cell(hit_cell)
		var old_hp := int(hit_nest["hp"])
		_hit_nest(state, caster, hit_cell, summary, 1)
		summary["text"] = "水炮击中巢穴，造成 %d 点耐久伤害" % (old_hp - int(hit_nest["hp"]))
	else:
		state.damage_reward_at(hit_cell)
		if _convert_to_water(state, target_cell, summary):
			summary["text"] = "水炮在目标格生成水面"
		else:
			summary["text"] = "水炮命中空地，但该格无法生成水面"


static func _convert_to_water(state: BattleState, cell: Vector2i, summary: Dictionary) -> bool:
	if not GridSpec.is_inside(cell):
		return false
	var terrain := state.terrain_at(cell)
	if terrain != TerrainDB.PLAIN and terrain != TerrainDB.GRASS and terrain != TerrainDB.VINES and terrain != TerrainDB.FRAGILE:
		return false
	state.set_terrain(cell, TerrainDB.WATER)
	summary["terrain_changes"].append({"cell": cell, "from": terrain, "to": TerrainDB.WATER})
	state.log_event("(%d,%d) 变为水面。" % [cell.x, cell.y])
	var occupant := state.unit_at(cell)
	if occupant != null and not occupant.has_buff("flight") and occupant.burn_ticks > 0:
		occupant.burn_ticks = 0
		state.log_event("%s 的灼烧被水熄灭。" % occupant.display_name)
	return true


static func _apply_leech_seed(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	target.parasite_source_uid = caster.uid
	target.parasite_source_side = caster.side
	summary["area_cells"].append(target.cell)
	summary["text"] = "%s 被寄生；每次整轮结算失去 %d HP，受到其他伤害时解除。" % [target.display_name, Balance.PARASITE_DAMAGE + int(caster.upgrades.get("leech_seed_tick_bonus", 0))]
	state.log_event(summary["text"])


static func _apply_fire_amplify(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var absorbed := 0
	for cell in state.burning_cells.keys().duplicate():
		if GridSpec.manhattan(caster.cell, cell) > 2:
			continue
		state.burning_cells.erase(cell)
		state.burning_origin.erase(cell)
		state.burning_forced.erase(cell)
		state.burning_sources.erase(cell)
		summary["area_cells"].append(cell)
		absorbed += 1
	caster.fire_amp_stacks += absorbed * int(caster.upgrades.get("fire_amplify_power", Balance.SKILL_DAMAGE_UPGRADE))
	summary["text"] = "火焰增幅熄灭 %d 格火焰，当前蓄积 +%d 直伤。" % [absorbed, caster.fire_amp_stacks]
	state.log_event(summary["text"])


static func _apply_terrain_travel(state: BattleState, caster: CombatUnit, skill_id: String, summary: Dictionary) -> void:
	if skill_id == "ice_glide":
		caster.ice_glide_until_round = state.round + 2 + int(caster.upgrades.get("ice_glide_duration", 0))
	else:
		caster.surf_until_round = state.round + 2 + int(caster.upgrades.get("surf_duration", 0))
	summary["text"] = "%s 获得%s：本回合及后两回合沿连通%s移动不消耗普通移动机会，可重复移动并越过敌方单位。" % [caster.display_name, SkillDB.name_of(skill_id), "冰面" if skill_id == "ice_glide" else "水域"]
	state.log_event(summary["text"])


static func _apply_mirror_water_moon(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var duration := Balance.MIRROR_WATER_MOON_ROUNDS + int(caster.upgrades.get("mirror_water_moon_duration", 0))
	caster.mirror_until_round = state.round + duration - 1
	var applied := 0
	for target in state.alive_units("enemy" if caster.side == "player" else "player"):
		summary["area_cells"].append(target.cell)
		if state.apply_wet(target, 1):
			applied += 1
	summary["text"] = "镜花水月：持续 %d 回合，水伤 +%d，可跃迁至任意水格；%d 名敌人浸湿一回合。" % [duration, Balance.MIRROR_WATER_DAMAGE_BONUS, applied]
	state.log_event(summary["text"])


static func _apply_burn_out(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var sacrifice_damage := ceili(float(caster.max_hp) * 0.5)
	for target in state.alive_units("enemy" if caster.side == "player" else "player"):
		if state.ended:
			break
		var hit := _hit_entry(state, caster, "burn_out", target, sacrifice_damage)
		if target.is_alive() and state.apply_burn(target, caster):
			(hit["statuses"] as Array).append("灼烧")
		summary["hits"].append(hit)
	var hp_lost := mini(caster.hp, sacrifice_damage)
	caster.hp -= hp_lost
	summary["self_damage"] = hp_lost
	state.emit_feedback(caster, "damage", "-%d" % hp_lost, hp_lost)
	state.log_event("%s 为燃尽献祭 %d HP。" % [caster.display_name, hp_lost])
	if caster.hp <= 0:
		caster.hp = 0
		summary["self_death"] = true
		state.kill_unit(caster, "燃尽反噬", caster.side, caster.uid)
	summary["text"] = "燃尽命中 %d 名敌人；%s损失 %d HP%s。" % [summary["hits"].size(), caster.display_name, hp_lost, "并倒下" if bool(summary["self_death"]) else ""]


static func _apply_flame_charge(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	var dir := _axis_dir(caster.cell, dest)
	var impact_damage := SkillDB.damage_of("flame_charge") + (Balance.SKILL_DAMAGE_UPGRADE if caster.has_buff("flame_charge") or int(caster.upgrades.get("flame_charge_damage", 0)) > 0 else 0)
	for step in range(1, 3):
		var next: Vector2i = caster.cell + dir
		if not GridSpec.is_inside(next):
			break
		summary["ray_cells"].append(next)
		var occupant := state.unit_at(next)
		if occupant != null:
			var hit := _hit_entry(state, caster, "flame_charge", occupant, impact_damage)
			if occupant.is_alive():
				hit["push"] = PushResolver.push(state, occupant, dir, 1, 0, "闪焰冲锋", caster.side, caster.uid, "flame_charge")
			summary["hits"].append(hit)
			var outcome := ""
			if hit["push"] != null:
				if bool(hit["push"].get("death", false)):
					outcome = "，被推入致死地形"
				elif bool(hit["push"].get("moved", false)):
					outcome = "，击退 1 格"
				else:
					outcome = "，击退受阻"
			summary["text"] = "闪焰冲锋撞击 %s：%d 伤害%s。" % [hit["name"], hit["damage"], outcome]
			break
		if state.is_interaction_cell(next):
			summary["text"] = "设施阻挡了冲锋。"
			break
		if state.is_nest_cell(next):
			var hit_nest: Dictionary = state.nest_at_cell(next)
			var old_hp := int(hit_nest["hp"])
			var destroyed := _hit_nest(state, caster, next, summary, 1 + (1 if caster.has_buff("flame_charge") or int(caster.upgrades.get("flame_charge_damage", 0)) > 0 else 0))
			var actual := old_hp - int(hit_nest["hp"])
			summary["nest_damaged"] = {"damage": actual, "destroyed": destroyed}
			summary["text"] = "闪焰冲锋撞击巢穴：耐久 −%d。" % actual
			break
		if TerrainDB.blocks_move(state.terrain_at(next)):
			var obstacle_name := TerrainDB.name_of(state.terrain_at(next))
			var old_hp := int(state.obstacle_durability.get(next, 0))
			var destroyed := state.damage_obstacle(next, 1 + (1 if caster.has_buff("flame_charge") or int(caster.upgrades.get("flame_charge_damage", 0)) > 0 else 0), caster.side)
			var actual := old_hp - int(state.obstacle_durability.get(next, 0))
			summary["obstacles_damaged"].append({"cell": next, "damage": actual, "destroyed": destroyed})
			summary["text"] = "闪焰冲锋撞击%s：耐久 −%d。" % [obstacle_name, actual]
			break
		caster.cell = next
		caster.last_move_direction = dir
		summary["self_move"] = next
		var terrain := state.terrain_at(next)
		if not caster.has_buff("flight") and (terrain == TerrainDB.WATER or terrain == TerrainDB.DEEP):
			caster.burn_ticks = 0
		if TerrainDB.is_lethal(terrain) and not caster.has_buff("flight"):
			summary["self_death"] = true
			state.kill_unit(caster, "闪焰冲锋落入" + TerrainDB.name_of(terrain), caster.side, caster.uid)
			summary["text"] = "闪焰冲锋冲入%s，倒下（濒死）。" % TerrainDB.name_of(terrain)
			break
	if caster.is_alive() and summary["self_move"] != null:
		state.apply_vine_on_landing(caster)
		state.try_pickup_fruit(caster)
	if summary["text"] == "":
		summary["text"] = "闪焰冲锋前进到 (%d,%d)。" % [caster.cell.x, caster.cell.y]


static func _apply_discharge(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, "discharge", target, int(SkillDB.get_def("discharge").get("damage", 2)))
	if target.is_alive():
		state.apply_root(target)
		(hit["statuses"] as Array).append("定身")
	summary["hits"].append(hit)
	summary["text"] = "放电命中 %s：%d 伤害%s" % [hit["name"], hit["damage"], "，附加定身" if target.is_alive() else "，直接淘汰"]


static func _apply_volt_step(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	if _player_forbidden_landing(state, caster, dest):
		return
	caster.cell = dest
	state.apply_vine_on_landing(caster)
	summary["self_move"] = dest
	var terrain := state.terrain_at(dest)
	if terrain == TerrainDB.WATER or terrain == TerrainDB.DEEP:
		caster.burn_ticks = 0
	state.try_pickup_fruit(caster)
	summary["text"] = "电光步瞬移到 (%d,%d)" % [dest.x, dest.y]


static func _apply_flame_rush(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	if _player_forbidden_landing(state, caster, dest):
		return
	var origin := caster.cell
	caster.cell = dest
	caster.last_move_direction = dest - origin
	summary["self_move"] = dest
	state.apply_vine_on_landing(caster)
	if TerrainDB.is_water_body(state.terrain_at(dest)):
		state.clear_burn(caster)
	state.try_pickup_fruit(caster)
	var affected: Array = GridSpec.neighbors8(dest)
	for target in state.alive_units("enemy" if caster.side == "player" else "player"):
		if maxi(absi(target.cell.x - dest.x), absi(target.cell.y - dest.y)) > 1:
			continue
		summary["hits"].append(_hit_entry(state, caster, "flame_rush", target, SkillDB.damage_of("flame_rush")))
	summary["area_cells"] = affected
	summary["text"] = "炎袭跃迁至 (%d,%d)，命中 %d 名敌人。" % [dest.x, dest.y, summary["hits"].size()]


static func _apply_seed_sow(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var cell: Vector2i = entry["cell"]
	var from := state.terrain_at(cell)
	state.set_terrain(cell, TerrainDB.GRASS)
	summary["terrain_changes"].append({"cell": cell, "from": from, "to": TerrainDB.GRASS})
	var occupant := state.unit_at(cell)
	if occupant != null:
		summary["text"] = "播种：%s 脚下成荫" % occupant.display_name
	else:
		summary["text"] = "播种：(%d,%d) 生成草丛" % [cell.x, cell.y]
	state.log_event(summary["text"] + "。")


static func _apply_drain(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, "drain", target, int(SkillDB.get_def("drain").get("damage", 1)))
	summary["hits"].append(hit)
	var healed := mini(caster.max_hp, caster.hp + Balance.DRAIN_HEAL)
	if healed > caster.hp:
		summary["heal"] = {"uid": caster.uid, "amount": healed - caster.hp}
		state.log_event("%s 回复 %d 生命。" % [caster.display_name, healed - caster.hp])
		state.feedback_heal(caster, healed - caster.hp)
		caster.hp = healed
	summary["text"] = "吸取：对 %s 造成 %d 伤害，自身回复 %d" % [hit["name"], hit["damage"], int(summary["heal"]["amount"]) if summary["heal"] != null else 0]


static func _apply_ice_shard(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var bonus := int(caster.upgrades.get("ice_shard_damage", 0))
	var hit := _hit_entry(state, caster, "ice_shard", target, SkillDB.damage_of("ice_shard") + bonus)
	summary["hits"].append(hit)
	summary["text"] = "冰锥命中 %s：%d 伤害。" % [hit["name"], hit["damage"]]


static func _apply_furnace_fist(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var had_burn := target.burn_ticks > 0
	var hit := _hit_entry(state, caster, "furnace_fist", target, SkillDB.damage_of("furnace_fist"))
	summary["hits"].append(hit)
	if had_burn:
		state.clear_burn(target)
		(hit["statuses"] as Array).append("清除灼烧")
	var healing := 5 + int(caster.upgrades.get("furnace_fist_healing", 0)) + (5 if had_burn else 0)
	var healed := mini(caster.max_hp - caster.hp, healing)
	if healed > 0:
		caster.hp += healed
		summary["heal"] = {"uid": caster.uid, "amount": healed}
		state.feedback_heal(caster, healed)
		state.log_event("%s 通过炎炉拳回复 %d HP。" % [caster.display_name, healed])
	summary["text"] = "炎炉拳命中 %s：%d 伤害，自身回复 %d%s。" % [target.display_name, int(hit["damage"]), healed, "并清除灼烧" if had_burn else ""]


static func _apply_combustion(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var had_burn := target.burn_ticks > 0
	var base_damage := 16 if had_burn else 8
	var hit := _hit_entry(state, caster, "combustion", target, base_damage)
	summary["hits"].append(hit)
	if had_burn:
		state.clear_burn(target)
		(hit["statuses"] as Array).append("清除灼烧")
	summary["text"] = "爆燃命中 %s：%d 伤害%s。" % [target.display_name, int(hit["damage"]), "，消耗灼烧并触发爆燃" if had_burn else ""]


static func front_area_cells(origin: Vector2i, direction: Vector2i, length: int) -> Array:
	var cells: Array = []
	var sideways := Vector2i(-direction.y, direction.x)
	for depth in range(1, length + 1):
		for offset in [-1, 0, 1]:
			var cell: Vector2i = origin + direction * depth + sideways * offset
			if GridSpec.is_inside(cell):
				cells.append(cell)
	return cells


static func half_circle_cells(origin: Vector2i, direction: Vector2i) -> Array:
	var cells: Array = []
	var sideways := Vector2i(-direction.y, direction.x)
	for depth in range(1, 3):
		var half_width := depth
		for offset in range(-half_width, half_width + 1):
			var cell: Vector2i = origin + direction * depth + sideways * offset
			if GridSpec.is_inside(cell):
				cells.append(cell)
	return cells


static func wild_vines_reach(caster: CombatUnit) -> int:
	return 2 + int(caster.upgrades.get("wild_vines_reach", 0))


static func wild_vines_cells(state: BattleState, caster: CombatUnit, direction: Vector2i) -> Array:
	var cells: Array = []
	for distance in range(1, wild_vines_reach(caster) + 1):
		var cell: Vector2i = caster.cell + direction * distance
		if not GridSpec.is_inside(cell) or TerrainDB.blocks_move(state.terrain_at(cell)) or state.is_nest_cell(cell):
			continue
		cells.append(cell)
	return cells


static func _apply_push(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var dir: Vector2i = target.cell - caster.cell
	var bonus_damage := 0
	if caster.side == "player" and int(state.effects.get("push_damage", 0)) > 0 and state.adjacent_to_obstacle(caster):
		bonus_damage = int(state.effects.get("push_damage", 0))
	var skill_id := "rock_push" if caster.skills.has("rock_push") else "push"
	var hit := _hit_entry(state, caster, skill_id, target, int(SkillDB.get_def(skill_id).get("damage", 2)) + bonus_damage)
	if target.is_alive():
		var push_distance := int(caster.upgrades.get("push_distance", Balance.PUSH_DISTANCE)) + (1 if caster.has_buff("rock_push") else 0)
		var collision_bonus := 0
		if caster.side == "player":
			collision_bonus = int(state.effects.get("push_collision", 0))
		var push_result := PushResolver.push(state, target, dir, push_distance, collision_bonus, "推击", caster.side, caster.uid, "rock_push")
		hit["push"] = push_result
	summary["hits"].append(hit)
	var text := "推击 %s：%d 伤害" % [hit["name"], hit["damage"]]
	if hit["push"] != null and bool(hit["push"].get("death", false)):
		text += "，被推入致死地形"
	elif hit["push"] != null and bool(hit["push"].get("blocked", false)):
		text += "，对方站稳脚跟未被推离"
	elif hit["push"] != null and bool(hit["push"].get("moved", false)):
		text += "，推开 1 格"
	summary["text"] = text


static func _apply_rock_smash(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	var entry_type := String(entry.get("type", "cell"))
	if entry_type == "unit":
		var target := state.unit_by_uid(int(entry["unit"]))
		if target == null:
			return
		var opts := {"break_frozen": true, "frozen_multiplier": 3} if skill_id == "rock_break" else {}
		var hit := _hit_entry(state, caster, skill_id, target, int(SkillDB.get_def(skill_id).get("damage", 1)), opts)
		summary["hits"].append(hit)
		summary["text"] = "碎岩命中 %s：%d 伤害" % [hit["name"], hit["damage"]]
		return
	var cell: Vector2i = entry["cell"]
	if entry_type == "nest":
		var hit_nest: Dictionary = state.nest_at_cell(cell)
		var old_hp := int(hit_nest["hp"])
		var destroyed := _hit_nest(state, caster, cell, summary, 2)
		var actual := old_hp - int(hit_nest["hp"])
		summary["nest_damaged"] = {"damage": actual, "destroyed": destroyed}
		summary["text"] = "碎岩击中巢穴：耐久 −%d%s" % [actual, "，巢穴被摧毁" if destroyed else ""]
		return
	if state.obstacle_durability.has(cell):
		_hit_obstacle(state, cell, summary, caster.side)
		return
	if state.terrain_at(cell) == TerrainDB.FRAGILE:
		state.damage_reward_at(cell)
		state.set_terrain(cell, TerrainDB.PIT)
		summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.FRAGILE, "to": TerrainDB.PIT})
		var occupant := state.unit_at(cell)
		if occupant != null:
			state.kill_unit(occupant, "地面塌陷", caster.side, caster.uid)
	summary["text"] = "碎岩击碎易碎地块。"


static func _apply_rain_dance(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = entry["cell"]
	var radius := 1 + int(caster.upgrades.get("rain_radius_bonus", 0))
	for cell in GridSpec.all_cells():
		if absi(center.x - cell.x) > radius or absi(center.y - cell.y) > radius:
			continue
		summary["area_cells"].append(cell)
		var terrain := state.terrain_at(cell)
		if terrain == TerrainDB.PLAIN or terrain == TerrainDB.GRASS or terrain == TerrainDB.VINES or terrain == TerrainDB.FRAGILE:
			state.set_terrain(cell, TerrainDB.WATER)
			summary["terrain_changes"].append({"cell": cell, "from": terrain, "to": TerrainDB.WATER})
			var occupant := state.unit_at(cell)
			if occupant != null and not occupant.has_buff("flight") and occupant.burn_ticks > 0:
				occupant.burn_ticks = 0
				state.log_event("%s 的灼烧被雨水熄灭。" % occupant.display_name)
		if caster.has_buff("rain_call"):
			var wet_target := state.unit_at(cell)
			if wet_target != null:
				state.apply_slow(wet_target)
	summary["text"] = "造雨术：%d 格变为水面" % summary["terrain_changes"].size()
	state.log_event(summary["text"] + "。")


static func _apply_rock_create(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dir: Vector2i = entry["dir"]
	var width := int(caster.upgrades.get("rock_create_width", 3))
	var offsets: Array = [-1, 0, 1] if width <= 3 else [-1, 0, 1, 2]
	var perpendicular := Vector2i(dir.y, dir.x)
	var base: Vector2i = caster.cell + dir
	var expire_round := (state.round if caster.side == "player" else state.round + 1) + (1 if caster.has_buff("rock_create") else 0)
	var made := 0
	for offset in offsets:
		var cell: Vector2i = base + perpendicular * int(offset)
		if not GridSpec.is_inside(cell):
			continue
		summary["area_cells"].append(cell)
		if state.is_interaction_cell(cell):
			continue
		if state.terrain_at(cell) == TerrainDB.FRAGILE:
			state.damage_reward_at(cell)
			state.set_terrain(cell, TerrainDB.PIT)
			summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.FRAGILE, "to": TerrainDB.PIT})
			var fallen := state.unit_at(cell)
			if fallen != null:
				state.kill_unit(fallen, "造岩使地面塌陷", caster.side, caster.uid)
			continue
		var occupant := state.unit_at(cell)
		if occupant != null:
			var hit := _hit_entry(state, caster, "rock_create", occupant, int(SkillDB.get_def("rock_create").get("damage", 2)))
			summary["hits"].append(hit)
			continue
		if state.obstacle_durability.has(cell):
			_hit_obstacle(state, cell, summary, caster.side)
			continue
		if state.is_nest_cell(cell):
			_hit_nest(state, caster, cell, summary, SkillDB.damage_of("rock_create"))
			continue
		if (String(state.reward.get("state", "")) == "map" and cell == state.reward["cell"]) or state.fruits.has(cell):
			continue
		var terrain := state.terrain_at(cell)
		if terrain != TerrainDB.PLAIN and terrain != TerrainDB.GRASS and terrain != TerrainDB.WATER:
			continue
		state.place_temp_obstacle(cell, terrain, expire_round)
		summary["terrain_changes"].append({"cell": cell, "from": terrain, "to": TerrainDB.OBSTACLE})
		made += 1
	var text := "造岩：生成 %d 格临时障碍" % made
	if not summary["hits"].is_empty():
		var names: Array = []
		for hit in summary["hits"]:
			names.append("%s %d伤" % [hit["name"], hit["damage"]])
		text += "；挤压 " + ", ".join(names)
	if not summary["obstacles_damaged"].is_empty():
		text += "；击中 %d 处障碍" % summary["obstacles_damaged"].size()
	summary["text"] = text


static func mountain_chain_segment_count(state: BattleState, caster: CombatUnit) -> int:
	var count := int(SkillDB.get_def("mountain_chain").get("segments_base", 2))
	count += int(caster.upgrades.get("mountain_chain_segments", 0))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Vector2i = caster.cell + Vector2i(dx, dy)
			if GridSpec.is_inside(cell) and state.terrain_at(cell) == TerrainDB.OBSTACLE:
				count += 1
	return count


static func mountain_form_area(caster: CombatUnit) -> Array:
	return support_area(caster.cell, 1 + int(caster.upgrades.get("mountain_form_radius", 0)), true)


static func _apply_mountain_chain(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var segments := mountain_chain_segment_count(state, caster)
	summary["segments_total"] = segments
	summary["continuous"] = true
	summary["area_cells"].append(target.cell)
	for index in segments:
		if not target.is_alive():
			break
		var hit := _hit_entry(state, caster, "mountain_chain", target, SkillDB.damage_of("mountain_chain"))
		hit["segment_index"] = index + 1
		hit["segments_total"] = segments
		hit["continuous"] = true
		summary["hits"].append(hit)
	summary["text"] = "山脉连袭：%d 段 × %d 基础伤害，命中 %s%s" % [
		segments,
		SkillDB.damage_of("mountain_chain"),
		target.display_name,
		"，目标倒下" if not target.is_alive() else "",
	]
	state.log_event(summary["text"])


static func _apply_mountain_form(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var duration := int(SkillDB.get_def("mountain_form").get("duration", 1))
	caster.mountain_form_ticks = maxi(caster.mountain_form_ticks, duration)
	summary["buff_applied"] = "mountain_form"
	summary["area_cells"] = mountain_form_area(caster)
	summary["text"] = "山岳形态生效 1 回合：3×3 内友军与自身伤害减免三分之一后由施法者承受。"
	state.log_event(summary["text"])


static func _apply_rock_blast(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var impact_cell := target.cell
	var dir := _axis_dir(caster.cell, impact_cell)
	var hit := _hit_entry(state, caster, "rock_blast", target, SkillDB.damage_of("rock_blast"))
	summary["hits"].append(hit)
	if target.is_alive():
		hit["push"] = PushResolver.push(state, target, dir, 1, 0, "岩爆弹", caster.side, caster.uid, "rock_blast")
	var fragment_damage := int(SkillDB.get_def("rock_blast").get("fragment_damage", 3))
	var upgrade_info := RunState.upgrade_info("rock_blast_damage")
	if not upgrade_info.is_empty() and caster.upgrades.has(String(upgrade_info.get("key", ""))):
		fragment_damage += int(upgrade_info.get("fragment_bonus", 0))
	var perpendicular := Vector2i(dir.y, dir.x)
	for side_sign in [-1, 1]:
		var fragment_dir := perpendicular * int(side_sign)
		for step in range(1, int(SkillDB.get_def("rock_blast").get("fragment_range", 2)) + 1):
			var cell := impact_cell + fragment_dir * step
			if not GridSpec.is_inside(cell):
				break
			summary["area_cells"].append(cell)
			if TerrainDB.blocks_rays(state.terrain_at(cell)) or state.is_interaction_cell(cell):
				break
			var occupant := state.unit_at(cell)
			if occupant == null:
				continue
			var fragment := _hit_entry(state, caster, "rock_blast", occupant, fragment_damage, {"ignore_skill_upgrade": true})
			fragment["fragment"] = true
			fragment["fragment_cell"] = cell
			summary["hits"].append(fragment)
			break
	summary["text"] = "岩爆弹命中 %s：%d 伤害并向两侧分裂。" % [target.display_name, hit["damage"]]
	if hit["push"] != null and bool(hit["push"].get("death", false)):
		summary["text"] += "目标被推入致死地形。"
	state.log_event(summary["text"])


static func _apply_water_drop_stone(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var route := water_drop_obstacle_route(state, caster, target)
	for cell in route:
		var before := int(state.obstacle_durability.get(cell, 0))
		var destroyed := state.damage_obstacle(cell, 1, caster.side)
		var actual := before - int(state.obstacle_durability.get(cell, 0))
		summary["obstacles_damaged"].append({"cell": cell, "damage": actual, "destroyed": destroyed})
		summary["area_cells"].append(cell)
	var hit := _hit_entry(state, caster, "water_drop_stone", target, SkillDB.damage_of("water_drop_stone"))
	summary["hits"].append(hit)
	var bonus_damage := 0
	if target.is_alive() and target.slow_ticks > 0:
		bonus_damage = int(SkillDB.get_def("water_drop_stone").get("wet_bonus", 3))
		var upgrade_info := RunState.upgrade_info("water_drop_stone_damage")
		if not upgrade_info.is_empty() and caster.upgrades.has(String(upgrade_info.get("key", ""))):
			bonus_damage += int(upgrade_info.get("wet_bonus", 0))
		var bonus := _hit_entry(state, caster, "water_drop_stone", target, bonus_damage, {
			"element": String(SkillDB.get_def("water_drop_stone").get("wet_bonus_element", "water")),
			"ignore_skill_upgrade": true,
			"ranged": false,
			"cause": "水滴石穿·浸湿",
		})
		bonus["bonus_for"] = "浸湿"
		summary["hits"].append(bonus)
	var text := "水滴石穿：%s 受到 %d 点伤害" % [target.display_name, hit["damage"]]
	if not route.is_empty():
		text += "；贯穿 %d 格岩石，每格耐久 -1" % route.size()
	if bonus_damage > 0:
		text += "；浸湿追加 %d 点水属性伤害" % bonus_damage
	summary["text"] = text
	state.log_event(text)


static func _apply_imprint(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary, preview: bool) -> void:
	var source := state.unit_by_uid(int(entry.get("unit", -1)))
	if source == null or not _can_imprint_source(state, caster, source):
		summary["ok"] = false
		summary["text"] = "拓印失败：目标没有可复制的普通技能。"
		return
	var copied_id := source.last_skill_id
	var replay_entry := _imprint_replay_entry(state, caster, source)
	var replay := _apply_rules(state, caster, copied_id, replay_entry, preview)
	if not bool(replay.get("ok", false)):
		summary["ok"] = false
		summary["text"] = "拓印失败：复制的技能当前无法打出。"
		return
	for key in replay:
		if key not in ["ok", "skill_id", "caster_uid"]:
			summary[key] = replay[key]
	summary["copied_skill_id"] = copied_id
	summary["copied_from_uid"] = source.uid
	summary["copied_skill_name"] = SkillDB.name_of(copied_id)
	summary["text"] = "拓印复制 %s 的%s并打出：%s" % [
		source.display_name, SkillDB.name_of(copied_id), String(replay.get("text", "")),
	]


static func _axis_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	if from.x == to.x:
		return Vector2i(0, signi(to.y - from.y))
	return Vector2i(signi(to.x - from.x), 0)


static func _apply_skyfire(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = entry["cell"]
	var cells: Array = [center]
	for dir in GridSpec.DIRS4:
		var cell: Vector2i = center + dir
		if GridSpec.is_inside(cell):
			cells.append(cell)
	var ignited := 0
	for cell in cells:
		summary["area_cells"].append(cell)
		if state.ignite(cell, caster.side, true):
			ignited += 1
	for cell in cells:
		if state.ended:
			break
		var target := state.unit_at(cell)
		if target == null:
			continue
		var hit := _hit_entry(state, caster, "skyfire", target, SkillDB.damage_of("skyfire"))
		if target.is_alive() and state.apply_burn(target, caster):
			(hit["statuses"] as Array).append("灼烧")
		summary["hits"].append(hit)
	summary["text"] = "天火在 (%d,%d) 生成 %d 格十字火焰，命中 %d 个单位。" % [center.x, center.y, ignited, summary["hits"].size()]


static func _apply_water_magic_burst(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = entry["cell"]
	var cells: Array = [center] + GridSpec.neighbors4(center)
	summary["area_cells"] = cells
	var push_targets: Array = []
	for cell in cells:
		var target := state.unit_at(cell)
		if target == null or target.side == caster.side:
			continue
		var base_damage := 11 if cell == center else 8
		var hit := _hit_entry(state, caster, "water_magic_burst", target, base_damage)
		summary["hits"].append(hit)
		if cell != center and target.is_alive():
			push_targets.append({"target": target, "direction": cell - center})
	for entry_data in push_targets:
		var target: CombatUnit = entry_data["target"]
		if not target.is_alive():
			continue
		var direction: Vector2i = entry_data["direction"]
		for hit in summary["hits"]:
			if int(hit.get("uid", -1)) == target.uid:
				hit["push"] = PushResolver.push(state, target, direction, 1, 0, "水魔爆", caster.side, caster.uid, "water_magic_burst")
				break
	summary["text"] = "水魔爆炸开五格十字，命中 %d 名敌人。" % summary["hits"].size()


static func _apply_fire_burst(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = entry["cell"]
	var direction := _axis_dir(caster.cell, center)
	for step in range(1, GridSpec.manhattan(caster.cell, center) + 1):
		summary["ray_cells"].append(caster.cell + direction * step)
	var cells: Array = []
	var nest_damage := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if GridSpec.is_inside(cell):
				cells.append(cell)
	for cell in cells:
		if state.ended:
			break
		summary["area_cells"].append(cell)
		state.damage_reward_at(cell)
		if TerrainDB.is_water_body(state.terrain_at(cell)):
			state.add_steam(cell)
		state.ignite(cell, caster.side)
		if state.terrain_at(cell) == TerrainDB.FRAGILE:
			state.set_terrain(cell, TerrainDB.PIT)
			summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.FRAGILE, "to": TerrainDB.PIT})
			var fallen := state.unit_at(cell)
			if fallen != null:
				state.kill_unit(fallen, "地面塌陷", caster.side, caster.uid)
		var target := state.unit_at(cell)
		if target != null:
			var center_bonus := int(caster.upgrades.get("fireball_damage", 0)) if cell == center else 0
			var hit := _hit_entry(state, caster, "fire_burst", target, SkillDB.damage_of("fire_burst") + center_bonus)
			summary["hits"].append(hit)
			if cell != center and target.is_alive() and caster.has_buff("fire_burst"):
				state.apply_burn(target, caster)
		if state.obstacle_durability.has(cell):
			_hit_obstacle(state, cell, summary, caster.side)
		if state.is_nest_cell(cell):
			var hit_nest: Dictionary = state.nest_at_cell(cell)
			var old_hp := int(hit_nest["hp"])
			_hit_nest(state, caster, cell, summary, 4)
			nest_damage += old_hp - int(hit_nest["hp"])
	summary["text"] = "火球术命中九宫格：%d 个单位受伤。" % summary["hits"].size()
	if nest_damage > 0:
		summary["text"] += "巢穴耐久 −%d。" % nest_damage
	elif (summary.get("_nest_covered_cells", []) as Array).any(func(cell): return cells.has(cell)):
		summary["text"] += "单位覆盖巢穴，本次不伤及巢穴。"


static func _apply_line(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	var dir := _axis_dir(caster.cell, entry["cell"])
	var max_steps := (3 + int(caster.upgrades.get("flame_jet_length", 0))) if skill_id == "flame_jet" else GridSpec.manhattan(caster.cell, entry["cell"])
	for step in range(1, max_steps + 1):
		var cell: Vector2i = caster.cell + dir * step
		if not GridSpec.is_inside(cell):
			break
		summary["ray_cells"].append(cell)
		if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE or (state.is_nest_cell(cell) and state.unit_at(cell) == null):
			if skill_id == "flame_jet":
				if state.is_nest_cell(cell):
					var hit_nest: Dictionary = state.nest_at_cell(cell)
					var old_hp := int(hit_nest["hp"])
					_hit_nest(state, caster, cell, summary, 1)
					summary["text"] = "喷射火焰击中巢穴：耐久 −%d。" % (old_hp - int(hit_nest["hp"]))
				else:
					_hit_obstacle(state, cell, summary, caster.side)
			break
		if skill_id == "flame_jet":
			state.damage_reward_at(cell)
			if TerrainDB.is_water_body(state.terrain_at(cell)):
				state.add_steam(cell)
			state.ignite(cell, caster.side)
		var target := state.unit_at(cell)
		if target == null:
			continue
		if skill_id == "freeze_ray":
			if target.side == caster.side:
				break
			state.apply_freeze(target)
			summary["text"] = "%s 被冰冻。" % target.display_name
			break
		var base_damage := SkillDB.damage_of("flame_jet") + (int(SkillDB.get_def("flame_jet").get("adjacent_bonus", 5)) if skill_id == "flame_jet" and step == 1 else 0)
		var hit := _hit_entry(state, caster, skill_id, target, base_damage)
		if target.is_alive():
			state.apply_burn(target, caster)
			hit["statuses"].append("灼烧")
		summary["hits"].append(hit)
	if summary["text"] == "":
		summary["text"] = "喷射火焰命中 %d 个单位。" % summary["hits"].size() if skill_id == "flame_jet" else "急冻光线未命中。"


static func _apply_ice_breath(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dir := _axis_dir(caster.cell, entry["cell"])
	for step in range(1, 7):
		var cell: Vector2i = caster.cell + dir * step
		if not GridSpec.is_inside(cell):
			break
		summary["ray_cells"].append(cell)
		if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE or (state.is_nest_cell(cell) and state.unit_at(cell) == null):
			break
		var target := state.unit_at(cell)
		if target == null:
			continue
		if target.side == caster.side:
			break
		var had_wet := target.slow_ticks > 0
		var hit := _hit_entry(state, caster, "ice_breath", target, SkillDB.damage_of("ice_breath"))
		if target.is_alive() and had_wet and SkillDB.has_tag("ice_breath", "freeze_combo"):
			state.clear_wet(target)
			state.apply_freeze(target)
			(hit["statuses"] as Array).append("冰冻")
		summary["hits"].append(hit)
		summary["text"] = "冰之息命中 %s：%d 伤害%s。" % [target.display_name, int(hit["damage"]), "，解除浸湿并施加冰冻" if had_wet and target.is_alive() else ""]
		break
	if summary["text"] == "":
		summary["text"] = "冰之息未命中。"


static func _apply_directional(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	if skill_id == "windfire_breath":
		_apply_windfire_breath(state, caster, entry, summary)
		return
	if skill_id == "electric_spark":
		var spark_dir: Vector2i = entry["dir"]
		var spark_cells := electric_spark_cells(state, caster, spark_dir)
		summary["ray_cells"] = spark_cells.duplicate()
		for cell in spark_cells:
			summary["area_cells"].append(cell)
			var target := state.unit_at(cell)
			if target != null and target.side != caster.side:
				var had_electric_status: bool = target.shock_ticks > 0 or target.paralyzed_ticks > 0
				var hit := _hit_entry(state, caster, "electric_spark", target, SkillDB.damage_of("electric_spark"))
				if target.is_alive() and had_electric_status and state.apply_burn(target, caster):
					(hit["statuses"] as Array).append("灼烧")
				summary["hits"].append(hit)
			if state.is_interaction_cell(cell) or TerrainDB.blocks_move(state.terrain_at(cell)):
				break
		summary["text"] = "电极火花沿%s方向命中 %d 名敌人%s。" % [
			GridSpec.DIR_NAMES.get(spark_dir, ""),
			summary["hits"].size(),
			"；带电目标附加灼烧" if summary["hits"].any(func(hit): return (hit.get("statuses", []) as Array).has("灼烧")) else "",
		]
		return
	if skill_id == "flame_jet":
		_apply_line(state, caster, skill_id, entry, summary)
		return
	var dir: Vector2i = entry["dir"]
	var perpendicular := Vector2i(dir.y, dir.x)
	if skill_id == "wild_vines":
		for cell in wild_vines_cells(state, caster, dir):
			var from := state.terrain_at(cell)
			state.place_temp_vines(cell)
			summary["area_cells"].append(cell)
			summary["terrain_changes"].append({"cell": cell, "from": from, "to": TerrainDB.VINES})
	elif skill_id == "frozen_ground":
		var reach := 3 + int(caster.upgrades.get("ice_ground_reach", 0))
		for distance in range(1, reach + 1):
			for offset in [-1, 0, 1]:
				var cell: Vector2i = caster.cell + dir * distance + perpendicular * offset
				if not GridSpec.is_inside(cell) or TerrainDB.blocks_move(state.terrain_at(cell)) or state.is_nest_cell(cell):
					continue
				var from := state.terrain_at(cell)
				state.set_terrain(cell, TerrainDB.ICE)
				summary["terrain_changes"].append({"cell": cell, "from": from, "to": TerrainDB.ICE})
	summary["text"] = "%s 影响 %d 格。" % [SkillDB.name_of(skill_id), summary["terrain_changes"].size()]


static func _apply_windfire_breath(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dir: Vector2i = entry["dir"]
	var cells := half_circle_cells(caster.cell, dir)
	summary["area_cells"] = cells
	for target in state.alive_units("enemy" if caster.side == "player" else "player"):
		if state.ended:
			break
		if not cells.has(target.cell):
			continue
		var hit := _hit_entry(state, caster, "windfire_breath", target, SkillDB.damage_of("windfire_breath"))
		if target.is_alive():
			var push_dir := Vector2i(signi(target.cell.x - caster.cell.x), signi(target.cell.y - caster.cell.y))
			hit["push"] = PushResolver.push(state, target, push_dir, 1, 0, "风怒炎息", caster.side, caster.uid, "windfire_breath")
		summary["hits"].append(hit)
	summary["text"] = "风怒炎息席卷前方 %d 格，命中 %d 名敌人。" % [cells.size(), summary["hits"].size()]


static func _apply_electric_arc(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	_hit_nest(state, caster, entry["cell"], summary, SkillDB.damage_of("electric_arc"))
	if not TerrainDB.is_water_body(state.terrain_at(entry["cell"])):
		if state.obstacle_durability.has(entry["cell"]):
			_hit_obstacle(state, entry["cell"], summary, caster.side)
			summary["area_cells"].append(entry["cell"])
			return
		var target := state.unit_at(entry["cell"])
		if target != null:
			var bonus := int(caster.upgrades.get("electric_arc_damage", 0))
			summary["hits"].append(_hit_entry(state, caster, "electric_arc", target, SkillDB.damage_of("electric_arc") + bonus))
			if target.is_alive() and caster.has_buff("electric_arc"):
				state.apply_slow(target)
			summary["area_cells"].append(target.cell)
			summary["text"] = "放电命中 %s：%d 伤害。" % [target.display_name, summary["hits"][0]["damage"]]
		return
	var visited: Dictionary = {}
	var queue: Array = [entry["cell"]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if visited.has(cell) or not TerrainDB.is_water_body(state.terrain_at(cell)):
			continue
		visited[cell] = true
		for next in GridSpec.neighbors4(cell):
			if not visited.has(next) and TerrainDB.is_water_body(state.terrain_at(next)):
				queue.append(next)
	for target in state.alive_units():
		if target.uid == caster.uid:
			continue
		var affected := visited.has(target.cell)
		if not affected and target.slow_ticks > 0:
			for next in GridSpec.neighbors4(target.cell):
				if visited.has(next):
					affected = true
					break
		if affected:
				var bonus := int(caster.upgrades.get("electric_arc_damage", 0))
				summary["hits"].append(_hit_entry(state, caster, "electric_arc", target, SkillDB.damage_of("electric_arc") + bonus))
				if target.is_alive() and caster.has_buff("electric_arc"):
					state.apply_slow(target)
	for cell in visited:
		_hit_nest(state, caster, cell, summary, SkillDB.damage_of("electric_arc"))
		state.damage_reward_at(cell)
	summary["area_cells"] = visited.keys()
	summary["text"] = "放电传导命中 %d 个单位。" % summary["hits"].size()


static func _apply_electromagnetic_laser(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry.get("unit", -1)))
	if target == null:
		return
	var dir := _axis_dir(caster.cell, target.cell)
	for step in range(1, GridSpec.manhattan(caster.cell, target.cell) + 1):
		summary["ray_cells"].append(caster.cell + dir * step)
	var hit := _hit_entry(state, caster, "electromagnetic_laser", target, SkillDB.damage_of("electromagnetic_laser"))
	summary["hits"].append(hit)
	summary["area_cells"].append(target.cell)
	var pierced := not _electric_line_clear(state, caster.cell, target.cell, true)
	summary["text"] = "电磁镭射命中 %s：%d 伤害%s。" % [
		target.display_name,
		int(hit["damage"]),
		"（感电/麻痹穿透障碍）" if pierced else "",
	]


static func resonance_shock_bonus(caster: CombatUnit) -> int:
	return Balance.ELECTRIC_RESONANCE_SHOCK_BONUS + int(caster.upgrades.get("electric_resonance_power", 0))


static func resonance_paralysis_bonus(caster: CombatUnit) -> int:
	return Balance.ELECTRIC_RESONANCE_PARALYSIS_BONUS + int(caster.upgrades.get("electric_resonance_power", 0))


static func _apply_electric_resonance(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	summary["area_cells"] = resonance_area(caster)
	var gained := 0
	var shock_layers := 0
	var paralysis_layers := 0
	for target in resonance_candidates(state, caster):
		if target.shock_ticks > 0:
			target.shock_ticks = maxi(0, target.shock_ticks - 1)
			gained += resonance_shock_bonus(caster)
			shock_layers += 1
		if target.paralyzed_ticks > 0:
			target.paralyzed_ticks = maxi(0, target.paralyzed_ticks - 1)
			gained += resonance_paralysis_bonus(caster)
			paralysis_layers += 1
	caster.electric_resonance_bonus += gained
	summary["resonance_gain"] = gained
	summary["text"] = "电共鸣消耗 %d 层感电、%d 层麻痹，为下一次技能蓄伤 +%d。" % [shock_layers, paralysis_layers, gained]
	state.log_event(summary["text"])


static func _apply_swap(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	if _player_forbidden_landing(state, caster, target.cell):
		return
	var origin := caster.cell
	var direction := _axis_dir(caster.cell, target.cell) if (caster.cell.x == target.cell.x or caster.cell.y == target.cell.y) else Vector2i.ZERO
	caster.cell = target.cell
	target.cell = origin
	state.apply_vine_on_landing(caster, true)
	state.apply_vine_on_landing(target, false)
	caster.last_move_direction = direction
	target.last_move_direction = -direction
	for unit in [caster, target]:
		if not unit.has_buff("flight") and TerrainDB.is_lethal(state.terrain_at(unit.cell)) and (state.terrain_at(unit.cell) != TerrainDB.DEEP or unit.element != "water"):
			state.kill_unit(unit, "伏特替换落入致死地形", caster.side, caster.uid)
	summary["self_move"] = caster.cell
	summary["text"] = "伏特替换：与 %s 交换位置。" % target.display_name


static func _apply_volt_replace_empty(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	if _player_forbidden_landing(state, caster, dest):
		return
	var origin := caster.cell
	caster.cell = dest
	caster.last_move_direction = _axis_dir(origin, dest) if origin.x == dest.x or origin.y == dest.y else Vector2i.ZERO
	state.apply_vine_on_landing(caster)
	if state.terrain_at(dest) == TerrainDB.WATER:
		caster.burn_ticks = 0
	state.try_pickup_fruit(caster)
	summary["self_move"] = dest
	summary["text"] = "伏特替换：移动到 (%d,%d)。" % [dest.x, dest.y]


static func _apply_tree_wrath(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, "tree_wrath", target, SkillDB.damage_of("tree_wrath"))
	summary["hits"].append(hit)
	summary["text"] = "大树之怒命中 %s：%d 伤害。" % [target.display_name, hit["damage"]]


static func first_aid_healing(caster: CombatUnit) -> int:
	return 8 + int(caster.upgrades.get("first_aid_healing", 0))


static func antidote_healing(caster: CombatUnit) -> int:
	return 3 + int(caster.upgrades.get("antidote_healing", 0))


static func _apply_first_aid(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var healed := mini(first_aid_healing(caster), target.max_hp - target.hp)
	target.hp += healed
	state.feedback_heal(target, healed)
	summary["heal"] = {"uid": target.uid, "amount": healed}
	summary["area_cells"].append(target.cell)
	summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": target.cell, "damage": -healed})
	summary["text"] = "急救恢复 %s %d HP。" % [target.display_name, healed]
	state.log_event(summary["text"])


static func _apply_antidote(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var removed := state.clear_debuff_status(target)
	var healed := mini(antidote_healing(caster), target.max_hp - target.hp)
	target.hp += healed
	state.feedback_heal(target, healed)
	summary["heal"] = {"uid": target.uid, "amount": healed}
	summary["area_cells"].append(target.cell)
	summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": target.cell, "damage": -healed})
	summary["status_cleansed"] = removed
	summary["text"] = "解药%s%s，恢复 %s %d HP。" % [
		"解除异常状态" if removed else "未发现可解除异常",
		"（冰冻保留）" if target.frozen else "",
		target.display_name,
		healed,
	]
	state.log_event(summary["text"])


static func _apply_leaf_wind(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var terrain := state.terrain_at(caster.cell)
	var base_damage := 12 if terrain == TerrainDB.GRASS or terrain == TerrainDB.VINES else 8
	var hit := _hit_entry(state, caster, "leaf_wind", target, base_damage)
	summary["hits"].append(hit)
	summary["area_cells"].append(target.cell)
	summary["text"] = "叶之风命中 %s：%d 伤害%s。" % [
		target.display_name,
		int(hit["damage"]),
		"（草丛/藤蔓强化）" if base_damage == 12 else "",
	]


static func _apply_heal(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = entry["cell"]
	summary["area_cells"] = support_area(center, 2, false)
	var amount := Balance.HERBAL_HEAL + int(caster.upgrades.get("herbal_heal_amount", 0))
	for target in state.alive_units(caster.side):
		if GridSpec.manhattan(target.cell, center) <= 2 and target.hp < target.max_hp:
			var healed := mini(amount, target.max_hp - target.hp)
			target.hp += healed
			state.feedback_heal(target, healed)
			summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": target.cell, "damage": -healed})
	summary["text"] = "药草治疗恢复 %d 个友军。" % summary["hits"].size()


static func _apply_double_cast(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var ids: Array = entry.get("units", []) if String(entry.get("type", "")) == "unit_pair" else [entry["unit"]]
	var names: Array = []
	for uid in ids:
		var target := state.unit_by_uid(int(uid))
		if target == null:
			continue
		target.extra_casts += 1
		names.append(target.display_name)
		summary["area_cells"].append(target.cell)
	summary["text"] = "%s各获得一次额外施法机会。" % "、".join(names)


static func support_area(center: Vector2i, radius: int, square: bool) -> Array:
	var cells: Array = []
	for cell in GridSpec.all_cells():
		if (square and absi(cell.x - center.x) <= radius and absi(cell.y - center.y) <= radius) or (not square and GridSpec.manhattan(center, cell) <= radius):
			cells.append(cell)
	return cells


static func rooted_grass_area(caster: CombatUnit) -> Array:
	return support_area(caster.cell, 1 + int(caster.upgrades.get("rooted_grass_radius", 0)), true)


static func rooted_grass_cells(state: BattleState, caster: CombatUnit) -> Array:
	var cells: Array = []
	for cell in rooted_grass_area(caster):
		if state.obstacle_durability.has(cell) or state.is_interaction_cell(cell) or state.is_nest_cell(cell):
			continue
		if state.terrain_at(cell) in [TerrainDB.PLAIN, TerrainDB.VINES, TerrainDB.FRAGILE]:
			cells.append(cell)
	return cells


static func _apply_rooted_grass(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	summary["area_cells"] = rooted_grass_area(caster)
	for cell in rooted_grass_cells(state, caster):
		var from := state.terrain_at(cell)
		state.set_terrain(cell, TerrainDB.GRASS)
		summary["terrain_changes"].append({"cell": cell, "from": from, "to": TerrainDB.GRASS})
	summary["text"] = "落地生根：将以 %s 为中心的 %d×%d 区域中 %d 格转为草丛。" % [
		caster.display_name,
		3 + 2 * int(caster.upgrades.get("rooted_grass_radius", 0)),
		3 + 2 * int(caster.upgrades.get("rooted_grass_radius", 0)),
		summary["terrain_changes"].size(),
	]
	state.log_event(summary["text"])


static func _apply_tree_summon(state: BattleState, caster: CombatUnit, cell: Vector2i, summary: Dictionary) -> void:
	summary["area_cells"] = [cell]
	var summon := state.summon_tree(caster, cell)
	summary["text"] = "落点不可用或已有召唤物，取消召唤。" if summon == null else "召唤树人：生命 %d，技能威力 +%d；出生轮待机。" % [summon.max_hp, summon.summon_power_bonus]


static func _apply_magnet_pull(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var target := magnet_pull_target(state, caster)
	if target == null:
		return
	var from_cell := target.cell
	var dir := _axis_dir(target.cell, caster.cell)
	var distance := 2 if target.shock_ticks > 0 or target.paralyzed_ticks > 0 else 1
	var moved := 0
	summary["area_cells"].append(from_cell)
	for step in distance:
		var next: Vector2i = target.cell + dir
		if next == caster.cell or not GridSpec.is_inside(next) or state.unit_at(next) != null or state.is_interaction_cell(next) or TerrainDB.blocks_move(state.terrain_at(next)):
			break
		target.cell = next
		target.last_move_direction = dir
		moved += 1
		summary["area_cells"].append(next)
		var terrain := state.terrain_at(next)
		if not target.has_buff("flight") and (terrain == TerrainDB.WATER or terrain == TerrainDB.DEEP):
			target.burn_ticks = 0
		if TerrainDB.is_lethal(terrain) and (terrain != TerrainDB.DEEP or target.element != "water"):
			state.kill_unit(target, "磁吸拉入" + TerrainDB.name_of(terrain), caster.side, caster.uid)
			break
	if target.is_alive() and moved > 0:
		state.apply_vine_on_landing(target, false)
	summary["pull"] = {"uid": target.uid, "from": from_cell, "to": target.cell, "distance": moved, "status_boosted": distance == 2}
	summary["text"] = "磁吸将 %s 向%s拉近 %d 格%s。" % [
		target.display_name,
		GridSpec.DIR_NAMES.get(dir, "自身"),
		moved,
		"（感电/麻痹追加一格）" if distance == 2 else "",
	]
	state.log_event(summary["text"])


static func _apply_glare(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	summary["area_cells"] = glare_area(caster)
	var shocked := 0
	var paralyzed := 0
	for target in glare_candidates(state, caster).duplicate():
		var had_shock: bool = target.shock_ticks > 0
		if not state.apply_shock(target, 1):
			continue
		if had_shock and target.paralyzed_ticks > 0:
			paralyzed += 1
		else:
			shocked += 1
	summary["text"] = "眩光使 %d 名敌人感电%s。" % [shocked, "，%d 名转为麻痹" % paralyzed if paralyzed > 0 else ""]
	state.log_event(summary["text"])


static func _apply_magnetic(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	summary["area_cells"] = support_area(caster.cell, 2 + int(caster.upgrades.get("tailwind_reach", 0)), true)
	# The cast consumes movement, so self haste must survive this phase.
	caster.moved = true
	for target in state.alive_units(caster.side):
		if summary["area_cells"].has(target.cell):
			state.apply_haste(target)
	summary["text"] = "磁场加速：区域内友军下一次移动力 +2。"
