class_name SkillResolver
extends RefCounted

## 技能瞄准与结算。预览通过「在克隆状态上真实执行」得到，
## 保证预览、结算与 AI 判断使用同一套规则。


static func targets(state: BattleState, unit: CombatUnit, skill_id: String) -> Array:
	var def := SkillDB.get_def(skill_id)
	var entries: Array = []
	if def.is_empty() or unit == null or not unit.is_alive():
		return entries
	if state.steam_cells.has(unit.cell):
		return entries
	if not unit.can_use_in_battle(skill_id):
		return entries
	match String(def.get("kind", "")):
		"ray":
			_ray_targets(state, unit, skill_id, def, entries)
		"charge":
			for dir in GridSpec.DIRS4:
				var cell: Vector2i = unit.cell + dir * 2
				if not GridSpec.is_inside(cell):
					continue
				entries.append({"type": "cell", "cell": cell})
		"unit":
			_unit_targets(state, unit, skill_id, def, entries)
			if skill_id == "volt_replace":
				_volt_empty_targets(state, unit, def, entries)
		"cell":
			_cell_targets(state, unit, skill_id, def, entries)
		"teleport":
			_teleport_targets(state, unit, def, entries)
		"direction":
			for dir in GridSpec.DIRS4:
				if skill_id == "tsunami" and tsunami_cells(unit.cell, dir).is_empty():
					continue
				entries.append({"type": "dir", "dir": dir, "cell": unit.cell + dir})
		"self":
			if skill_id != "lightning" or not state.alive_units("enemy" if unit.side == "player" else "player").is_empty():
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


static func _unit_targets(state: BattleState, unit: CombatUnit, skill_id: String, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 1))
	if SkillDB.is_placeholder(skill_id):
		skill_range += int(unit.upgrades.get(skill_id + "_range", 0))
	if unit.side == "player" and skill_id == "drain":
		skill_range += int(unit.upgrades.get("drain_range", 0))
	if skill_id == "rock_break":
		skill_range += int(unit.upgrades.get("rock_break_range", 0))
	if skill_id == "double_cast":
		skill_range += int(unit.upgrades.get("double_cast_range", 0))
	for other in state.units:
		if other.uid == unit.uid or not other.is_alive():
			continue
		var distance := GridSpec.manhattan(unit.cell, other.cell)
		if skill_id == "volt_replace" and distance != 2 and not (distance == 1 and int(unit.upgrades.get("volt_replace_flex", 0)) > 0):
			continue
		if skill_id == "wind_gust" and other.cell.x != unit.cell.x and other.cell.y != unit.cell.y:
			continue
		if skill_id == "lightning" and other.side == unit.side:
			continue
		if skill_id == "rock_push":
			if distance != 1:
				continue
		elif distance > skill_range:
			continue
		if skill_id == "herbal_heal" or skill_id == "double_cast":
			if other.side != unit.side:
				continue
		elif skill_id != "volt_replace" and other.side == unit.side:
			continue
		if _concealed(state, skill_id, distance, other):
			continue
		entries.append({"type": "unit", "unit": other.uid, "cell": other.cell})
	if int(def.get("damage", 0)) > 0 or skill_id == "rock_smash" or skill_id == "rock_break":
		for cell in GridSpec.all_cells():
			var distance := GridSpec.manhattan(unit.cell, cell)
			if distance == 0 or distance > skill_range:
				continue
			if state.obstacle_durability.has(cell):
				entries.append({"type": "cell", "cell": cell})
			elif (skill_id == "rock_smash" or skill_id == "rock_break") and state.is_nest_cell(cell):
				entries.append({"type": "nest", "cell": cell})
			elif skill_id == "rock_break" and unit.has_buff("rock_break") and state.terrain_at(cell) == TerrainDB.FRAGILE:
				entries.append({"type": "cell", "cell": cell})


static func _cell_targets(state: BattleState, unit: CombatUnit, skill_id: String, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 3)) + _range_bonus(state, unit, skill_id)
	var water_in_range := false
	if skill_id == "electric_arc":
		for water_cell in GridSpec.all_cells():
			if GridSpec.manhattan(unit.cell, water_cell) <= skill_range and TerrainDB.is_water_body(state.terrain_at(water_cell)):
				water_in_range = true
				break
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if distance > skill_range or (distance == 0 and (skill_id == "rock_slide" or skill_id == "tree_man")):
			continue
		if skill_id == "seed_sow":
			if state.terrain_at(cell) == TerrainDB.PLAIN:
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "rain_dance" or skill_id == "rain_call":
			if _rain_would_change(state, unit, cell):
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "herbal_heal":
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc" and TerrainDB.is_water_body(state.terrain_at(cell)):
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc" and state.obstacle_durability.has(cell):
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "electric_arc" and not water_in_range:
			var target := state.unit_at(cell)
			if target != null and target.uid != unit.uid:
				entries.append({"type": "cell", "cell": cell})
		elif skill_id == "rock_slide":
			entries.append({"type": "cell", "cell": cell})
		elif skill_id == "tree_man" and state.active_summon(unit.uid) == null and state.unit_at(cell) == null and not state.is_nest_cell(cell) and TerrainDB.can_stand(state.terrain_at(cell), "grass"):
			entries.append({"type": "cell", "cell": cell})


static func _volt_empty_targets(state: BattleState, unit: CombatUnit, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 2))
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if distance != skill_range and not (distance == 1 and int(unit.upgrades.get("volt_replace_flex", 0)) > 0):
			continue
		if state.unit_at(cell) != null or state.is_nest_cell(cell):
			continue
		if TerrainDB.can_stand(state.terrain_at(cell), unit.element):
			entries.append({"type": "cell", "cell": cell})


static func _teleport_targets(state: BattleState, unit: CombatUnit, def: Dictionary, entries: Array) -> void:
	var skill_range := int(def.get("range", 2)) + int(unit.upgrades.get("volt_step_bonus", 0))
	for cell in GridSpec.all_cells():
		var distance := GridSpec.manhattan(unit.cell, cell)
		if distance == 0 or distance > skill_range:
			continue
		if state.unit_at(cell) != null or state.is_nest_cell(cell):
			continue
		if not TerrainDB.can_stand(state.terrain_at(cell), unit.element):
			continue
		if not _teleport_path_clear(state, unit.cell, cell, unit.element):
			continue
		entries.append({"type": "cell", "cell": cell})


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
	var def := SkillDB.get_def(skill_id)
	if def.is_empty() or caster == null or not caster.is_alive():
		return {"ok": false}
	if state.steam_cells.has(caster.cell):
		return {"ok": false}
	if target_entry.is_empty():
		return {"ok": false}
	if not caster.can_use_in_battle(skill_id):
		return {"ok": false}
	if not _entry_valid(state, caster, skill_id, target_entry):
		return {"ok": false}
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
		"text": "",
	}
	if bool(def.get("channel", false)):
		var cells: Array = []
		if skill_id == "fire_burst" or skill_id == "rock_slide":
			cells = [target_entry["cell"]]
		elif skill_id == "lightning":
			for enemy in state.alive_units("enemy" if caster.side == "player" else "player"):
				if not cells.has(enemy.cell):
					cells.append(enemy.cell)
		elif skill_id == "tsunami":
			cells = tsunami_cells(caster.cell, target_entry["dir"])
		state.begin_channel(caster, skill_id, cells)
		for cell in cells:
			if skill_id == "fire_burst":
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var area: Vector2i = cell + Vector2i(dx, dy)
						if GridSpec.is_inside(area):
							summary["area_cells"].append(area)
			else:
				summary["area_cells"].append(cell)
		summary["text"] = "%s 吟唱中：第 %d 回合本方阶段开始命中固定落点。" % [SkillDB.name_of(skill_id), state.round + 1]
		if state.round >= Balance.MAX_ROUNDS:
			summary["text"] += "本场将在结算前结束，此次吟唱不会生效。"
		return summary
	state.log_event("%s 施放%s。" % [caster.display_name, SkillDB.name_of(skill_id)])
	if String(def.get("kind", "")) == "unit" and String(target_entry.get("type", "")) == "cell" and state.obstacle_durability.has(target_entry["cell"]):
		_hit_obstacle(state, target_entry["cell"], summary)
		if SkillDB.battle_limit_of(skill_id) > 0:
			caster.battle_skill_uses[skill_id] = int(caster.battle_skill_uses.get(skill_id, 0)) + 1
		caster.moved = true
		return summary
	match String(def.get("kind", "")):
		"ray":
			if skill_id == "fire_burst":
				_apply_fire_burst(state, caster, target_entry, summary)
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
					"wind_gust":
						_apply_wind_gust(state, caster, target_entry, summary)
					"leech_seed":
						_apply_leech_seed(state, caster, target_entry, summary)
					"push", "rock_push":
						_apply_push(state, caster, target_entry, summary)
					"rock_smash", "rock_break":
						_apply_rock_smash(state, caster, skill_id, target_entry, summary)
					"tree_wrath":
						_apply_tree_wrath(state, caster, target_entry, summary)
		"cell":
			if skill_id == "electric_arc":
				_apply_electric_arc(state, caster, target_entry, summary)
			elif skill_id == "rain_dance" or skill_id == "rain_call":
				_apply_rain_dance(state, caster, target_entry, summary)
			elif skill_id == "tree_man":
				_apply_tree_man(state, caster, target_entry, summary)
			else:
				_apply_seed_sow(state, caster, target_entry, summary)
		"teleport":
			_apply_volt_step(state, caster, target_entry, summary)
		"direction":
			match skill_id:
				"flame_jet", "wild_vines", "frozen_ground", "tailwind":
					_apply_directional(state, caster, skill_id, target_entry, summary)
				"rock_create":
					_apply_rock_create(state, caster, target_entry, summary)
		"self":
			match skill_id:
				"fire_amplify": _apply_fire_amplify(state, caster, summary)
				"ice_glide", "surf": _apply_terrain_travel(state, caster, skill_id, summary)
				_: _apply_heal(state, caster, target_entry, summary)
	_consume_fire_amp_if_used(state, caster, summary)
	if SkillDB.battle_limit_of(skill_id) > 0:
		caster.battle_skill_uses[skill_id] = int(caster.battle_skill_uses.get(skill_id, 0)) + 1
	caster.moved = true
	return summary


static func _entry_valid(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary) -> bool:
	var key := _entry_key(entry)
	for candidate in targets(state, caster, skill_id):
		if _entry_key(candidate) == key:
			return true
	return false


static func resolve_channel(state: BattleState, caster: CombatUnit, skill_id: String, cells: Array) -> Dictionary:
	var summary := {"ok": true, "skill_id": skill_id, "caster_uid": caster.uid, "hits": [],
		"area_cells": [], "ray_cells": [], "terrain_changes": [], "obstacles_damaged": [], "text": ""}
	if skill_id == "fire_burst":
		_apply_fire_burst(state, caster, {"cell": cells[0]}, summary)
	elif skill_id == "lightning":
		summary["area_cells"] = cells.duplicate()
		for index in range(cells.size()):
			if state.ended:
				break
			var cell: Vector2i = cells[index]
			if state.obstacle_durability.has(cell):
				_hit_obstacle(state, cell, summary)
			var target := state.unit_at(cell)
			if target == null:
				continue
			var hit := _hit_entry(state, caster, "lightning", target, 4)
			summary["hits"].append(hit)
			if target.is_alive():
				if target.shock_ticks > 0:
					target.paralyzed_ticks = 2
					state.cancel_channel(target, "麻痹")
				target.shock_ticks = 2
				if index == 0 and int(caster.upgrades.get("lightning_first_shock", 0)) > 0:
					target.paralyzed_ticks = 2
					state.cancel_channel(target, "双重感电")
		summary["text"] = "打雷落下：%d 个单位受击。" % summary["hits"].size()
	elif skill_id == "rock_slide":
		summary["area_cells"] = cells.duplicate()
		if state.obstacle_durability.has(cells[0]):
			_hit_obstacle(state, cells[0], summary)
		var target := state.unit_at(cells[0])
		if target != null:
			summary["hits"].append(_hit_entry(state, caster, "rock_slide", target, 8))
		summary["text"] = "岩崩落下：%d 个单位受击。" % summary["hits"].size()
	elif skill_id == "tsunami":
		summary["area_cells"] = cells.duplicate()
		for cell in cells:
			if state.ended:
				break
			if state.obstacle_durability.has(cell):
				_hit_obstacle(state, cell, summary)
			if not TerrainDB.is_water_body(state.terrain_at(cell)):
				continue
			var target := state.unit_at(cell)
			if target != null and target.side != caster.side:
				summary["hits"].append(_hit_entry(state, caster, "tsunami", target, 4))
		summary["text"] = "海啸落下：%d 个水域内敌方单位受击。" % summary["hits"].size()
	_consume_fire_amp_if_used(state, caster, summary)
	return summary


static func tsunami_cells(origin: Vector2i, dir: Vector2i) -> Array:
	var cells: Array = []
	var sideways := Vector2i(-dir.y, dir.x)
	for length in range(1, 5):
		for offset in range(-2, 3):
			var cell: Vector2i = origin + dir * length + sideways * offset
			if GridSpec.is_inside(cell):
				cells.append(cell)
	return cells


static func _consume_fire_amp_if_used(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	if caster.fire_amp_stacks <= 0:
		return
	for hit in summary.get("hits", []):
		if int(hit.get("damage", 0)) > 0:
			state.log_event("%s 的火焰增幅 +%d 已用于本次技能。" % [caster.display_name, caster.fire_amp_stacks])
			caster.fire_amp_stacks = 0
			return


static func _entry_key(entry: Dictionary) -> String:
	if not entry.has("cell"):
		return "invalid"
	match String(entry.get("type", "")):
		"unit":
			return "unit:%d" % int(entry["unit"])
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


static func _hit_obstacle(state: BattleState, cell: Vector2i, summary: Dictionary) -> void:
	var before := int(state.obstacle_durability.get(cell, 0))
	if before <= 0:
		return
	var destroyed := state.damage_obstacle(cell, 1)
	var actual := before - int(state.obstacle_durability.get(cell, 0))
	summary["obstacles_damaged"].append({"cell": cell, "damage": actual, "destroyed": destroyed})
	summary["text"] = "障碍耐久 −%d%s" % [actual, "，障碍被破坏" if destroyed else ""]
	state.log_event("(%d,%d) %s" % [cell.x, cell.y, summary["text"]])


static func _hit_entry(state: BattleState, caster: CombatUnit, skill_id: String, target: CombatUnit, base: int, extra_opts: Dictionary = {}) -> Dictionary:
	var def := SkillDB.get_def(skill_id)
	if base > 0:
		base += caster.fire_amp_stacks
	var modifier := Elements.modifier(String(def.get("element", "")), target.element) if base > 0 else 0
	var opts := {
		"element": String(def.get("element", "")),
		"ranged": SkillDB.is_ranged(skill_id),
		"cause": SkillDB.name_of(skill_id),
		"conductive": skill_id == "electric_arc",
	}
	opts.merge(extra_opts, true)
	var result := state.damage_unit(caster, target, base, opts)
	return {
		"uid": target.uid,
		"name": target.display_name,
		"cell": target.cell,
		"damage": int(result.get("amount", 0)),
		"modifier": modifier if int(result.get("amount", 0)) > 0 else 0,
		"killed": bool(result.get("killed", false)),
		"statuses": [],
		"push": null,
	}


static func _apply_placeholder(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, skill_id, target, 1)
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
			_hit_obstacle(state, hit_cell, summary)
		elif state.is_nest_cell(hit_cell):
			state.damage_nest(int(SkillDB.get_def("fire_seed").get("damage", 2)), caster.side)
		var splash_cells := GridSpec.neighbors4(hit_cell)
		for cell in splash_cells:
			summary["area_cells"].append(cell)
			var occupant := state.unit_at(cell)
			if occupant == null:
				continue
			var hit := _hit_entry(state, caster, "fire_seed", occupant, 1)
			summary["hits"].append(hit)
		summary["text"] = "火种打空，终点格相邻 4 格各受 1 伤害"
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
			var push_result := PushResolver.push(state, hit_unit, dir, push_distance, 0, "水炮击退", caster.side, caster.uid)
			hit["push"] = push_result
		summary["hits"].append(hit)
		summary["text"] = "水炮命中 %s：%d 伤害，击退并减速" % [hit["name"], hit["damage"]]
	elif hit_object == "obstacle":
		_hit_obstacle(state, hit_cell, summary)
		var prev: Vector2i = hit_cell - dir
		if _convert_to_water(state, prev, summary):
			summary["text"] = "水炮击中障碍，在前方生成水面"
		else:
			summary["text"] = "水炮击中障碍"
	elif hit_object == "nest":
		var old_hp := int(state.nest["hp"])
		state.damage_nest(1, caster.side)
		summary["text"] = "水炮击中巢穴，造成 %d 点耐久伤害" % (old_hp - int(state.nest["hp"]))
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
	summary["text"] = "%s 被寄生；每次整轮结算失去 1 HP，受到其他伤害时解除。" % target.display_name
	state.log_event(summary["text"])


static func _apply_fire_amplify(state: BattleState, caster: CombatUnit, summary: Dictionary) -> void:
	var absorbed := 0
	for cell in state.burning_cells.keys().duplicate():
		if GridSpec.manhattan(caster.cell, cell) > 2:
			continue
		state.burning_cells.erase(cell)
		summary["area_cells"].append(cell)
		absorbed += 1
	caster.fire_amp_stacks += absorbed
	summary["text"] = "火焰增幅熄灭 %d 格火焰，当前蓄积 +%d 直伤。" % [absorbed, caster.fire_amp_stacks]
	state.log_event(summary["text"])


static func _apply_terrain_travel(state: BattleState, caster: CombatUnit, skill_id: String, summary: Dictionary) -> void:
	if skill_id == "ice_glide":
		caster.ice_glide_until_round = state.round + 2
	else:
		caster.surf_until_round = state.round + 2
	summary["text"] = "%s 获得%s：接下来两个本方阶段可在连通%s上不限距离移动。" % [caster.display_name, SkillDB.name_of(skill_id), "冰面" if skill_id == "ice_glide" else "水域"]
	state.log_event(summary["text"])


static func _apply_flame_charge(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	var dir := Vector2i((dest.x - caster.cell.x) / 2, (dest.y - caster.cell.y) / 2)
	var impact_damage := 1 + (1 if caster.has_buff("flame_charge") or int(caster.upgrades.get("flame_charge_damage", 0)) > 0 else 0)
	for step in range(1, 3):
		var next: Vector2i = caster.cell + dir
		summary["ray_cells"].append(next)
		var occupant := state.unit_at(next)
		if occupant != null:
			var hit := _hit_entry(state, caster, "flame_charge", occupant, impact_damage)
			if occupant.is_alive():
				hit["push"] = PushResolver.push(state, occupant, dir, 1, 0, "闪焰冲锋", caster.side, caster.uid)
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
		if state.is_nest_cell(next):
			var old_hp := int(state.nest["hp"])
			var destroyed := state.damage_nest(impact_damage, caster.side)
			var actual := old_hp - int(state.nest["hp"])
			summary["nest_damaged"] = {"damage": actual, "destroyed": destroyed}
			summary["text"] = "闪焰冲锋撞击巢穴：耐久 −%d。" % actual
			break
		if TerrainDB.blocks_move(state.terrain_at(next)):
			var obstacle_name := TerrainDB.name_of(state.terrain_at(next))
			var old_hp := int(state.obstacle_durability.get(next, 0))
			var destroyed := state.damage_obstacle(next, impact_damage)
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
	caster.cell = dest
	state.apply_vine_on_landing(caster)
	summary["self_move"] = dest
	var terrain := state.terrain_at(dest)
	if terrain == TerrainDB.WATER or terrain == TerrainDB.DEEP:
		caster.burn_ticks = 0
	state.try_pickup_fruit(caster)
	summary["text"] = "电光步瞬移到 (%d,%d)" % [dest.x, dest.y]


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
	var healed := mini(caster.max_hp, caster.hp + 1)
	if healed > caster.hp:
		summary["heal"] = {"uid": caster.uid, "amount": healed - caster.hp}
		state.log_event("%s 回复 %d 生命。" % [caster.display_name, healed - caster.hp])
		caster.hp = healed
	summary["text"] = "吸取：对 %s 造成 %d 伤害，自身回复 %d" % [hit["name"], hit["damage"], int(summary["heal"]["amount"]) if summary["heal"] != null else 0]


static func _apply_ice_shard(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var bonus := int(caster.upgrades.get("ice_shard_damage", 0))
	var hit := _hit_entry(state, caster, "ice_shard", target, 1 + bonus)
	summary["hits"].append(hit)
	summary["text"] = "冰锥命中 %s：%d 伤害。" % [hit["name"], hit["damage"]]


static func _apply_wind_gust(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var direction := Vector2i(signi(target.cell.x - caster.cell.x), signi(target.cell.y - caster.cell.y))
	var distance := 1 + int(caster.upgrades.get("wind_gust_distance", 0))
	var result := PushResolver.push(state, target, direction, distance, 0, "推风", caster.side, caster.uid)
	summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": target.cell, "damage": 0, "killed": not target.is_alive(), "statuses": [], "push": result})
	summary["text"] = "推风：%s%s。" % [target.display_name, "被推离" if result["moved"] else "受阻"]


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
		var push_result := PushResolver.push(state, target, dir, push_distance, collision_bonus, "推击", caster.side, caster.uid)
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
		var old_hp := int(state.nest["hp"])
		var destroyed := state.damage_nest(2, caster.side)
		var actual := old_hp - int(state.nest["hp"])
		summary["nest_damaged"] = {"damage": actual, "destroyed": destroyed}
		summary["text"] = "碎岩击中巢穴：耐久 −%d%s" % [actual, "，巢穴被摧毁" if destroyed else ""]
		return
	if state.obstacle_durability.has(cell):
		_hit_obstacle(state, cell, summary)
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
			_hit_obstacle(state, cell, summary)
			continue
		if state.is_nest_cell(cell):
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


static func _axis_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	if from.x == to.x:
		return Vector2i(0, signi(to.y - from.y))
	return Vector2i(signi(to.x - from.x), 0)


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
		state.ignite(cell)
		if state.terrain_at(cell) == TerrainDB.FRAGILE:
			state.set_terrain(cell, TerrainDB.PIT)
			summary["terrain_changes"].append({"cell": cell, "from": TerrainDB.FRAGILE, "to": TerrainDB.PIT})
			var fallen := state.unit_at(cell)
			if fallen != null:
				state.kill_unit(fallen, "地面塌陷", caster.side, caster.uid)
		var target := state.unit_at(cell)
		if target != null:
			var center_bonus := int(caster.upgrades.get("fireball_damage", 0)) if cell == center else 0
			var hit := _hit_entry(state, caster, "fire_burst", target, 4 + center_bonus)
			summary["hits"].append(hit)
			if cell != center and target.is_alive() and caster.has_buff("fire_burst"):
				state.apply_burn(target, caster)
		if state.obstacle_durability.has(cell):
			_hit_obstacle(state, cell, summary)
		if state.is_nest_cell(cell):
			var old_hp := int(state.nest["hp"])
			state.damage_nest(4 + (int(caster.upgrades.get("fireball_damage", 0)) if cell == center else 0), caster.side)
			nest_damage += old_hp - int(state.nest["hp"])
	summary["text"] = "火球术命中九宫格：%d 个单位受伤。" % summary["hits"].size()
	if nest_damage > 0:
		summary["text"] += "巢穴耐久 −%d。" % nest_damage
	elif state.nest_exit_guarded() and cells.has(state.nest["cell"]):
		summary["text"] += "巢穴伤害被守口抵消。"


static func _apply_line(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	var dir := _axis_dir(caster.cell, entry["cell"])
	var max_steps := (3 + int(caster.upgrades.get("flame_jet_length", 0))) if skill_id == "flame_jet" else GridSpec.manhattan(caster.cell, entry["cell"])
	for step in range(1, max_steps + 1):
		var cell: Vector2i = caster.cell + dir * step
		if not GridSpec.is_inside(cell):
			break
		summary["ray_cells"].append(cell)
		if state.terrain_at(cell) == TerrainDB.OBSTACLE or state.terrain_at(cell) == TerrainDB.TREE or state.is_nest_cell(cell):
			if skill_id == "flame_jet":
				if state.is_nest_cell(cell):
					var old_hp := int(state.nest["hp"])
					state.damage_nest(1, caster.side)
					summary["text"] = "喷射火焰击中巢穴：耐久 −%d。" % (old_hp - int(state.nest["hp"]))
				else:
					_hit_obstacle(state, cell, summary)
			break
		if skill_id == "flame_jet":
			state.damage_reward_at(cell)
			if TerrainDB.is_water_body(state.terrain_at(cell)):
				state.add_steam(cell)
			state.ignite(cell)
		var target := state.unit_at(cell)
		if target == null:
			continue
		if skill_id == "freeze_ray":
			if target.side == caster.side:
				break
			target.frozen = true
			state.cancel_channel(target, "冻结")
			summary["text"] = "%s 被冰冻。" % target.display_name
			break
		var base_damage := 1 + (1 if skill_id == "flame_jet" and step == 1 else 0)
		var hit := _hit_entry(state, caster, skill_id, target, base_damage)
		if target.is_alive():
			state.apply_burn(target, caster)
			hit["statuses"].append("灼烧")
		summary["hits"].append(hit)
	if summary["text"] == "":
		summary["text"] = "喷射火焰命中 %d 个单位。" % summary["hits"].size() if skill_id == "flame_jet" else "急冻光线未命中。"


static func _apply_directional(state: BattleState, caster: CombatUnit, skill_id: String, entry: Dictionary, summary: Dictionary) -> void:
	if skill_id == "flame_jet":
		_apply_line(state, caster, skill_id, entry, summary)
		return
	var dir: Vector2i = entry["dir"]
	var perpendicular := Vector2i(dir.y, dir.x)
	if skill_id == "wild_vines":
		for distance in range(1, 3 + int(caster.upgrades.get("wild_vines_reach", 0))):
			var cell: Vector2i = caster.cell + dir * distance
			if not GridSpec.is_inside(cell) or TerrainDB.blocks_move(state.terrain_at(cell)) or state.is_nest_cell(cell):
				continue
			var from := state.terrain_at(cell)
			state.place_temp_vines(cell)
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
	elif skill_id == "tailwind":
		for distance in range(1, 3 + int(caster.upgrades.get("tailwind_reach", 0))):
			for offset in [-1, 0, 1]:
				var cell: Vector2i = caster.cell + dir * distance + perpendicular * offset
				if not GridSpec.is_inside(cell):
					continue
				var target := state.unit_at(cell)
				if target != null and target.side == caster.side:
					state.apply_haste(target)
	summary["text"] = "%s 影响 %d 格。" % [SkillDB.name_of(skill_id), summary["terrain_changes"].size()]


static func _apply_electric_arc(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	if not TerrainDB.is_water_body(state.terrain_at(entry["cell"])):
		if state.obstacle_durability.has(entry["cell"]):
			_hit_obstacle(state, entry["cell"], summary)
			summary["area_cells"].append(entry["cell"])
			return
		var target := state.unit_at(entry["cell"])
		if target != null:
			var bonus := int(caster.upgrades.get("electric_arc_damage", 0))
			summary["hits"].append(_hit_entry(state, caster, "electric_arc", target, 1 + bonus))
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
				summary["hits"].append(_hit_entry(state, caster, "electric_arc", target, 1 + bonus))
				if target.is_alive() and caster.has_buff("electric_arc"):
					state.apply_slow(target)
	for cell in visited:
		state.damage_reward_at(cell)
	summary["area_cells"] = visited.keys()
	summary["text"] = "放电传导命中 %d 个单位。" % summary["hits"].size()


static func _apply_swap(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var origin := caster.cell
	var direction := _axis_dir(caster.cell, target.cell) if (caster.cell.x == target.cell.x or caster.cell.y == target.cell.y) else Vector2i.ZERO
	caster.cell = target.cell
	target.cell = origin
	state.apply_vine_on_landing(caster)
	state.apply_vine_on_landing(target)
	caster.last_move_direction = direction
	target.last_move_direction = -direction
	for unit in [caster, target]:
		if not unit.has_buff("flight") and TerrainDB.is_lethal(state.terrain_at(unit.cell)) and (state.terrain_at(unit.cell) != TerrainDB.DEEP or unit.element != "water"):
			state.kill_unit(unit, "伏特替换落入致死地形", caster.side, caster.uid)
	summary["self_move"] = caster.cell
	summary["text"] = "伏特替换：与 %s 交换位置。" % target.display_name


static func _apply_volt_replace_empty(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var dest: Vector2i = entry["cell"]
	var origin := caster.cell
	caster.cell = dest
	caster.last_move_direction = _axis_dir(origin, dest) if origin.x == dest.x or origin.y == dest.y else Vector2i.ZERO
	state.apply_vine_on_landing(caster)
	if state.terrain_at(dest) == TerrainDB.WATER:
		caster.burn_ticks = 0
	state.try_pickup_fruit(caster)
	summary["self_move"] = dest
	summary["text"] = "伏特替换：移动到 (%d,%d)。" % [dest.x, dest.y]


static func _apply_tree_man(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var cell: Vector2i = entry["cell"]
	var summon := state.summon_tree(caster, cell)
	if summon == null:
		return
	summary["area_cells"].append(cell)
	summary["text"] = "召唤树人：生命 %d/%d，出生轮待机。" % [summon.hp, summon.max_hp]


static func _apply_tree_wrath(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	var hit := _hit_entry(state, caster, "tree_wrath", target, 1)
	summary["hits"].append(hit)
	summary["text"] = "大树之怒命中 %s：%d 伤害。" % [target.display_name, hit["damage"]]


static func _apply_heal(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var center: Vector2i = caster.cell
	var amount := 1 + int(caster.upgrades.get("herbal_heal_amount", 0))
	for target in state.alive_units(caster.side):
		if absi(target.cell.x - center.x) <= 1 and absi(target.cell.y - center.y) <= 1 and target.hp < target.max_hp:
			var healed := mini(amount, target.max_hp - target.hp)
			target.hp += healed
			summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": target.cell, "damage": -healed})
	summary["text"] = "药草治疗恢复 %d 个友军。" % summary["hits"].size()


static func _apply_double_cast(state: BattleState, caster: CombatUnit, entry: Dictionary, summary: Dictionary) -> void:
	var target := state.unit_by_uid(int(entry["unit"]))
	if target == null:
		return
	target.extra_casts += 1
	summary["text"] = "%s 获得一次额外施法机会。" % target.display_name
