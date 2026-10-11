class_name EnvironmentResolver
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const GridSpec = preload("res://scripts/grid_spec.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func skill_area(state: RefCounted, skill_id: String, target: Vector2i, caster_cell: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var area: Array[Vector2i] = [target]
	if skill_id == "fire_burst":
		for direction in DIRECTIONS:
			var neighbor: Vector2i = target + direction
			if GridSpec.is_inside(neighbor):
				area.append(neighbor)
	elif skill_id == "flame_jet":
		area.clear()
		var offset: Vector2i = target - caster_cell
		var facing := Vector2i(signi(offset.x), signi(offset.y))
		for distance_step in 3:
			var flame_cell: Vector2i = caster_cell + facing * (distance_step + 1)
			if not GridSpec.is_inside(flame_cell):
				break
			area.append(flame_cell)
			if not state.terrain.object_at(flame_cell).is_empty() or state.is_nest_at(flame_cell):
				break
	elif skill_id == "flame_charge":
		area.clear()
		var direction: Vector2i = target - caster_cell
		area.append(caster_cell + Vector2i(signi(direction.x), signi(direction.y)))
		area.append(target)
	elif skill_id == "rain_call":
		area.clear()
		for y in range(target.y - 1, target.y + 2):
			for x in range(target.x - 1, target.x + 2):
				var rain_cell := Vector2i(x, y)
				if GridSpec.is_inside(rain_cell):
					area.append(rain_cell)
	elif skill_id == "rock_create":
		area.clear()
		var facing: Vector2i = target - caster_cell
		if absi(facing.x) + absi(facing.y) == 1:
			var sideways := Vector2i(-facing.y, facing.x)
			for offset in [-1, 0, 1]:
				var wall_cell: Vector2i = target + sideways * offset
				if GridSpec.is_inside(wall_cell):
					area.append(wall_cell)
	elif skill_id in ["wild_vines", "frozen_ground", "tailwind"]:
		area.clear()
		var facing: Vector2i = target - caster_cell
		var sideways := Vector2i(-facing.y, facing.x)
		var depth: int = 2 if skill_id in ["wild_vines", "tailwind"] else 3
		for step in range(1, depth + 1):
			for lateral in ([0] if skill_id == "wild_vines" else [-1, 0, 1]):
				var affected_cell: Vector2i = caster_cell + facing * step + sideways * lateral
				if GridSpec.is_inside(affected_cell):
					area.append(affected_cell)
	elif skill_id == "herbal_heal":
		area.clear()
		for y in range(caster_cell.y - 1, caster_cell.y + 2):
			for x in range(caster_cell.x - 1, caster_cell.x + 2):
				var heal_cell := Vector2i(x, y)
				if GridSpec.is_inside(heal_cell):
					area.append(heal_cell)
	elif skill_id == "electric_arc" and state.terrain.is_water(target):
		area = state.terrain.connected_water(target)
		var seen: Dictionary = {}
		for cell in area:
			seen[cell] = true
		for water_cell in area.duplicate():
			for direction in DIRECTIONS:
				var adjacent: Vector2i = water_cell + direction
				var occupant: CombatUnit = state.unit_at(adjacent)
				if GridSpec.is_inside(adjacent) and not seen.has(adjacent) and not state.terrain.is_water(adjacent) and occupant != null and occupant.wet:
					seen[adjacent] = true
					area.append(adjacent)
	return area


static func apply_skill(state: RefCounted, caster: CombatUnit, skill_id: String, target: Vector2i) -> void:
	var skill: Dictionary = CombatConfig.SKILLS[skill_id]
	state.add_event("%s 对 (%d, %d) 使用 %s。" % [caster.display_name, target.x + 1, target.y + 1, skill["name"]])
	match skill_id:
		"fire_burst":
			var center_unit: CombatUnit = state.unit_at(target)
			var center_landed := false
			for cell in skill_area(state, skill_id, target):
				var affected_unit: CombatUnit = state.unit_at(cell)
				_melt_ice(state, cell, skill["name"])
				if state.terrain.is_water(cell):
					state.terrain.add_steam(cell)
					state.add_event("水域产生蒸汽：站在雾中的怪物不能施法。")
				var damage: int = int(skill["damage"]) + (1 if center_unit != null and cell == target else 0)
				var landed: bool = state.hit_cell(cell, damage, skill["name"], true)
				if cell == target:
					center_landed = landed
				_damage_obstacle(state, cell, int(skill["damage"]), skill["name"])
				if state.terrain.ignite_plant(cell):
					state.add_event("(%d, %d) 的可燃物被点燃，之后每轮向四邻格蔓延。" % [cell.x + 1, cell.y + 1])
				if landed and caster.upgraded_skill_id == "fire_burst" and affected_unit != null and cell != target:
					state.apply_skill_burn(affected_unit)
			if center_landed and center_unit != null and center_unit.is_alive():
				state.apply_skill_burn(center_unit)
		"flame_jet":
			for cell in skill_area(state, skill_id, target, caster.cell):
				var victim: CombatUnit = state.unit_at(cell)
				_melt_ice(state, cell, skill["name"])
				var landed: bool = state.hit_cell(cell, int(skill["damage"]), skill["name"])
				if landed and victim != null and victim.is_alive():
					state.apply_skill_burn(victim)
				if not state.terrain.object_at(cell).is_empty():
					_damage_obstacle(state, cell, int(skill["damage"]), skill["name"])
				state.terrain.ignite_plant(cell)
		"flame_charge":
			state.resolve_flame_charge(caster, target)
		"water_flow":
			state.resolve_water_flow(caster, target)
		"rain_call":
			var changed := 0
			for cell in skill_area(state, skill_id, target):
				var affected_unit: CombatUnit = state.unit_at(cell)
				if state.is_nest_at(cell):
					continue
				if state.terrain.set_rain_water(cell):
					changed += 1
					var occupant: CombatUnit = state.unit_at(cell)
					if occupant != null:
						state._apply_entry_effects(occupant)
				if caster.upgraded_skill_id == "rain_call" and affected_unit != null:
					state.apply_skill_wet(affected_unit)
			state.add_event("造雨术形成 %d 格浅水；水格火焰已熄灭。" % changed)
		"electric_arc":
			var affected: Dictionary = {}
			for cell in skill_area(state, skill_id, target):
				var victim: CombatUnit = state.unit_at(cell)
				if victim == null or not affected.has(victim.unit_id):
					var landed: bool = state.hit_cell(cell, CombatConfig.ELECTRIC_DAMAGE, "导电", false, false)
					if victim != null:
						affected[victim.unit_id] = true
						if landed and caster.upgraded_skill_id == "electric_arc":
							state.apply_skill_wet(victim)
			state.add_event("电流沿连通水域及相邻浸湿陆地传导，命中 %d 个单位。" % affected.size())
		"lightning":
			var victim: CombatUnit = state.unit_at(target)
			if victim != null and state.hit_cell(target, int(skill["damage"]), skill["name"]) and victim.is_alive():
				state.apply_shock(victim)
		"wild_vines":
			for cell in skill_area(state, skill_id, target, caster.cell):
				if not state.is_nest_at(cell) and state.terrain.set_vine(cell):
					var occupant: CombatUnit = state.unit_at(cell)
					if occupant != null:
						state.apply_root(occupant)
		"herbal_heal":
			for cell in skill_area(state, skill_id, target, caster.cell):
				var ally: CombatUnit = state.unit_at(cell)
				if ally != null and ally.team == caster.team and ally.hp < ally.max_hp:
					ally.hp += 1
					state.add_event("%s 恢复 1 HP。" % ally.display_name)
		"frozen_ground":
			for cell in skill_area(state, skill_id, target, caster.cell):
				if not state.is_nest_at(cell) and state.terrain.set_ice(cell):
					state.add_event("(%d, %d) 被冰面覆盖。" % [cell.x + 1, cell.y + 1])
		"freeze_ray":
			state.apply_freeze(state.unit_at(target))
		"tailwind":
			for cell in skill_area(state, skill_id, target, caster.cell):
				var ally: CombatUnit = state.unit_at(cell)
				if ally != null and ally.team == caster.team:
					state.apply_tailwind(ally)
		"double_cast":
			state.apply_double_cast(state.unit_at(target))
		"rock_break":
			state.hit_cell(target, int(skill["damage"]), skill["name"], caster.upgraded_skill_id == "rock_break")
			var result: Dictionary = state.terrain.damage_object(target, CombatConfig.ROCK_SKILL_OBJECT_DAMAGE)
			if result.get("destroyed", false):
				state.add_event("岩石被击碎，格子变为可通行。")
		"rock_create":
			var expiry_round: int = (state.turn_number if caster.team == "player" else state.turn_number + 1) + (1 if caster.upgraded_skill_id == "rock_create" else 0)
			for cell in skill_area(state, skill_id, target, caster.cell):
				if state.terrain.is_fragile(cell):
					state.hit_cell(cell, int(skill["damage"]), skill["name"], true)
					continue
				var victim: CombatUnit = state.unit_at(cell)
				if victim != null or state.is_nest_at(cell):
					state.hit_cell(cell, int(skill["damage"]), skill["name"])
				elif state.reward_state == "ground" and state.reward_cell == cell:
					state.add_event("奖励格被占用，未生成岩石。")
				elif state.terrain.add_rock(cell, expiry_round):
					state.add_event("(%d, %d) 生成临时岩石。" % [cell.x + 1, cell.y + 1])


static func on_push_obstacle(state: RefCounted, cell: Vector2i) -> void:
	var result: Dictionary = state.terrain.damage_object(cell, CombatConfig.PUSH_OBJECT_DAMAGE)
	if not result.is_empty():
		state.add_event("%s 受到碰撞，剩余 %d 点耐久。" % ["岩石" if result["type"] == "rock" else "植物", result["hp"]])
		if result["destroyed"]:
			state.add_event("障碍被撞碎，通路已打开。")


static func _melt_ice(state: RefCounted, cell: Vector2i, source_name: String) -> void:
	if not state.terrain.melt_ice(cell):
		return
	state.add_event("%s 融化了 (%d, %d) 的冰面，露出原地形。" % [source_name, cell.x + 1, cell.y + 1])
	var occupant: CombatUnit = state.unit_at(cell)
	if occupant != null and (state.terrain.is_water(cell) or state.terrain.is_collapsed(cell)):
		state._apply_entry_effects(occupant)


static func _damage_obstacle(state: RefCounted, cell: Vector2i, damage: int, source_name: String) -> void:
	var result: Dictionary = state.terrain.damage_object(cell, damage)
	if not result.is_empty():
		state.add_event("%s 命中%s，造成 %d 耐久伤害（剩余 %d）。" % [source_name, "岩石" if result["type"] == "rock" else "树木", damage, result["hp"]])


static func settle_round(state: RefCounted) -> void:
	var terrain: TerrainManager = state.terrain
	for unit in state.units:
		if unit.is_alive() and unit.burned and state.turn_number >= unit.burn_damage_from_round:
			state.apply_environment_damage(unit, CombatConfig.BURN_DAMAGE, "灼烧")
	var current_flames: Array = terrain.burning.keys()
	var spread_to: Dictionary = {}
	for cell in current_flames:
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if GridSpec.is_inside(neighbor) and terrain.is_flammable(neighbor) and not terrain.is_burning(neighbor):
				spread_to[neighbor] = true
	for cell in current_flames:
		state._damage_reward_at(cell)
		var unit: CombatUnit = state.unit_at(cell)
		if unit != null and unit.element_type != "fire" and not unit.flying:
			state.apply_skill_burn(unit)
		var turns: int = int(terrain.burning[cell]) - 1
		if turns <= 0:
			if terrain.object_at(cell).get("type", "") == "plant":
				terrain.objects.erase(cell)
			elif terrain.is_vine(cell):
				terrain.remove_vine(cell)
			elif terrain.ground_at(cell) == "grass":
				terrain.ground.erase(cell)
			terrain.burning.erase(cell)
			state.add_event("(%d, %d) 的可燃物烧尽。" % [cell.x + 1, cell.y + 1])
		else:
			terrain.burning[cell] = turns
			var object: Dictionary = terrain.object_at(cell)
			if object.get("type", "") == "plant":
				object["burn_turns"] = turns
				terrain.objects[cell] = object
	for cell in spread_to.keys():
		if terrain.ignite_plant(cell):
			state.add_event("火势蔓延至 (%d, %d)。" % [cell.x + 1, cell.y + 1])
	for unit in state.units:
		if unit.is_alive():
			var should_be_wet: bool = not unit.debuff_immune and unit.element_type != "water" and (not unit.flying and terrain.is_shallow_water(unit.cell) or state.turn_number < unit.skill_wet_through_round)
			if should_be_wet and not unit.wet:
				state.add_event("%s 获得浸湿：下一回合移动力 -1。" % unit.display_name)
			unit.wet = should_be_wet
			unit.wet_move_from_round = state.turn_number + 1 if should_be_wet else 0
	for cell in terrain.steam.keys():
		var turns: int = int(terrain.steam[cell]) - 1
		if turns <= 0:
			terrain.steam.erase(cell)
		else:
			terrain.steam[cell] = turns
